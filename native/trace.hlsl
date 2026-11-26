RaytracingAccelerationStructure scene : register(t0);
struct Material {float4 colorMetal,roughEmit,ax,ay,az,scaleSpec,emitColor,tex0,tex1;};
StructuredBuffer<Material> mats : register(t1);
StructuredBuffer<float3> meshNormals : register(t2);
RWStructuredBuffer<float4> history : register(u0);
RWTexture2D<float4> output : register(u1);
RWStructuredBuffer<float4> guides : register(u2);
RWStructuredBuffer<float4> albedos : register(u3);
RWStructuredBuffer<float4> waveA : register(u4);
RWStructuredBuffer<float4> waveB : register(u5);
StructuredBuffer<uint> sunPixels : register(t3);
cbuffer Params : register(b0) {
 float4 dims,eye,right,up,forward,sun,options,quality,switches,display,environment;
};
static const float PI=3.14159265;
uint hash(uint x){x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
float rnd(inout uint s){s=hash(s+0x9e3779b9u);return float(s>>8)*(1.0/16777216.0);}
float3 basis(float3 n,float x,float y,float z){float3 t=normalize(cross(abs(n.y)>.95?float3(1,0,0):float3(0,1,0),n));return normalize(t*x+cross(n,t)*y+n*z);}
float3 cosine(float3 n,inout uint s){float phi=2*PI*rnd(s),r=sqrt(rnd(s));return basis(n,r*cos(phi),r*sin(phi),sqrt(max(0,1-r*r)));}
float3 linearColor(float3 c){c=saturate(c);return lerp(c/12.92,pow((c+.055)/1.055,2.4),step(.04045,c));}
float4 assetTexel(uint base,uint2 p){uint v=sunPixels[base+p.y*256+p.x];return float4(v&255u,(v>>8)&255u,(v>>16)&255u,(v>>24)&255u)/255.;}
float4 assetSample(uint base,float2 uv,bool wrap){
 float2 coord=wrap?frac(uv)*256-.5:saturate(uv)*255;
 int2 a=int2(floor(coord)),b=a+1;float2 f=frac(coord);
 uint2 p0=wrap?uint2(a&255):uint2(clamp(a,0,255));
 uint2 p1=wrap?uint2(b&255):uint2(clamp(b,0,255));
 return lerp(lerp(assetTexel(base,p0),assetTexel(base,uint2(p1.x,p0.y)),f.x),lerp(assetTexel(base,uint2(p0.x,p1.y)),assetTexel(base,p1),f.x),f.y);
}
float3 surfaceColor(Material m,uint primitive,float3 localP,float2 bary){
 float3 c=linearColor(m.colorMetal.xyz);if(m.tex0.x<=0)return c;
 uint mode=uint(m.tex0.y);float2 uv=0;
 if(mode==0){uint at=uint(m.az.w)+primitive*3;if(m.az.w<=0)return c;uv=meshNormals[at].xy*(1-bary.x-bary.y)+meshNormals[at+1].xy*bary.x+meshNormals[at+2].xy*bary.y;}
 else {
  if(primitive/2+1!=mode)return c;
  if(mode==1)uv=float2(-localP.z,-localP.y)+.5;
  else if(mode==2)uv=float2(localP.z,-localP.y)+.5;
  else if(mode==3)uv=float2(localP.x,localP.z)+.5;
  else if(mode==4)uv=float2(localP.x,-localP.z)+.5;
  else if(mode==5)uv=float2(localP.x,-localP.y)+.5;
  else uv=float2(-localP.x,-localP.y)+.5;
 }
 uv=uv*m.tex0.zw+m.tex1.xy;
 float4 tex=assetSample(uint(m.tex0.x),uv,m.tex1.w>0);
 float3 texColor=linearColor(tex.rgb);
 return lerp(c,mode==0?c*texColor:texColor,saturate(tex.a*m.tex1.z));
}
float daylight(){return smoothstep(-.16,.12,sun.y);}
float sunPower(){return smoothstep(-.035,.08,sun.y)*quality.z*environment.z;}
float3 sunTint(){return lerp(float3(1,.28,.065),float3(1,.93,.8),smoothstep(0,.35,sun.y));}
float3 sky(float3 d){
 float elev=saturate(d.y),day=daylight();
 float twilight=exp(-pow((sun.y+.025)*8,2));
 float toward=pow(saturate(dot(normalize(float3(d.x,.001,d.z)),normalize(float3(sun.x,.001,sun.z)))),5);
 float3 dayColor=lerp(float3(.37,.50,.69),float3(.17,.39,.90),pow(elev,.65));
 float3 nightColor=lerp(float3(.008,.013,.028),float3(.0015,.003,.012),elev);
 return (lerp(nightColor,dayColor,day)+float3(.72,.19,.038)*twilight*(.18+.82*toward)*exp(-elev*5))*quality.y;
}
float4 sunTexel(uint2 p){uint v=sunPixels[p.y*128+p.x];return float4(v&255,(v>>8)&255,(v>>16)&255,(v>>24)&255)/255;}
float3 visibleSun(float3 d){
 if(environment.y>=1||sun.y<-.08||d.y<-.015||quality.z<=0)return 0;
 float3 s=normalize(sun.xyz);if(dot(d,s)<environment.y)return 0;
 float3 t=normalize(cross(abs(s.y)>.95?float3(1,0,0):float3(0,1,0),s));float3 b=cross(s,t);
 float2 q=saturate(float2(dot(d,t),-dot(d,b))/sqrt(max(1e-8,1-environment.y*environment.y))*.5+.5)*127;
 uint2 a=uint2(q),z=min(a+1,uint2(127,127));float2 f=frac(q);
 float4 c=lerp(lerp(sunTexel(a),sunTexel(uint2(z.x,a.y)),f.x),lerp(sunTexel(uint2(a.x,z.y)),sunTexel(z),f.x),f.y);
 return linearColor(c.xyz)*c.w*sunTint()*20*sunPower();
}
RayDesc ray(float3 o,float3 d,float limit){RayDesc r;r.Origin=o;r.Direction=d;r.TMin=.001;r.TMax=limit;return r;}
bool blocked(float3 o,float3 d){RayQuery<RAY_FLAG_FORCE_OPAQUE|RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> q;q.TraceRayInline(scene,RAY_FLAG_NONE,255,ray(o,d,quality.x));while(q.Proceed()){}return q.CommittedStatus()==COMMITTED_TRIANGLE_HIT;}
// Straight-line colored shadow transmission. Each boundary contributes
// sqrt(tint * transmission), so a closed pane applies its tint once.
// This is thin-glass visibility, not refracted caustic transport.
float3 lightVisibility(float3 o,float3 d){
 if(switches.z<=0)return blocked(o,d)?float3(0,0,0):float3(1,1,1);
 float3 visibility=1;float remaining=quality.x;
 [loop]for(uint layer=0;layer<16;++layer){
  if(remaining<=.001)return visibility;
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
  q.TraceRayInline(scene,RAY_FLAG_NONE,255,ray(o,d,remaining));
  while(q.Proceed()){}
  if(q.CommittedStatus()!=COMMITTED_TRIANGLE_HIT)return visibility;
  Material m=mats[q.CommittedInstanceID()];
  float trans=saturate(m.roughEmit.z)*(1-saturate(m.colorMetal.w));
  if(trans<=.001)return 0;
  float ior=clamp(m.roughEmit.w,1.001,3);
  float f=(ior-1)/(ior+1);f*=f;
  visibility*=sqrt(saturate(linearColor(m.colorMetal.xyz)*trans))*(1-f);
  if(max(visibility.r,max(visibility.g,visibility.b))<.001)return 0;
  float advance=q.CommittedRayT()+.0015;
  o+=d*advance;remaining-=advance;
 }
 // Conservatively reject rays whose layer budget was exhausted.
 return 0;
}
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
 if(options.w==3)return sky(d)+visibleSun(d);
 for(uint i=0;i<=uint(options.x);++i){
  RayQuery<RAY_FLAG_FORCE_OPAQUE> q;q.TraceRayInline(scene,RAY_FLAG_NONE,i==0?1u:2u,ray(o,d,quality.x));while(q.Proceed()){}
  if(q.CommittedStatus()!=COMMITTED_TRIANGLE_HIT){if(options.w>=4)return 1;L+=beta*sky(d)*(prevDelta||!prevSkyNEE?1:powerWeight(prevPdf,1/(2*PI)));if(prevDelta)L+=beta*visibleSun(d);break;}
  Material m=mats[q.CommittedInstanceID()];uint primitive=q.CommittedPrimitiveIndex();uint shape=uint(m.ax.w);
  float3 localP=q.CommittedObjectRayOrigin()+q.CommittedObjectRayDirection()*q.CommittedRayT();
  float3 ln;
  if(shape==3)ln=meshNormals[uint(m.ay.w)+primitive];
  else if(shape==1)ln=normalize(localP);
  else if(shape==2){uint face=primitive%4;if(face==2)ln=float3(-1,0,0);else if(face==3)ln=float3(1,0,0);else ln=normalize(float3(0,localP.y,localP.z));}
  else {uint face=primitive/2;ln=face<2?float3(1,0,0):face<4?float3(0,1,0):float3(0,0,1);if(face%2==1)ln=-ln;}
  float3 invN=ln/max(m.scaleSpec.xyz,.0001);float3 gn=normalize(m.ax.xyz*invN.x+m.ay.xyz*invN.y+m.az.xyz*invN.z);
  bool entering=dot(gn,d)<0;float3 n=entering?gn:-gn,wo=-d;
  float3 p=o+d*q.CommittedRayT(),c=surfaceColor(m,primitive,localP,q.CommittedTriangleBarycentrics());
  float metal=saturate(m.colorMetal.w),rough=clamp(m.roughEmit.x,.025,1),ior=clamp(m.roughEmit.w,1.001,3),spec=saturate(m.scaleSpec.w);
  float trans=saturate(m.roughEmit.z)*(1-metal)*switches.z,opaque=1-trans;
  float prob=(spec>0||metal>0)?(.25+.65*metal)*switches.y:0;
  if(i==0){guide=float4(n,q.CommittedRayT());alb=float4(c,float(q.CommittedInstanceID()+1));}
  if(options.w==1)return c;if(options.w==2)return n*.5+.5;
  if(options.w==4){float v=saturate(dot(n,sun.xyz));return v>0&&sun.y>0?lightVisibility(p+n*.003,sun.xyz)*v:float3(0,0,0);}
  if(options.w==5)return lightVisibility(p+n*.003,float3(0,1,0));
  if(i==0)L+=c*(1-metal)*opaque*quality.w*lerp(.035,1,daylight());
  if(entering)L+=beta*linearColor(m.emitColor.xyz)*m.roughEmit.y;
  if(opaque>0&&entering){
   float3 wi=sunDirection(seed);float nl=dot(n,wi),pdf;
   float3 f=evalBSDF(n,wo,wi,c,metal,rough,ior,spec,prob,pdf);
   if(nl>0&&sunPower()>0)L+=beta*f*opaque*nl*sunTint()*5*sunPower()*lightVisibility(p+n*.003,wi);
   if(switches.x>0){float z=rnd(seed),phi=2*PI*rnd(seed),r=sqrt(1-z*z);wi=basis(n,r*cos(phi),r*sin(phi),z);f=evalBSDF(n,wo,wi,c,metal,rough,ior,spec,prob,pdf);
    float lp=1/(2*PI);L+=beta*f*opaque*sky(wi)*(z/lp)*(i==uint(options.x)?1:powerWeight(lp,pdf*opaque))*lightVisibility(p+n*.003,wi);}
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

static const float waveKernel[5]={1,4,6,4,1};
float lum(float3 c){return dot(c,float3(.2126,.7152,.0722));}
float4 waveRead(uint idx,int pass){if(pass==0)return history[idx];if(pass%2==1)return waveA[idx];return waveB[idx];}
[numthreads(8,8,1)]void wavelet(uint3 id:SV_DispatchThreadID){
 uint w=uint(dims.x),h=uint(dims.y);if(id.x>=w||id.y>=h)return;
 uint idx=id.y*w+id.x;int pass=int(environment.w),stride=1<<pass;
 float4 g=guides[idx],a=albedos[idx],center=waveRead(idx,pass);
 float3 sum=0;float weights=0;
 float sigma=max(.04,display.z*.85*(.1+sqrt(max(.0,lum(center.rgb)))));
 for(int y=-2;y<=2;++y)for(int x=-2;x<=2;++x){
  int2 xy=clamp(int2(id.xy)+int2(x,y)*stride,int2(0,0),int2(w-1,h-1));uint j=xy.y*w+xy.x;
  float4 gg=guides[j],aa=albedos[j],v=waveRead(j,pass);float edge=0;
  if(g.w==0&&gg.w==0)edge=1;
  else if(g.w>0&&gg.w>0){edge=pow(saturate(dot(g.xyz,gg.xyz)),32)*exp(-abs(g.w-gg.w)/max(.04,g.w*.022*stride))*exp(-length(a.xyz-aa.xyz)*10);}
  float weight=waveKernel[x+2]*waveKernel[y+2]*edge*exp(-abs(lum(v.rgb)-lum(center.rgb))/sigma);
  sum+=v.rgb*weight;weights+=weight;
 }
 float4 result=float4(sum/max(weights,1e-6),1);if(pass%2==0)waveA[idx]=result;else waveB[idx]=result;
}
float3 resolveSample(uint idx){if(environment.w>=0){int pass=int(environment.w);return pass%2==0?waveA[idx].rgb:waveB[idx].rgb;}return history[idx].rgb;}
[numthreads(8,8,1)]void resolve(uint3 id:SV_DispatchThreadID){
 uint w=uint(dims.x),h=uint(dims.y),ow=uint(display.x),oh=uint(display.y);if(id.x>=ow||id.y>=oh)return;
 float2 pos=(float2(id.xy)+.5)*float2(w,h)/float2(ow,oh)-.5;int2 center=clamp(int2(floor(pos+.5)),int2(0,0),int2(w-1,h-1));uint idx=center.y*w+center.x;
 float3 c=resolveSample(idx);
 if(display.z>0&&environment.w<0){float4 g=guides[idx],a=albedos[idx];float3 sum=0;float ws=0;int r=int(display.w);
 for(int y=-r;y<=r;++y)for(int x=-r;x<=r;++x){int2 xy=clamp(center+int2(x,y),int2(0,0),int2(w-1,h-1));uint j=xy.y*w+xy.x;float k=exp(-float(x*x+y*y)/max(.5,2*display.z*display.z*r))*weightGuide(g,a,guides[j],albedos[j]);sum+=history[j].xyz*k;ws+=k;}
 c=sum/max(ws,1e-6);
 }else if(w!=ow||h!=oh){int2 a=clamp(int2(floor(pos)),int2(0,0),int2(w-1,h-1)),b=clamp(int2(floor(pos))+1,int2(0,0),int2(w-1,h-1));float2 f=frac(pos);c=lerp(lerp(resolveSample(a.y*w+a.x),resolveSample(a.y*w+b.x),f.x),lerp(resolveSample(b.y*w+a.x),resolveSample(b.y*w+b.x),f.x),f.y);}
 c*=exp2(options.z);if(switches.w==0)c=saturate(c*(2.51*c+.03)/(c*(2.43*c+.59)+.14));else if(switches.w==1)c=c/(1+c);else c=saturate(c);output[id.xy]=float4(pow(saturate(c),1/2.2),1);
}
