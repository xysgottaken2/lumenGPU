package main
import("testing";"encoding/binary";"math")
func TestVisualWire(t *testing.T){
 p:=Part{Extra:[8]float64{4095,1,2,3,.5,1,0,0}}
 if !validExtra(p.Extra){t.Fatal("valid extra rejected")}
 b:=nativePacket(State{Parts:[]Part{p}});if len(b)!=264||string(b[:4])!="LGP4"||math.Float32frombits(binary.LittleEndian.Uint32(b[232:]))!=4095{t.Fatal("extended packet")}
 p.Extra[1]=129;if validExtra(p.Extra){t.Fatal("invalid map slot accepted")}
 ns:=[]V{{0,0,1},{0,0,1},{0,0,1}};v:=[]V{{0,0,0},{1,0,0},{0,1,0}}
 m:=normalMeshPacket(v,nil,ns);if len(m)!=104||string(m[:4])!="LGM3"{t.Fatal("normal wire")}
 d:=fixtureMesh();at:=len("version 2.00\n")+12+20;binary.LittleEndian.PutUint32(d[at:],math.Float32bits(1))
 n:=decodeLumenNormals(d,3,V{2,4,1});if len(n)!=3||n[0]!=(V{0,0,1}){t.Fatalf("normal decode %v",n)}
}
