package main
import "testing"
func TestKeyQueue(t *testing.T){
 b:=&Bridge{};b.storeControl(Control{Active:true,Keys:[]KeyEvent{{VK:49,Down:true}},Pointer:[]PointerEvent{{X:.5,Y:.5,Button:2,Down:true}}})
 b.storeControl(Control{Active:true,Keys:[]KeyEvent{{VK:49}},Pointer:[]PointerEvent{{X:.5,Y:.5,Button:2}}})
 c:=b.apply(Update{},true);if len(c.Keys)!=2||c.Keys[0].VK!=49||!c.Keys[0].Down||c.Keys[1].Down||len(c.Pointer)!=2{t.Fatal("input edge lost")}
 if len(b.apply(Update{},true).Keys)!=0{t.Fatal("key repeated")}
 if validKeys([]KeyEvent{{VK:256}})||!validPointer([]PointerEvent{{Button:3}}){t.Fatal("validation")}
}
