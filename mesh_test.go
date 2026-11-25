package main
import("testing";"net/http/httptest";"strings";"encoding/binary")
func TestMeshRegistry(t *testing.T){
 b:= &Bridge{};h:=b.handler()
 call:=func(method,path,body string)*httptest.ResponseRecorder{r:=httptest.NewRequest(method,"http://"+addr+path,strings.NewReader(body));w:=httptest.NewRecorder();h.ServeHTTP(w,r);return w}
 payload:=`{"id":42,"vertices":[[0,0,0],[1,0,0],[0,1,0]]}`
 if w:=call("POST","/api/mesh",payload);w.Code!=204{t.Fatal(w.Code,w.Body.String())}
 if w:=call("POST","/api/mesh",payload);w.Code!=204{t.Fatal("retry",w.Code)}
 if w:=call("POST","/api/mesh",`{"id":42,"vertices":[[0,0,0],[2,0,0],[0,1,0]]}`);w.Code!=409{t.Fatal("collision",w.Code)}
 if w:=call("POST","/api/mesh",`{"id":1,"vertices":[[0,0,0],[1,0,0],[0,1,0]]}`);w.Code!=400{t.Fatal("reserved id",w.Code)}
 w:=call("GET","/api/mesh?id=42","");p:=w.Body.Bytes();if w.Code!=200||len(p)!=44||string(p[:4])!="LGM1"||binary.LittleEndian.Uint32(p[4:])!=3{t.Fatal("mesh packet",w.Code)}
 if w:=call("GET","/api/mesh?id=43","");w.Code!=404{t.Fatal("missing mesh",w.Code)}
}
