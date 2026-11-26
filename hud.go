package main
import("encoding/binary";"math";"net/http";"time";"github.com/gorilla/websocket")
type HUDItem struct {
 X float64 `json:"x"`; Y float64 `json:"y"`; W float64 `json:"w"`; H float64 `json:"h"`
 CX float64 `json:"cx"`; CY float64 `json:"cy"`; CW float64 `json:"cw"`; CH float64 `json:"ch"`
 Size float64 `json:"size"`; Border float64 `json:"border"`; Round float64 `json:"round"`
 BG uint32 `json:"bg"`; FG uint32 `json:"fg"`; BC uint32 `json:"bc"`
 AX uint32 `json:"ax"`; AY uint32 `json:"ay"`; Text string `json:"text"`
}
type PointerEvent struct { X float64 `json:"x"`; Y float64 `json:"y"`; Button int `json:"button"`; Down bool `json:"down"` }
func validPointer(a []PointerEvent)bool{if len(a)>64{return false};for _,v:=range a{if !finite(v.X)||!finite(v.Y)||v.X<0||v.X>1||v.Y<0||v.Y>1||v.Button<0||v.Button>3{return false}};return true}
func validHUD(a []HUDItem)bool{if len(a)>256{return false};for _,v:=range a{for _,n:=range []float64{v.X,v.Y,v.W,v.H,v.CX,v.CY,v.CW,v.CH,v.Size,v.Border,v.Round}{if !finite(n)||math.Abs(n)>16{return false}};if len(v.Text)>1024||v.W<0||v.H<0||v.CW<0||v.CH<0||v.Size<0||v.Border<0||v.Round<0||v.AX>2||v.AY>2{return false}};return true}
func hudPacket(a []HUDItem)[]byte{
 b:=[]byte("LGH1");put:=func(v uint32){b=binary.LittleEndian.AppendUint32(b,v)};put(uint32(len(a)))
 for _,v:=range a{for _,n:=range []float64{v.X,v.Y,v.W,v.H,v.CX,v.CY,v.CW,v.CH,v.Size,v.Border,v.Round}{put(math.Float32bits(float32(n)))};for _,n:=range []uint32{v.BG,v.FG,v.BC,v.AX,v.AY,uint32(len(v.Text))}{put(n)};b=append(b,v.Text...)};return b
}
func(b *Bridge)hudStream(w http.ResponseWriter,r *http.Request){
 c,err:=localUpgrade.Upgrade(w,r,nil);if err!=nil{return};defer c.Close()
 tick:=time.NewTicker(100*time.Millisecond);defer tick.Stop();last:=^uint64(0);sent:=time.Time{}
 for range tick.C{b.mu.RLock();a,rev,received:=b.hud,b.hudRevision,b.state.Received;b.mu.RUnlock()
 if time.Now().UnixMilli()-received>1500{a=nil;rev=^uint64(0)-1}
 if rev==last&&time.Since(sent)<400*time.Millisecond{continue};c.SetWriteDeadline(time.Now().Add(time.Second));if c.WriteMessage(websocket.BinaryMessage,hudPacket(a))!=nil{return};last=rev;sent=time.Now()}
}

type KeyEvent struct { VK int `json:"vk"`; Down bool `json:"down"`; Repeat bool `json:"repeat,omitempty"` }
func validKeys(a []KeyEvent)bool{if len(a)>128{return false};for _,e:=range a{if e.VK<1||e.VK>255{return false}};return true}
