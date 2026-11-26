#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <io.h>
#include <fcntl.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>
using Microsoft::WRL::ComPtr;
using Clock=std::chrono::steady_clock;
static void check(HRESULT hr,const char* where){ if(FAILED(hr)){char b[160];sprintf_s(b,"%s failed: 0x%08lx",where,(unsigned long)hr);throw std::runtime_error(b);} }
struct Params { uint32_t w,h,frame,spp,bounces; float tanHalfY,aspect,range,gi,reflection,ao,pad; };
struct Vertex {float x,y,z,u,v;};
struct Effect {float r,g,b,a;};
struct Stats {float meshMs,gpuMs,totalMs; uint32_t triangles;};
static_assert(sizeof(Params)==48 && sizeof(Vertex)==20 && sizeof(Effect)==16 && sizeof(Stats)==16);
static float ms(Clock::time_point t){return std::chrono::duration<float,std::milli>(Clock::now()-t).count();}
static bool read(void* p,size_t n){return fread(p,1,n,stdin)==n;}
static void write(const void* p,size_t n){if(fwrite(p,1,n,stdout)!=n)throw std::runtime_error("Output pipe closed");}
struct Buffer {ComPtr<ID3D12Resource> r; uint64_t size=0; D3D12_GPU_VIRTUAL_ADDRESS va()const{return r->GetGPUVirtualAddress();}};
class Engine {
    ComPtr<ID3D12Device5> dev; ComPtr<ID3D12CommandQueue> queue; ComPtr<ID3D12CommandAllocator> alloc;
    ComPtr<ID3D12GraphicsCommandList4> cmd; ComPtr<ID3D12Fence> fence; ComPtr<ID3D12RootSignature> root;
    ComPtr<ID3D12PipelineState> pso; ComPtr<ID3D12QueryHeap> times;
    HANDLE event=nullptr; uint64_t ticket=0,frequency=0;
    Buffer verts,depth,colors,instances,blas,tlas,scratch,out,download,timing;
    void ensure(Buffer& b,uint64_t bytes,D3D12_HEAP_TYPE heap,D3D12_RESOURCE_STATES state,D3D12_RESOURCE_FLAGS flags=D3D12_RESOURCE_FLAG_NONE){
        if(b.r && b.size>=bytes)return;
        bytes=std::max<uint64_t>(256,(bytes+255)&~255ull);
        D3D12_HEAP_PROPERTIES hp{}; hp.Type=heap;hp.CreationNodeMask=hp.VisibleNodeMask=1;
        D3D12_RESOURCE_DESC d{};d.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;d.Width=bytes;d.Height=1;d.DepthOrArraySize=1;d.MipLevels=1;d.SampleDesc.Count=1;d.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;d.Flags=flags;
        b.r.Reset();check(dev->CreateCommittedResource(&hp,D3D12_HEAP_FLAG_NONE,&d,state,nullptr,IID_PPV_ARGS(&b.r)),"Create buffer");b.size=bytes;
    }
    void upload(Buffer& b,const void* src,size_t bytes){ensure(b,bytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);void* ptr;D3D12_RANGE noRead{0,0};check(b.r->Map(0,&noRead,&ptr),"Map upload");memcpy(ptr,src,bytes);b.r->Unmap(0,nullptr);}
    void barrier(ID3D12Resource* r){D3D12_RESOURCE_BARRIER b{};b.Type=D3D12_RESOURCE_BARRIER_TYPE_UAV;b.UAV.pResource=r;cmd->ResourceBarrier(1,&b);}
    void transition(ID3D12Resource* r,D3D12_RESOURCE_STATES a,D3D12_RESOURCE_STATES b){D3D12_RESOURCE_BARRIER x{};x.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;x.Transition={r,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,a,b};cmd->ResourceBarrier(1,&x);}
    void submit(){check(cmd->Close(),"Close");ID3D12CommandList* lists[]={cmd.Get()};queue->ExecuteCommandLists(1,lists);check(queue->Signal(fence.Get(),++ticket),"Signal");if(fence->GetCompletedValue()<ticket){check(fence->SetEventOnCompletion(ticket,event),"Fence event");if(WaitForSingleObject(event,30000)!=WAIT_OBJECT_0)throw std::runtime_error("GPU fence timeout");}check(dev->GetDeviceRemovedReason(),"GPU device");}
public:
    explicit Engine(const std::filesystem::path& shader){
        ComPtr<IDXGIFactory6> factory;check(CreateDXGIFactory2(0,IID_PPV_ARGS(&factory)),"DXGI factory");
        for(UINT i=0;;i++){ComPtr<IDXGIAdapter1> adapter;HRESULT hr=factory->EnumAdapterByGpuPreference(i,DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,IID_PPV_ARGS(&adapter));if(hr==DXGI_ERROR_NOT_FOUND)break;check(hr,"Adapter enumeration");DXGI_ADAPTER_DESC1 desc{};adapter->GetDesc1(&desc);if(desc.Flags&DXGI_ADAPTER_FLAG_SOFTWARE)continue;
            ComPtr<ID3D12Device5> candidate;if(FAILED(D3D12CreateDevice(adapter.Get(),D3D_FEATURE_LEVEL_12_0,IID_PPV_ARGS(&candidate))))continue;
            D3D12_FEATURE_DATA_D3D12_OPTIONS5 opt{};D3D12_FEATURE_DATA_SHADER_MODEL sm{D3D_SHADER_MODEL_6_5};
            if(SUCCEEDED(candidate->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS5,&opt,sizeof(opt))) && opt.RaytracingTier>=D3D12_RAYTRACING_TIER_1_1 && SUCCEEDED(candidate->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL,&sm,sizeof(sm))) && sm.HighestShaderModel>=D3D_SHADER_MODEL_6_5){dev=candidate;std::wcerr<<L"DXR adapter: "<<desc.Description<<L"\n";break;}}
        if(!dev)throw std::runtime_error("No hardware DXR Tier 1.1 / SM 6.5 adapter found. Update graphics drivers.");
        D3D12_COMMAND_QUEUE_DESC q{};q.Type=D3D12_COMMAND_LIST_TYPE_DIRECT;check(dev->CreateCommandQueue(&q,IID_PPV_ARGS(&queue)),"Queue");check(queue->GetTimestampFrequency(&frequency),"Timestamp frequency");check(dev->CreateCommandAllocator(q.Type,IID_PPV_ARGS(&alloc)),"Allocator");check(dev->CreateCommandList(0,q.Type,alloc.Get(),nullptr,IID_PPV_ARGS(&cmd)),"Command list");check(cmd->Close(),"Initial close");check(dev->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)),"Fence");event=CreateEventW(nullptr,FALSE,FALSE,nullptr);if(!event)throw std::runtime_error("CreateEvent failed");
        D3D12_ROOT_PARAMETER rp[6]{};for(UINT i=0;i<4;i++){rp[i].ParameterType=D3D12_ROOT_PARAMETER_TYPE_SRV;rp[i].Descriptor={i,0};rp[i].ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;}
        rp[4].ParameterType=D3D12_ROOT_PARAMETER_TYPE_UAV;rp[4].Descriptor={0,0};rp[4].ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;
        rp[5].ParameterType=D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS;rp[5].Constants={0,0,12};rp[5].ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;
        D3D12_ROOT_SIGNATURE_DESC rs{};rs.NumParameters=6;rs.pParameters=rp;ComPtr<ID3DBlob> sig,err;HRESULT hr=D3D12SerializeRootSignature(&rs,D3D_ROOT_SIGNATURE_VERSION_1,&sig,&err);if(FAILED(hr)&&err)std::cerr<<(const char*)err->GetBufferPointer()<<"\n";check(hr,"Root signature serialization");check(dev->CreateRootSignature(0,sig->GetBufferPointer(),sig->GetBufferSize(),IID_PPV_ARGS(&root)),"Root signature");
        std::ifstream f(shader,std::ios::binary|std::ios::ate);if(!f)throw std::runtime_error("Cannot open trace.cso. Run build.ps1 first.");auto n=f.tellg();if(n<=0)throw std::runtime_error("Empty shader");std::vector<char> code(static_cast<size_t>(n));f.seekg(0);f.read(code.data(),static_cast<std::streamsize>(n));D3D12_COMPUTE_PIPELINE_STATE_DESC ps{};ps.pRootSignature=root.Get();ps.CS={code.data(),code.size()};check(dev->CreateComputePipelineState(&ps,IID_PPV_ARGS(&pso)),"Compute PSO");
        D3D12_QUERY_HEAP_DESC h{};h.Type=D3D12_QUERY_HEAP_TYPE_TIMESTAMP;h.Count=2;check(dev->CreateQueryHeap(&h,IID_PPV_ARGS(&times)),"Timestamp heap");ensure(timing,16,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
    }
    ~Engine(){if(event)CloseHandle(event);}
    Stats render(const Params& p,const std::vector<float>& z,const std::vector<uint32_t>& rgb,std::vector<Effect>& result){
        auto begin=Clock::now();std::vector<Vertex> mesh;mesh.reserve(size_t(p.w-1)*(p.h-1)*6);
        auto vertex=[&](uint32_t x,uint32_t y){float u=(x+0.5f)/p.w,v=(y+0.5f)/p.h,d=z[size_t(y)*p.w+x];return Vertex{(2*u-1)*p.tanHalfY*p.aspect*d,(1-2*v)*p.tanHalfY*d,d,u,v};};
        auto tri=[&](Vertex a,Vertex b,Vertex c){float lo=std::min({a.z,b.z,c.z}),hi=std::max({a.z,b.z,c.z});if(lo>0.001f && std::isfinite(hi) && hi-lo<=0.12f*lo){mesh.push_back(a);mesh.push_back(b);mesh.push_back(c);}};
        for(uint32_t y=0;y+1<p.h;y++)for(uint32_t x=0;x+1<p.w;x++){auto a=vertex(x,y),b=vertex(x+1,y),c=vertex(x,y+1),d=vertex(x+1,y+1);tri(a,b,c);tri(b,d,c);}
        Stats stats{ms(begin),0,0,uint32_t(mesh.size()/3)};result.resize(z.size());if(mesh.empty()){std::fill(result.begin(),result.end(),Effect{});stats.totalMs=ms(begin);return stats;}
        upload(verts,mesh.data(),mesh.size()*sizeof(Vertex));upload(depth,z.data(),z.size()*sizeof(float));upload(colors,rgb.data(),rgb.size()*sizeof(uint32_t));
        D3D12_RAYTRACING_GEOMETRY_DESC geom{};geom.Type=D3D12_RAYTRACING_GEOMETRY_TYPE_TRIANGLES;geom.Flags=D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE;geom.Triangles.VertexBuffer={verts.va(),sizeof(Vertex)};geom.Triangles.VertexCount=UINT(mesh.size());geom.Triangles.VertexFormat=DXGI_FORMAT_R32G32B32_FLOAT;geom.Triangles.IndexFormat=DXGI_FORMAT_UNKNOWN;
        D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS bi{};bi.Type=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;bi.Flags=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_BUILD;bi.NumDescs=1;bi.DescsLayout=D3D12_ELEMENTS_LAYOUT_ARRAY;bi.pGeometryDescs=&geom;
        D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS ti{};ti.Type=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL;ti.Flags=bi.Flags;ti.NumDescs=1;ti.DescsLayout=D3D12_ELEMENTS_LAYOUT_ARRAY;
        D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO bp{},tp{};dev->GetRaytracingAccelerationStructurePrebuildInfo(&bi,&bp);dev->GetRaytracingAccelerationStructurePrebuildInfo(&ti,&tp);if(!bp.ResultDataMaxSizeInBytes||!tp.ResultDataMaxSizeInBytes)throw std::runtime_error("Invalid acceleration structure size");
        auto ua=D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;ensure(blas,bp.ResultDataMaxSizeInBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE,ua);ensure(tlas,tp.ResultDataMaxSizeInBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE,ua);ensure(scratch,std::max(bp.ScratchDataSizeInBytes,tp.ScratchDataSizeInBytes),D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_UNORDERED_ACCESS,ua);
        D3D12_RAYTRACING_INSTANCE_DESC inst{};inst.Transform[0][0]=inst.Transform[1][1]=inst.Transform[2][2]=1;inst.InstanceMask=0xff;inst.AccelerationStructure=blas.va();upload(instances,&inst,sizeof(inst));ti.InstanceDescs=instances.va();
        auto bytes=result.size()*sizeof(Effect);ensure(out,bytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_UNORDERED_ACCESS,ua);ensure(download,bytes,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
        check(alloc->Reset(),"Allocator reset");check(cmd->Reset(alloc.Get(),pso.Get()),"List reset");cmd->EndQuery(times.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0);
        D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC bd{};bd.Inputs=bi;bd.DestAccelerationStructureData=blas.va();bd.ScratchAccelerationStructureData=scratch.va();cmd->BuildRaytracingAccelerationStructure(&bd,0,nullptr);barrier(nullptr);
        bd.Inputs=ti;bd.DestAccelerationStructureData=tlas.va();cmd->BuildRaytracingAccelerationStructure(&bd,0,nullptr);barrier(nullptr);
        cmd->SetComputeRootSignature(root.Get());cmd->SetComputeRootShaderResourceView(0,tlas.va());cmd->SetComputeRootShaderResourceView(1,verts.va());cmd->SetComputeRootShaderResourceView(2,depth.va());cmd->SetComputeRootShaderResourceView(3,colors.va());cmd->SetComputeRootUnorderedAccessView(4,out.va());cmd->SetComputeRoot32BitConstants(5,12,&p,0);cmd->Dispatch((p.w+7)/8,(p.h+7)/8,1);barrier(out.r.Get());cmd->EndQuery(times.Get(),D3D12_QUERY_TYPE_TIMESTAMP,1);
        transition(out.r.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE);cmd->CopyBufferRegion(download.r.Get(),0,out.r.Get(),0,bytes);transition(out.r.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);cmd->ResolveQueryData(times.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0,2,timing.r.Get(),0);submit();
        void* ptr;D3D12_RANGE rr{0,bytes};check(download.r->Map(0,&rr,&ptr),"Readback map");memcpy(result.data(),ptr,bytes);D3D12_RANGE none{0,0};download.r->Unmap(0,&none);D3D12_RANGE tr{0,16};check(timing.r->Map(0,&tr,&ptr),"Timestamp map");uint64_t ticks[2];memcpy(ticks,ptr,16);timing.r->Unmap(0,&none);stats.gpuMs=float(double(ticks[1]-ticks[0])*1000/frequency);stats.totalMs=ms(begin);return stats;
    }
};
int main(int argc,char** argv){try{_setmode(_fileno(stdin),_O_BINARY);_setmode(_fileno(stdout),_O_BINARY);Engine engine(argc>1?std::filesystem::path(argv[1]):std::filesystem::path("trace.cso"));write("LSS1",4);fflush(stdout);Params p{};while(read(&p,sizeof(p))){if(p.w==0)break;if(p.w<2||p.h<2||p.w>640||p.h>360||p.spp<1||p.spp>8||p.bounces<1||p.bounces>3||!std::isfinite(p.tanHalfY)||p.tanHalfY<=0||!std::isfinite(p.aspect)||p.aspect<=0||!std::isfinite(p.range)||p.range<=0)throw std::runtime_error("Invalid frame parameters");size_t count=size_t(p.w)*p.h;std::vector<float> z(count);std::vector<uint32_t> c(count);std::vector<Effect> result;if(!read(z.data(),count*4)||!read(c.data(),count*4))throw std::runtime_error("Truncated frame");for(auto& d:z)if(!std::isfinite(d)||d<0.01f||d>1000)d=50;auto stats=engine.render(p,z,c,result);write(&stats,sizeof(stats));write(result.data(),result.size()*sizeof(Effect));fflush(stdout);}return 0;}catch(const std::exception& e){std::cerr<<"LumenSSPT: "<<e.what()<<"\n";return 1;}}
