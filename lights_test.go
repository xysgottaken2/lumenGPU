package main
import "testing"
func TestIndependentLights(t *testing.T){
 b:=&Bridge{}
 l:=Part{P:V{0,4,0},R:V{1,0,0},U:V{0,1,0},B:V{0,0,-1},S:V{20,1,1},C:V{1,1,1},Rough:1,Emit:2,IOR:1.5,Extra:[8]float64{0,0,0,0,0,1,1,-1}}
 lights:=[]Part{l}
 u:=Update{Camera:Camera{R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70},Sun:V{0,1,0},Lights:&lights}
 if why:=updateError(u);why!=""{t.Fatal(why)}
 b.apply(u,false);s,rev:=b.splitState(3);if len(s.Parts)!=1||rev!=1||s.Parts[0]!=l{t.Fatal("missing light")}
 b.apply(Update{},false);b.applyMode(Update{Avatar:&[]Part{}},false,true)
 s,rev=b.splitState(3);if len(s.Parts)!=1||rev!=1{t.Fatal("light overwritten by other channel")}
 b.apply(u,false);_,rev=b.splitState(3);if rev!=1{t.Fatal("unchanged light revision")}
 moved:=l;moved.P[0]=3;lights2:=[]Part{moved};u.Lights=&lights2;b.apply(u,false);s,rev=b.splitState(3);if rev!=2||s.Parts[0]!=moved{t.Fatal("light move lost")}
 empty:=[]Part{};u.Lights=&empty;b.apply(u,false);s,rev=b.splitState(3);if rev!=3||len(s.Parts)!=0{t.Fatal("light disable lost")}
 l.Extra[6]=0;u.Lights=&[]Part{l};if updateError(u)==""{t.Fatal("geometry accepted as light")}
}
