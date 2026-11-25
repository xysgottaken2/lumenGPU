package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net"
	"net/http"
	"sync"
	"time"
)

const addr = "127.0.0.1:8765"

type V [3]float64
type Camera struct {
	P   V       `json:"p"`
	R   V       `json:"r"`
	U   V       `json:"u"`
	F   V       `json:"f"`
	Fov float64 `json:"fov"`
}
type Part struct {
	P     V       `json:"p"`
	R     V       `json:"r"`
	U     V       `json:"u"`
	B     V       `json:"b"`
	S     V       `json:"s"`
	C     V       `json:"c"`
	Metal float64 `json:"metal"`
	Rough float64 `json:"rough"`
	Emit  float64 `json:"emit"`
}
type Update struct {
	Camera Camera  `json:"camera"`
	Sun    V       `json:"sun"`
	Parts  *[]Part `json:"parts,omitempty"`
}
type State struct {
	Camera   Camera `json:"camera"`
	Sun      V      `json:"sun"`
	Parts    []Part `json:"parts"`
	Scene    uint64 `json:"scene"`
	Seq      uint64 `json:"seq"`
	Received int64  `json:"received"`
}
type Control struct {
 Active bool `json:"active"`
 X float64 `json:"x"`
 Z float64 `json:"z"`
 DX float64 `json:"dx"`
 DY float64 `json:"dy"`
 Jump bool `json:"jump"`
}
type Bridge struct {
	mu sync.RWMutex
	state State
 control Control
 controlAt time.Time
}

func finite(x float64) bool { return !math.IsNaN(x) && !math.IsInf(x, 0) && math.Abs(x) < 1e7 }
func vec(v V) bool          { return finite(v[0]) && finite(v[1]) && finite(v[2]) }
func norm(v V) float64      { return math.Sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]) }
func axis(v V) bool         { return vec(v) && math.Abs(norm(v)-1) < .03 }
func valid(u Update) bool {
	c := u.Camera
	if !vec(c.P) || !axis(c.R) || !axis(c.U) || !axis(c.F) || !finite(c.Fov) || c.Fov < 5 || c.Fov > 120 || !axis(u.Sun) {
		return false
	}
	if u.Parts != nil {
		if len(*u.Parts) > 1024 {
			return false
		}
		for _, p := range *u.Parts {
			if !vec(p.P) || !axis(p.R) || !axis(p.U) || !axis(p.B) || !vec(p.S) || !vec(p.C) || !finite(p.Metal) || !finite(p.Rough) || !finite(p.Emit) {
				return false
			}
			for i := 0; i < 3; i++ {
				if p.S[i] <= 0 || p.S[i] > 1e5 || p.C[i] < 0 || p.C[i] > 1 {
					return false
				}
			}
			if p.Metal < 0 || p.Metal > 1 || p.Rough < 0 || p.Rough > 1 || p.Emit < 0 || p.Emit > 50 {
				return false
			}
		}
	}
	return true
}
func (b *Bridge) handler() http.Handler {
	mux := http.NewServeMux()
 mux.HandleFunc("/api/input", func(w http.ResponseWriter,r *http.Request){
  if r.Method!="POST" || r.Header.Get("Origin")!="" {http.Error(w,"native POST only",403);return}
  var c Control; d:=json.NewDecoder(http.MaxBytesReader(w,r.Body,4096)); if d.Decode(&c)!=nil || d.Decode(new(any))!=io.EOF || !finite(c.X)||!finite(c.Z)||!finite(c.DX)||!finite(c.DY)||math.Abs(c.X)>1||math.Abs(c.Z)>1||math.Abs(c.DX)>2000||math.Abs(c.DY)>2000 {http.Error(w,"invalid input",400);return}
  b.mu.Lock(); if c.Active {if b.control.Active && time.Since(b.controlAt)<500*time.Millisecond {c.DX=math.Max(-2000,math.Min(2000,c.DX+b.control.DX));c.DY=math.Max(-2000,math.Min(2000,c.DY+b.control.DY));c.Jump=c.Jump||b.control.Jump}} else {c=Control{}};b.control=c;b.controlAt=time.Now();b.mu.Unlock();w.WriteHeader(204)
 })
	mux.HandleFunc("/api/native", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" || r.Header.Get("Origin") != "" {
			http.Error(w, "native GET only", 403)
			return
		}
		b.mu.RLock()
		s := b.state
		b.mu.RUnlock()
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Cache-Control", "no-store")
		w.Write(nativePacket(s))
	})
	mux.HandleFunc("/api/state", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			http.Error(w, "GET only", 405)
			return
		}
		b.mu.RLock()
		s := b.state
		b.mu.RUnlock()
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		json.NewEncoder(w).Encode(s)
	})
	mux.HandleFunc("/api/update", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.Header.Get("Origin") != "" {
			http.Error(w, "Studio POST only", 403)
			return
		}
		var u Update
		d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<20))
		if d.Decode(&u) != nil || d.Decode(new(any)) != io.EOF || !valid(u) {
			http.Error(w, "invalid scene update", 400)
			return
		}
		b.mu.Lock()
		b.state.Camera = u.Camera
		b.state.Sun = u.Sun
		if u.Parts != nil {
			b.state.Parts = *u.Parts
			b.state.Scene++
		}
		b.state.Seq++
		b.state.Received = time.Now().UnixMilli()
  c:=Control{}
  if r.URL.Query().Get("controls")=="1" && time.Since(b.controlAt)<500*time.Millisecond {c=b.control;b.control.DX=0;b.control.DY=0;b.control.Jump=false}
		b.mu.Unlock()
  if r.URL.Query().Get("controls")=="1" {w.Header().Set("Content-Type","application/json");json.NewEncoder(w).Encode(c);return}
		w.WriteHeader(204)
	})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host != addr && r.Host != "localhost:8765" {
			http.Error(w, "loopback host only", 403)
			return
		}
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'")
		mux.ServeHTTP(w, r)
	})
}
func main() {
	l, err := net.Listen("tcp4", addr)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println("LUMEN GPU 0.2.1 | Native bridge at http://" + addr + " | Ctrl+C to stop")
	s := http.Server{Handler: (&Bridge{}).handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 30 * time.Second}
	log.Fatal(s.Serve(l))
}
