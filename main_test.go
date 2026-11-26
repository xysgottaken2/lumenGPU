package main

import (
	"encoding/binary"
	"encoding/json"
	"math"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestBridge(t *testing.T) {
	b := &Bridge{}
	h := b.handler()
	call := func(method, path, body, host, origin string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "http://"+addr+path, strings.NewReader(body))
		r.Host = host
		if origin != "" {
			r.Header.Set("Origin", origin)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	cam := Camera{P: V{0, 2, 6}, R: V{1, 0, 0}, U: V{0, 1, 0}, F: V{0, 0, -1}, Fov: 70}
	parts := []Part{{R: V{1, 0, 0}, U: V{0, 1, 0}, B: V{0, 0, 1}, S: V{2, 2, 2}, C: V{1, 0, 0}}}
	u := Update{Camera: cam, Sun: V{0, 1, 0}, Parts: &parts}
	data, _ := json.Marshal(u)
	if w := call("POST", "/api/update", string(data), addr, ""); w.Code != 204 {
		t.Fatalf("update %d %s", w.Code, w.Body.String())
	}
	u.Parts = nil
	u.Camera.P[0] = 2
	data, _ = json.Marshal(u)
	if w := call("POST", "/api/update", string(data), addr, ""); w.Code != 204 {
		t.Fatal(w.Code)
	}
	w := call("GET", "/api/state", "", addr, "")
	var s State
	if json.Unmarshal(w.Body.Bytes(), &s) != nil || s.Seq != 2 || s.Scene != 1 || len(s.Parts) != 1 || s.Camera.P[0] != 2 {
		t.Fatal(w.Body.String())
	}
	if call("POST", "/api/update", "{}", addr, "").Code != 400 {
		t.Fatal("bad input accepted")
	}
	if call("POST", "/api/update", string(data), addr, "https://elsewhere.test").Code != 403 {
		t.Fatal("origin accepted")
	}
	if call("GET", "/api/state", "", "elsewhere.test", "").Code != 403 {
		t.Fatal("host accepted")
	}
	packet := call("GET", "/api/native", "", addr, "").Body.Bytes()
	if len(packet) != 88+112 || string(packet[:4]) != "LGR4" || binary.LittleEndian.Uint64(packet[4:12]) != 1 || binary.LittleEndian.Uint64(packet[12:20]) != 2 || binary.LittleEndian.Uint32(packet[20:24]) != 1 || math.Float32frombits(binary.LittleEndian.Uint32(packet[24:28])) != 2 {
		t.Fatal("native packet mismatch")
	}
	if call("GET", "/api/native", "", addr, "https://elsewhere.test").Code != 403 {
		t.Fatal("origin accepted")
	}
	if call("POST","/api/input",`{"active":true,"x":1,"z":-1,"dx":3,"dy":4,"jump":true}`,addr,"").Code!=204 {t.Fatal("control post failed")}
 if call("POST","/api/input",`{"active":true,"x":2}`,addr,"").Code!=400 {t.Fatal("invalid control accepted")}
 w=call("POST","/api/update-controls",string(data),addr,"");var ctrl Control;if json.Unmarshal(w.Body.Bytes(),&ctrl)!=nil||!ctrl.Active||ctrl.X!=1||ctrl.DX!=3||!ctrl.Jump {t.Fatal("control response",w.Body.String())}
 w=call("POST","/api/update?controls=1",string(data),addr,"");if json.Unmarshal(w.Body.Bytes(),&ctrl)!=nil||ctrl.DX!=0||ctrl.Jump {t.Fatal("control not consumed",w.Body.String())}
 if call("POST","/api/input",`{"active":false}`,addr,"").Code!=204 {t.Fatal("release failed")}
 w=call("POST","/api/update?controls=1",string(data),addr,"");if json.Unmarshal(w.Body.Bytes(),&ctrl)!=nil||ctrl.Active {t.Fatal("control not released")}
 if call("GET", "/", "", addr, "").Code != 404 {
		t.Fatal("unexpected web frontend")
	}
}

func TestAvatarUpdates(t *testing.T) {
 b:= &Bridge{}; h:=b.handler()
 cam:=Camera{R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70}
 part:=Part{R:V{1,0,0},U:V{0,1,0},B:V{0,0,1},S:V{1,1,1},C:V{1,1,1}}
 world:=[]Part{part}; avatar:=[]Part{part}
 u:=Update{Camera:cam,Sun:V{0,1,0},Parts:&world,Avatar:&avatar}
 send:=func(){data,_:=json.Marshal(u);r:=httptest.NewRequest("POST","http://"+addr+"/api/update-controls",strings.NewReader(string(data)));w:=httptest.NewRecorder();h.ServeHTTP(w,r);if w.Code!=200 {t.Fatal(w.Code,w.Body.String())}}
 send();if len(b.state.Parts)!=2||b.state.Scene!=1 {t.Fatal("initial avatar")}
 u.Parts=nil; avatar[0].P[0]=3;send();if len(b.state.Parts)!=2||b.state.Parts[0].P[0]!=0||b.state.Parts[1].P[0]!=3||b.state.Scene!=2 {t.Fatal("avatar motion")}
 send();if b.state.Scene!=2 {t.Fatal("unchanged avatar rebuilt")}
 avatar=[]Part{};send();if len(b.state.Parts)!=1||b.state.Scene!=3 {t.Fatal("avatar removal")}
}

func TestFullRangeMeshIDs(t *testing.T){
 b:=&Bridge{}
 cam:=Camera{R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70}
 part:=Part{R:V{1,0,0},U:V{0,1,0},B:V{0,0,1},S:V{1,1,1},C:V{1,1,1}}
 world,moving,character:=[]Part{part},[]Part{part},[]Part{part}
 u:=Update{Camera:cam,Sun:V{0,1,0},Parts:&world,Avatar:&moving,Character:&character}
 post:=func(path string)int{data,_:=json.Marshal(u);w:=httptest.NewRecorder();b.handler().ServeHTTP(w,httptest.NewRequest("POST","http://"+addr+path,strings.NewReader(string(data))));return w.Code}
 for _,id:=range []float64{-6,-5,0,3,9999999,10000000,12345678,16777215}{
  world[0].Shape=id;moving[0].Shape=id;character[0].Shape=id
  if !valid(u)||post("/api/geometry-update")!=204||post("/api/update-controls")!=200{t.Fatalf("rejected valid shape %v: %s",id,updateError(u))}
 }
 for _,id:=range []float64{-7,3.5,16777216,math.Inf(1),math.NaN()}{
  world[0].Shape=id;if valid(u){t.Fatalf("accepted invalid shape %v",id)}
 }
 world[0].Shape=16777215;world[0].P[0]=1e7
 if valid(u){t.Fatal("coordinate bound relaxed")}
}
