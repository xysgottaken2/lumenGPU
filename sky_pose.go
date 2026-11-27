package main
import "math"
func validSky(e Environment)bool{
 active:=false
 for _,slot:=range e.SkySlots{if slot>textureMax{return false};if slot>0{active=true}}
 for _,v:=range e.SkyBasis{if !finite(v)||math.Abs(v)>1.01{return false}}
 if !active{return e.SkyBasis==[9]float64{}}
 for i:=0;i<9;i+=3{if !axis(V{e.SkyBasis[i],e.SkyBasis[i+1],e.SkyBasis[i+2]}){return false}}
 for i:=0;i<3;i++{for j:=i+1;j<3;j++{dot:=0.;for k:=0;k<3;k++{dot+=e.SkyBasis[i*3+k]*e.SkyBasis[j*3+k]};if math.Abs(dot)>.03{return false}}}
 return true
}
