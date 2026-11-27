package main
import("bytes";"encoding/binary";"image";"image/color";"os";"path/filepath";"testing")
func TestLocalAssetNames(t *testing.T){
 for _,a:=range []string{"local-face.png","local-sparkles_main.dds"}{if _,ok:=assetKey(assetRequest{Asset:a,Kind:"image"});!ok{t.Fatal(a)}}
 for _,a:=range []string{"local-../x.png","local-a/b.png","local-C:secret.png","local-a.exe","local-..png"}{if validLocalAsset("image",a){t.Fatal(a)}}
 root:=t.TempDir();app:=t.TempDir();dir:=filepath.Join(app,"Roblox","Versions","version-test","content","avatar","heads");if e:=os.MkdirAll(dir,0700);e!=nil{t.Fatal(e)}
 if e:=os.WriteFile(filepath.Join(dir,"head.mesh"),[]byte("fixture"),0600);e!=nil{t.Fatal(e)}
 t.Setenv("LOCALAPPDATA",app);l:=&Lumenus{imports:filepath.Join(root,"AssetImports")}
 b,e:=l.fetchLocal(assetRequest{Asset:"local-head.mesh",Kind:"mesh"});if e!=nil||string(b)!="fixture"{t.Fatal(e)}
 if e=os.MkdirAll(filepath.Join(root,"meshes"),0700);e!=nil{t.Fatal(e)}
 if e=os.WriteFile(filepath.Join(root,"meshes","head.mesh"),[]byte("override"),0600);e!=nil{t.Fatal(e)}
 b,e=l.fetchLocal(assetRequest{Asset:"local-head.mesh",Kind:"mesh"});if e!=nil||string(b)!="override"{t.Fatal(e)}
}
func TestDDS(t *testing.T){
 for _,kind:=range []string{"DXT1","DXT3","DXT5"}{
  n:=16;if kind=="DXT1"{n=8};b:=make([]byte,128+n);copy(b,"DDS ");binary.LittleEndian.PutUint32(b[4:],124);binary.LittleEndian.PutUint32(b[12:],4);binary.LittleEndian.PutUint32(b[16:],4);binary.LittleEndian.PutUint32(b[76:],32);copy(b[84:],kind)
  if kind=="DXT3"{b[128]=0x08};if kind=="DXT5"{b[128]=127;b[129]=0}
  binary.LittleEndian.PutUint16(b[128+n-8:],0xf800)
  im,_,e:=image.Decode(bytes.NewReader(b));if e!=nil{t.Fatal(kind,e)}
  c:=color.NRGBAModel.Convert(im.At(0,0)).(color.NRGBA);want:=uint8(255);if kind=="DXT3"{want=136};if kind=="DXT5"{want=127};if c.R!=255||c.G!=0||c.B!=0||c.A!=want{t.Fatal(kind,c)}
  if _,_,e=image.Decode(bytes.NewReader(b[:len(b)-1]));e==nil{t.Fatal("truncated DDS accepted")}
 }
}
