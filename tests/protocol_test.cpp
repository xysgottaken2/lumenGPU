#include "../native/protocol.hpp"
#include <cassert>
#include <fstream>
#include <iterator>
int main(int argc,char** argv){assert(argc==2);std::ifstream f(argv[1],std::ios::binary);std::vector<unsigned char>a((std::istreambuf_iterator<char>(f)),{});auto s=parse(a);assert(s.revision==7&&s.seq==9&&s.parts.size()==1);assert(s.p.x==1&&s.fov==55&&s.parts[0].s.z==4&&s.parts[0].emit==5);a.pop_back();try{parse(a);assert(false);}catch(const std::runtime_error&){}assert(demo().parts.size()==7);}
