package main
import("net/http";"testing";"net/http/httptest";"strings";"github.com/gorilla/websocket")
func TestStudioStream(t *testing.T){
 b:= &Bridge{}
 // httptest uses another port; test websocket endpoint directly, not host filter.
 s:=httptest.NewServer(http.HandlerFunc(b.stream));defer s.Close()
 c,_,err:=websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(s.URL,"http"),nil);if err!=nil{t.Fatal(err)};defer c.Close()
 u:=Update{Camera:Camera{R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70},Sun:V{0,1,0}}
 if err=c.WriteJSON(u);err!=nil{t.Fatal(err)}
 var ctrl Control;if err=c.ReadJSON(&ctrl);err!=nil{t.Fatal(err)}
 b.mu.RLock();defer b.mu.RUnlock();if b.state.Seq!=1{t.Fatal("update missing")}
}
