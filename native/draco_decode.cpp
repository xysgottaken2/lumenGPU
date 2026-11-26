// Lumenus standalone Draco adapter. All geometry is decoded locally.
// Uses the upstream Apache-2.0 Draco library.
#include <cstdint>
#include <cmath>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <vector>
#include <array>
#include <utility>
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif
#include "draco/compression/decode.h"
#include "draco/compression/encode.h"
#include "draco/mesh/triangle_soup_mesh_builder.h"

static void u32(std::vector<char>& out,uint32_t x){
 for(unsigned k=0;k<4;++k)out.push_back(char((x>>(k*8))&255));
}
static void flt(std::vector<char>& out,float f){
 uint32_t x;static_assert(sizeof(float)==4);std::memcpy(&x,&f,4);u32(out,x);
}
static uint32_t get32(const std::vector<char>& b,size_t i){
 return uint32_t(uint8_t(b.at(i)))|(uint32_t(uint8_t(b.at(i+1)))<<8)|(uint32_t(uint8_t(b.at(i+2)))<<16)|(uint32_t(uint8_t(b.at(i+3)))<<24);
}
static const draco::PointAttribute* attr(const draco::Mesh& mesh,unsigned id,draco::GeometryAttribute::Type type,int n){
 const auto* a=mesh.GetAttributeByUniqueId(id);
 if(a&&a->num_components()==n&&a->attribute_type()==type)return a;
 a=mesh.GetNamedAttribute(type);return a&&a->num_components()==n?a:nullptr;
}
static std::vector<char> decode(const char* data,size_t length){
 if(length<5||length>(16u<<20)||std::memcmp(data,"DRACO",5)!=0)throw std::runtime_error("invalid Draco stream");
 draco::DecoderBuffer buffer;buffer.Init(data,length);
 draco::Decoder decoder;
 auto result=decoder.DecodeMeshFromBuffer(&buffer);
 if(!result.ok())throw std::runtime_error("Draco rejected mesh");
 auto mesh=std::move(result).value();
 if(!mesh||mesh->num_points()<3||mesh->num_points()>200000||mesh->num_faces()<1||mesh->num_faces()>200000)throw std::runtime_error("Draco geometry count exceeds limits");
 const auto* pos=attr(*mesh,0,draco::GeometryAttribute::POSITION,3);
 const auto* uv=attr(*mesh,2,draco::GeometryAttribute::TEX_COORD,2);
 const auto* normals=mesh->GetNamedAttribute(draco::GeometryAttribute::NORMAL);if(!normals)normals=mesh->GetAttributeByUniqueId(1);if(normals&&normals->num_components()!=3)normals=nullptr;
 if(!pos)throw std::runtime_error("Draco position attribute missing");
 // Untextured geometry may omit UVs. Positions are still usable.
 // COREMESH v1 payload: vertex records (40 bytes) and indexed triangles.
 std::vector<char> out;out.reserve(8+size_t(mesh->num_points())*40+size_t(mesh->num_faces())*12);
 u32(out,mesh->num_points());
 for(uint32_t i=0;i<mesh->num_points();++i){
  const draco::PointIndex p(i);float xyz[3]{},tex[2]{};
  if(!pos->ConvertValue<float,3>(pos->mapped_index(p),xyz)||(uv&&!uv->ConvertValue<float,2>(uv->mapped_index(p),tex)))throw std::runtime_error("Draco attribute conversion failed");
  for(float x:xyz){if(!std::isfinite(x)||std::fabs(x)>=1e7f)throw std::runtime_error("Draco invalid position");flt(out,x);}
  // Renderer computes triangle normals; preserve positions and UV seams using point mapping.
  float normal[3]{};if(normals&&!normals->ConvertValue<float,3>(normals->mapped_index(p),normal))normal[0]=normal[1]=normal[2]=0;for(float x:normal)flt(out,std::isfinite(x)?x:0.f);
  for(float x:tex){if(!std::isfinite(x)||std::fabs(x)>4096)throw std::runtime_error("Draco invalid UV");flt(out,x);}
  u32(out,0);u32(out,0xffffffffu);
 }
 u32(out,mesh->num_faces());
 for(uint32_t i=0;i<mesh->num_faces();++i){
  const auto& face=mesh->face(draco::FaceIndex(i));
  for(int j=0;j<3;++j){auto index=face[j].value();if(index>=mesh->num_points())throw std::runtime_error("Draco invalid index");u32(out,index);}
 }
 return out;
}
static std::vector<char> fixture(){
 draco::TriangleSoupMeshBuilder b;b.Start(1);
 int p=b.AddAttribute(draco::GeometryAttribute::POSITION,3,draco::DT_FLOAT32);
 int n=b.AddAttribute(draco::GeometryAttribute::GENERIC,3,draco::DT_FLOAT32);
 int t=b.AddAttribute(draco::GeometryAttribute::TEX_COORD,2,draco::DT_FLOAT32);
 b.SetAttributeUniqueId(p,0);b.SetAttributeUniqueId(n,1);b.SetAttributeUniqueId(t,2);
 float a[3]={-1,-2,0},c[3]={1,-2,0},d[3]={0,2,0},normal[3]={0,0,1};
 float u[2]={.25f,.75f},v[2]={1,0},w[2]={0,1};
 b.SetAttributeValuesForFace(p,draco::FaceIndex(0),a,c,d);
 b.SetAttributeValuesForFace(n,draco::FaceIndex(0),normal,normal,normal);
 b.SetAttributeValuesForFace(t,draco::FaceIndex(0),u,v,w);
 auto mesh=b.Finalize();if(!mesh)throw std::runtime_error("fixture mesh failed");
 draco::Encoder enc;enc.SetEncodingMethod(draco::MESH_SEQUENTIAL_ENCODING);
 draco::EncoderBuffer buf;auto status=enc.EncodeMeshToBuffer(*mesh,&buf);
 if(!status.ok())throw std::runtime_error("fixture encoding failed");
 return std::vector<char>(buf.data(),buf.data()+buf.size());
}
static void write(const std::vector<char>& b){
 std::cout.write(b.data(),std::streamsize(b.size()));if(!std::cout)throw std::runtime_error("output failed");
}
int main(int argc,char** argv){
 try{
 #ifdef _WIN32
 _setmode(_fileno(stdin),_O_BINARY);_setmode(_fileno(stdout),_O_BINARY);
 #endif
 if(argc==2&&std::strcmp(argv[1],"--fixture")==0){write(fixture());return 0;}
 if(argc==2&&std::strcmp(argv[1],"--self-test")==0){
  auto raw=fixture();auto out=decode(raw.data(),raw.size());
  if(out.size()!=4+3*40+4+12||get32(out,0)!=3||get32(out,124)!=1)throw std::runtime_error("roundtrip geometry count mismatch");
  bool uv=false;for(size_t i=0;i<3;++i){float u,v;std::memcpy(&u,out.data()+4+i*40+24,4);std::memcpy(&v,out.data()+4+i*40+28,4);if(std::fabs(u-.25f)<.001f&&std::fabs(v-.75f)<.001f)uv=true;}
  if(!uv)throw std::runtime_error("roundtrip UV mismatch");
  try{decode("invalid",7);throw 1;}catch(const std::runtime_error&){}
  return 0;
 }
 if(argc!=1)throw std::runtime_error("invalid arguments");
 std::vector<char> data;std::array<char,8192> block{};
 while(std::cin){std::cin.read(block.data(),block.size());auto n=std::cin.gcount();if(data.size()+size_t(n)>(16u<<20))throw std::runtime_error("input limit");data.insert(data.end(),block.data(),block.data()+n);}
 if(!std::cin.eof())throw std::runtime_error("input failed");
 write(decode(data.data(),data.size()));return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}catch(...){return 1;}
}
