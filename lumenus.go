package main

// Lumenus: bounded, session-only asset worker. Uses documented Open Cloud
// delivery; does not read browser credentials or retry access denials.
import (
 "bytes"
 "image"
 "context"
 "encoding/binary"
 "encoding/json"
 "fmt"
 "io"
 "math"
 "log"
 "net/http"
 "net/url"
 "os"
 "path/filepath"
 "strconv"
 "strings"
 "sync"
 "time"
 _ "image/jpeg"
 _ "image/png"
)

const assetLimit = 16 << 20
type assetRequest struct { Asset string `json:"asset"`; Kind string `json:"kind"`; ID uint32 `json:"id"` }
type assetResult struct { Status string `json:"status"`; Detail string `json:"detail,omitempty"`; Size V `json:"size,omitempty"`; Slot uint32 `json:"slot,omitempty"` }
type assetJob struct { key string; req assetRequest }
type Lumenus struct {
 mu sync.Mutex
 jobs chan assetJob
 images chan assetJob
 entries map[string]assetResult
 ids map[uint32]string
 imageIDs map[uint32]string
 imageSlots map[string]uint32
 dir,key,imports string
 oauth *oauthSession
 ctx context.Context
 cancel context.CancelFunc
 wg sync.WaitGroup
 bridge *Bridge
}
func newLumenus(b *Bridge, root string) (*Lumenus,error) {
 if err:=os.MkdirAll(root,0700);err!=nil{return nil,err}
 dir,err:=os.MkdirTemp(root,"session-");if err!=nil{return nil,err}
 ctx,cancel:=context.WithCancel(context.Background())
 l:=&Lumenus{jobs:make(chan assetJob,256),images:make(chan assetJob,128),entries:map[string]assetResult{},ids:map[uint32]string{},imageIDs:map[uint32]string{},imageSlots:map[string]uint32{},dir:dir,key:os.Getenv("LUMEN_ASSET_API_KEY"),imports:filepath.Join(filepath.Dir(root),"AssetImports"),ctx:ctx,cancel:cancel,bridge:b}
 l.wg.Add(1);go l.worker();return l,nil
}
func(l *Lumenus)close(){l.cancel();l.wg.Wait();os.RemoveAll(l.dir)}
func assetKey(r assetRequest)(string,bool){
 if validLocalAsset(r.Kind,r.Asset){
  if r.Kind=="mesh"&&meshID(r.ID)||r.Kind=="image"&&r.ID<=textureMax{return r.Kind+":"+r.Asset,true};return "",false
 }
 n,e:=strconv.ParseUint(r.Asset,10,64)
 if e!=nil||n==0||strconv.FormatUint(n,10)!=r.Asset{return "",false}
 if r.Kind=="mesh"&&meshID(r.ID){return r.Kind+":"+r.Asset,true}
 if r.Kind=="image"&&r.ID<=textureMax{return r.Kind+":"+r.Asset,true}
 return "",false
}
func(l *Lumenus)handler(w http.ResponseWriter,r *http.Request){
 if r.Method!="POST"||r.Header.Get("Origin")!=""{http.Error(w,"local POST only",403);return}
 var a assetRequest;d:=json.NewDecoder(http.MaxBytesReader(w,r.Body,2048))
 if d.Decode(&a)!=nil||d.Decode(new(any))!=io.EOF{http.Error(w,"invalid request",400);return}
 key,ok:=assetKey(a);if !ok{http.Error(w,"invalid asset reference",400);return}
 l.mu.Lock();defer l.mu.Unlock()
 if a.Kind=="mesh" {
  if prior,found:=l.ids[a.ID];found&&prior!=key{http.Error(w,"mesh ID collision",409);return}
  // One renderer ID per asset in this session. Client already deduplicates.
  key=key+":"+strconv.FormatUint(uint64(a.ID),10)
 }
 if a.Kind=="image"&&a.ID==0{
  if slot,found:=l.imageSlots[key];found{a.ID=slot}else{
   for slot:=uint32(1);slot<=textureMax;slot++{if _,found:=l.imageIDs[slot];!found{a.ID=slot;break}}
   if a.ID==0{http.Error(w,"texture slot capacity",429);return};l.imageSlots[key]=a.ID
  }
 }
 if a.Kind=="image"&&a.ID>0{
  if prior,found:=l.imageIDs[a.ID];found&&prior!=key{http.Error(w,"texture slot collision",409);return}
  l.imageIDs[a.ID]=key;key=key+":"+strconv.FormatUint(uint64(a.ID),10)
 }
 result,found:=l.entries[key]
 if !found {
  if len(l.entries)>=384{http.Error(w,"session asset cap",429);return}
  queue:=l.jobs;if a.Kind=="image"{queue=l.images}
  select{case queue<-assetJob{key,a}:result=assetResult{Status:"queued"};l.entries[key]=result;if a.Kind=="mesh"{l.ids[a.ID]="mesh:"+a.Asset}
  default:http.Error(w,"queue full",429);return}
 }
 if a.Kind=="image"{result.Slot=a.ID}
 w.Header().Set("Content-Type","application/json");w.Header().Set("Cache-Control","no-store");json.NewEncoder(w).Encode(result)
}
func(l *Lumenus)worker(){
 defer l.wg.Done()
 for {
  var j assetJob
  select{case <-l.ctx.Done():return;case j=<-l.jobs:default:
   select{case <-l.ctx.Done():return;case j=<-l.jobs:case j=<-l.images:}
  }
  if l.ctx.Err()!=nil{return}
  result:=l.process(j.req)
  l.mu.Lock();l.entries[j.key]=result;l.mu.Unlock()
  log.Printf("[Lumenus] %s %s: %s %s",j.req.Kind,j.req.Asset,result.Status,result.Detail)
  // Pace remote requests; never busy-loop on rejected assets.
  select{case <-l.ctx.Done():return;case <-time.After(250*time.Millisecond):}
 }
}
func readLimited(r io.Reader,n int64)([]byte,error){
 data,e:=io.ReadAll(io.LimitReader(r,n+1));if e!=nil{return nil,e};if int64(len(data))>n{return nil,fmt.Errorf("asset too large")};return data,nil
}
func cdnURL(u *url.URL)bool{return u!=nil&&u.Scheme=="https"&&u.User==nil&&u.Port()==""&&(u.Hostname()=="rbxcdn.com"||strings.HasSuffix(u.Hostname(),".rbxcdn.com"))}
func(l *Lumenus)fetch(a assetRequest)([]byte,error){
 if validLocalAsset(a.Kind,a.Asset){return l.fetchLocal(a)}
 // Explicit local imports remain available without an API key.
 ext:=[]string{".mesh"};if a.Kind=="image"{ext=[]string{".png",".jpg",".jpeg",".dds"}}
 for _,suffix:=range ext {
  f,e:=os.Open(filepath.Join(l.imports,a.Asset+suffix));if e==nil{data,e:=readLimited(f,assetLimit);f.Close();return data,e};if !os.IsNotExist(e){return nil,fmt.Errorf("local import unreadable")}
 }
 if l.key==""&&l.oauth==nil{return nil,fmt.Errorf("not connected: run Connect-Roblox.bat or supply a permitted local import")}
 c:=&http.Client{Timeout:12*time.Second,CheckRedirect:func(r *http.Request,via []*http.Request)error{return http.ErrUseLastResponse}}
 req,e:=http.NewRequestWithContext(l.ctx,"GET","https://apis.roblox.com/asset-delivery-api/v1/assetId/"+a.Asset,nil);if e!=nil{return nil,e}
 if l.oauth!=nil{token,e:=l.oauth.bearer(l.ctx);if e!=nil{return nil,e};req.Header.Set("Authorization","Bearer "+token)}else{req.Header.Set("x-api-key",l.key)}
 res,e:=c.Do(req);if e!=nil{return nil,fmt.Errorf("asset delivery request failed")}
 defer res.Body.Close()
 var target string
 if res.StatusCode>=300&&res.StatusCode<400{target=res.Header.Get("Location")}else{
  if res.StatusCode!=200{return nil,fmt.Errorf("asset delivery HTTP %d",res.StatusCode)}
  data,e:=readLimited(res.Body,assetLimit);if e!=nil{return nil,e}
  var envelope struct{Location string;Locations []struct{Location string}; IsCopyrightProtected bool; IsArchived bool}
  if json.Unmarshal(data,&envelope)!=nil{return data,nil}
  if envelope.IsCopyrightProtected||envelope.IsArchived{return nil,fmt.Errorf("asset unavailable for external use")}
  target=envelope.Location;if target==""&&len(envelope.Locations)>0{target=envelope.Locations[0].Location}
 }
 u,e:=url.Parse(target);if e!=nil||!cdnURL(u){return nil,fmt.Errorf("unrecognized delivery location")}
 // New request, never forward the API key to a CDN.
 req,e=http.NewRequestWithContext(l.ctx,"GET",u.String(),nil);if e!=nil{return nil,fmt.Errorf("invalid delivery location")}
 res2,e:=c.Do(req);if e!=nil{return nil,fmt.Errorf("CDN request failed")};defer res2.Body.Close()
 if res2.StatusCode!=200{return nil,fmt.Errorf("CDN HTTP %d",res2.StatusCode)}
 return readLimited(res2.Body,assetLimit)
}
func(l *Lumenus)process(a assetRequest)assetResult{
 cachePath:=filepath.Join(l.dir,a.Kind+"-"+a.Asset+".bin")
 data,e:=os.ReadFile(cachePath);cached:=e==nil
 if !cached{data,e=l.fetch(a)}
 if e!=nil{return assetResult{Status:"failed",Detail:e.Error()}}
 // No aggregate disk cap; per-file and GPU limits remain.
 if a.Kind=="image" {
  b:=l.bridge;b.mu.RLock();used:=0;for id,p:=range b.textures{if id!=a.ID{used+=len(p)}};slots:=len(b.textures);if _,ok:=b.textures[a.ID];ok{slots--};b.mu.RUnlock()
  var pixels []uint32
  if a.Asset=="local-studs.dds"{pixels,e=decodeStudAtlas(data)}else{pixels,e=decodeTextureBudget(data,used,slots)}
  if e!=nil{return assetResult{Status:"failed",Detail:"unsupported image format or dimensions"}}
  cfg,_,_:=image.DecodeConfig(bytes.NewReader(data))
  if strings.HasPrefix(a.Asset,"local-mtrl_")&&cfg.Width<=128&&cfg.Height<=128{sharpenPreview(pixels,pixelSide(len(pixels)))}
  if !cached {if e=os.WriteFile(cachePath,data,0600);e!=nil{return assetResult{Status:"failed",Detail:"cache write failed"}}}
  if a.ID==0{return assetResult{Status:"cached"}}
  b.mu.Lock();if b.textures==nil{b.textures=map[uint32][]uint32{}};b.textures[a.ID]=pixels;b.mu.Unlock()
  return assetResult{Status:"ready",Detail:fmt.Sprintf("source %dx%d -> atlas %dx%d",cfg.Width,cfg.Height,pixelSide(len(pixels)),pixelSide(len(pixels)))}
 }
 decoded:=data
 if bytes.HasPrefix(data,[]byte("version 7.00\n"))||bytes.HasPrefix(data,[]byte("version 6.00\n")){
  decoded,e=chunkMeshWithDecoder(data,func(chunk []byte)([]byte,error){return runDraco(l.ctx,dracoHelper(),chunk)})
  if e!=nil{return assetResult{Status:"failed",Detail:meshDiagnostic(data,e)}}
 }
 if bytes.HasPrefix(decoded,[]byte("version 1.00\n"))||bytes.HasPrefix(decoded,[]byte("version 1.01\n")){decoded,e=textMeshToV2(decoded);if e!=nil{return assetResult{Status:"failed",Detail:meshDiagnostic(data,e)}}}
 vs,size,e:=decodeLumenMesh(decoded);if e!=nil{return assetResult{Status:"failed",Detail:meshDiagnostic(data,e)}}
 uv:=decodeLumenUV(decoded,len(vs));ns:=decodeLumenNormals(decoded,len(vs),size);m:=MeshUpload{ID:a.ID,Vertices:vs,UVs:uv,Normals:ns};if !meshValid(m){return assetResult{Status:"failed",Detail:"invalid normalized mesh"}}
 b:=l.bridge;b.mu.Lock();defer b.mu.Unlock()
 if _,ok:=b.meshes[a.ID];ok||len(b.meshes)>=256||b.meshVertices+len(vs)>meshTotalVertices{return assetResult{Status:"failed",Detail:"mesh ID collision or cache full"}}
 if !cached {if e=os.WriteFile(cachePath,data,0600);e!=nil{return assetResult{Status:"failed",Detail:"cache write failed"}}};if b.meshes==nil{b.meshes=map[uint32][]V{}};if b.meshUV==nil{b.meshUV=map[uint32][]UV{}};b.meshUV[a.ID]=uv;if b.meshN==nil{b.meshN=map[uint32][]V{}};b.meshN[a.ID]=ns;b.meshes[a.ID]=vs;b.meshVertices+=len(vs)
 return assetResult{Status:"ready",Size:size}
}
// Decode FileMesh geometry; skin envelopes are skipped (bind pose only).
func decodeLumenMesh(data []byte)([]V,V,error){
 fail:=func()([]V,V,error){return nil,V{},fmt.Errorf("unsupported or malformed mesh")}
 i:=bytes.IndexByte(data,'\n');if i<0||i>20{return fail()}
 version:=strings.TrimSpace(string(data[:i]));d:=data[i+1:]
 if len(d)<12{return fail()}
 u16:=func(i int)int{return int(binary.LittleEndian.Uint16(d[i:]))}
 u32:=func(i int)int{return int(binary.LittleEndian.Uint32(d[i:]))}
 h:=u16(0);stride,faceStride,nv,nf,nlod,skin:=0,12,0,0,0,0
 if version=="version 6.00"||version=="version 7.00"{v,err:=chunkMeshToV2(data);if err!=nil{return nil,V{},err};return decodeLumenMesh(v)}
 if version=="version 1.00"||version=="version 1.01"{v,err:=textMeshToV2(data);if err!=nil{return nil,V{},err};return decodeLumenMesh(v)}
 switch version{
 case "version 2.00":if h!=12{return fail()};stride=int(d[2]);faceStride=int(d[3]);nv=u32(4);nf=u32(8)
 case "version 3.00","version 3.01":if h!=16||len(d)<16||u16(4)!=4{return fail()};stride=int(d[2]);faceStride=int(d[3]);nlod=u16(6);nv=u32(8);nf=u32(12)
 case "version 4.00","version 4.01","version 5.00":if len(d)<24||((version=="version 5.00"&&h!=32)||(version!="version 5.00"&&h!=24))||len(d)<h{return fail()};stride=40;nv=u32(4);nf=u32(8);nlod=u16(12);if u16(14)>0{skin=8}
 default:return fail()
 }
 if (stride!=36&&stride!=40)||faceStride!=12||nv<3||nv>200000||nf<1||nf>200000{return fail()}
 start:=h+nv*(stride+skin);lodStart:=start+nf*12;if lodStart+nlod*4>len(d){return fail()}
 count:=nf
 if nlod>0{if nlod<2||u32(lodStart)!=0||u32(lodStart+(nlod-1)*4)!=nf{return fail()};count=u32(lodStart+4);prev:=0;for j:=1;j<nlod;j++{v:=u32(lodStart+j*4);if v<=prev||v>nf{return fail()};prev=v}}
 if count<1||count>20000{return fail()}
 points:=make([]V,nv);lo:=V{math.Inf(1),math.Inf(1),math.Inf(1)};hi:=V{math.Inf(-1),math.Inf(-1),math.Inf(-1)}
 for j:=range points{for k:=0;k<3;k++{v:=float64(math.Float32frombits(binary.LittleEndian.Uint32(d[h+j*stride+k*4:])));if !finite(v){return fail()};points[j][k]=v;lo[k]=math.Min(lo[k],v);hi[k]=math.Max(hi[k],v)}}
 var size V;for k:=0;k<3;k++{size[k]=math.Max(hi[k]-lo[k],.0001)}
 out:=make([]V,0,count*3)
 for j:=0;j<count*3;j++{idx:=u32(start+j*4);if idx<0||idx>=nv{return fail()};v:=points[idx];for k:=0;k<3;k++{v[k]/=size[k]};out=append(out,v)}
 return out,size,nil
}

