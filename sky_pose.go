package main
import("encoding/json";"io";"net/http";"slices";"time";"math";"github.com/gorilla/websocket")
func validSky(e Environment)bool{
 active:=false
 for _,slot:=range e.SkySlots{if slot>textureMax{return false};if slot>0{active=true}}
 for _,v:=range e.SkyBasis{if !finite(v)||math.Abs(v)>1.01{return false}}
 if !active{return e.SkyBasis==[9]float64{}}
 for i:=0;i<9;i+=3{if !axis(V{e.SkyBasis[i],e.SkyBasis[i+1],e.SkyBasis[i+2]}){return false}}
 for i:=0;i<3;i++{for j:=i+1;j<3;j++{dot:=0.;for k:=0;k<3;k++{dot+=e.SkyBasis[i*3+k]*e.SkyBasis[j*3+k]};if math.Abs(dot)>.03{return false}}}
 return true
}
type PoseUpdate struct{Character *[]Part}
func poseError(p PoseUpdate)string{
 if p.Character==nil{return "missing character pose"}
 return updateError(Update{Camera:Camera{R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70},Sun:V{0,1,0},Character:p.Character})
}
func(b *Bridge) applyPose(p PoseUpdate){
 b.mu.Lock();defer b.mu.Unlock()
 if p.Character!=nil&&!slices.Equal(b.characterParts,*p.Character){b.characterParts=*p.Character;b.characterRevision++}
}
func(b *Bridge)poseHTTP(w http.ResponseWriter,r *http.Request){
 if r.Method!="POST"||r.Header.Get("Origin")!=""{http.Error(w,"local pose POST only",403);return}
 var p PoseUpdate;d:=json.NewDecoder(http.MaxBytesReader(w,r.Body,256<<10))
 if d.Decode(&p)!=nil||d.Decode(new(any))!=io.EOF{http.Error(w,"invalid pose JSON",400);return}
 if why:=poseError(p);why!=""{http.Error(w,why,400);return};b.applyPose(p);w.WriteHeader(204)
}
func(b *Bridge)poseStream(w http.ResponseWriter,r *http.Request){
 c,err:=localUpgrade.Upgrade(w,r,nil);if err!=nil{return};defer c.Close();c.SetReadLimit(256<<10)
 for{
  c.SetReadDeadline(time.Now().Add(8*time.Second));kind,data,err:=c.ReadMessage();if err!=nil{return};if kind!=websocket.TextMessage{continue}
  var p PoseUpdate;why:="";if json.Unmarshal(data,&p)!=nil{why="invalid pose JSON"}else{why=poseError(p)}
  c.SetWriteDeadline(time.Now().Add(2*time.Second))
  if why!=""{if c.WriteJSON(map[string]string{"error":why})!=nil{return};continue}
  b.applyPose(p);if c.WriteJSON(struct{}{})!=nil{return}
 }
}
