package main
import("fmt";"runtime";"syscall";"unsafe")
type dpapiBlob struct{Size uint32; Data *byte}
var crypt32=syscall.NewLazyDLL("crypt32.dll")
var protectProc=crypt32.NewProc("CryptProtectData")
var unprotectProc=crypt32.NewProc("CryptUnprotectData")
var localFree=syscall.NewLazyDLL("kernel32.dll").NewProc("LocalFree")
func dpapiTransform(data []byte, decrypt bool)([]byte,error){
 if len(data)==0||len(data)>oauthStoreLimit{return nil,fmt.Errorf("invalid DPAPI input")}
 in:=dpapiBlob{uint32(len(data)),&data[0]};var out dpapiBlob
 proc:=protectProc;if decrypt{proc=unprotectProc}
 ret,_,_:=proc.Call(uintptr(unsafe.Pointer(&in)),0,0,0,0,1,uintptr(unsafe.Pointer(&out)))
 runtime.KeepAlive(data)
 if out.Data!=nil{defer localFree.Call(uintptr(unsafe.Pointer(out.Data)))}
 if ret==0||out.Data==nil||out.Size==0||out.Size>oauthStoreLimit{return nil,fmt.Errorf("Windows DPAPI operation failed")}
 return append([]byte(nil),unsafe.Slice(out.Data,int(out.Size))...),nil
}
func protectOAuth(data []byte)([]byte,error){return dpapiTransform(data,false)}
func unprotectOAuth(data []byte)([]byte,error){return dpapiTransform(data,true)}
