package main
import "math"
func validExtra(a [8]float64)bool{
 for _,v:=range a{if !finite(v){return false}}
 if a[0]<0||a[0]>262143||a[0]!=math.Trunc(a[0]){return false}
 for _,v:=range a[1:4]{if v<0||v>textureMax||v!=math.Trunc(v){return false}}
 return a[4]>=0&&a[4]<=1&&(a[5]==0||a[5]==1)&&a[6]>=0&&a[6]<=4&&a[6]==math.Trunc(a[6])&&a[7]>=-1&&a[7]<=1&&(a[6]!=4||a[7]>=0)
}

func validCloth(a [8]float64)bool{
 for _,v:=range a{if !finite(v){return false}}
 for _,v:=range a[:4]{if v<0||v>textureMax||v!=math.Trunc(v){return false}}
 return a[4]>=0&&a[4]<=3&&a[4]==math.Trunc(a[4])&&a[5]>=0&&a[5]<=1&&a[6]>=0&&a[6]<=1&&a[5]+a[6]<=1.000001&&(a[7]==0||a[7]==1)
}
