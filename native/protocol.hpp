#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
#include <cmath>
#include <stdexcept>
struct V { float x,y,z; float operator[](int i) const { return i==0?x:i==1?y:z; } };
struct Part { V p,r,u,b,s,c; float metal,rough,emit,transmission=0,ior=1.5f,shape=0,specular=1; V emissionColor{0,0,0}; };
struct Scene { uint64_t revision=0,seq=0; V p,r,u,f; float fov; V sun; std::vector<Part> parts; size_t characterCount=0; uint64_t poseRevision=0; float clock=12,sunSize=11,brightness=2,celestial=1; };
static_assert(sizeof(V)==12 && sizeof(Part)==112);
// A box proxy can enclose the camera even when its source mesh does not.
// Keep transmissive volumes, since the camera can legitimately be inside glass.
inline bool enclosingOpaque(const Part& p,V eye) {
 if(p.transmission>=.5f || p.shape!=0)return false;
 V d{eye.x-p.p.x,eye.y-p.p.y,eye.z-p.p.z};
 auto dot=[&](V v){return d.x*v.x+d.y*v.y+d.z*v.z;};
 return std::fabs(dot(p.r))<p.s.x*.5f-.001f &&
        std::fabs(dot(p.u))<p.s.y*.5f-.001f &&
        std::fabs(dot(p.b))<p.s.z*.5f-.001f;
}
inline uint64_t enclosingSignature(const Scene& s,bool glassEnabled) {
 uint64_t sig=1469598103934665603ull;
 for(size_t i=0;i<s.parts.size();++i){Part p=s.parts[i];if(!glassEnabled)p.transmission=0;
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
inline V triangleNormal(V a,V b,V c){
 V e{b.x-a.x,b.y-a.y,b.z-a.z},f{c.x-a.x,c.y-a.y,c.z-a.z};
 V n{e.y*f.z-e.z*f.y,e.z*f.x-e.x*f.z,e.x*f.y-e.y*f.x};
 float len=std::sqrt(n.x*n.x+n.y*n.y+n.z*n.z);
 return len>1e-12f?V{n.x/len,n.y/len,n.z/len}:V{0,1,0};
}
inline Scene parse(const std::vector<unsigned char>& a) {
 if(a.size()<88||(memcmp(a.data(),"LGR4",4)&&memcmp(a.data(),"LGR5",4))) throw std::runtime_error("Invalid bridge header");
 bool env=!memcmp(a.data(),"LGR5",4);
 size_t at=4; auto read=[&](auto& v){if(at+sizeof(v)>a.size())throw std::runtime_error("Truncated bridge packet"); memcpy(&v,a.data()+at,sizeof(v));at+=sizeof(v);};
 Scene s; uint32_t count; read(s.revision);read(s.seq);read(count);
 if(count>16384||a.size()!=88+size_t(count)*112+(env?16:0))throw std::runtime_error("Invalid bridge length");
 read(s.p);read(s.r);read(s.u);read(s.f);read(s.fov);read(s.sun);
 s.parts.resize(count); for(auto& p:s.parts)read(p);if(env){read(s.clock);read(s.sunSize);read(s.brightness);read(s.celestial);}return s;
}
inline Scene demo(){Scene s; s.p={0,3,9};s.r={1,0,0};s.f={0,-.187f,-.98236f};s.u={0,.98236f,-.187f};s.fov=55;s.sun={.414f,.88f,.259f};
 auto box=[&](V p,V size,V c,float m=0,float r=.45f,float e=0){Part part{p,{1,0,0},{0,1,0},{0,0,1},size,c,m,r,e};part.emissionColor=c;s.parts.push_back(part);};
 box({0,-.25f,0},{14,.5f,14},{.75f,.75f,.75f});box({-6,2,-1},{.5f,4,10},{.8f,.12f,.09f});box({6,2,-1},{.5f,4,10},{.12f,.75f,.2f});box({0,2,-6},{12,4,.5f},{.8f,.8f,.8f});box({-1.9f,1,-1},{2,2,2},{.9f,.9f,.9f},.9f,.12f);box({1.7f,.7f,0},{1.4f,1.4f,1.4f},{.85f,.57f,.16f});box({0,3.8f,-2},{2,.15f,2},{1,.92f,.7f},0,.5f,5);return s;}
