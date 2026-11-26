package main
import("testing";"encoding/binary")
func TestFirstPersonPacket(t *testing.T){
 b:=&Bridge{};e:=&Environment{Clock:12,SunSize:11,Brightness:2,Celestial:true,FirstPerson:true}
 b.apply(Update{Environment:e},true);s,_:=b.splitState(0);p:=nativeEnvironmentPacket(s)
 if string(p[:4])!="LGR6"||len(p)!=108||binary.LittleEndian.Uint32(p[104:108])!=1{t.Fatal("first person packet")}
 b.applyMode(Update{Environment:&Environment{}},false,true);s,_=b.splitState(0);if !s.Environment.FirstPerson{t.Fatal("geometry reset camera mode")}
 e.FirstPerson=false;b.apply(Update{Environment:e},true);s,_=b.splitState(0);p=nativeEnvironmentPacket(s)
 if string(p[:4])!="LGR5"||len(p)!=104{t.Fatal("third person packet")}
}
