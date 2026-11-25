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
	if len(packet) != 88+84 || string(packet[:4]) != "LGR2" || binary.LittleEndian.Uint64(packet[4:12]) != 1 || binary.LittleEndian.Uint64(packet[12:20]) != 2 || binary.LittleEndian.Uint32(packet[20:24]) != 1 || math.Float32frombits(binary.LittleEndian.Uint32(packet[24:28])) != 2 {
		t.Fatal("native packet mismatch")
	}
	if call("GET", "/api/native", "", addr, "https://elsewhere.test").Code != 403 {
		t.Fatal("origin accepted")
	}
	if call("GET", "/", "", addr, "").Code != 404 {
		t.Fatal("unexpected web frontend")
	}
}
