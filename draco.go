package main
import("bytes";"context";"encoding/binary";"fmt";"os";"os/exec";"path/filepath";"runtime";"strings";"time")
type limitedDracoOutput struct{bytes.Buffer;limit int}
func(b *limitedDracoOutput)Write(p []byte)(int,error){
 if len(p)>b.limit-b.Len(){return 0,fmt.Errorf("decoder output limit")};return b.Buffer.Write(p)
}
func dracoHelper()string{
 exe,e:=os.Executable();if e!=nil{return ""}
 name:="LumenDraco";if runtime.GOOS=="windows"{name+=".exe"};return filepath.Join(filepath.Dir(exe),name)
}
func runDraco(ctx context.Context,helper string,chunk []byte)([]byte,error){
 if len(chunk)<9||uint64(binary.LittleEndian.Uint32(chunk))!=uint64(len(chunk)-4)||!bytes.HasPrefix(chunk[4:],[]byte("DRACO")){return nil,fmt.Errorf("invalid Draco COREMESH length or magic")}
 if helper==""{return nil,fmt.Errorf("LumenDraco executable path unavailable")}
 ctx,cancel:=context.WithTimeout(ctx,20*time.Second);defer cancel()
 cmd:=exec.CommandContext(ctx,helper)
 cmd.Stdin=bytes.NewReader(chunk[4:])
 out:=&limitedDracoOutput{limit:8+200000*40+200000*12};errout:=&limitedDracoOutput{limit:4096}
 cmd.Stdout=out;cmd.Stderr=errout
 // Don't pass Lumenus authentication environment to a geometry-only process.
 cmd.Env=[]string{};for _,k:=range []string{"SystemRoot","WINDIR","TEMP","TMP","TMPDIR"}{if v,ok:=os.LookupEnv(k);ok{cmd.Env=append(cmd.Env,k+"="+v)}}
 if e:=cmd.Run();e!=nil{
  if ctx.Err()!=nil{return nil,fmt.Errorf("Draco decode timed out or cancelled")}
  msg:=strings.TrimSpace(errout.String());if msg==""{msg="decoder failed or LumenDraco executable missing"}
  return nil,fmt.Errorf("Draco: %s",msg)
 }
 return out.Bytes(),nil
}
