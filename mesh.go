package main

import (
 "encoding/binary"
 "encoding/json"
 "io"
 "math"
 "net/http"
 "strconv"
)
const meshMaxVertices=60000
const meshTotalVertices=1500000
type MeshUpload struct { ID uint32 `json:"id"`; Vertices []V `json:"vertices"`; UVs []UV `json:"uvs,omitempty"`; Normals []V `json:"normals,omitempty"` }
func meshID(id uint32) bool {return id>=3&&id<=16777215}
func meshValid(m MeshUpload) bool {
 if !meshID(m.ID)||len(m.Vertices)<3||len(m.Vertices)>meshMaxVertices||len(m.Vertices)%3!=0{return false}
 for _,v:=range m.Vertices {if !vec(v)||math.Abs(v[0])>100||math.Abs(v[1])>100||math.Abs(v[2])>100{return false}}
 if len(m.UVs)!=0&&len(m.UVs)!=len(m.Vertices){return false};for _,uv:=range m.UVs{if !validUV(uv){return false}}
 if len(m.Normals)!=0&&len(m.Normals)!=len(m.Vertices){return false};for _,n:=range m.Normals{if !vec(n)||norm(n)>1.01{return false}}
 return true
}
func meshPacket(vs []V) []byte {
 out:=make([]byte,8+len(vs)*12);copy(out,"LGM1");binary.LittleEndian.PutUint32(out[4:],uint32(len(vs)))
 at:=8;for _,v:=range vs{for _,x:=range v{binary.LittleEndian.PutUint32(out[at:],math.Float32bits(float32(x)));at+=4}}
 return out
}
func texturedMeshPacket(vs []V,uv []UV)[]byte{
 out:=meshPacket(vs);if len(uv)!=len(vs){return out};copy(out,"LGM2")
 for _,v:=range uv{for _,x:=range v{out=binary.LittleEndian.AppendUint32(out,math.Float32bits(float32(x)))}}
 return out
}
func normalMeshPacket(vs []V,uv []UV,ns []V)[]byte{
 if len(ns)!=len(vs){return texturedMeshPacket(vs,uv)}
 if len(uv)!=len(vs){uv=make([]UV,len(vs))}
 out:=texturedMeshPacket(vs,uv);copy(out,"LGM3")
 for _,n:=range ns{for _,x:=range n{out=binary.LittleEndian.AppendUint32(out,math.Float32bits(float32(x)))}}
 return out
}
func (b *Bridge) meshHandler(w http.ResponseWriter,r *http.Request){
 if r.Header.Get("Origin")!=""{http.Error(w,"local mesh only",403);return}
 switch r.Method {
 case "POST":
  var m MeshUpload;d:=json.NewDecoder(http.MaxBytesReader(w,r.Body,8<<20))
  if d.Decode(&m)!=nil||d.Decode(new(any))!=io.EOF||!meshValid(m){http.Error(w,"invalid mesh",400);return}
  b.mu.Lock();defer b.mu.Unlock()
  if old,ok:=b.meshes[m.ID];ok{
   if len(old)!=len(m.Vertices){http.Error(w,"mesh ID collision",409);return}
   for i:=range old{if old[i]!=m.Vertices[i]{http.Error(w,"mesh ID collision",409);return}}
   oldUV:=b.meshUV[m.ID];if len(oldUV)!=len(m.UVs){http.Error(w,"mesh UV collision",409);return};for i:=range oldUV{if oldUV[i]!=m.UVs[i]{http.Error(w,"mesh UV collision",409);return}}
   oldN:=b.meshN[m.ID];if len(oldN)!=len(m.Normals){http.Error(w,"mesh normal collision",409);return};for i:=range oldN{if oldN[i]!=m.Normals[i]{http.Error(w,"mesh normal collision",409);return}}
   w.WriteHeader(204);return
  }
  if len(b.meshes)>=256||b.meshVertices+len(m.Vertices)>meshTotalVertices{http.Error(w,"mesh cache full",413);return}
  if b.meshes==nil{b.meshes=make(map[uint32][]V)}
  if b.meshUV==nil{b.meshUV=map[uint32][]UV{}};b.meshUV[m.ID]=m.UVs;if b.meshN==nil{b.meshN=map[uint32][]V{}};b.meshN[m.ID]=m.Normals;b.meshes[m.ID]=m.Vertices;b.meshVertices+=len(m.Vertices);w.WriteHeader(204)
 case "GET":
  id,err:=strconv.ParseUint(r.URL.Query().Get("id"),10,32);if err!=nil||!meshID(uint32(id)){http.Error(w,"invalid id",400);return}
  b.mu.RLock();vs,ok:=b.meshes[uint32(id)];uv:=b.meshUV[uint32(id)];ns:=b.meshN[uint32(id)];b.mu.RUnlock()
  if !ok{http.NotFound(w,r);return}
  w.Header().Set("Content-Type","application/octet-stream");w.Header().Set("Cache-Control","no-store");w.Write(normalMeshPacket(vs,uv,ns))
 default:http.Error(w,"method",405)
 }
}
