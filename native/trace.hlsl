RaytracingAccelerationStructure scene : register(t0);
struct Material {float4 colorMetal,roughEmit,ax,ay,az,scaleSpec,emitColor;};
StructuredBuffer<Material> mats : register(t1);
StructuredBuffer<float3> meshNormals : register(t2);
RWStructuredBuffer<float4> history : register(u0);
RWTexture2D<float4> output : register(u1);
RWStructuredBuffer<float4> guides : register(u2);
RWStructuredBuffer<float4> albedos : register(u3);
cbuffer Params : register(b0) {
 float4 dims,eye,right,up,forward,sun,options,quality,switches,display;
};
static const float PI=3.14159265;
uint hash(uint x){x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
float rnd(inout uint s){s=hash(s+0x9e3779b9u);return float(s>>8)*(1.0/16777216.0);}
float3 basis(float3 n,float x,float y,float z){float3 t=normalize(cross(abs(n.y)>.95?float3(1,0,0):float3(0,1,0),n));return normalize(t*x+cross(n,t)*y+n*z);}
float3 cosine(float3 n,inout uint s){float phi=2*PI*rnd(s),r=sqrt(rnd(s));return basis(n,r*cos(phi),r*sin(phi),sqrt(max(0,1-r*r)));}
float3 linearColor(float3 c){c=saturate(c);return lerp(c/12.92,pow((c+.055)/1.055,2.4),step(.04045,c));}
float3 sky(float3 d){return lerp(float3(.32,.46,.65),float3(.20,.44,.95),saturate(d.y))*.9*quality.y;}
RayDesc ray(float3 o,float3 d,float limit){RayDesc r;r.Origin=o;r.Direction=d;r.TMin=.001;r.TMax=limit;return r;}
bool blocked(float3 o,float3 d){RayQuery<RAY_FLAG_FORCE_OPAQUE|RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> q;q.TraceRayInline(scene,RAY_FLAG_NONE,255,ray(o,d,quality.x));while(q.Proceed()){}return q.CommittedStatus()==COMMITTED_TRIANGLE_HIT;}
float smith(float n,float a2){return 2*n/max(1e-6,n+sqrt(a2+(1-a2)*n*n));}
float3 fresnel(float v,float3 f0){return f0+(1-f0)*pow(1-saturate(v),5);}
float powerWeight(float a,float b){return a*a/max(1e-12,a*a+b*b);}
float3 evalBSDF(float3 n,float3 wo,float3 wi,float3 base,float metal,float rough,float ior,float spec,float q,out float pdf){
 float nv=dot(n,wo),nl=dot(n,wi);pdf=0;if(nv<=0||nl<=0)return 0;
 float3 h=normalize(wo+wi);float nh=saturate(dot(n,h)),vh=max(1e-6,dot(wo,h));
 float a=rough*rough,a2=a*a,den=nh*nh*(a2-1)+1,D=a2/max(1e-8,PI*den*den);
 float f0=(ior-1)/(ior+1);f0*=f0;
 float3 F=fresnel(vh,lerp(float3(f0,f0,f0),base,metal))*(metal+(1-metal)*spec)*switches.y;
 float3 glossy=F*(D*smith(nv,a2)*smith(nl,a2)/max(1e-6,4*nv*nl));
 float3 diffuse=(1-F)*base*((1-metal)/PI);
 pdf=(1-q)*nl/PI+q*D*nh/(4*vh);
 return diffuse+glossy;
}
float3 sunDirection(inout uint seed){float r=sqrt(rnd(seed))*sun.w,phi=2*PI*rnd(seed);return basis(normalize(sun.xyz),r*cos(phi),r*sin(phi),1);}
float3 path(float3 o,float3 d,inout uint seed,out float4 guide,out float4 alb){
 float3 beta=1,L=0;guide=0;alb=0;float prevPdf=0;bool prevDelta=true;bool prevSkyNEE=false;
 if(options.w==3)return sky(d);
 for(uint i=0;i<=uint(options.x);++i){
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;q.TraceRayInline(scene,RAY_FLAG_NONE,255,ray(o,d,quality.x));while(q.Proceed()){}
  if(q.CommittedStatus()!=COMMITTED_TRIANGLE_HIT){if(options.w>=4)return 1;L+=beta*sky(d)*(prevDelta||!prevSkyNEE?1:powerWeight(prevPdf,1/(2*PI)));break;}
  Material m=mats[q.CommittedInstanceID()];uint primitive=q.CommittedPrimitiveIndex();uint shape=uint(m.ax.w);
  float3 localP=q.CommittedObjectRayOrigin()+q.CommittedObjectRayDirection()*q.CommittedRayT();
  float3 ln;
  if(shape==3)ln=meshNormals[uint(m.ay.w)+primitive];
  else if(shape==1)ln=normalize(localP);
  else if(shape==2){uint face=primitive%4;if(face==2)ln=float3(-1,0,0);else if(face==3)ln=float3(1,0,0);else ln=normalize(float3(0,localP.y,localP.z));}
  else {uint face=primitive/2;ln=face<2?float3(1,0,0):face<4?float3(0,1,0):float3(0,0,1);if(face%2==1)ln=-ln;}
  float3 invN=ln/max(m.scaleSpec.xyz,.0001);float3 gn=normalize(m.ax.xyz*invN.x+m.ay.xyz*invN.y+m.az.xyz*invN.z);
  bool entering=dot(gn,d)<0;float3 n=entering?gn:-gn,wo=-d;
  float3 p=o+d*q.CommittedRayT(),c=linearColor(m.colorMetal.xyz);
  float metal=saturate(m.colorMetal.w),rough=clamp(m.roughEmit.x,.025,1),ior=clamp(m.roughEmit.w,1.001,3),spec=saturate(m.scaleSpec.w);
  float trans=saturate(m.roughEmit.z)*(1-metal)*switches.z,opaque=1-trans;
  float prob=(spec>0||metal>0)?(.25+.65*metal)*switches.y:0;
  if(i==0){guide=float4(n,q.CommittedRayT());alb=float4(c,float(q.CommittedInstanceID()+1));}
  if(options.w==1)return c;if(options.w==2)return n*.5+.5;
  if(options.w==4){float v=saturate(dot(n,sun.xyz));return v>0&&!blocked(p+n*.003,sun.xyz)?v:0;}
  if(options.w==5)return blocked(p+n*.003,float3(0,1,0))?0:1;
  if(i==0)L+=c*(1-metal)*opaque*quality.w;
  if(entering)L+=beta*linearColor(m.emitColor.xyz)*m.roughEmit.y;
  if(opaque>0&&entering){
   float3 wi=sunDirection(seed);float nl=dot(n,wi),pdf;
   float3 f=evalBSDF(n,wo,wi,c,metal,rough,ior,spec,prob,pdf);
   if(nl>0&&quality.z>0&&!blocked(p+n*.003,wi))L+=beta*f*opaque*nl*float3(5,4.65,4)*quality.z;
   if(switches.x>0){float z=rnd(seed),phi=2*PI*rnd(seed),r=sqrt(1-z*z);wi=basis(n,r*cos(phi),r*sin(phi),z);f=evalBSDF(n,wo,wi,c,metal,rough,ior,spec,prob,pdf);
    float lp=1/(2*PI);if(!blocked(p+n*.003,wi))L+=beta*f*opaque*sky(wi)*(z/lp)*(i==uint(options.x)?1:powerWeight(lp,pdf*opaque));}
  }
  if(i==uint(options.x))break;
  if(trans>0&&(!entering||rnd(seed)<trans)){
   float eta=entering?1/ior:ior,ci=saturate(dot(n,wo)),st2=eta*eta*(1-ci*ci);
   bool reflectIt=st2>=1;float ct=sqrt(max(0,1-st2));
   if(!reflectIt){float ei=entering?1:ior,et=entering?ior:1;float rs=(ei*ci-et*ct)/max(1e-6,ei*ci+et*ct),rp=(et*ci-ei*ct)/max(1e-6,et*ci+ei*ct);reflectIt=switches.y>0&&rnd(seed)<.5*(rs*rs+rp*rp);}
   d=reflectIt?reflect(d,n):normalize(refract(d,n,eta));
   if(!reflectIt)beta*=(entering?c:float3(1,1,1))*eta*eta;
   o=p+(reflectIt?n:-n)*.003;prevDelta=true;prevSkyNEE=false;continue;
  }
  float3 wi;
  if(rnd(seed)<prob){float a=rough*rough,u=rnd(seed),phi=2*PI*rnd(seed),ct=sqrt((1-u)/max(1e-6,1+(a*a-1)*u));float st=sqrt(max(0,1-ct*ct));float3 h=basis(n,st*cos(phi),st*sin(phi),ct);if(dot(wo,h)<=0)break;wi=reflect(d,h);}
  else {if(switches.x==0)break;wi=cosine(n,seed);}
  float pdf;float3 f=evalBSDF(n,wo,wi,c,metal,rough,ior,spec,prob,pdf);float nl=dot(n,wi);if(pdf<=0||nl<=0)break;
  beta*=f*(nl/pdf);prevPdf=pdf*opaque;prevDelta=false;prevSkyNEE=entering&&switches.x>0&&opaque>0;
  if(i>=3){float rr=clamp(max(beta.x,max(beta.y,beta.z)),.05,.95);if(rnd(seed)>=rr)break;beta/=rr;}
  o=p+n*.003;d=wi;
 }
 return min(L,40);
}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){
 uint w=uint(dims.x),h=uint(dims.y);if(id.x>=w||id.y>=h)return;
 uint idx=id.y*w+id.x,seed=hash(idx+uint(dims.z)*1973u+123u);float3 color=0;float4 g=0,a=0;uint spp=max(1u,uint(options.y));
 for(uint i=0;i<spp;++i){float2 uv=(float2(id.xy)+float2(rnd(seed),rnd(seed)))/float2(w,h)*2-1;float3 dir=normalize(forward.xyz+right.xyz*uv.x*eye.w*display.x/display.y-up.xyz*uv.y*eye.w);float4 gg,aa;color+=path(eye.xyz,dir,seed,gg,aa);if(i==0){g=gg;a=aa;}}
 color/=spp;if(any(isnan(color))||any(isinf(color)))color=float3(1,0,1);
 if(dims.w>0)color=lerp(history[idx].xyz,color,1/(dims.w+1));history[idx]=float4(color,1);guides[idx]=g;albedos[idx]=a;
}
float weightGuide(float4 g,float4 a,float4 gg,float4 aa){
 if((g.w==0)!=(gg.w==0))return 0;
 if(g.w==0)return 1;
 float wn=pow(saturate(dot(g.xyz,gg.xyz)),32);
 float wz=exp(-abs(g.w-gg.w)/max(.05,g.w*.035*display.w));
 float wa=exp(-length(a.xyz-aa.xyz)*8);
 return wn*wz*wa;
}
[numthreads(8,8,1)]void resolve(uint3 id:SV_DispatchThreadID){
 uint w=uint(dims.x),h=uint(dims.y),ow=uint(display.x),oh=uint(display.y);if(id.x>=ow||id.y>=oh)return;
 float2 pos=(float2(id.xy)+.5)*float2(w,h)/float2(ow,oh)-.5;int2 center=clamp(int2(floor(pos+.5)),int2(0,0),int2(w-1,h-1));uint idx=center.y*w+center.x;
 float3 c=history[idx].xyz;
 if(display.z>0){float4 g=guides[idx],a=albedos[idx];float3 sum=0;float ws=0;int r=int(display.w);
 for(int y=-r;y<=r;++y)for(int x=-r;x<=r;++x){int2 xy=clamp(center+int2(x,y),int2(0,0),int2(w-1,h-1));uint j=xy.y*w+xy.x;float k=exp(-float(x*x+y*y)/max(.5,2*display.z*display.z*r))*weightGuide(g,a,guides[j],albedos[j]);sum+=history[j].xyz*k;ws+=k;}
 c=sum/max(ws,1e-6);
 }else if(w!=ow||h!=oh){int2 a=clamp(int2(floor(pos)),int2(0,0),int2(w-1,h-1)),b=clamp(int2(floor(pos))+1,int2(0,0),int2(w-1,h-1));float2 f=frac(pos);c=lerp(lerp(history[a.y*w+a.x].xyz,history[a.y*w+b.x].xyz,f.x),lerp(history[b.y*w+a.x].xyz,history[b.y*w+b.x].xyz,f.x),f.y);}
 c*=exp2(options.z);if(switches.w==0)c=saturate(c*(2.51*c+.03)/(c*(2.43*c+.59)+.14));else if(switches.w==1)c=c/(1+c);else c=saturate(c);output[id.xy]=float4(pow(saturate(c),1/2.2),1);
}
