package main
import("bytes";"os";"path/filepath";"testing")
func TestRememberOAuthDPAPI(t *testing.T){
 path:=filepath.Join(t.TempDir(),"oauth.dpapi")
 if e:=saveOAuth(path,"123","synthetic-refresh-token-one");e!=nil{t.Fatal(e)}
 data,e:=os.ReadFile(path);if e!=nil||bytes.Contains(data,[]byte("synthetic-refresh-token-one")){t.Fatal("plaintext or missing encrypted record")}
 v,e:=loadOAuth(path);if e!=nil||v.ClientID!="123"||v.Refresh!="synthetic-refresh-token-one"{t.Fatal("DPAPI roundtrip failed",e)}
 if e=saveOAuth(path,"123","synthetic-refresh-token-two");e!=nil{t.Fatal("rotation",e)}
 v,e=loadOAuth(path);if e!=nil||v.Refresh!="synthetic-refresh-token-two"{t.Fatal("rotated token not retained",e)}
 if e=forgetOAuth(path);e!=nil{t.Fatal(e)};if _,e=loadOAuth(path);!os.IsNotExist(e){t.Fatal("logout failed")}
 if e=forgetOAuth(path);e!=nil{t.Fatal("repeat logout",e)}
}
