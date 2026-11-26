package main
import("testing";"encoding/binary")
func TestHUDPacket(t *testing.T){a:=[]HUDItem{{X:.5,W:.2,H:.1,Text:"test",FG:0xffffffff}};if !validHUD(a){t.Fatal("valid")};p:=hudPacket(a);if len(p)!=80||string(p[:4])!="LGH1"||binary.LittleEndian.Uint32(p[4:8])!=1||string(p[76:])!="test"{t.Fatal("packet")};a[0].W=-1;if validHUD(a){t.Fatal("negative bounds")}}
func TestPointerQueue(t *testing.T){b:=&Bridge{};b.storeControl(Control{Active:true,Pointer:[]PointerEvent{{X:.5,Y:.5,Button:1,Down:true}}});b.storeControl(Control{Active:true,Pointer:[]PointerEvent{{X:.5,Y:.5,Button:1}}});c:=b.apply(Update{},true);if len(c.Pointer)!=2||!c.Pointer[0].Down||c.Pointer[1].Down{t.Fatal("events lost")};if len(b.apply(Update{},true).Pointer)!=0{t.Fatal("events repeated")}}
