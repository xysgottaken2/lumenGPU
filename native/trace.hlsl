RaytracingAccelerationStructure scene : register(t0);
struct Material {float4 colorMetal,roughEmit,ax,ay,az,scaleSpec,emitColor,tex0,tex1,extra0,extra1;};
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
uint visualFlags(){return uint(max(0.,-1-environment.w));}
float2 faceUV(uint face,float3 p){
 if(face==1)return float2(-p.z,-p.y)+.5;
 if(face==2)return float2(p.z,-p.y)+.5;
 if(face==3)return float2(p.x,p.z)+.5;
 if(face==4)return float2(p.x,-p.z)+.5;
 if(face==5)return float2(p.x,-p.y)+.5;
 return float2(-p.x,-p.y)+.5;
}
bool materialUV(Material m,uint primitive,float3 p,float2 bary,out float2 uv){
 uv=0;uint mode=uint(m.tex0.y);
 if(mode==0){
  if(m.az.w<=0)return false;uint at=uint(m.az.w)+primitive*3;uv=meshNormals[at].xy*(1-bary.x-bary.y)+meshNormals[at+1].xy*bary.x+meshNormals[at+2].xy*bary.y;
 }else{if(primitive/2+1!=mode)return false;uv=faceUV(mode,p);}
 uv=uv*m.tex0.zw+m.tex1.xy;return true;
}
float3 tangentWorld(Material m,float3 v){v*=m.scaleSpec.xyz;return m.ax.xyz*v.x+m.ay.xyz*v.y+m.az.xyz*v.z;}
float3 bumpNormal(float3 n,float3 t,float3 b,float2 grad){
 t-=n*dot(n,t);if(dot(t,t)<1e-8)return n;t=normalize(t);
 b-=n*dot(n,b)+t*dot(t,b);if(dot(b,b)<1e-8)b=cross(n,t);else b=normalize(b);
 return normalize(n+t*grad.x+b*grad.y);
}
float luma(float3 c){return dot(c,float3(.2126,.7152,.0722));}
void materialSurface(Material m,uint primitive,uint shape,float3 lp,float2 bary,inout float3 n,out float3 c,inout float rough,inout float metal){
 c=linearColor(m.colorMetal.xyz);float2 uv;
 bool hasUV=materialUV(m,primitive,lp,bary,uv);
 float3 t=m.ax.xyz,b=m.az.xyz;
 if(shape==3){uint at=uint(m.ay.w)+primitive*6;t=tangentWorld(m,meshNormals[at+4]);b=tangentWorld(m,meshNormals[at+5]);}
 else if(shape==0){
  uint face=primitive/2+1;
  if(face<=2){t=m.az.xyz*(face==1?-1:1);b=-m.ay.xyz;}
  else if(face<=4){t=m.ax.xyz;b=m.az.xyz*(face==3?1:-1);}
  else{t=m.ax.xyz*(face==5?1:-1);b=-m.ay.xyz;}
  if((visualFlags()&256u)!=0){
   uint kind=(uint(m.extra0.x)>>((face-1)*2))&3u;
   if(kind>0){
    float2 scale=face<=2?m.scaleSpec.zy:face<=4?m.scaleSpec.xz:m.scaleSpec.xy;
    float2 delta=frac(faceUV(face,lp)*scale)-.5;float rad=length(delta);
    float ring=smoothstep(.23,.29,rad)*(1-smoothstep(.34,.40,rad));
    float signBump=kind==2?-1:1;
    if(kind==3)signBump=delta.x*delta.y>0?-1:1;
    n=bumpNormal(n,t,b,delta/max(rad,.001)*ring*signBump*.65);
    c*=1-.12*ring;
   }
  }
  if(m.extra1.y>0&&face==3){
   float2 d=faceUV(face,lp)-.5;float r=length(d);float a=atan2(d.y,d.x);
   float rays=1-smoothstep(.03,.12,abs(sin(a*4))*r);
   float mark=max(1-smoothstep(.17,.20,r),rays*smoothstep(.19,.22,r)*(1-smoothstep(.37,.40,r)));
   c=lerp(c,float3(.055,.055,.055),mark*.85);
  }
 }
 if(!hasUV)return;
 bool wrap=m.tex1.w>0;
 if(m.tex0.x>0){
  float4 tex=assetSample(uint(m.tex0.x),uv,wrap);float3 tc=linearColor(tex.rgb);
  c=lerp(c,m.tex0.y==0?c*tc:tc,saturate(tex.a*m.tex1.z));
 }
 if(m.extra0.z>0)rough=clamp(assetSample(uint(m.extra0.z),uv,wrap).r,.025,1);
 if(m.extra0.w>0)metal=saturate(assetSample(uint(m.extra0.w),uv,wrap).r);
 if(m.extra0.y>0){
  float3 nn=assetSample(uint(m.extra0.y),uv,wrap).xyz*2-1;
  n=bumpNormal(n,t,b,nn.xy/max(.2,nn.z));
 }else if((visualFlags()&128u)!=0&&m.extra1.x>0&&m.tex0.x>0){
  uint off=uint(m.tex0.x);float stepUV=1./256.;
  float h=luma(assetSample(off,uv,wrap).rgb);
  float hx=luma(assetSample(off,uv+float2(stepUV,0),wrap).rgb)-h;
  float hy=luma(assetSample(off,uv+float2(0,stepUV),wrap).rgb)-h;
  n=bumpNormal(n,t,b,-float2(hx,hy)*m.extra1.x*3);
  if(m.extra0.z<=0)rough=clamp(lerp(rough,.3+.6*(1-h),m.extra1.x),.025,1);
 }
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
bool blocked(float3 o,float3 d,float limit){RayQuery<RAY_FLAG_FORCE_OPAQUE|RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> q;q.TraceRayInline(scene,RAY_FLAG_NONE,255,ray(o,d,limit));while(q.Proceed()){}return q.CommittedStatus()==COMMITTED_TRIANGLE_HIT;}
// Straight-line colored shadow transmission. Each boundary contributes
// sqrt(tint * transmission), so a closed pane applies its tint once.
// This is thin-glass visibility, not refracted caustic transport.
float3 lightVisibilityTo(float3 o,float3 d,float limit){
 if(limit<=.001)return 1;
 if(switches.z<=0)return blocked(o,d,limit)?float3(0,0,0):float3(1,1,1);
 float3 visibility=1;float remaining=limit;
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
float3 lightVisibility(float3 o,float3 d){return lightVisibilityTo(o,d,quality.x);}
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
float3 sampleLocalLight(float3 p,float3 gn,float3 n,float3 wo,float3 c,float metal,float rough,float ior,float spec,float prob,inout uint seed){
 uint flags=visualFlags(),count=flags&127u;if(count==0)return 0;
 uint at=(flags>>9)+min(count-1,uint(rnd(seed)*count));Material l=mats[at];
 float3 delta=l.ax.xyz-p;float dist=length(delta);if(dist<.006||dist>=l.roughEmit.x)return 0;
 float3 wi=delta/dist;float nl=dot(n,wi);if(nl<=0||dot(gn,wi)<=0)return 0;
 float cone=1;if(l.extra1.z>1){float cosA=dot(-wi,l.ay.xyz);cone=smoothstep(l.extra1.w-.001,min(1.,l.extra1.w+.08),cosA);if(l.extra1.z==3)cone*=saturate(cosA);}
 if(cone<=0)return 0;
 float attenuation=pow(saturate(1-dist/l.roughEmit.x),2)*l.roughEmit.y*12/(1+dist*dist);
 float pdf;float3 f=evalBSDF(n,wo,wi,c,metal,rough,ior,spec,prob,pdf);
 return f*nl*linearColor(l.colorMetal.xyz)*attenuation*cone*count*lightVisibilityTo(p+gn*.003,wi,max(.001,dist-.007));
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
  if(shape==3)ln=meshNormals[uint(m.ay.w)+primitive*6];
  else if(shape==1)ln=normalize(localP);
  else if(shape==2){uint face=primitive%4;if(face==2)ln=float3(-1,0,0);else if(face==3)ln=float3(1,0,0);else ln=normalize(float3(0,localP.y,localP.z));}
  else {uint face=primitive/2;ln=face<2?float3(1,0,0):face<4?float3(0,1,0):float3(0,0,1);if(face%2==1)ln=-ln;}
  float3 invN=ln/max(m.scaleSpec.xyz,.0001);float3 gn=normalize(m.ax.xyz*invN.x+m.ay.xyz*invN.y+m.az.xyz*invN.z);
  bool entering=dot(gn,d)<0;float3 n=entering?gn:-gn,wo=-d;
  float3 orientedGN=n;float2 bary=q.CommittedTriangleBarycentrics();
  if(shape==3){uint at=uint(m.ay.w)+primitive*6;float3 sn=meshNormals[at+1]*(1-bary.x-bary.y)+meshNormals[at+2]*bary.x+meshNormals[at+3]*bary.y;sn/=max(m.scaleSpec.xyz,.0001);sn=normalize(m.ax.xyz*sn.x+m.ay.xyz*sn.y+m.az.xyz*sn.z);if(!entering)sn=-sn;if(dot(sn,orientedGN)>0&&dot(sn,wo)>.001)n=sn;}
  float3 p=o+d*q.CommittedRayT(),c;
  float metal=saturate(m.colorMetal.w),rough=clamp(m.roughEmit.x,.025,1),ior=clamp(m.roughEmit.w,1.001,3),spec=saturate(m.scaleSpec.w);
  materialSurface(m,primitive,shape,localP,bary,n,c,rough,metal);
  if(dot(n,orientedGN)<=0||dot(n,wo)<=.001)n=orientedGN;
  float trans=saturate(m.roughEmit.z)*(1-metal)*switches.z,opaque=1-trans;
  float prob=(spec>0||metal>0)?(.25+.65*metal)*switches.y:0;
  if(i==0){guide=float4(n,q.CommittedRayT());alb=float4(c,float(q.CommittedInstanceID()+1));}
  if(options.w==1)return c;if(options.w==2)return n*.5+.5;
  if(options.w==4){float v=saturate(dot(n,sun.xyz));return v>0&&sun.y>0?lightVisibility(p+orientedGN*.003,sun.xyz)*v:float3(0,0,0);}
  if(options.w==5)return lightVisibility(p+orientedGN*.003,float3(0,1,0));
  if(i==0)L+=c*(1-metal)*opaque*quality.w*lerp(.035,1,daylight());
  if(entering)L+=beta*linearColor(m.emitColor.xyz)*m.roughEmit.y;
  if(opaque>0&&entering){
   L+=beta*opaque*sampleLocalLight(p,orientedGN,n,wo,c,metal,rough,ior,spec,prob,seed);
   float3 wi=sunDirection(seed);float nl=dot(n,wi),pdf;
   float3 f=evalBSDF(n,wo,wi,c,metal,rough,ior,spec,prob,pdf);
   if(nl>0&&dot(orientedGN,wi)>0&&sunPower()>0)L+=beta*f*opaque*nl*sunTint()*5*sunPower()*lightVisibility(p+orientedGN*.003,wi);
   if(switches.x>0){float z=rnd(seed),phi=2*PI*rnd(seed),r=sqrt(1-z*z);wi=basis(n,r*cos(phi),r*sin(phi),z);f=evalBSDF(n,wo,wi,c,metal,rough,ior,spec,prob,pdf);
    float lp=1/(2*PI);if(dot(orientedGN,wi)>0)L+=beta*f*opaque*sky(wi)*(z/lp)*(i==uint(options.x)?1:powerWeight(lp,pdf*opaque))*lightVisibility(p+orientedGN*.003,wi);}
  }
  if(i==uint(options.x))break;
  if(trans>0&&(!entering||rnd(seed)<trans)){
   float eta=entering?1/ior:ior,ci=saturate(dot(n,wo)),st2=eta*eta*(1-ci*ci);
   bool reflectIt=st2>=1;float ct=sqrt(max(0,1-st2));
   if(!reflectIt){float ei=entering?1:ior,et=entering?ior:1;float rs=(ei*ci-et*ct)/max(1e-6,ei*ci+et*ct),rp=(et*ci-ei*ct)/max(1e-6,et*ci+ei*ct);reflectIt=switches.y>0&&rnd(seed)<.5*(rs*rs+rp*rp);}
   d=reflectIt?reflect(d,n):normalize(refract(d,n,eta));
   if(!reflectIt)beta*=(entering?c:float3(1,1,1))*eta*eta;
   o=p+(reflectIt?orientedGN:-orientedGN)*.003;prevDelta=true;prevSkyNEE=false;continue;
  }
  float3 wi;
  if(rnd(seed)<prob){float a=rough*rough,u=rnd(seed),phi=2*PI*rnd(seed),ct=sqrt((1-u)/max(1e-6,1+(a*a-1)*u));float st=sqrt(max(0,1-ct*ct));float3 h=basis(n,st*cos(phi),st*sin(phi),ct);if(dot(wo,h)<=0)break;wi=reflect(d,h);}
  else {if(switches.x==0)break;wi=cosine(n,seed);}
  float pdf;float3 f=evalBSDF(n,wo,wi,c,metal,rough,ior,spec,prob,pdf);float nl=dot(n,wi);if(pdf<=0||nl<=0||dot(orientedGN,wi)<=0)break;
  beta*=f*(nl/pdf);prevPdf=pdf*opaque;prevDelta=false;prevSkyNEE=entering&&switches.x>0&&opaque>0;
  if(i>=3){float rr=clamp(max(beta.x,max(beta.y,beta.z)),.05,.95);if(rnd(seed)>=rr)break;beta/=rr;}
  o=p+orientedGN*.003;d=wi;
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
 uint idx=id.y*w+id.x;int pass=int(environment.w),stride=int(1u<<uint(pass));
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