// Called only after decodeLumenMesh has validated header, LOD and indices.
func decodeLumenUV(data []byte,count int)[]UV{
 i:=bytes.IndexByte(data,'\n');if i<0{return nil};version:=strings.TrimSpace(string(data[:i]));d:=data[i+1:]
 if len(d)<12{return nil}
 h:=int(binary.LittleEndian.Uint16(d));stride:=int(d[2]);nv,skin:=0,0
 if version=="version 6.00"||version=="version 7.00"{v,e:=chunkMeshToV2(data);if e!=nil{return nil};return decodeLumenUV(v,count)}
 if version=="version 1.00"||version=="version 1.01"{v,e:=textMeshToV2(data);if e!=nil{return nil};return decodeLumenUV(v,count)}
 switch version{case "version 2.00":nv=int(binary.LittleEndian.Uint32(d[4:]));case "version 3.00","version 3.01":if len(d)<16{return nil};nv=int(binary.LittleEndian.Uint32(d[8:]));case "version 4.00","version 4.01","version 5.00":if len(d)<24{return nil};stride=40;nv=int(binary.LittleEndian.Uint32(d[4:]));if binary.LittleEndian.Uint16(d[14:])>0{skin=8};default:return nil}
 if h<12||stride<32||nv<3||nv>200000||count<3||count>60000{return nil}
 start:=h+nv*(stride+skin);if start+count*4>len(d){return nil}
 uv:=make([]UV,count)
 for j:=range uv{
  idx:=int(binary.LittleEndian.Uint32(d[start+j*4:]));if idx<0||idx>=nv{return nil}
  pos:=h+idx*stride+24
  u:=float64(math.Float32frombits(binary.LittleEndian.Uint32(d[pos:])))
  v:=float64(math.Float32frombits(binary.LittleEndian.Uint32(d[pos+4:])))
  uv[j]=UV{u,v};if !validUV(uv[j]){return nil}
 }
 return uv
}
