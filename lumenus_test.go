package main

import (
 "encoding/binary"
 "encoding/json"
 "math"
 "net/http/httptest"
 "net/url"
 "os"
 "path/filepath"
 "strings"
 "testing"
 "time"
)
func fixtureMesh() []byte {
 prefix:=[]byte("version 2.00\n")
 d:=make([]byte,12+36*3+12)
 binary.LittleEndian.PutUint16(d,12);d[2]=36;d[3]=12
 binary.LittleEndian.PutUint32(d[4:],3);binary.LittleEndian.PutUint32(d[8:],1)
 for i,v:=range []V{{-1,-2,0},{1,-2,0},{0,2,0}} {
  for k,x:=range v{binary.LittleEndian.PutUint32(d[12+i*36+k*4:],math.Float32bits(float32(x)))}
 }
 for i:=0;i<3;i++{binary.LittleEndian.PutUint32(d[12+36*3+i*4:],uint32(i))}
 return append(prefix,d...)
}
func TestLumenusDecodeMesh(t *testing.T){
 d:=fixtureMesh();vs,size,e:=decodeLumenMesh(d)
 if e!=nil||len(vs)!=3||size[0]!=2||size[1]!=4||vs[0][0]!=-.5||vs[0][1]!=-.5{t.Fatalf("unexpected mesh %v %v %v",vs,size,e)}
 for i:=0;i<len(d);i++{if _,_,e:=decodeLumenMesh(d[:i]);e==nil{t.Fatalf("truncated mesh accepted: %d",i)}}
 d[len(d)-1]=255;if _,_,e:=decodeLumenMesh(d);e==nil{t.Fatal("bad index accepted")}
}
func TestLumenusAssetIDs(t *testing.T){
 for _,a:=range []string{"../a","01","0","1/2","https://test","18446744073709551616"}{if _,ok:=assetKey(assetRequest{Asset:a,Kind:"mesh",ID:3});ok{t.Fatal(a)}}
 if _,ok:=assetKey(assetRequest{Asset:"123456789012345",Kind:"mesh",ID:3});!ok{t.Fatal("valid asset rejected")}
 for _,s:=range []string{"https://rbxcdn.com.bad.example/x","http://rbxcdn.com/x","https://user@rbxcdn.com/x","https://rbxcdn.com:1234/x"}{u,_:=url.Parse(s);if cdnURL(u){t.Fatal(s)}}
 u,_:=url.Parse("https://sc2.rbxcdn.com/asset");if !cdnURL(u){t.Fatal("valid CDN rejected")}
}
func TestLumenusSession(t *testing.T){
 t.Setenv("LUMEN_ASSET_API_KEY","")
 root:=t.TempDir();imports:=filepath.Join(root,"AssetImports");if e:=os.MkdirAll(imports,0700);e!=nil{t.Fatal(e)}
 if e:=os.WriteFile(filepath.Join(imports,"42.mesh"),fixtureMesh(),0600);e!=nil{t.Fatal(e)}
 b:=&Bridge{};l,e:=newLumenus(b,filepath.Join(root,"TempAssets"));if e!=nil{t.Fatal(e)}
 defer l.close()
 b.lumenus=l
 poll:=func()assetResult{
  r:=httptest.NewRequest("POST","http://"+addr+"/api/lumenus",strings.NewReader("{\"asset\":\"42\",\"kind\":\"mesh\",\"id\":3}"))
  w:=httptest.NewRecorder();b.handler().ServeHTTP(w,r);if w.Code!=200{t.Fatalf("status %d %s",w.Code,w.Body.String())}
  var res assetResult;if e:=json.Unmarshal(w.Body.Bytes(),&res);e!=nil{t.Fatal(e)};return res
 }
 deadline:=time.Now().Add(3*time.Second)
 for {res:=poll();if res.Status=="ready"{break};if res.Status!="queued"||time.Now().After(deadline){t.Fatal(res)};time.Sleep(10*time.Millisecond)}
 if poll().Status!="ready"{t.Fatal("cache miss")}
 b.mu.RLock();n:=b.meshVertices;b.mu.RUnlock();if n!=3{t.Fatalf("mesh not published: %d",n)}
 l.close();if _,e:=os.Stat(l.dir);!os.IsNotExist(e){t.Fatal("session directory not removed")}
 if _,e:=os.Stat(filepath.Join(imports,"42.mesh"));e!=nil{t.Fatal("original import removed")}
}
