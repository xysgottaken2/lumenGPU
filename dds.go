package main
import("encoding/binary";"fmt";"image";"image/color";"io")
func init(){image.RegisterFormat("dds","DDS ",decodeDDS,configDDS)}
type ddsInfo struct{w,h,block int;kind string}
func ddsHeader(r io.Reader)(ddsInfo,error){
 var h [128]byte;if _,e:=io.ReadFull(r,h[:]);e!=nil{return ddsInfo{},e}
 if string(h[:4])!="DDS "||binary.LittleEndian.Uint32(h[4:])!=124||binary.LittleEndian.Uint32(h[76:])!=32{return ddsInfo{},fmt.Errorf("invalid DDS header")}
 w,hh:=binary.LittleEndian.Uint32(h[16:]),binary.LittleEndian.Uint32(h[12:])
 if w<1||hh<1||w>4096||hh>4096{return ddsInfo{},errTextureSize}
 kind:=string(h[84:88]);block:=16;switch kind{case "DXT1":block=8;case "DXT3","DXT5":default:return ddsInfo{},fmt.Errorf("unsupported DDS format")}
 return ddsInfo{int(w),int(hh),block,kind},nil
}
func configDDS(r io.Reader)(image.Config,error){
 d,e:=ddsHeader(r);return image.Config{ColorModel:color.NRGBAModel,Width:d.w,Height:d.h},e
}
func rgb565(v uint16)color.NRGBA{return color.NRGBA{uint8(((v>>11)&31)*255/31),uint8(((v>>5)&63)*255/63),uint8((v&31)*255/31),255}}
func mixDDS(a,b color.NRGBA,x,y int)color.NRGBA{return color.NRGBA{uint8((int(a.R)*x+int(b.R)*y)/(x+y)),uint8((int(a.G)*x+int(b.G)*y)/(x+y)),uint8((int(a.B)*x+int(b.B)*y)/(x+y)),255}}
func decodeDDS(r io.Reader)(image.Image,error){
 d,e:=ddsHeader(r);if e!=nil{return nil,e}
 im:=image.NewNRGBA(image.Rect(0,0,d.w,d.h));var block [16]byte
 for y:=0;y<d.h;y+=4{for x:=0;x<d.w;x+=4{
  if _,e=io.ReadFull(r,block[:d.block]);e!=nil{return nil,e}
  off:=d.block-8;a,b:=binary.LittleEndian.Uint16(block[off:]),binary.LittleEndian.Uint16(block[off+2:])
  p:=[4]color.NRGBA{rgb565(a),rgb565(b)}
  if d.kind=="DXT1"&&a<=b{p[2]=mixDDS(p[0],p[1],1,1);p[3]=color.NRGBA{}}else{p[2]=mixDDS(p[0],p[1],2,1);p[3]=mixDDS(p[0],p[1],1,2)}
  indices:=binary.LittleEndian.Uint32(block[off+4:]);var alpha [8]uint8;var bits uint64
  if d.kind=="DXT5"{
   alpha[0]=block[0];alpha[1]=block[1]
   if alpha[0]>alpha[1]{for i:=2;i<8;i++{alpha[i]=uint8(((8-i)*int(alpha[0])+(i-1)*int(alpha[1]))/7)}}else{for i:=2;i<6;i++{alpha[i]=uint8(((6-i)*int(alpha[0])+(i-1)*int(alpha[1]))/5)};alpha[6]=0;alpha[7]=255}
   for i:=0;i<6;i++{bits|=uint64(block[2+i])<<uint(8*i)}
  }else if d.kind=="DXT3"{bits=binary.LittleEndian.Uint64(block[:8])}
  for i:=0;i<16;i++{px,py:=x+i%4,y+i/4;if px>=d.w||py>=d.h{continue};c:=p[(indices>>uint(2*i))&3]
   if d.kind=="DXT3"{c.A=uint8((bits>>uint(4*i))&15)*17}else if d.kind=="DXT5"{c.A=alpha[(bits>>uint(3*i))&7]}
   im.SetNRGBA(px,py,c)
  }
 }}
 return im,nil
}
