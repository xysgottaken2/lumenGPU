package main
import("testing";"encoding/binary";"net/http";"net/http/httptest";"strings";"time";"github.com/gorilla/websocket")
func TestPoseIsolation(t *testing.T){
 b:=&Bridge{};cam:=Camera{P:V{1,2,3},R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70}
 world:=[]Part{{S:V{1,1,1}}};moving:=[]Part{{P:V{4,0,0},S:V{1,1,1}}};pose:=[]Part{{P:V{1,0,0},S:V{1,1,1}}}
 b.applyMode(Update{Camera:cam,Sun:V{0,1,0},Parts:&world,Avatar:&moving},false,true)
 b.apply(Update{Camera:cam,Sun:V{0,1,0},Character:&pose},true)
 before:=b.state.Scene
 cam.P[0]=2;pose=[]Part{{P:V{2,0,0},S:V{1,1,1}}};b.apply(Update{Camera:cam,Sun:V{0,1,0},Character:&pose},true)
 s,k:=b.splitState(0);if k!=2||s.Camera.P[0]!=2||len(s.Parts)!=1||s.Parts[0].P[0]!=2||s.Scene!=2{t.Fatal("unpaired pose")}
 if b.state.Scene!=before||b.worldRevision!=1||b.movingRevision!=1{t.Fatal("pose invalidated world")}
 old:=[]Part{{P:V{99,0,0}}};b.applyMode(Update{Camera:Camera{},Character:&old},false,true)
 s,_=b.splitState(0);if s.Camera.P[0]!=2||s.Parts[0].P[0]!=2{t.Fatal("geometry overwrote pose")}
 ws,_:=b.splitState(1);ms,_:=b.splitState(2);if len(ws.Parts)!=1||len(ms.Parts)!=1||ms.Parts[0].P[0]!=4{t.Fatal("channels mixed")}
 empty:=[]Part{};b.apply(Update{Camera:cam,Sun:V{0,1,0},Character:&empty},true);s,_=b.splitState(0);if len(s.Parts)!=0||s.Scene!=3{t.Fatal("avatar removal")}
}
func TestPoseStreamPacket(t *testing.T){
 b:=&Bridge{};cam:=Camera{P:V{8,2,3},R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70};pose:=[]Part{{P:V{8,0,0}}}
 b.apply(Update{Camera:cam,Sun:V{0,1,0},Character:&pose},true)
 s:=httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){b.nativeSplitStream(w,r,0)}));defer s.Close()
 c,_,err:=websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(s.URL,"http"),nil);if err!=nil{t.Fatal(err)};defer c.Close()
 c.SetReadDeadline(time.Now().Add(time.Second));kind,p,err:=c.ReadMessage()
 if err!=nil||kind!=websocket.BinaryMessage||len(p)!=200||binary.LittleEndian.Uint32(p[20:24])!=1||binary.LittleEndian.Uint32(p[24:28])!=binary.LittleEndian.Uint32(p[88:92]){t.Fatal("pose wire mismatch",err)}
}
