package main

import (
 "context"
 "crypto/rand"
 "crypto/sha256"
 "crypto/subtle"
 "encoding/base64"
 "encoding/json"
 "fmt"
 "io"
 "net"
 "net/http"
 "net/url"
 "os"
 "os/exec"
 "runtime"
 "strings"
 "sync"
 "time"
)

const oauthRedirect = "http://localhost:8766/oauth/callback"
const oauthScope = "legacy-asset:manage"
const oauthBase = "https://apis.roblox.com/oauth/v1/"
type oauthToken struct {
 Access string `json:"access_token"`
 Refresh string `json:"refresh_token"`
 Type string `json:"token_type"`
 Expires int `json:"expires_in"`
 Scope string `json:"scope"`
}
type oauthSession struct { mu sync.Mutex; clientID string; token oauthToken; expiry time.Time; rememberPath string }
func oauthRandom()(string,error){b:=make([]byte,32);if _,e:=rand.Read(b);e!=nil{return "",e};return base64.RawURLEncoding.EncodeToString(b),nil}
func oauthChallenge(v string)string{h:=sha256.Sum256([]byte(v));return base64.RawURLEncoding.EncodeToString(h[:])}
func oauthURL(id,state,verifier string)string{
 q:=url.Values{"client_id":{id},"redirect_uri":{oauthRedirect},"scope":{oauthScope},"response_type":{"code"},"state":{state},"code_challenge":{oauthChallenge(verifier)},"code_challenge_method":{"S256"}}
 return oauthBase+"authorize?"+q.Encode()
}
func validClientID(id string)bool{
 if len(id)<1||len(id)>64{return false}
 for _,r:=range id{if r<'0'||r>'9'{return false}}
 return true
}
func oauthExchange(ctx context.Context, form url.Values)(oauthToken,error){
 var t oauthToken
 req,e:=http.NewRequestWithContext(ctx,"POST",oauthBase+"token",strings.NewReader(form.Encode()));if e!=nil{return t,e}
 req.Header.Set("Content-Type","application/x-www-form-urlencoded")
 c:=&http.Client{Timeout:15*time.Second,CheckRedirect:func(*http.Request,[]*http.Request)error{return http.ErrUseLastResponse}}
 res,e:=c.Do(req);if e!=nil{return t,fmt.Errorf("token service unavailable")};defer res.Body.Close()
 if res.StatusCode!=200{
  var failure struct{Error string}
  if json.NewDecoder(io.LimitReader(res.Body,64<<10)).Decode(&failure)==nil&&failure.Error=="invalid_grant"{return t,errOAuthGrant}
  return t,fmt.Errorf("token exchange HTTP %d; check app settings and consent",res.StatusCode)
 }
 if json.NewDecoder(io.LimitReader(res.Body,64<<10)).Decode(&t)!=nil||t.Access==""||!strings.EqualFold(t.Type,"Bearer")||t.Expires<=0{return oauthToken{},fmt.Errorf("invalid token response")}
 if t.Scope!=""&&!strings.Contains(" "+t.Scope+" "," "+oauthScope+" "){return oauthToken{},fmt.Errorf("asset delivery permission not granted")}
 return t,nil
}
func(s *oauthSession)bearer(ctx context.Context)(string,error){
 s.mu.Lock();defer s.mu.Unlock()
 if s.token.Access!=""&&time.Until(s.expiry)>30*time.Second{return s.token.Access,nil}
 if s.token.Refresh==""{return "",fmt.Errorf("authorization expired; reconnect")}
 t,e:=oauthExchange(ctx,url.Values{"client_id":{s.clientID},"grant_type":{"refresh_token"},"refresh_token":{s.token.Refresh}})
 if e!=nil{return "",e}
 if t.Refresh==""{t.Refresh=s.token.Refresh}
 s.token=t;s.expiry=time.Now().Add(time.Duration(t.Expires)*time.Second)
 if s.rememberPath!=""{if e:=saveOAuth(s.rememberPath,s.clientID,t.Refresh);e!=nil{fmt.Println("[Lumenus] Could not update encrypted authorization; this session will continue.")}}
 return t.Access,nil
}
func openOAuthBrowser(link string){
 if runtime.GOOS=="windows" {if e:=exec.Command("rundll32.exe","url.dll,FileProtocolHandler",link).Start();e==nil{return}}
 fmt.Println("Open this official Roblox authorization URL in your browser:",link)
}
func connectOAuth(ctx context.Context,id string)(*oauthSession,error){
 if !validClientID(id){return nil,fmt.Errorf("invalid OAuth client ID")}
 verifier,e:=oauthRandom();if e!=nil{return nil,e};state,e:=oauthRandom();if e!=nil{return nil,e}
 listener,e:=net.Listen("tcp4","127.0.0.1:8766");if e!=nil{return nil,fmt.Errorf("OAuth callback port 8766 unavailable")}
 defer listener.Close()
 type callback struct{code string; denied bool}
 result:=make(chan callback,1)
 mux:=http.NewServeMux()
 mux.HandleFunc("/oauth/callback",func(w http.ResponseWriter,r *http.Request){
  w.Header().Set("Cache-Control","no-store");w.Header().Set("Referrer-Policy","no-referrer")
  w.Header().Set("Content-Security-Policy","default-src 'none'; frame-ancestors 'none'")
  if r.Method!="GET"||r.Host!="localhost:8766"||subtle.ConstantTimeCompare([]byte(r.URL.Query().Get("state")),[]byte(state))!=1{http.Error(w,"Invalid authorization callback",400);return}
  q:=r.URL.Query();code:=q.Get("code");denied:=q.Get("error")!=""||code==""
  select{case result<-callback{code,denied}:default:http.Error(w,"Callback already received",409);return}
  fmt.Fprintln(w,"Roblox authorization response received. Return to the LumenBridge console.")
 })
 srv:=&http.Server{Handler:mux,ReadHeaderTimeout:3*time.Second,WriteTimeout:5*time.Second}
 defer srv.Close()
 go srv.Serve(listener)
 fmt.Println("[Lumenus] Opening official Roblox consent. Approve only your own registered app.")
 openOAuthBrowser(oauthURL(id,state,verifier))
 timer:=time.NewTimer(3*time.Minute);defer timer.Stop()
 var cb callback
 select{case cb=<-result:case <-timer.C:return nil,fmt.Errorf("authorization timed out");case <-ctx.Done():return nil,ctx.Err()}
 if cb.denied{return nil,fmt.Errorf("authorization cancelled")}
 t,e:=oauthExchange(ctx,url.Values{"client_id":{id},"grant_type":{"authorization_code"},"code":{cb.code},"code_verifier":{verifier},"redirect_uri":{oauthRedirect}})
 if e!=nil{return nil,e};return &oauthSession{clientID:id,token:t,expiry:time.Now().Add(time.Duration(t.Expires)*time.Second)},nil
}
func configureOAuth(ctx context.Context)(*oauthSession,error){
 id:=strings.TrimSpace(os.Getenv("LUMEN_OAUTH_CLIENT_ID"))
 path,pathErr:=oauthStorePath()
 if pathErr==nil {
  saved,e:=loadOAuth(path)
  if e==nil&&(id==""||id==saved.ClientID){
   s:=&oauthSession{clientID:saved.ClientID,token:oauthToken{Refresh:saved.Refresh},rememberPath:path}
   fmt.Println("[Lumenus] Restoring remembered Roblox authorization...")
   if _,e=s.bearer(ctx);e==nil{fmt.Println("[Lumenus] Remembered authorization restored.");return s,nil}
   if e!=errOAuthGrant{return nil,fmt.Errorf("saved authorization could not be refreshed; retry later or run Forget-Roblox.bat to reconnect: %w",e)}
   fmt.Println("[Lumenus] Saved authorization expired or revoked. New consent required.")
   id=saved.ClientID
   if e=forgetOAuth(path);e!=nil{return nil,fmt.Errorf("could not clear expired authorization")}
  }else if e!=nil&&!os.IsNotExist(e){
   fmt.Println("[Lumenus] Saved authorization unreadable. Run Forget-Roblox.bat to clear it, or authorize again.")
  }
 }
 if id==""{fmt.Print("[Lumenus] Enter your registered public OAuth application Client ID (not secret): ");if _,e:=fmt.Scanln(&id);e!=nil{return nil,fmt.Errorf("client ID not provided")}}
 s,e:=connectOAuth(ctx,id);if e!=nil{return nil,e}
 if pathErr==nil&&s.token.Refresh!=""{
  fmt.Print("[Lumenus] Remember authorization on this Windows account? [y/N]: ")
  var answer string;fmt.Scanln(&answer)
  if strings.EqualFold(answer,"y")||strings.EqualFold(answer,"yes"){
   if e:=saveOAuth(path,id,s.token.Refresh);e!=nil{fmt.Println("[Lumenus] Encrypted storage unavailable; authorization remains session-only.")}else{s.rememberPath=path;fmt.Println("[Lumenus] Encrypted authorization saved.")}
  }
 }
 return s,nil
}
