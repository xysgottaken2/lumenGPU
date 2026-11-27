package main
import("testing";"encoding/binary";"math";"net/http/httptest";"net/http";"strings";"time";"github.com/gorilla/websocket")
func TestSkyPacket(t *testing.T){
 e:=Environment{Clock:12,SunSize:11,Brightness:2,Celestial:true,FirstPerson:true,SkySlots:[6]uint32{1,2,3,4,5,6},SkyBasis:[9]float64{1,0,0,0,1,0,0,0,1}}
 if !validSky(e){t.Fatal("valid cubemap rejected")};p:=nativeEnvironmentPacket(State{Environment:&e})
 if len(p)!=168||string(p[:4])!="LGR7"||binary.LittleEndian.Uint32(p[104:])!=1||binary.LittleEndian.Uint32(p[128:])!=6||math.Float32frombits(binary.LittleEndian.Uint32(p[132:]))!=1{t.Fatal("sky wire")}
 e.SkySlots[0]=129;if validSky(e){t.Fatal("invalid slot")};e.SkySlots[0]=1;e.SkyBasis[0]=2;if validSky(e){t.Fatal("invalid basis")}
}
func TestIndependentPose(t *testing.T){
 b:=&Bridge{};cam:=Camera{R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70};u:=Update{Camera:cam,Sun:V{0,1,0}}
 b.apply(u,true);part:=Part{R:V{1,0,0},U:V{0,1,0},B:V{0,0,1},S:V{1,1,1},C:V{1,1,1}}
 rows:=[]Part{part};pose:=PoseUpdate{Character:&rows};if poseError(pose)!=""{t.Fatal(poseError(pose))}
 b.applyPose(pose);if b.state.Seq!=1||b.characterRevision!=1||b.worldRevision!=0{t.Fatal("pose modified camera/world")}
 s:=httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){b.nativeSplitStream(w,r,0)}));defer s.Close()
 c,_,err:=websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(s.URL,"http"),nil);if err!=nil{t.Fatal(err)};defer c.Close();c.SetReadDeadline(time.Now().Add(2*time.Second))
 read:=func(want uint32){_,p,e:=c.ReadMessage();if e!=nil||binary.LittleEndian.Uint32(p[20:])!=want{t.Fatalf("pose packet count %d: %v",want,e)}}
 read(1);u.Camera.P[0]=1;b.apply(u,true);read(0)
 rows=[]Part{part};rows[0].P[0]=2;b.applyPose(PoseUpdate{Character:&rows});read(1)
 if b.state.Seq!=2||b.characterRevision!=2{t.Fatal("pose changed view sequence")}
}
