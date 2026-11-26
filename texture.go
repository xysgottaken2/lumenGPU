package main
import(
 "bytes"
 "encoding/binary"
 "image"
 "image/color"
 "math"
 "net/http"
 "strconv"
)
const textureSide=256
const textureMax=128
type UV [2]float64
func validUV(v UV)bool{return finite(v[0])&&finite(v[1])&&math.Abs(v[0])<=4096&&math.Abs(v[1])<=4096}
func validTexture(t [8]float64)bool{
 for _,x:=range t{if !finite(x){return false}}
 if t[0]==0{return t==[8]float64{}}
 return t[0]>=1&&t[0]<=textureMax&&t[0]==math.Trunc(t[0])&&t[1]>=0&&t[1]<=6&&t[1]==math.Trunc(t[1])&&t[2]>0&&t[2]<=4096&&t[3]>0&&t[3]<=4096&&math.Abs(t[4])<=4096&&math.Abs(t[5])<=4096&&t[6]>=0&&t[6]<=1&&(t[7]==0||t[7]==1)
}
func decodeTexture(data []byte)([]uint32,error){
 cfg,_,e:=image.DecodeConfig(bytes.NewReader(data))
 if e!=nil{return nil,e}
 if cfg.Width<1||cfg.Height<1||cfg.Width>4096||cfg.Height>4096{return nil,errTextureSize}
 im,_,e:=image.Decode(bytes.NewReader(data));if e!=nil{return nil,e}
 b:=im.Bounds();out:=make([]uint32,textureSide*textureSide)
 // Fixed-size atlas slots; box-like center sampling keeps memory bounded.
 for y:=0;y<textureSide;y++{for x:=0;x<textureSide;x++{
  sx:=b.Min.X+(2*x+1)*b.Dx()/(2*textureSide);sy:=b.Min.Y+(2*y+1)*b.Dy()/(2*textureSide)
  c:=color.NRGBAModel.Convert(im.At(sx,sy)).(color.NRGBA)
  out[y*textureSide+x]=uint32(c.R)|uint32(c.G)<<8|uint32(c.B)<<16|uint32(c.A)<<24
 }}
 return out,nil
}
type textureSizeError struct{}
func(textureSizeError)Error()string{return "image exceeds 4096x4096 or has invalid size"}
var errTextureSize error=textureSizeError{}
func(b *Bridge)textureHandler(w http.ResponseWriter,r *http.Request){
 if r.Method!="GET"||r.Header.Get("Origin")!=""{http.Error(w,"local GET only",403);return}
 id,e:=strconv.ParseUint(r.URL.Query().Get("id"),10,32);if e!=nil||id<1||id>textureMax{http.Error(w,"invalid texture slot",400);return}
 b.mu.RLock();pixels:=b.textures[uint32(id)];b.mu.RUnlock();if len(pixels)!=textureSide*textureSide{http.NotFound(w,r);return}
 out:=make([]byte,8+len(pixels)*4);copy(out,"LGT1");binary.LittleEndian.PutUint32(out[4:],textureSide)
 for i,v:=range pixels{binary.LittleEndian.PutUint32(out[8+i*4:],v)}
 w.Header().Set("Content-Type","application/octet-stream");w.Header().Set("Cache-Control","no-store");w.Write(out)
}
