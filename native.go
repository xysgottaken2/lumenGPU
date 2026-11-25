package main

import ("encoding/binary";"math")

// LGR4: 88-byte header, 112-byte part records, little endian.
func nativePacket(s State) []byte {
 b:=make([]byte,88+len(s.Parts)*112);copy(b,"LGR4")
 binary.LittleEndian.PutUint64(b[4:],s.Scene)
 binary.LittleEndian.PutUint64(b[12:],s.Seq)
 binary.LittleEndian.PutUint32(b[20:],uint32(len(s.Parts)))
 at:=24
 put:=func(v float64){binary.LittleEndian.PutUint32(b[at:],math.Float32bits(float32(v)));at+=4}
 vec:=func(v V){for _,x:=range v {put(x)}}
 vec(s.Camera.P);vec(s.Camera.R);vec(s.Camera.U);vec(s.Camera.F);put(s.Camera.Fov);vec(s.Sun)
 for _,p:=range s.Parts {vec(p.P);vec(p.R);vec(p.U);vec(p.B);vec(p.S);vec(p.C);put(p.Metal);put(p.Rough);put(p.Emit);put(p.Transmission);put(p.IOR);put(p.Shape);put(p.Specular);vec(p.EmissionColor)}
 return b
}
