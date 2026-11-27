package main
import("testing";"encoding/binary";"math")
func TestSkyPacket(t *testing.T){
 e:=Environment{Clock:12,SunSize:11,Brightness:2,Celestial:true,FirstPerson:true,SkySlots:[6]uint32{1,2,3,4,5,6},SkyBasis:[9]float64{1,0,0,0,1,0,0,0,1}}
 if !validSky(e){t.Fatal("valid cubemap rejected")};p:=nativeEnvironmentPacket(State{Environment:&e})
 if len(p)!=168||string(p[:4])!="LGR7"||binary.LittleEndian.Uint32(p[104:])!=1||binary.LittleEndian.Uint32(p[128:])!=6||math.Float32frombits(binary.LittleEndian.Uint32(p[132:]))!=1{t.Fatal("sky wire")}
 e.SkySlots[0]=129;if validSky(e){t.Fatal("invalid slot")};e.SkySlots[0]=1;e.SkyBasis[0]=2;if validSky(e){t.Fatal("invalid basis")}
}

func TestSkyWithPairedPose(t *testing.T){
 b:=&Bridge{};e:=Environment{Clock:12,SunSize:11,Brightness:2,SkySlots:[6]uint32{1,0,0,0,0,0},SkyBasis:[9]float64{1,0,0,0,1,0,0,0,1}}
 if !validSky(e){t.Fatal("partial sky rejected")}
 parts:=[]Part{{S:V{1,1,1}}};cam:=Camera{R:V{1,0,0},U:V{0,1,0},F:V{0,0,-1},Fov:70}
 b.apply(Update{Camera:cam,Sun:V{0,1,0},Environment:&e,Character:&parts},true)
 s,seq:=b.splitState(0);p:=nativeEnvironmentPacket(s)
 if seq!=1||s.Scene!=1||len(s.Parts)!=1||len(p)!=280||string(p[:4])!="LGR7"{t.Fatal("paired pose or sky lost")}
}
