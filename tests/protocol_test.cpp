#include "../native/protocol.hpp"
#include "../native/primitives.hpp"
#include <cassert>
#include <fstream>
#include <iterator>
int main(int argc,char** argv){
 {std::vector<unsigned char> b(88+208);memcpy(b.data(),"LGC4",4);uint32_t n=1;memcpy(b.data()+20,&n,4);float k=7;memcpy(b.data()+264,&k,4);assert(parse(b).parts[0].cloth[0]==7);}
 {std::vector<unsigned char> b(88+176);memcpy(b.data(),"LGP4",4);uint32_t n=1;memcpy(b.data()+20,&n,4);float k=4095;memcpy(b.data()+232,&k,4);assert(parse(b).parts[0].extra[0]==4095);}
 {std::vector<unsigned char> b(8+3*32);memcpy(b.data(),"LGM3",4);uint32_t n=3;memcpy(b.data()+4,&n,4);float normal=1;memcpy(b.data()+8+60+8,&normal,4);assert(parseMeshData(b).normals[0].z==1);}
 for(bool corner:{false,true}){auto v=primitives::wedge(corner);assert(v.size()==(corner?18:24));V inside{corner?.2f:0.f,-.25f,.2f};for(size_t i=0;i<v.size();i+=3){auto n=triangleNormal(v[i],v[i+1],v[i+2]);assert(primitives::dot(n,primitives::sub(inside,v[i]))<0);}}
 for(unsigned style=0;style<3;++style){auto v=primitives::truss(4,style);assert(!v.empty()&&v.size()%3==0);for(auto a:v){assert(std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z));assert(std::fabs(a.x)<.51f&&std::fabs(a.y)<.53f&&std::fabs(a.z)<.51f);}}
 assert(primitives::truss(4,0).size()>primitives::truss(4,1).size());assert(primitives::truss(4,1).size()>primitives::truss(4,2).size());assert(primitives::bays(512)==256);

 {Scene fp;fp.parts.resize(3);fp.characterCount=2;fp.firstPerson=true;
 assert(instanceVisibility(fp,0)==3);assert(instanceVisibility(fp,1)==2);assert(instanceVisibility(fp,2)==2);
 fp.firstPerson=false;assert(instanceVisibility(fp,2)==3);
 std::vector<unsigned char> wire(108);memcpy(wire.data(),"LGR6",4);wire[104]=1;assert(parse(wire).firstPerson);
 }
assert(argc==2);std::ifstream f(argv[1],std::ios::binary);std::vector<unsigned char>a((std::istreambuf_iterator<char>(f)),{});auto s=parse(a);assert(s.revision==7&&s.seq==9&&s.parts.size()==1);assert(s.p.x==1&&s.fov==55&&s.parts[0].s.z==4&&s.parts[0].emit==5&&s.parts[0].ior==1.5f);a.pop_back();try{parse(a);assert(false);}catch(const std::runtime_error&){}assert(demo().parts.size()==7);std::vector<unsigned char> mesh(44);memcpy(mesh.data(),"LGM1",4);uint32_t count=3;memcpy(mesh.data()+4,&count,4);V tri[3]={{0,0,0},{1,0,0},{0,1,0}};memcpy(mesh.data()+8,tri,36);auto verts=parseMesh(mesh);assert(verts.size()==3&&triangleNormal(verts[0],verts[1],verts[2]).z==1);mesh.pop_back();try{parseMesh(mesh);assert(false);}catch(const std::runtime_error&){}  Part p{};p.p={0,0,0};p.r={0,0,1};p.u={0,1,0};p.b={-1,0,0};p.s={4,6,8};assert(enclosingOpaque(p,{3,0,1}));assert(!enclosingOpaque(p,{5,0,1}));assert(!enclosingOpaque(p,{0,0,3}));p.transmission=.98f;assert(!enclosingOpaque(p,{0,0,0}));}
