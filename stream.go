package main

import (
 "encoding/json"
 "log"
 "net/http"
 "time"
 "github.com/gorilla/websocket"
)

// Studio only: loopback WebSocket. No browser cross-origin access.
func (b *Bridge) stream(w http.ResponseWriter,r *http.Request) {
 up:=websocket.Upgrader{CheckOrigin:func(r *http.Request)bool{return r.Header.Get("Origin")==""}}
 c,err:=up.Upgrade(w,r,nil);if err!=nil{return}
 defer c.Close()
 c.SetReadLimit(32<<20)
 log.Println("Studio WebSocket connected")
 defer log.Println("Studio WebSocket closed")
 for {
  c.SetReadDeadline(time.Now().Add(8*time.Second))
  kind,data,err:=c.ReadMessage();if err!=nil{return}
  if kind!=websocket.TextMessage{continue}
  var u Update
  if json.Unmarshal(data,&u)!=nil || !valid(u) {c.SetWriteDeadline(time.Now().Add(time.Second));c.WriteJSON(map[string]string{"error":"invalid scene update"});continue}
  ctrl:=b.apply(u,true)
  c.SetWriteDeadline(time.Now().Add(2*time.Second))
  if c.WriteJSON(ctrl)!=nil{return}
 }
}
