package main
import("encoding/json";"errors";"fmt";"os";"path/filepath";"runtime";"io")
var errOAuthGrant=errors.New("Roblox authorization expired or revoked")
type rememberedOAuth struct { ClientID string; Refresh string }
const oauthStoreLimit=128<<10
func oauthStorePath()(string,error){
 if runtime.GOOS!="windows"{return "",fmt.Errorf("remembered authorization requires Windows DPAPI")}
 root:=os.Getenv("LOCALAPPDATA");if root==""{var e error;root,e=os.UserConfigDir();if e!=nil{return "",e}}
 return filepath.Join(root,"LumenGPU","oauth.dpapi"),nil
}
func validRemembered(v rememberedOAuth)bool{return validClientID(v.ClientID)&&len(v.Refresh)>0&&len(v.Refresh)<=32<<10}
func loadOAuth(path string)(rememberedOAuth,error){
 var v rememberedOAuth
 f,e:=os.Open(path);if e!=nil{return v,e};defer f.Close()
 blob,e:=io.ReadAll(io.LimitReader(f,oauthStoreLimit+1));if e!=nil||len(blob)==0||len(blob)>oauthStoreLimit{return v,fmt.Errorf("invalid encrypted authorization file")}
 plain,e:=unprotectOAuth(blob);if e!=nil{return v,e}
 if json.Unmarshal(plain,&v)!=nil||!validRemembered(v){return rememberedOAuth{},fmt.Errorf("invalid saved authorization")}
 return v,nil
}
func saveOAuth(path,id,refresh string)error{
 v:=rememberedOAuth{ClientID:id,Refresh:refresh};if !validRemembered(v){return fmt.Errorf("invalid authorization record")}
 plain,e:=json.Marshal(v);if e!=nil{return e};blob,e:=protectOAuth(plain);if e!=nil{return e}
 if len(blob)==0||len(blob)>oauthStoreLimit{return fmt.Errorf("invalid encrypted authorization size")}
 dir:=filepath.Dir(path);if e=os.MkdirAll(dir,0700);e!=nil{return e}
 file,e:=os.CreateTemp(dir,"oauth-encrypted-");if e!=nil{return e};defer os.Remove(file.Name());defer file.Close()
 if _,e=file.Write(blob);e!=nil{return e};if e=file.Sync();e!=nil{return e};if e=file.Close();e!=nil{return e}
 return os.Rename(file.Name(),path)
}
func forgetOAuth(path string)error{e:=os.Remove(path);if os.IsNotExist(e){return nil};return e}
