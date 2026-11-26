#pragma once
#include "protocol.hpp"
#include <algorithm>
namespace primitives {
inline V add(V a,V b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
inline V sub(V a,V b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
inline V mul(V a,float k){return {a.x*k,a.y*k,a.z*k};}
inline float dot(V a,V b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline V cross(V a,V b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline V unit(V a){return mul(a,1/std::sqrt(std::max(1e-20f,dot(a,a))));}
inline void tri(std::vector<V>& v,V a,V b,V c,V inside){
 if(dot(cross(sub(b,a),sub(c,a)),sub(inside,a))>0)std::swap(b,c);
 v.insert(v.end(),{a,b,c});
}
inline void quad(std::vector<V>& v,V a,V b,V c,V d,V inside){tri(v,a,b,c,inside);tri(v,a,c,d,inside);}
inline std::vector<V> wedge(bool corner){
 std::vector<V> v;V a{-.5f,-.5f,-.5f},b{.5f,-.5f,-.5f},c{.5f,-.5f,.5f},d{-.5f,-.5f,.5f},e{.5f,.5f,.5f},f{-.5f,.5f,.5f};
 V inside{corner?.2f:0.f,-.25f,.2f};
 quad(v,a,b,c,d,inside);
 if(corner){tri(v,a,b,e,inside);tri(v,a,e,d,inside);tri(v,b,c,e,inside);tri(v,c,d,e,inside);}
 else{quad(v,a,b,e,f,inside);quad(v,d,f,e,c,inside);tri(v,a,d,f,inside);tri(v,b,c,e,inside);}
 return v;
}
// Beam geometry built in a square 2-stud cross-section and normalized
// along its length. Shared BLAS per bay count and support style.
inline void beam(std::vector<V>& v,V a,V b,float width,float length){
 V n=unit(sub(b,a));V u=mul(unit(cross(n,std::fabs(n.y)>.95f?V{1,0,0}:V{0,1,0})),width*.5f);V w=mul(unit(cross(n,u)),width*.5f);
 V center=mul(add(a,b),.5f);V q[8]={sub(sub(a,u),w),add(sub(a,w),u),add(add(a,u),w),add(sub(a,u),w),sub(sub(b,u),w),add(sub(b,w),u),add(add(b,u),w),add(sub(b,u),w)};
 auto start=v.size();quad(v,q[0],q[1],q[2],q[3],center);quad(v,q[4],q[5],q[6],q[7],center);
 for(int i=0;i<4;++i)quad(v,q[i],q[(i+1)%4],q[(i+1)%4+4],q[i+4],center);
 for(size_t i=start;i<v.size();++i){v[i].x*=.5f;v[i].y/=length;v[i].z*=.5f;}
}
inline unsigned bays(float y){return unsigned(std::clamp(std::round(y/2.f),1.f,256.f));}
inline unsigned trussKey(float shape,float height){return (unsigned(-shape)-3u)*256u+bays(height);}
inline std::vector<V> truss(unsigned count,unsigned style){
 count=std::clamp(count,1u,256u);std::vector<V> v;float length=float(count)*2.f,low=-length*.5f,high=-low;
 constexpr float edge=.90f,thick=.13f;V corners[4]={{-edge,0,-edge},{edge,0,-edge},{edge,0,edge},{-edge,0,edge}};
 auto p=[&](int c,float y){V a=corners[c%4];a.y=y;return a;};
 for(int i=0;i<4;++i)beam(v,p(i,low+thick*.5f),p(i,high-thick*.5f),thick,length);
 for(unsigned j=0;j<=count;++j){float y=std::clamp(low+j*2.f,low+thick*.5f,high-thick*.5f);for(int i=0;i<4;++i)beam(v,p(i,y),p(i+1,y),thick,length);}
 if(style!=2)for(unsigned j=0;j<count;++j){
 float a=std::max(low+thick*.5f,low+j*2.f),b=std::min(high-thick*.5f,low+(j+1)*2.f);
 for(int i=0;i<4;++i){if(style==1&&i%2!=0)continue;bool flip=style==0?((j+i)%2!=0):j>=count/2;beam(v,p(i,flip?b:a),p(i+1,flip?a:b),thick*.75f,length);}
 }
 return v;
}
}
