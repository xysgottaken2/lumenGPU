package main
import("bytes";"encoding/binary";"math";"strings")
// Transform original normals into the unit-sized mesh coordinate system.
// Called only after geometry validation; zero normal means geometric fallback.
func decodeLumenNormals(data []byte,count int,size V)[]V{
 i:=bytes.IndexByte(data,'\n');if i<0{return nil};version:=strings.TrimSpace(string(data[:i]));d:=data[i+1:]
 if len(d)<12{return nil}
 h:=int(binary.LittleEndian.Uint16(d));stride:=int(d[2]);nv,skin:=0,0
 switch version{
 case "version 2.00":nv=int(binary.LittleEndian.Uint32(d[4:]))
 case "version 3.00","version 3.01":if len(d)<16{return nil};nv=int(binary.LittleEndian.Uint32(d[8:]))
 case "version 4.00","version 4.01","version 5.00":if len(d)<24{return nil};stride=40;nv=int(binary.LittleEndian.Uint32(d[4:]));if binary.LittleEndian.Uint16(d[14:])>0{skin=8}
 default:return nil
 }
 if h<12||stride<24||nv<3||nv>200000||count<3||count>60000{return nil}
 start:=h+nv*(stride+skin);if start+count*4>len(d){return nil}
 out:=make([]V,count)
 for j:=range out{
  idx:=int(binary.LittleEndian.Uint32(d[start+j*4:]));if idx<0||idx>=nv{return nil}
  at:=h+idx*stride+12;var n V
  for k:=0;k<3;k++{n[k]=float64(math.Float32frombits(binary.LittleEndian.Uint32(d[at+k*4:])))*size[k]}
  l:=norm(n);if vec(n)&&l>1e-8{for k:=range n{n[k]/=l};out[j]=n}
 }
 return out
}
