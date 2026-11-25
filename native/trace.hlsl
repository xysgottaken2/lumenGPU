// DXR 1.1 inline ray queries. Triangle instances use the same unit cube BLAS.
RaytracingAccelerationStructure scene : register(t0);
struct Material { float4 colorMetal; float4 roughEmit; float4 ax; float4 ay; float4 az; };
StructuredBuffer<Material> mats : register(t1);
RWStructuredBuffer<float4> history : register(u0);
RWTexture2D<float4> output : register(u1);
cbuffer Params : register(b0) {
 float4 dims; // width height frame history count
 float4 eye; // xyz tan(vertical FOV/2)
 float4 right; float4 up; float4 forward; float4 sun;
 float4 options; // bounces spp exposure unused
};
uint hash(uint x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; return x ^ (x >> 16); }
float rnd(inout uint s) { s=hash(s+0x9e3779b9u); return float(s>>8)*(1.0/16777216.0); }
float3 cosine(float3 n,inout uint s) {
 float phi=6.2831853*rnd(s), r=sqrt(rnd(s));
 float3 t=normalize(cross(abs(n.y)>.95?float3(1,0,0):float3(0,1,0),n));
 return normalize(t*(r*cos(phi))+cross(n,t)*(r*sin(phi))+n*sqrt(max(0,1-r*r)));
}
float3 sky(float3 d) { return lerp(float3(.18,.20,.24),float3(.48,.70,1),saturate(d.y*.5+.5))*.65; }
RayDesc ray(float3 o,float3 d,float limit) { RayDesc r; r.Origin=o; r.Direction=d; r.TMin=.002; r.TMax=limit; return r; }
bool blocked(float3 o,float3 d) {
 RayQuery<RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> q;
 q.TraceRayInline(scene,RAY_FLAG_NONE,255,ray(o,d,2000)); while(q.Proceed()) {} return q.CommittedStatus()==COMMITTED_TRIANGLE_HIT;
}
float3 path(float3 o,float3 d,inout uint seed) {
 float3 beta=1, L=0;
 for(uint i=0;i<=uint(options.x);++i) {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  q.TraceRayInline(scene,RAY_FLAG_NONE,255,ray(o,d,2000)); while(q.Proceed()) {}
  if(q.CommittedStatus()!=COMMITTED_TRIANGLE_HIT) { L+=beta*sky(d); break; }
  Material m=mats[q.CommittedInstanceID()];
  uint face=q.CommittedPrimitiveIndex()/2;
  float3 n=face<2?m.ax.xyz:(face<4?m.ay.xyz:m.az.xyz);
  if(face%2==1) n=-n; if(dot(n,d)>0) n=-n;
  float3 p=o+d*q.CommittedRayT();
  float3 c=pow(saturate(m.colorMetal.xyz),2.2); float metal=m.colorMetal.w, rough=m.roughEmit.x;
  L+=beta*c*m.roughEmit.y;
  float nd=saturate(dot(n,sun.xyz));
  if(nd>0 && metal<.999 && !blocked(p+n*.003,sun.xyz)) L+=beta*c*(1-metal)*nd*float3(1.6,1.48,1.27);
  if(i==uint(options.x)) break;
  if(rnd(seed)<metal) { float3 mirror=reflect(d,n); d=normalize(lerp(mirror,cosine(n,seed),rough*rough)); if(dot(d,n)<=0)d=mirror; }
  else d=cosine(n,seed);
  beta*=c; o=p+n*.003;
 }
 return min(L,30);
}
[numthreads(8,8,1)] void main(uint3 id:SV_DispatchThreadID) {
 uint w=uint(dims.x),h=uint(dims.y); if(id.x>=w||id.y>=h)return;
 uint idx=id.y*w+id.x,seed=hash(idx+uint(dims.z)*1973u+123u);
 float3 color=0; uint spp=uint(options.y);
 for(uint i=0;i<spp;++i){float2 uv=(float2(id.xy)+float2(rnd(seed),rnd(seed)))/float2(w,h)*2-1;
 float3 dir=normalize(forward.xyz+right.xyz*uv.x*eye.w*float(w)/float(h)-up.xyz*uv.y*eye.w); color+=path(eye.xyz,dir,seed);}
 color/=spp;
 if(dims.w>0)color=lerp(history[idx].xyz,color,1/(dims.w+1)); history[idx]=float4(color,1);
 color*=exp2(options.z); color=saturate((color*(2.51*color+.03))/(color*(2.43*color+.59)+.14));
 output[id.xy]=float4(pow(color,1/2.2),1);
}
