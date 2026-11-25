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
 float4 options; // bounces spp exposure debug view
 float4 quality; // distance sky sun ambient
 float4 switches; // GI, reflections, glass, tonemap
};
uint hash(uint x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; return x ^ (x >> 16); }
float rnd(inout uint s) { s=hash(s+0x9e3779b9u); return float(s>>8)*(1.0/16777216.0); }
float3 cosine(float3 n,inout uint s) {
 float phi=6.2831853*rnd(s), r=sqrt(rnd(s));
 float3 t=normalize(cross(abs(n.y)>.95?float3(1,0,0):float3(0,1,0),n));
 return normalize(t*(r*cos(phi))+cross(n,t)*(r*sin(phi))+n*sqrt(max(0,1-r*r)));
}
float3 sky(float3 d) { return lerp(float3(.32,.46,.65),float3(.20,.44,.95),saturate(d.y))*.9*quality.y; }
RayDesc ray(float3 o,float3 d,float limit) { RayDesc r; r.Origin=o; r.Direction=d; r.TMin=.002; r.TMax=limit; return r; }
bool blocked(float3 o,float3 d) {
 RayQuery<RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> q;
 q.TraceRayInline(scene,RAY_FLAG_NONE,255,ray(o,d,quality.x)); while(q.Proceed()) {} return q.CommittedStatus()==COMMITTED_TRIANGLE_HIT;
}
float3 path(float3 o,float3 d,inout uint seed) {
 float3 beta=1, L=0;
 if(options.w==3) return sky(d);
 for(uint i=0;i<=uint(options.x);++i) {
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  q.TraceRayInline(scene,RAY_FLAG_NONE,255,ray(o,d,quality.x)); while(q.Proceed()) {}
  if(q.CommittedStatus()!=COMMITTED_TRIANGLE_HIT) { L+=beta*sky(d); break; }
  Material m=mats[q.CommittedInstanceID()];
  uint face=q.CommittedPrimitiveIndex()/2;
  float3 n=face<2?m.ax.xyz:(face<4?m.ay.xyz:m.az.xyz);
  if(face%2==1) n=-n;
  bool entering=dot(n,d)<0; if(!entering)n=-n;
  float3 p=o+d*q.CommittedRayT();
  float3 c=pow(saturate(m.colorMetal.xyz),2.2); float metal=saturate(m.colorMetal.w), rough=saturate(m.roughEmit.x);
  if(options.w==1) return c;
  if(options.w==2) return n*.5+.5;
  // Small diffuse ambient floor for this prototype; not physically exact GI.
  float trans=saturate(m.roughEmit.z)*switches.z;
  if(i==0) L+=c*(1-metal)*(1-trans)*quality.w;
  L+=beta*c*m.roughEmit.y;
  float nd=saturate(dot(n,sun.xyz));
  if(nd>0 && metal<.999 && !blocked(p+n*.003,sun.xyz)) L+=beta*c*(1-metal)*(1-trans)*nd*float3(1.6,1.48,1.27)*quality.z;
  if(i==uint(options.x)) break;
  if(trans>0 && rnd(seed)<trans) {
   float ior=clamp(m.roughEmit.w,1.01,2.5), eta=entering?1/ior:ior;
   float f0=(ior-1)/(ior+1);f0*=f0;
   float fresnel=f0+(1-f0)*pow(1-saturate(-dot(n,d)),5);
   float3 refr=refract(d,n,eta);
   bool refl=dot(refr,refr)<.001 || (switches.y>0 && rnd(seed)<fresnel);
   d=refl?reflect(d,n):normalize(refr);
   if(!refl && entering)beta*=lerp(float3(1,1,1),c,.35);
   o=p+(refl?n:-n)*.003;continue;
  }
  float fresnel=.04+.96*pow(1-saturate(-dot(n,d)),5);
  float specProb=lerp(fresnel,1,metal)*switches.y;
  if(rnd(seed)<specProb) {
   // GGX half-vector sampling, approximate throughput for this preview integrator.
   float a=max(.03,rough*rough),u=rnd(seed),phi=6.2831853*rnd(seed);
   float ct=sqrt((1-u)/max(1e-6,1+(a*a-1)*u)),st=sqrt(max(0,1-ct*ct));
   float3 t=normalize(cross(abs(n.y)>.95?float3(1,0,0):float3(0,1,0),n));
   float3 h=normalize(t*(st*cos(phi))+cross(n,t)*(st*sin(phi))+n*ct);
   float3 r=reflect(d,h);d=dot(r,n)>.001?r:reflect(d,n);beta*=lerp(float3(1,1,1),c,metal);
  } else {if(switches.x==0)break;d=cosine(n,seed);beta*=c*(1-metal);}
  o=p+n*.003;
 }
 return min(L,30);
}
[numthreads(8,8,1)] void main(uint3 id:SV_DispatchThreadID) {
 uint w=uint(dims.x),h=uint(dims.y); if(id.x>=w||id.y>=h)return;
 uint idx=id.y*w+id.x,seed=hash(idx+uint(dims.z)*1973u+123u);
 float3 color=0; uint spp=uint(options.y);
 for(uint i=0;i<spp;++i){float2 uv=(float2(id.xy)+float2(rnd(seed),rnd(seed)))/float2(w,h)*2-1;
 float3 dir=normalize(forward.xyz+right.xyz*uv.x*eye.w*float(w)/float(h)-up.xyz*uv.y*eye.w); color+=path(eye.xyz,dir,seed);}
 color/=max(spp,1u);
 if(any(isnan(color)) || any(isinf(color))) color=float3(1,0,1);
 if(dims.w>0)color=lerp(history[idx].xyz,color,1/(dims.w+1)); history[idx]=float4(color,1);
 color*=exp2(options.z);
 if(switches.w==0)color=saturate((color*(2.51*color+.03))/(color*(2.43*color+.59)+.14));
 else if(switches.w==1)color=color/(1+color);
 else color=saturate(color);
 output[id.xy]=float4(pow(saturate(color),1.0/2.2),1);
}
