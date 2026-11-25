package main
import("testing";"net/http";"net/http/httptest";"strings";"encoding/binary";"time";"github.com/gorilla/websocket")
func TestGeometryDoesNotOverwriteCamera(t *testing.T){
 b:=&Bridge{};cam:=Camera{P:V{1,2,3},R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70};u:=Update{Camera:cam,Sun:V{0,1,0}}
 b.apply(u,true);u.Camera.P[0]=99;rows:=[]Part{{S:V{1,1,1}}};u.Parts=&rows;b.applyMode(u,false,true)
 if b.state.Camera.P[0]!=1||b.state.Seq!=1||b.state.Scene!=1||len(b.state.Parts)!=1{t.Fatal("geometry changed camera")}
}
func TestNativeStreams(t *testing.T){
 b:=&Bridge{};b.state=State{Seq:7,Scene:8,Parts:[]Part{{S:V{1,1,1}}}}
 for _,geometry:=range []bool{false,true}{
  s:=httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){b.nativeStream(w,r,geometry)}))
  c,_,err:=websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(s.URL,"http"),nil);if err!=nil{s.Close();t.Fatal(err)}
  c.SetReadDeadline(time.Now().Add(time.Second));kind,p,err:=c.ReadMessage()
  if err!=nil||kind!=websocket.BinaryMessage||len(p)<88{c.Close();s.Close();t.Fatal("bad frame",err)}
  want:=uint32(0);if geometry{want=1};if binary.LittleEndian.Uint32(p[20:24])!=want{t.Fatal("wrong geometry count")}
  c.Close();s.Close()
 }
}
