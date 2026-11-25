package main

import (
 "encoding/json"
 "log"
 "math"
 "net/http"
 "time"
 "github.com/gorilla/websocket"
)
var localUpgrade=websocket.Upgrader{CheckOrigin:func(r *http.Request)bool{return r.Header.Get("Origin")==""}}
func validControl(c Control)bool{
 return finite(c.X)&&finite(c.Z)&&finite(c.DX)&&finite(c.DY)&&math.Abs(c.X)<=1&&math.Abs(c.Z)<=1&&math.Abs(c.DX)<=2000&&math.Abs(c.DY)<=2000&&finite(c.Distance)&&finite(c.Sensitivity)&&finite(c.Fov)&&c.Distance>=0&&c.Distance<=40&&c.Sensitivity>=0&&c.Sensitivity<=5&&c.Fov>=0&&c.Fov<=120
}
func(b *Bridge)storeControl(c Control){
 b.mu.Lock();defer b.mu.Unlock()
 if c.Active {if b.control.Active&&time.Since(b.controlAt)<500*time.Millisecond{c.DX=math.Max(-2000,math.Min(2000,c.DX+b.control.DX));c.DY=math.Max(-2000,math.Min(2000,c.DY+b.control.DY));c.Jump=c.Jump||b.control.Jump}}else{c=Control{}}
 b.control=c;b.controlAt=time.Now()
}
func(b *Bridge)stream(w http.ResponseWriter,r *http.Request){b.studioStream(w,r,false)}
func(b *Bridge)geometryStream(w http.ResponseWriter,r *http.Request){b.studioStream(w,r,true)}
func(b *Bridge)studioStream(w http.ResponseWriter,r *http.Request,geometry bool){
 c,err:=localUpgrade.Upgrade(w,r,nil);if err!=nil{return};defer c.Close()
 c.SetReadLimit(32<<20);log.Println("Studio WebSocket connected; geometry:",geometry)
 for{
  c.SetReadDeadline(time.Now().Add(8*time.Second));kind,data,err:=c.ReadMessage();if err!=nil{return};if kind!=websocket.TextMessage{continue}
  var u Update
  c.SetWriteDeadline(time.Now().Add(2*time.Second))
  if json.Unmarshal(data,&u)!=nil||!valid(u){if c.WriteJSON(map[string]string{"error":"invalid scene update"})!=nil{return};continue}
  ctrl:=b.applyMode(u,!geometry,geometry)
  if c.WriteJSON(ctrl)!=nil{return}
 }
}
// Native view and geometry have independent streams; slow mesh/scene transfers
// cannot queue camera packets. Coalesce revisions and send a periodic heartbeat.
func(b *Bridge)nativeStream(w http.ResponseWriter,r *http.Request,geometry bool){
 c,err:=localUpgrade.Upgrade(w,r,nil);if err!=nil{return};defer c.Close()
 tick:=time.NewTicker(8*time.Millisecond);defer tick.Stop()
 last:=^uint64(0);lastSend:=time.Time{}
 for range tick.C{
  b.mu.RLock();s:=b.state;b.mu.RUnlock()
  rev:=s.Seq;if geometry{rev=s.Scene}
  changed:=rev!=last
  if !changed&&time.Since(lastSend)<250*time.Millisecond{continue}
  if !geometry||!changed{s.Parts=nil}
  c.SetWriteDeadline(time.Now().Add(time.Second))
  if c.WriteMessage(websocket.BinaryMessage,nativePacket(s))!=nil{return}
  last=rev;lastSend=time.Now()
 }
}
func(b *Bridge)inputStream(w http.ResponseWriter,r *http.Request){
 c,err:=localUpgrade.Upgrade(w,r,nil);if err!=nil{return};defer c.Close()
 c.SetReadLimit(4096)
 for{
  c.SetReadDeadline(time.Now().Add(time.Second));kind,data,err:=c.ReadMessage();if err!=nil{return};if kind!=websocket.TextMessage{continue}
  var v Control;if json.Unmarshal(data,&v)!=nil||!validControl(v){return};b.storeControl(v)
 }
}
