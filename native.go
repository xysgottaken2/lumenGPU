package main

import ("encoding/binary";"math")

// LGR4: 88-byte header, 112-byte part records, little endian.
func nativePacket(s State) []byte {
 textured,extended,clothed:=false,false,false;for _,p:=range s.Parts{if p.Tex[0]>0{textured=true};if p.Extra!=[8]float64{}{extended=true};if p.Cloth!=[8]float64{}{clothed=true;extended=true}}
 stride:=112;if textured||extended{stride=144};if extended{stride=176};if clothed{stride=208}
 b:=make([]byte,88+len(s.Parts)*stride);copy(b,"LGR4");if textured{copy(b,"LGT4")};if extended{copy(b,"LGP4")};if clothed{copy(b,"LGC4")}
 binary.LittleEndian.PutUint64(b[4:],s.Scene)
 binary.LittleEndian.PutUint64(b[12:],s.Seq)
 binary.LittleEndian.PutUint32(b[20:],uint32(len(s.Parts)))
 at:=24
 put:=func(v float64){binary.LittleEndian.PutUint32(b[at:],math.Float32bits(float32(v)));at+=4}
 vec:=func(v V){for _,x:=range v {put(x)}}
 vec(s.Camera.P);vec(s.Camera.R);vec(s.Camera.U);vec(s.Camera.F);put(s.Camera.Fov);vec(s.Sun)
 for _,p:=range s.Parts {vec(p.P);vec(p.R);vec(p.U);vec(p.B);vec(p.S);vec(p.C);put(p.Metal);put(p.Rough);put(p.Emit);put(p.Transmission);put(p.IOR);put(p.Shape);put(p.Specular);vec(p.EmissionColor);if textured||extended{for _,v:=range p.Tex{put(v)}};if extended{for _,v:=range p.Extra{put(v)}};if clothed{for _,v:=range p.Cloth{put(v)}}}
 return b
}

func nativeEnvironmentPacket(s State) []byte {
 b:=nativePacket(s)
 if s.Environment==nil{return b}
 b[3]='5';e:=s.Environment
 for _,v:=range []float64{e.Clock,e.SunSize,e.Brightness,0}{b=binary.LittleEndian.AppendUint32(b,math.Float32bits(float32(v)))}
 if e.Celestial{binary.LittleEndian.PutUint32(b[len(b)-4:],math.Float32bits(1))}
 if e.FirstPerson{b[3]='6';b=binary.LittleEndian.AppendUint32(b,1)}
 return b
}
