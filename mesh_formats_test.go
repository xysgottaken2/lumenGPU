package main
import("encoding/binary";"strings";"testing")
func TestChunkGeometry(t *testing.T){
 legacy:=fixtureMesh();d:=legacy[len("version 2.00\n"):]
 core:=make([]byte,4+3*40+4+12);binary.LittleEndian.PutUint32(core,3)
 for j:=0;j<3;j++{copy(core[4+j*40:],d[12+j*36:12+(j+1)*36])}
 binary.LittleEndian.PutUint32(core[124:],1);copy(core[128:],d[120:])
 file:=[]byte("version 6.00\nCOREMESH");file=binary.LittleEndian.AppendUint32(file,1);file=binary.LittleEndian.AppendUint32(file,uint32(len(core)));file=append(file,core...)
 v,s,e:=decodeLumenMesh(file);if e!=nil||len(v)!=3||s[0]!=2||len(decodeLumenUV(file,3))!=3{t.Fatalf("v6: %v %v",s,e)}
 for i:=0;i<len(file);i++{if _,_,e:=decodeLumenMesh(file[:i]);e==nil{t.Fatalf("accepted truncation %d",i)}}
 file[len("version 6.00\n")+8]=2;if _,_,e:=decodeLumenMesh(file);e==nil||!strings.Contains(e.Error(),"Draco"){t.Fatal("missing Draco diagnostic")}
}
func TestBindPose(t *testing.T){
 legacy:=fixtureMesh();d:=legacy[len("version 2.00\n"):];h:=make([]byte,24);binary.LittleEndian.PutUint16(h,24);binary.LittleEndian.PutUint32(h[4:],3);binary.LittleEndian.PutUint32(h[8:],1);binary.LittleEndian.PutUint16(h[14:],1)
 file:=append([]byte("version 4.00\n"),h...)
 for j:=0;j<3;j++{file=append(file,d[12+j*36:12+(j+1)*36]...);file=append(file,0,0,0,0)}
 file=append(file,make([]byte,24)...);file=append(file,d[120:]...)
 v,s,e:=decodeLumenMesh(file);if e!=nil||len(v)!=3||s[1]!=4||len(decodeLumenUV(file,3))!=3{t.Fatalf("bind pose: %v %v",s,e)}
}
