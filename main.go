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
 "strconv"
 "slices"
	"time"
 "context"
 "os"
 "os/signal"
 "path/filepath"
 "syscall"
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
 Transmission float64 `json:"transmission"`
 IOR float64 `json:"ior"`
 Shape float64 `json:"shape"`
 Specular float64 `json:"specular"`
 EmissionColor V `json:"emissionColor"`
}
type Environment struct {
 Clock float64 `json:"clock"`
 SunSize float64 `json:"sunSize"`
 Brightness float64 `json:"brightness"`
 Celestial bool `json:"celestial"`
 FirstPerson bool `json:"firstPerson"`
}
type Update struct {
 HUD *[]HUDItem `json:"hud,omitempty"`
 Environment *Environment `json:"environment,omitempty"`
	Camera Camera  `json:"camera"`
	Sun    V       `json:"sun"`
	Parts  *[]Part `json:"parts,omitempty"`
 Avatar *[]Part `json:"avatar,omitempty"`
 Character *[]Part `json:"character,omitempty"`
}
type State struct {
 Environment *Environment `json:"environment,omitempty"`
	Camera   Camera `json:"camera"`
	Sun      V      `json:"sun"`
	Parts    []Part `json:"parts"`
	Scene    uint64 `json:"scene"`
	Seq      uint64 `json:"seq"`
	Received int64  `json:"received"`
}
type Control struct {
 Pointer []PointerEvent `json:"pointer,omitempty"`
 Keys []KeyEvent `json:"keys,omitempty"`
 Active bool `json:"active"`
 X float64 `json:"x"`
 Z float64 `json:"z"`
 DX float64 `json:"dx"`
 DY float64 `json:"dy"`
 Jump bool `json:"jump"`
 Distance float64 `json:"distance"`
 Sensitivity float64 `json:"sensitivity"`
 Fov float64 `json:"fov"`
}
type Bridge struct {
 hud []HUDItem
 hudRevision uint64
	mu sync.RWMutex
	state State
 control Control
 controlAt time.Time
 worldParts []Part
 avatarParts []Part // moving world objects (legacy Avatar field)
 characterParts []Part
 worldRevision,movingRevision,characterRevision uint64
 meshes map[uint32][]V
 meshVertices int
 lumenus *Lumenus
}

