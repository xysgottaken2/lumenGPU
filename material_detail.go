package main
import("bytes";"fmt";"image";"image/color";"math";"os";"strconv")
func textureQualityLimit()int{
 n,_:=strconv.Atoi(os.Getenv("LUMEN_TEXTURE_MAX"));if n==256||n==512||n==1024{return n};return 1024
}
func packRGBA(c color.NRGBA)uint32{return uint32(c.R)|uint32(c.G)<<8|uint32(c.B)<<16|uint32(c.A)<<24}
// Roblox's legacy atlas is 128x2048. Four 512-high pattern bands each
// repeat a 128x128 tile. Preserve original texels in a 256x256 square.
func cropStudAtlas(im image.Image)([]uint32,error){
 b:=im.Bounds();if b.Dx()!=128||b.Dy()!=2048{return nil,fmt.Errorf("expected 128x2048 studs atlas")}
 offsets:=[4]int{0,1024,1536,512}
 out:=make([]uint32,256*256)
 for k,sy:=range offsets{ox,oy:=(k%2)*128,(k/2)*128
  for y:=0;y<128;y++{for x:=0;x<128;x++{out[(oy+y)*256+ox+x]=packRGBA(color.NRGBAModel.Convert(im.At(b.Min.X+x,b.Min.Y+sy+y)).(color.NRGBA))}}
 };return out,nil
}
func decodeStudAtlas(data []byte)([]uint32,error){im,_,e:=image.Decode(bytes.NewReader(data));if e!=nil{return nil,e};return cropStudAtlas(im)}
// Apply a mild wrapped unsharp filter once, only to small preview color
// textures. Never sharpen normal/roughness maps or alpha.
func sharpenPreview(p []uint32,side int){
 if side<=0||len(p)!=side*side||os.Getenv("LUMEN_PREVIEW_SHARPEN")=="0"{return}
 src:=append([]uint32(nil),p...)
 for y:=0;y<side;y++{for x:=0;x<side;x++{
  i:=y*side+x;v:=src[i];out:=v&0xff000000
  for shift:=0;shift<24;shift+=8{
   center:=float64((v>>shift)&255);sum:=0.
   for dy:=-1;dy<=1;dy++{for dx:=-1;dx<=1;dx++{sum+=float64((src[((y+dy+side)%side)*side+(x+dx+side)%side]>>shift)&255)}}
   q:=math.Round(math.Max(0,math.Min(255,center+.65*(center-sum/9))))
   out|=uint32(q)<<shift
  };p[i]=out
 }}
}
