package main
import("testing";"encoding/binary";"math")
func TestEnvironmentPacket(t *testing.T){
 b:=&Bridge{};e:=&Environment{Clock:18,SunSize:11,Brightness:2,Celestial:true}
 b.apply(Update{Environment:e},true);e.Clock=1
 s,_:=b.splitState(0);p:=nativeEnvironmentPacket(s)
 if len(p)!=104||string(p[:4])!="LGR5"||math.Float32frombits(binary.LittleEndian.Uint32(p[88:92]))!=18||math.Float32frombits(binary.LittleEndian.Uint32(p[100:104]))!=1{t.Fatal("environment packet")}
 b.applyMode(Update{Environment:&Environment{Clock:0}},false,true)
 s,_=b.splitState(0);if s.Environment.Clock!=18{t.Fatal("geometry overwrote lighting")}
 if len(nativePacket(s))!=88{t.Fatal("legacy layout changed")}
}