func finite(x float64) bool { return !math.IsNaN(x) && !math.IsInf(x, 0) && math.Abs(x) < 1e7 }
func vec(v V) bool          { return finite(v[0]) && finite(v[1]) && finite(v[2]) }
func norm(v V) float64      { return math.Sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]) }
func axis(v V) bool         { return vec(v) && math.Abs(norm(v)-1) < .03 }
func valid(u Update) bool {
	if e:=u.Environment;e!=nil&&(!finite(e.Clock)||e.Clock<0||e.Clock>24||!finite(e.SunSize)||e.SunSize<0||e.SunSize>180||!finite(e.Brightness)||e.Brightness<0||e.Brightness>100){return false}
 if u.HUD!=nil&&!validHUD(*u.HUD){return false}
 c := u.Camera
	if !vec(c.P) || !axis(c.R) || !axis(c.U) || !axis(c.F) || !finite(c.Fov) || c.Fov < 5 || c.Fov > 120 || !axis(u.Sun) {
		return false
	}
	for _, group:=range []*[]Part{u.Parts,u.Avatar,u.Character} {
 if group==nil {continue}
		if len(*group) > 16384 || (group==u.Avatar && len(*group)>1024) || (group==u.Character && len(*group)>64) {
			return false
		}
		for _, p := range *group {
			if !vec(p.P) || !axis(p.R) || !axis(p.U) || !axis(p.B) || !vec(p.S) || !vec(p.C) || !finite(p.Metal) || !finite(p.Rough) || !finite(p.Emit) || !finite(p.Transmission) || !finite(p.IOR) || !finite(p.Shape) || !finite(p.Specular) || !vec(p.EmissionColor) {
				return false
			}
			for i := 0; i < 3; i++ {
				if p.S[i] <= 0 || p.S[i] > 1e5 || p.C[i] < 0 || p.C[i] > 1 || p.EmissionColor[i]<0 || p.EmissionColor[i]>1 {
					return false
				}
			}
			if p.Metal < 0 || p.Metal > 1 || p.Rough < 0 || p.Rough > 1 || p.Emit < 0 || p.Emit > 50 || p.Transmission<0 || p.Transmission>1 || (p.IOR!=0 && (p.IOR<1 || p.IOR>3)) || p.Shape< -5 || p.Shape>16777215 || p.Shape!=math.Trunc(p.Shape) || p.Specular<0 || p.Specular>1 {
				return false
			}
		}
	}
	return true
}
func (b *Bridge) apply(u Update,wantsControls bool) Control {return b.applyMode(u,wantsControls,false)}
func (b *Bridge) applyMode(u Update,wantsControls,geometryOnly bool) Control {
		b.mu.Lock()
 if !geometryOnly&&u.HUD!=nil&&!slices.Equal(b.hud,*u.HUD){b.hud=*u.HUD;b.hudRevision++}
 if !geometryOnly {b.state.Camera=u.Camera;b.state.Sun=u.Sun;if u.Environment!=nil{e:=*u.Environment;b.state.Environment=&e}}
  changed:=false
  if u.Parts!=nil && !slices.Equal(b.worldParts,*u.Parts) {b.worldParts=*u.Parts;b.worldRevision++;changed=true}
  if u.Avatar!=nil && !slices.Equal(b.avatarParts,*u.Avatar) {b.avatarParts=*u.Avatar;b.movingRevision++;changed=true}
  // Only a camera packet may replace the character pose. No full-world copy.
  if !geometryOnly && u.Character!=nil && !slices.Equal(b.characterParts,*u.Character) {b.characterParts=*u.Character;b.characterRevision++}
  if changed { // Allocate a new slice; concurrent readers retain an immutable snapshot.
   limit:=16384-len(b.avatarParts);if len(b.worldParts)<limit {limit=len(b.worldParts)}
   combined:=make([]Part,0,limit+len(b.avatarParts));combined=append(combined,b.worldParts[:limit]...);combined=append(combined,b.avatarParts...);b.state.Parts=combined;b.state.Scene++
  }
if !geometryOnly {b.state.Seq++;b.state.Received=time.Now().UnixMilli()}
  c:=Control{}
  if wantsControls && time.Since(b.controlAt)<500*time.Millisecond {c=b.control;b.control.DX=0;b.control.DY=0;b.control.Jump=false;b.control.Pointer=nil;b.control.Keys=nil}
 b.mu.Unlock();return c
}
func (b *Bridge) handler() http.Handler {
	mux := http.NewServeMux()
 mux.HandleFunc("/api/ws",b.stream)
 mux.HandleFunc("/api/native-hud-ws",b.hudStream)
 mux.HandleFunc("/api/geometry-ws",b.geometryStream)
 mux.HandleFunc("/api/native-camera-ws",func(w http.ResponseWriter,r *http.Request){b.nativeStream(w,r,false)})
 mux.HandleFunc("/api/native-geometry-ws",func(w http.ResponseWriter,r *http.Request){b.nativeStream(w,r,true)})
 mux.HandleFunc("/api/native-input-ws",b.inputStream)
 mux.HandleFunc("/api/native-pose-ws",func(w http.ResponseWriter,r *http.Request){b.nativeSplitStream(w,r,0)})
 mux.HandleFunc("/api/native-world-ws",func(w http.ResponseWriter,r *http.Request){b.nativeSplitStream(w,r,1)})
 mux.HandleFunc("/api/native-moving-ws",func(w http.ResponseWriter,r *http.Request){b.nativeSplitStream(w,r,2)})
 mux.HandleFunc("/api/mesh",b.meshHandler)
 if b.lumenus!=nil {mux.HandleFunc("/api/lumenus",b.lumenus.handler)}
 mux.HandleFunc("/api/input", func(w http.ResponseWriter,r *http.Request){
  if r.Method!="POST" || r.Header.Get("Origin")!="" {http.Error(w,"native POST only",403);return}
  var c Control;d:=json.NewDecoder(http.MaxBytesReader(w,r.Body,4096))
  if d.Decode(&c)!=nil||d.Decode(new(any))!=io.EOF||!validControl(c){http.Error(w,"invalid input",400);return}
  b.storeControl(c);w.WriteHeader(204)
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
		if r.URL.Query().Get("rev")==strconv.FormatUint(s.Scene,10) {s.Parts=nil}
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
	updateHandler:=func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.Header.Get("Origin") != "" {
			http.Error(w, "Studio POST only", 403)
			return
		}
		var u Update
		d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 32<<20))
		if d.Decode(&u) != nil || d.Decode(new(any)) != io.EOF || !valid(u) {
			http.Error(w, "invalid scene update", 400)
			return
		}
  wantsControls:=r.URL.Path=="/api/update-controls" || r.URL.Query().Get("controls")=="1"
  c:=b.apply(u,wantsControls)
  if wantsControls {w.Header().Set("Content-Type","application/json");json.NewEncoder(w).Encode(c);return}
		w.WriteHeader(204)
	}
 mux.HandleFunc("/api/update",updateHandler)
 mux.HandleFunc("/api/update-controls",updateHandler)
 mux.HandleFunc("/api/geometry-update",func(w http.ResponseWriter,r *http.Request){
  if r.Method!="POST"||r.Header.Get("Origin")!=""{http.Error(w,"local geometry POST only",403);return}
  var u Update;d:=json.NewDecoder(http.MaxBytesReader(w,r.Body,32<<20));if d.Decode(&u)!=nil||d.Decode(new(any))!=io.EOF||!valid(u){http.Error(w,"invalid geometry update",400);return}
  b.applyMode(u,false,true);w.WriteHeader(204)
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
	b:= &Bridge{}
 exe,err:=os.Executable();if err!=nil{log.Fatal(err)}
 worker,err:=newLumenus(b,filepath.Join(filepath.Dir(exe),"TempAssets"));if err!=nil{log.Fatal(err)}
 b.lumenus=worker
 defer worker.close()
 fmt.Println("LUMEN GPU 0.9 | Lumenus session cache:",worker.dir)
 fmt.Println("Native bridge at http://" + addr + " | Ctrl+C to stop")
 s := http.Server{Handler: b.handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 30 * time.Second}
 ctx,stop:=signal.NotifyContext(context.Background(),os.Interrupt,syscall.SIGTERM);defer stop()
 go func(){<-ctx.Done();timeout,cancel:=context.WithTimeout(context.Background(),2*time.Second);defer cancel();s.Shutdown(timeout);s.Close()}()
 if err:=s.Serve(l);err!=nil&&err!=http.ErrServerClosed{log.Print(err)}
}
