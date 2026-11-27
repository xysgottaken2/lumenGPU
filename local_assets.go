package main
import("fmt";"os";"path/filepath";"strings";"sort")
func validLocalAsset(kind,asset string)bool{
 if !strings.HasPrefix(asset,"local-"){return false}
 name:=strings.TrimPrefix(asset,"local-");if len(name)<3||len(name)>96||strings.Contains(name,".."){return false}
 for _,r:=range name{if !(r>='a'&&r<='z'||r>='0'&&r<='9'||r=='_'||r=='-'||r=='.'){return false}}
 ext:=filepath.Ext(name)
 if kind=="mesh"{return ext==".mesh"}
 return kind=="image"&&(ext==".png"||ext==".jpg"||ext==".jpeg"||ext==".dds")
}
func localCandidates(root,appdata,kind,asset string)[]string{
 if !validLocalAsset(kind,asset){return nil}
 name:=strings.TrimPrefix(asset,"local-");folder:="textures";if kind=="mesh"{folder="meshes"}
 paths:=[]string{filepath.Join(root,folder,name)}
 if kind=="image"&&strings.HasPrefix(name,"mtrl_"){paths=append(paths,filepath.Join(root,"materials",name),filepath.Join(root,"textures","TerrainTools",name))}
 if appdata==""{return paths}
 versions:=filepath.Join(appdata,"Roblox","Versions")
 dirs,_:=os.ReadDir(versions)
 sort.SliceStable(dirs,func(i,j int)bool{a,e:=dirs[i].Info();b,f:=dirs[j].Info();if e==nil&&f==nil&&!a.ModTime().Equal(b.ModTime()){return a.ModTime().After(b.ModTime())};return dirs[i].Name()>dirs[j].Name()})
 for _,d:=range dirs{if !d.IsDir()||!strings.HasPrefix(d.Name(),"version-"){continue};base:=filepath.Join(versions,d.Name(),"content")
  if kind=="mesh"{
   paths=append(paths,filepath.Join(base,"avatar","meshes",name),filepath.Join(base,"avatar","heads",name))
  }else{
   paths=append(paths,filepath.Join(base,"textures",name),filepath.Join(base,"textures","particles",name),filepath.Join(base,"particles",name))
   if strings.HasPrefix(name,"mtrl_"){paths=append(paths,filepath.Join(base,"textures","TerrainTools",name),filepath.Join(base,"studio","textures","TerrainTools",name),filepath.Join(base,"TerrainTools",name))}
   if name=="studs.dds"{paths=append(paths,filepath.Join(versions,d.Name(),"PlatformContent","pc","textures",name),filepath.Join(base,"textures","ui",name))}
  }
 }
 return paths
}
func(l *Lumenus)fetchLocal(a assetRequest)([]byte,error){
 root:=filepath.Dir(l.imports)
 for _,p:=range localCandidates(root,os.Getenv("LOCALAPPDATA"),a.Kind,a.Asset){
  info,e:=os.Stat(p);if e!=nil||!info.Mode().IsRegular(){continue}
  f,e:=os.Open(p);if e!=nil{continue};data,e:=readLimited(f,assetLimit);f.Close();return data,e
 }
 return nil,fmt.Errorf("local asset not found; copy it into textures/ or meshes/ beside LumenBridge.exe")
}
