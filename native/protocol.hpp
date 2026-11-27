#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
#include <cmath>
#include <stdexcept>
struct V { float x,y,z; float operator[](int i) const { return i==0?x:i==1?y:z; } };
struct Part { V p,r,u,b,s,c; float metal,rough,emit,transmission=0,ior=1.5f,shape=0,specular=1; V emissionColor{0,0,0}; float tex[8]{}; float extra[8]{}; float cloth[8]{}; };
struct Scene { uint64_t revision=0,seq=0; V p,r,u,f; float fov; V sun; std::vector<Part> parts; size_t characterCount=0; uint64_t poseRevision=0; float clock=12,sunSize=11,brightness=2,celestial=1; bool firstPerson=false; uint32_t skySlots[6]{}; float skyBasis[9]{}; };
static_assert(sizeof(V)==12 && sizeof(Part)==208);
// A box proxy can enclose the camera even when its source mesh does not.
// Keep transmissive volumes, since the camera can legitimately be inside glass.
inline bool enclosingOpaque(const Part& p,V eye) {
 if(p.extra[6]>0||p.transmission>=.5f || p.shape!=0)return false;
 V d{eye.x-p.p.x,eye.y-p.p.y,eye.z-p.p.z};
 auto dot=[&](V v){return d.x*v.x+d.y*v.y+d.z*v.z;};
 return std::fabs(dot(p.r))<p.s.x*.5f-.001f &&
        std::fabs(dot(p.u))<p.s.y*.5f-.001f &&
        std::fabs(dot(p.b))<p.s.z*.5f-.001f;
}
// Character records are appended after the static and moving world.
inline bool hiddenAvatar(const Scene& s,size_t i){return s.firstPerson&&s.characterCount<=s.parts.size()&&i>=s.parts.size()-s.characterCount;}
inline unsigned instanceVisibility(const Scene& s,size_t i){return hiddenAvatar(s,i)?2u:3u;}
inline uint64_t enclosingSignature(const Scene& s,bool glassEnabled) {
 uint64_t sig=1469598103934665603ull;
 for(size_t i=0;i<s.parts.size();++i){if(hiddenAvatar(s,i))continue;Part p=s.parts[i];if(!glassEnabled)p.transmission=0;
 if(enclosingOpaque(p,s.p)){sig^=uint64_t(i)+1;sig*=1099511628211ull;}}
 return sig;
}
inline std::vector<V> parseMesh(const std::vector<unsigned char>& data){
 if(data.size()<8||memcmp(data.data(),"LGM1",4))throw std::runtime_error("Invalid mesh header");
 uint32_t count=0;memcpy(&count,data.data()+4,4);
 if(count<3||count>60000||count%3||data.size()!=8+size_t(count)*12)throw std::runtime_error("Invalid mesh length");
 std::vector<V> v(count);memcpy(v.data(),data.data()+8,count*12);
 for(auto p:v)for(int i=0;i<3;++i)if(!std::isfinite(p[i])||std::fabs(p[i])>100)throw std::runtime_error("Invalid mesh vertex");
 return v;
}
struct MeshData{std::vector<V> positions,uv,normals;};
inline MeshData parseMeshData(const std::vector<unsigned char>& data){
 bool hasNormals=data.size()>=8&&!memcmp(data.data(),"LGM3",4);
 if(data.size()>=8&&(hasNormals||!memcmp(data.data(),"LGM2",4))){
  uint32_t count=0;memcpy(&count,data.data()+4,4);
  if(count<3||count>60000||count%3||data.size()!=8+size_t(count)*(hasNormals?32:20))throw std::runtime_error("Invalid textured mesh");
  std::vector<unsigned char> legacy(data.begin(),data.begin()+8+size_t(count)*12);legacy[3]='1';
  MeshData m;m.positions=parseMesh(legacy);m.uv.resize(count);
  size_t at=8+size_t(count)*12;for(auto& v:m.uv){memcpy(&v.x,data.data()+at,4);memcpy(&v.y,data.data()+at+4,4);v.z=0;at+=8;if(!std::isfinite(v.x)||!std::isfinite(v.y)||std::fabs(v.x)>4096||std::fabs(v.y)>4096)throw std::runtime_error("Invalid UV");}
  if(hasNormals){m.normals.resize(count);memcpy(m.normals.data(),data.data()+at,count*12);for(auto n:m.normals)for(int i=0;i<3;++i)if(!std::isfinite(n[i])||std::fabs(n[i])>1.01f)throw std::runtime_error("Invalid normal");}
  return m;
 }
 MeshData m;m.positions=parseMesh(data);return m;
}
inline V triangleNormal(V a,V b,V c){
 V e{b.x-a.x,b.y-a.y,b.z-a.z},f{c.x-a.x,c.y-a.y,c.z-a.z};
 V n{e.y*f.z-e.z*f.y,e.z*f.x-e.x*f.z,e.x*f.y-e.y*f.x};
 float len=std::sqrt(n.x*n.x+n.y*n.y+n.z*n.z);
 return len>1e-12f?V{n.x/len,n.y/len,n.z/len}:V{0,1,0};
}
inline Scene parse(const std::vector<unsigned char>& a) {
 if(a.size()<88||a[0]!='L'||a[1]!='G'||(a[2]!='R'&&a[2]!='T'&&a[2]!='P'&&a[2]!='C')||a[3]<'4'||a[3]>'7')throw std::runtime_error("Invalid bridge header");
 bool clothed=a[2]=='C';bool extended=a[2]=='P'||clothed;bool textured=a[2]=='T'||extended;bool sky=a[3]=='7';bool fp=sky||a[3]=='6';bool env=fp||a[3]=='5';
 size_t at=4; auto read=[&](auto& v){if(at+sizeof(v)>a.size())throw std::runtime_error("Truncated bridge packet"); memcpy(&v,a.data()+at,sizeof(v));at+=sizeof(v);};
 Scene s; uint32_t count; read(s.revision);read(s.seq);read(count);
 if(count>16384||a.size()!=88+size_t(count)*(clothed?208:extended?176:textured?144:112)+(env?16:0)+(fp?4:0)+(sky?60:0))throw std::runtime_error("Invalid bridge length");
 read(s.p);read(s.r);read(s.u);read(s.f);read(s.fov);read(s.sun);
 s.parts.resize(count); for(auto& p:s.parts){if(textured){memcpy(&p,a.data()+at,144);at+=144;if(extended){read(p.extra);for(float x:p.extra)if(!std::isfinite(x))throw std::runtime_error("Invalid material data");}if(clothed){read(p.cloth);for(float x:p.cloth)if(!std::isfinite(x))throw std::runtime_error("Invalid clothing data");for(int i=0;i<4;++i)if(p.cloth[i]<0||p.cloth[i]>128||p.cloth[i]!=std::floor(p.cloth[i]))throw std::runtime_error("Invalid clothing slot");if(p.cloth[4]<0||p.cloth[4]>3||p.cloth[5]<0||p.cloth[6]<0||p.cloth[5]+p.cloth[6]>1.00001f)throw std::runtime_error("Invalid clothing region");}for(float x:p.tex)if(!std::isfinite(x))throw std::runtime_error("Invalid texture data");if(p.tex[0]<0||p.tex[0]>128||p.tex[0]!=std::floor(p.tex[0])||p.tex[1]<0||p.tex[1]>6||p.tex[1]!=std::floor(p.tex[1]))throw std::runtime_error("Invalid texture slot");}else{memcpy(&p,a.data()+at,112);at+=112;}}if(env){read(s.clock);read(s.sunSize);read(s.brightness);read(s.celestial);}if(fp){uint32_t flag;read(flag);if(flag>1)throw std::runtime_error("Invalid first-person flag");s.firstPerson=flag!=0;}if(sky){read(s.skySlots);read(s.skyBasis);for(auto v:s.skySlots)if(v>128)throw std::runtime_error("Invalid sky slot");for(auto v:s.skyBasis)if(!std::isfinite(v)||std::fabs(v)>1.01f)throw std::runtime_error("Invalid sky basis");}return s;
}
inline Scene demo(){Scene s; s.p={0,3,9};s.r={1,0,0};s.f={0,-.187f,-.98236f};s.u={0,.98236f,-.187f};s.fov=55;s.sun={.414f,.88f,.259f};
 auto box=[&](V p,V size,V c,float m=0,float r=.45f,float e=0){Part part{p,{1,0,0},{0,1,0},{0,0,1},size,c,m,r,e};part.emissionColor=c;s.parts.push_back(part);};
 box({0,-.25f,0},{14,.5f,14},{.75f,.75f,.75f});box({-6,2,-1},{.5f,4,10},{.8f,.12f,.09f});box({6,2,-1},{.5f,4,10},{.12f,.75f,.2f});box({0,2,-6},{12,4,.5f},{.8f,.8f,.8f});box({-1.9f,1,-1},{2,2,2},{.9f,.9f,.9f},.9f,.12f);box({1.7f,.7f,0},{1.4f,1.4f,1.4f},{.85f,.57f,.16f});box({0,3.8f,-2},{2,.15f,2},{1,.92f,.7f},0,.5f,5);return s;}
