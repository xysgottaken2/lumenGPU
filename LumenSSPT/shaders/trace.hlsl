// LumenSSPT: hardware DXR 1.1 inline ray queries on visible-only depth mesh.
struct Vertex { float3 p; float2 uv; };
RaytracingAccelerationStructure Scene : register(t0);
StructuredBuffer<Vertex> V : register(t1);
StructuredBuffer<float> Depth : register(t2);
StructuredBuffer<uint> Color : register(t3);
RWStructuredBuffer<float4> Effects : register(u0);
cbuffer Params : register(b0) {
    uint W, H, Frame, Spp;
    uint Bounces; float TanHalfY, Aspect, Range;
    float GI, Reflection, AO, Padding;
};
uint hash(uint x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; return x ^ (x >> 16); }
float rand(inout uint s) { s = hash(s + 1); return (s & 0x00ffffffu) / 16777216.0; }
float3 linearColor(uint c) {
    float3 s = float3(c & 255u, (c >> 8) & 255u, (c >> 16) & 255u) / 255.0;
    return pow(s, 2.2);
}
float3 sampleColor(float2 uv) {
    uint2 p = uint2(clamp(uv * float2(W,H), 0.0, float2(W-1,H-1)));
    return linearColor(Color[p.y*W+p.x]);
}
float3 position(uint2 p) {
    float2 uv = (float2(p)+0.5)/float2(W,H);
    float z = Depth[p.y*W+p.x];
    return float3((2*uv.x-1)*TanHalfY*Aspect*z,(1-2*uv.y)*TanHalfY*z,z);
}
float3 normalAt(uint2 p, float3 pos) {
    uint2 r=uint2(min(p.x+1,W-1),p.y), l=uint2(p.x==0?0:p.x-1,p.y);
    uint2 d=uint2(p.x,min(p.y+1,H-1)), u=uint2(p.x,p.y==0?0:p.y-1);
    float3 a=position(r)-pos, b=pos-position(l), c=position(d)-pos, e=pos-position(u);
    float3 dx=(p.x==W-1 || (p.x>0 && abs(b.z)<abs(a.z)))?b:a;
    float3 dy=(p.y==H-1 || (p.y>0 && abs(e.z)<abs(c.z)))?e:c;
    float3 n=cross(dx,dy); n=dot(n,n)>1e-14?normalize(n):float3(0,0,-1);
    return dot(n,pos)>0?-n:n;
}
float3 hemisphere(float3 n,inout uint seed) {
    float r=sqrt(rand(seed)), phi=6.2831853*rand(seed);
    float3 t=normalize(cross(abs(n.z)<0.95?float3(0,0,1):float3(0,1,0),n));
    return normalize(t*(r*cos(phi))+cross(n,t)*(r*sin(phi))+n*sqrt(max(0,1-r*r)));
}
struct Hit { float3 p,n,c; float distance; };
bool trace(float3 p,float3 n,float3 direction,out Hit h) {
    float bias=max(0.001,abs(p.z)*0.0025);
    RayDesc ray; ray.Origin=p+n*bias; ray.Direction=direction; ray.TMin=bias; ray.TMax=Range;
    RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
    q.TraceRayInline(Scene,RAY_FLAG_NONE,0xff,ray);
    while(q.Proceed()) {}
    h=(Hit)0;
    if(q.CommittedStatus()!=COMMITTED_TRIANGLE_HIT) return false;
    uint k=q.CommittedPrimitiveIndex()*3;
    Vertex a=V[k],b=V[k+1],c=V[k+2];
    float2 bc=q.CommittedTriangleBarycentrics();
    h.distance=q.CommittedRayT(); h.p=ray.Origin+direction*h.distance;
    h.n=normalize(cross(b.p-a.p,c.p-a.p)); if(dot(h.n,direction)>0) h.n=-h.n;
    h.c=sampleColor(a.uv*(1-bc.x-bc.y)+b.uv*bc.x+c.uv*bc.y);
    return true;
}
[numthreads(8,8,1)]
void main(uint3 id:SV_DispatchThreadID) {
    if(id.x>=W || id.y>=H) return;
    uint index=id.y*W+id.x; float3 p=position(id.xy), n=normalAt(id.xy,p);
    uint seed=hash(index ^ (Frame*0x9e3779b9u));
    float3 sum=0, reflected=0; float occ=0;
    for(uint s=0;s<Spp;s++) {
        float3 origin=p, normal=n, throughput=1;
        for(uint b=0;b<Bounces;b++) {
            Hit h;
            if(!trace(origin,normal,hemisphere(normal,seed),h)) break;
            float falloff=1/(1+h.distance*h.distance*0.25);
            if(b==0) occ+=exp(-h.distance/max(0.05,p.z*0.18));
            sum+=throughput*h.c*falloff;
            throughput*=h.c*0.35;
            origin=h.p; normal=h.n;
        }
        if(Reflection>0) {
            float3 direction=normalize(reflect(normalize(p),n)+hemisphere(n,seed)*0.10);
            Hit h;
            if(dot(direction,n)>0 && trace(p,n,direction,h)) {
                reflected+=h.c*Reflection/(1+0.10*h.distance);
            }
        }
    }
    Effects[index]=float4(min((sum*GI+reflected)/max(1u,Spp),1.0),saturate(occ/max(1u,Spp)*AO));
}
