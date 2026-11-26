package main
import("bytes";"encoding/binary";"fmt";"math";"strconv";"strings")
func meshDiagnostic(d []byte,e error)string{
 i:=bytes.IndexByte(d,'\n');v:="unknown header";if i>=0&&i<=20&&bytes.HasPrefix(d,[]byte("version ")){v=strings.TrimSpace(string(d[:i]))}
 return fmt.Sprintf("%s (%s, %d bytes)",e,v,len(d))
}
func makeV2(verts,faces []byte,nv,nf int)[]byte{
 out:=[]byte("version 2.00\n");h:=make([]byte,12);binary.LittleEndian.PutUint16(h,12);h[2]=40;h[3]=12;binary.LittleEndian.PutUint32(h[4:],uint32(nv));binary.LittleEndian.PutUint32(h[8:],uint32(nf));out=append(out,h...);out=append(out,verts...);return append(out,faces...)
}
func chunkMeshToV2(data []byte)([]byte,error){return chunkMeshWithDecoder(data,nil)}
func chunkMeshWithDecoder(data []byte,draco func([]byte)([]byte,error))([]byte,error){
 fail:=func(s string)([]byte,error){return nil,fmt.Errorf("chunk mesh: %s",s)}
 i:=bytes.IndexByte(data,'\n');if i<0{return fail("missing header")};d:=data[i+1:]
 var core,lods []byte
 for len(d)>0{
  if len(d)<16{return fail("truncated chunk header")}
  name:=strings.TrimRight(string(d[:8]),"\x00");version:=binary.LittleEndian.Uint32(d[8:]);size:=int(binary.LittleEndian.Uint32(d[12:]));d=d[16:]
  if size<0||size>len(d){return fail("truncated chunk")}
  if name=="COREMESH"{
   if core!=nil{return fail("duplicate COREMESH")}
   switch version{case 1:core=d[:size];case 2:
    if draco==nil{return fail("Draco COREMESH requires the native decoder")}
    var e error;core,e=draco(d[:size]);if e!=nil{return nil,e}
   default:return fail("unsupported COREMESH version")}
  }
  if name=="LODS"&&version==1{lods=d[:size]}
  d=d[size:]
 }
 if len(core)<8{return fail("missing COREMESH")}
 nv:=int(binary.LittleEndian.Uint32(core));if nv<3||nv>200000{return fail("vertex count")}
 at:=4+40*nv;if at+4>len(core){return fail("truncated vertices")}
 nf:=int(binary.LittleEndian.Uint32(core[at:]));if nf<1||nf>200000||at+4+nf*12!=len(core){return fail("invalid face count")}
 count:=nf
 if len(lods)>=15{
  n:=int(binary.LittleEndian.Uint32(lods[3:]));if n>=2&&n<=200000&&len(lods)==7+n*4&&binary.LittleEndian.Uint32(lods[7:])==0&&int(binary.LittleEndian.Uint32(lods[7+(n-1)*4:]))==nf{
   last:=0;for j:=1;j<n;j++{v:=int(binary.LittleEndian.Uint32(lods[7+j*4:]));if v<=last||v>nf{return fail("invalid LOD range")};last=v}
   count=int(binary.LittleEndian.Uint32(lods[11:]))
  }
 }
 if count>20000{return fail("highest LOD exceeds triangle limit")}
 return makeV2(core[4:at],core[at+4:at+4+count*12],nv,count),nil
}
func textMeshToV2(data []byte)([]byte,error){
 fail:=func()([]byte,error){return nil,fmt.Errorf("invalid legacy text mesh")}
 lines:=strings.SplitN(string(data),"\n",3);if len(lines)!=3{return fail()}
 n,e:=strconv.Atoi(strings.TrimSpace(lines[1]));if e!=nil||n<1||n>20000{return fail()}
 words:=strings.FieldsFunc(lines[2],func(r rune)bool{return r=='['||r==']'||r==','||r==' '||r=='\r'||r=='\n'||r=='\t'})
 if len(words)!=n*27{return fail()}
 nv:=n*3;verts:=make([]byte,nv*40);faces:=make([]byte,nv*4)
 for j:=0;j<nv;j++{for k:=0;k<8;k++{
  x,e:=strconv.ParseFloat(words[j*9+k],32);if e!=nil||!finite(x){return fail()}
  if k<3&&strings.TrimSpace(lines[0])=="version 1.00"{x*=.5}
  if k==7{x=1-x}
  binary.LittleEndian.PutUint32(verts[j*40+k*4:],math.Float32bits(float32(x)))
 };binary.LittleEndian.PutUint32(faces[j*4:],uint32(j))}
 return makeV2(verts,faces,nv,n),nil
}
