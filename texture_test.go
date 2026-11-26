package main
import("bytes";"encoding/binary";"image";"image/color";"image/png";"math";"net/http/httptest";"testing")
func TestTexturePixels(t *testing.T){
 im:=image.NewNRGBA(image.Rect(0,0,2,2));im.SetNRGBA(0,0,color.NRGBA{255,128,7,64});var buf bytes.Buffer;if e:=png.Encode(&buf,im);e!=nil{t.Fatal(e)}
 pixels,e:=decodeTexture(buf.Bytes());if e!=nil||len(pixels)!=65536||pixels[0]!=0x400780ff{t.Fatalf("decode %v",e)}
 b:=&Bridge{textures:map[uint32][]uint32{1:pixels}};w:=httptest.NewRecorder();r:=httptest.NewRequest("GET","http://"+addr+"/api/texture?id=1",nil);b.handler().ServeHTTP(w,r)
 if w.Code!=200||w.Body.Len()!=8+65536*4||string(w.Body.Bytes()[:4])!="LGT1"{t.Fatal("texture packet")}
}
func TestTextureProtocol(t *testing.T){
 p:=Part{Tex:[8]float64{1,3,2,4,0,0,1,1}}
 if !validTexture(p.Tex){t.Fatal("valid texture")}
 p.Tex[0]=129;if validTexture(p.Tex){t.Fatal("invalid slot")};p.Tex[0]=1
 b:=nativePacket(State{Parts:[]Part{p}});if len(b)!=88+144||string(b[:4])!="LGT4"||math.Float32frombits(binary.LittleEndian.Uint32(b[200:]))!=1{t.Fatal("texture wire")}
 v:=[]V{{0,0,0},{1,0,0},{0,1,0}};uv:=[]UV{{0,0},{1,0},{0,1}}
 m:=texturedMeshPacket(v,uv);if len(m)!=68||string(m[:4])!="LGM2"||math.Float32frombits(binary.LittleEndian.Uint32(m[52:]))!=1{t.Fatal("mesh UV packet")}
 d:=fixtureMesh();off:=len("version 2.00\n")+12+24;binary.LittleEndian.PutUint32(d[off:],math.Float32bits(.25));binary.LittleEndian.PutUint32(d[off+4:],math.Float32bits(.75))
 z:=decodeLumenUV(d,3);if len(z)!=3||z[0]!=(UV{.25,.75}){t.Fatal("external UV decode")}
}

func TestAdaptiveTextureResolution(t *testing.T){
 if textureResolution(585,559,0,0)!=1024{t.Fatal("classic atlas downsampled")}
 if textureResolution(400,400,0,0)!=512{t.Fatal("medium image")}
 if textureResolution(1024,1024,texturePixelBudget-128*256*256,0)!=256{t.Fatal("budget reserve")}
 im:=image.NewNRGBA(image.Rect(0,0,585,559));im.SetNRGBA(584,558,color.NRGBA{255,128,7,255});var buf bytes.Buffer;if e:=png.Encode(&buf,im);e!=nil{t.Fatal(e)}
 pixels,e:=decodeTextureBudget(buf.Bytes(),0,0);if e!=nil||len(pixels)!=1024*1024||pixels[len(pixels)-1]!=0xff0780ff{t.Fatalf("HD decode %v",e)}
 b:=&Bridge{textures:map[uint32][]uint32{1:pixels}};w:=httptest.NewRecorder();b.textureHandler(w,httptest.NewRequest("GET","http://"+addr+"/api/texture?id=1",nil))
 if w.Code!=200||w.Body.Len()!=8+1024*1024*4||binary.LittleEndian.Uint32(w.Body.Bytes()[4:])!=1024{t.Fatal("HD texture wire")}
}
