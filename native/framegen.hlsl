// Experimental two-frame block-motion interpolation, independent of DXR.
Texture2D<float4> previousFrame : register(t0);
Texture2D<float4> currentFrame : register(t1);
RWTexture2D<float4> generated : register(u0);
RWStructuredBuffer<float4> motion : register(u1);
cbuffer FrameGenParams : register(b0) { uint width,height,gridWidth,gridHeight; };
static const int TILE=16;
int2 bound(int2 p){return clamp(p,int2(0,0),int2(width-1,height-1));}
float luma(float3 c){return dot(c,float3(.2126,.7152,.0722));}
float3 readFrame(bool current,int2 p){
 p=bound(p);return current?currentFrame.Load(int3(p,0)).rgb:previousFrame.Load(int3(p,0)).rgb;
}
float patchError(bool current,int2 p,int2 delta){
 float err=0;
 const int2 offsets[5]={int2(0,0),int2(-5,-5),int2(5,-5),int2(-5,5),int2(5,5)};
 [unroll]for(int i=0;i<5;++i){
  int2 q=p+offsets[i];
  float3 a=readFrame(current,q),b=readFrame(!current,q+delta);
  err+=abs(luma(a)-luma(b))+.2*length(a-b);
 }
 return err*.2;
}
float4 estimate(bool current,int2 p){
 int2 best=int2(0,0);float bestCost=patchError(current,p,best);
 // Penalize long motion in flat regions; coarse search then local refinement.
 [loop]for(int level=0;level<3;++level){
  int stepSize=level==0?8:level==1?2:1;
  int radius=level==0?2:1;int2 center=best;
  [loop]for(int y=-radius;y<=radius;++y)[loop]for(int x=-radius;x<=radius;++x){
   int2 v=center+int2(x,y)*stepSize;
   float cost=patchError(current,p,v)+.0007*length(float2(v));
   if(cost<bestCost){bestCost=cost;best=v;}
  }
 }
 float error=patchError(current,p,best);
 return float4(float2(best),error,1);
}
[numthreads(8,8,1)]void estimateMotion(uint3 tid:SV_DispatchThreadID){
 if(tid.x>=gridWidth||tid.y>=gridHeight)return;
 uint idx=(tid.y*gridWidth+tid.x)*2;
 int2 p=bound(int2(tid.xy)*TILE+TILE/2);
 motion[idx]=estimate(false,p);
 motion[idx+1]=estimate(true,p);
}
float3 sampleFrame(bool current,float2 p){
 int2 a=int2(floor(p)),b=a+1;float2 f=frac(p);
 return lerp(lerp(readFrame(current,a),readFrame(current,int2(b.x,a.y)),f.x),
             lerp(readFrame(current,int2(a.x,b.y)),readFrame(current,b),f.x),f.y);
}
float4 blockMotion(float2 p,uint direction){
 float2 q=p/TILE-.5;int2 a=int2(floor(q));float2 f=frac(q);
 float4 sum=0;float weight=0;
 [unroll]for(int y=0;y<2;++y)[unroll]for(int x=0;x<2;++x){
  int2 b=clamp(a+int2(x,y),int2(0,0),int2(gridWidth-1,gridHeight-1));
  float4 v=motion[(uint(b.y)*gridWidth+uint(b.x))*2+direction];
  float w=(x==0?1-f.x:f.x)*(y==0?1-f.y:f.y)/(1+v.z*12);
  sum+=v*w;weight+=w;
 }
 return sum/max(weight,1e-5);
}
[numthreads(8,8,1)]void interpolateFrame(uint3 tid:SV_DispatchThreadID){
 if(tid.x>=width||tid.y>=height)return;
 float2 p=float2(tid.xy);
 float4 a=blockMotion(p,0),b=blockMotion(p,1);
 // Forward and backward motion predict a midpoint. Refine at estimated source positions.
 a=blockMotion(p-a.xy*.5,0);b=blockMotion(p-b.xy*.5,1);
 float2 pa=p-a.xy*.5,pb=p-b.xy*.5;
 float3 oldColor=sampleFrame(false,pa),newColor=sampleFrame(true,pb);
 float mismatch=length(oldColor-newColor);
 float inconsistent=length(a.xy+b.xy);
 float reliability=1-smoothstep(.06,.24,max(a.z,b.z)+mismatch*.2+inconsistent*.004);
 // At disocclusions, prefer a single source rather than blend unrelated pixels.
 float3 selected=a.z<b.z?oldColor:newColor;
 float3 color=lerp(selected,(oldColor+newColor)*.5,reliability);
 if(max(a.z,b.z)>.28)color=readFrame(true,int2(tid.xy));
 generated[tid.xy]=float4(saturate(color),1);
}
