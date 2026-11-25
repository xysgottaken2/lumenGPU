package main

import (
	"bytes"
	"encoding/binary"
)

// LGR3: magic, scene and sequence (u64), part count (u32), 16 camera/sun f32,
// then 23 f32 per part. Explicit little endian, no native struct padding.
func nativePacket(s State) []byte {
	var b bytes.Buffer
	b.Grow(88+len(s.Parts)*92)
 b.WriteString("LGR3")
	put := func(v any) { binary.Write(&b, binary.LittleEndian, v) }
	vec := func(v V) {
		for _, x := range v {
			put(float32(x))
		}
	}
	put(s.Scene)
	put(s.Seq)
	put(uint32(len(s.Parts)))
	vec(s.Camera.P)
	vec(s.Camera.R)
	vec(s.Camera.U)
	vec(s.Camera.F)
	put(float32(s.Camera.Fov))
	vec(s.Sun)
	for _, p := range s.Parts {
		vec(p.P)
		vec(p.R)
		vec(p.U)
		vec(p.B)
		vec(p.S)
		vec(p.C)
		put(float32(p.Metal))
		put(float32(p.Rough))
		put(float32(p.Emit))
  put(float32(p.Transmission))
  put(float32(p.IOR))
	}
	return b.Bytes()
}
