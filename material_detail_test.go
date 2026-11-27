package main
import("image";"image/color";"testing")
func TestStudAtlasCrop(t *testing.T){
 im:=image.NewNRGBA(image.Rect(0,0,128,2048))
 for i,sy:=range []int{0,1024,1536,512}{im.SetNRGBA(0,sy,color.NRGBA{uint8(i+1),0,0,255})}
 p,e:=cropStudAtlas(im);if e!=nil{t.Fatal(e)}
 for i,j:=range []int{0,128,128*256,128*256+128}{if p[j]&255!=uint32(i+1){t.Fatal("wrong atlas band")}}
 if _,e=cropStudAtlas(image.NewNRGBA(image.Rect(0,0,32,32)));e==nil{t.Fatal("wrong dimensions accepted")}
}
func TestMaterialTextureSettings(t *testing.T){
 t.Setenv("LUMEN_TEXTURE_MAX","512");if textureResolution(2048,2048,0,0)!=512{t.Fatal("cap")}
 t.Setenv("LUMEN_TEXTURE_MAX","256");if textureResolution(2048,2048,0,0)!=256{t.Fatal("cap")}
 a:=[8]float64{1,8,1,1,0,0,1,1};if !validTexture(a){t.Fatal("stud mode")}
 b:=[8]float64{4*32768,0,0,0,0,0,0,0};if !validExtra(b){t.Fatal("packed surface")}
}
