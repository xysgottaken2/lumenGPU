package main
import("net/url";"testing")
func TestOAuthPKCE(t *testing.T){
 v:="dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
 if oauthChallenge(v)!="E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"{t.Fatal("PKCE challenge")}
 u,e:=url.Parse(oauthURL("123","state",v));if e!=nil||u.Host!="apis.roblox.com"||u.Query().Get("scope")!=oauthScope||u.Query().Get("redirect_uri")!=oauthRedirect||u.Query().Get("client_secret")!=""{t.Fatal("authorization URL")}
 for _,id:=range []string{"","abc","1&scope=openid"}{if validClientID(id){t.Fatal("invalid ID accepted")}}
}
