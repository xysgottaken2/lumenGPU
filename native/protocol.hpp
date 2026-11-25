#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
#include <cmath>
#include <stdexcept>
struct V { float x,y,z; float operator[](int i) const { return i==0?x:i==1?y:z; } };
struct Part { V p,r,u,b,s,c; float metal,rough,emit; };
struct Scene { uint64_t revision=0,seq=0; V p,r,u,f; float fov; V sun; std::vector<Part> parts; };
static_assert(sizeof(V)==12 && sizeof(Part)==84);
inline Scene parse(const std::vector<unsigned char>& a) {
 if(a.size()<88||memcmp(a.data(),"LGR2",4)) throw std::runtime_error("Invalid bridge header");
 size_t at=4; auto read=[&](auto& v){if(at+sizeof(v)>a.size())throw std::runtime_error("Truncated bridge packet"); memcpy(&v,a.data()+at,sizeof(v));at+=sizeof(v);};
 Scene s; uint32_t count; read(s.revision);read(s.seq);read(count);
 if(count>1024||a.size()!=88+size_t(count)*84)throw std::runtime_error("Invalid bridge length");
 read(s.p);read(s.r);read(s.u);read(s.f);read(s.fov);read(s.sun);
 s.parts.resize(count); for(auto& p:s.parts)read(p);return s;
}
inline Scene demo(){Scene s; s.p={0,3,9};s.r={1,0,0};s.f={0,-.187f,-.98236f};s.u={0,.98236f,-.187f};s.fov=55;s.sun={.414f,.88f,.259f};
 auto box=[&](V p,V size,V c,float m=0,float r=.45f,float e=0){s.parts.push_back({p,{1,0,0},{0,1,0},{0,0,1},size,c,m,r,e});};
 box({0,-.25f,0},{14,.5f,14},{.75f,.75f,.75f});box({-6,2,-1},{.5f,4,10},{.8f,.12f,.09f});box({6,2,-1},{.5f,4,10},{.12f,.75f,.2f});box({0,2,-6},{12,4,.5f},{.8f,.8f,.8f});box({-1.9f,1,-1},{2,2,2},{.9f,.9f,.9f},.9f,.12f);box({1.7f,.7f,0},{1.4f,1.4f,1.4f},{.85f,.57f,.16f});box({0,3.8f,-2},{2,.15f,2},{1,.92f,.7f},0,.5f,5);return s;}
