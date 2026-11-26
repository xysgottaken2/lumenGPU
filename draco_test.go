package main
import("bytes";"context";"encoding/binary";"os";"os/exec";"testing";"math")
func dracoWrapper(raw []byte)[]byte{
 b:=[]byte("version 7.00\nCOREMESH");b=binary.LittleEndian.AppendUint32(b,2);b=binary.LittleEndian.AppendUint32(b,uint32(len(raw)+4));b=binary.LittleEndian.AppendUint32(b,uint32(len(raw)));return append(b,raw...)
}
func TestDracoMalformed(t *testing.T){
 for _,x:=range [][]byte{nil,[]byte("DRACO"),{5,0,0,0,'D','R','A','C','X'}}{
  if _,e:=runDraco(context.Background(),"not used",x);e==nil{t.Fatal("accepted malformed Draco")}
 }
}
func TestDracoIntegration(t *testing.T){
 helper:=os.Getenv("LUMEN_DRACO_TEST_EXE");if helper==""{t.Skip("native helper built in Windows CI")}
 raw,e:=exec.Command(helper,"--fixture").Output();if e!=nil{t.Fatal(e)}
 b:=dracoWrapper(raw);calls:=0
 decoded,e:=chunkMeshWithDecoder(b,func(c []byte)([]byte,error){calls++;return runDraco(context.Background(),helper,c)})
 if e!=nil||calls!=1||!bytes.HasPrefix(decoded,[]byte("version 2.00\n")){t.Fatalf("chunk conversion: %v",e)}
 vs,size,e:=decodeLumenMesh(decoded);if e!=nil||len(vs)!=3||math.Abs(size[0]-2)>.01||math.Abs(size[1]-4)>.01{t.Fatalf("geometry %v %v",size,e)}
 uv:=decodeLumenUV(decoded,3);found:=false;for _,v:=range uv{if math.Abs(v[0]-.25)<.001&&math.Abs(v[1]-.75)<.001{found=true}}
 if !found{t.Fatalf("missing UV: %v",uv)}
}
