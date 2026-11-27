#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <wincodec.h>
#include <winhttp.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <mutex>
#include <sstream>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <memory>
#include "protocol.hpp"
#include "primitives.hpp"
#include "imgui.h"
#include "backends/imgui_impl_win32.h"
#include "backends/imgui_impl_dx12.h"
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND,UINT,WPARAM,LPARAM);
using Microsoft::WRL::ComPtr;
using namespace std::chrono_literals;
void check(HRESULT h,const char* msg){if(FAILED(h)){std::ostringstream o;o<<msg<<" (HRESULT 0x"<<std::hex<<uint32_t(h)<<")";throw std::runtime_error(o.str());}}
struct Http { HINTERNET h=nullptr; ~Http(){if(h)WinHttpCloseHandle(h);} };
std::mutex mtx; Scene incoming; std::vector<Part> incomingMoving,incomingCharacter; bool connected=false; std::atomic<bool> stop=false;
std::mutex meshMutex;std::unordered_map<uint32_t,std::shared_ptr<const MeshData>> downloadedMeshes;std::unordered_map<uint32_t,std::shared_ptr<const std::vector<uint32_t>>> downloadedTextures;std::atomic<uint64_t> meshEpoch{0};
struct PointerEvent{float x,y;int button;bool down;};
struct KeyEvent{int vk;bool down,repeat;};
struct Input {bool active=false;int x=0,z=0,dx=0,dy=0;bool jump=false;std::vector<PointerEvent> pointer;std::vector<KeyEvent> keys;};
std::mutex inputMutex; Input input; bool captured=false;bool mouseLocked=false;bool rightDrag=false;POINT lastCursor{},dragAnchor{};bool cursorValid=false;bool dragHidden=false;bool lastJump=false; std::atomic<DWORD> inputHttp{0}; int debugView=0; float exposure=0;
bool denoise=true;int denoiseMode=1,wavePasses=3;bool followSunSize=true;float visualSunSize=11.f;float denoiseStrength=1.f,renderScale=.5f,sunRadius=.012f;int filterRadius=2;
bool uiVisible=true,uiReady=false,gi=true,reflections=true,glass=true;int tonemap=0;float rayDistance=10000,skyStrength=1,sunStrength=1,ambientStrength=.10f;std::atomic<float> orbitSetting{10},sensitivitySetting{1},fovSetting{70};
void unlockMouse(){if(mouseLocked){ClipCursor(nullptr);ShowCursor(TRUE);mouseLocked=false;}cursorValid=false;}
void endDrag(){if(dragHidden){ShowCursor(TRUE);dragHidden=false;}rightDrag=false;cursorValid=false;}
void releaseInput(){captured=false;unlockMouse();endDrag();if(GetCapture())ReleaseCapture();lastJump=false;std::lock_guard<std::mutex> lk(inputMutex);input=Input{};}
void captureInput(HWND h){if(captured){releaseInput();return;}if(GetForegroundWindow()!=h){SetForegroundWindow(h);if(GetForegroundWindow()!=h)return;}captured=true;cursorValid=false;}
void pointerEvent(HWND h,int button,bool down,LPARAM l){
 if(!captured)return;RECT r{};GetClientRect(h,&r);if(r.right<=0||r.bottom<=0)return;
 float x=mouseLocked?.5f:std::clamp(float(short(LOWORD(l)))/r.right,0.f,1.f);
 float y=mouseLocked?.5f:std::clamp(float(short(HIWORD(l)))/r.bottom,0.f,1.f);
 std::lock_guard<std::mutex> lk(inputMutex);if(input.pointer.size()<32)input.pointer.push_back({x,y,button,down});
}
void sampleInput(HWND h){
 if(!captured)return;if(GetForegroundWindow()!=h||IsIconic(h)){releaseInput();return;}
 bool fp=false;{std::lock_guard<std::mutex> lk(mtx);fp=connected?incoming.firstPerson:orbitSetting.load()<=.75f;}
 RECT r{};GetClientRect(h,&r);POINT a{r.left,r.top},b{r.right,r.bottom};ClientToScreen(h,&a);ClientToScreen(h,&b);
 int cx=(a.x+b.x)/2,cy=(a.y+b.y)/2;POINT cursor{};GetCursorPos(&cursor);int dx=0,dy=0;
 if(fp){if(dragHidden){ShowCursor(TRUE);dragHidden=false;}RECT clip{a.x,a.y,b.x,b.y};ClipCursor(&clip);if(!mouseLocked){ShowCursor(FALSE);mouseLocked=true;SetCursorPos(cx,cy);cursor={cx,cy};}dx=cursor.x-cx;dy=cursor.y-cy;if(dx||dy)SetCursorPos(cx,cy);}
 else{if(mouseLocked)unlockMouse();if(rightDrag){if(!dragHidden){ShowCursor(FALSE);dragHidden=true;}dx=cursor.x-dragAnchor.x;dy=cursor.y-dragAnchor.y;if(dx||dy)SetCursorPos(dragAnchor.x,dragAnchor.y);}else{lastCursor=cursor;cursorValid=true;}}
 auto down=[](int k){return (GetAsyncKeyState(k)&0x8000)!=0;};bool j=down(VK_SPACE);std::lock_guard<std::mutex> lk(inputMutex);input.active=true;input.x=int(down('D'))-int(down('A'));input.z=int(down('W'))-int(down('S'));input.dx=std::clamp(input.dx+dx,-2000,2000);input.dy=std::clamp(input.dy+dy,-2000,2000);input.jump=input.jump||(j&&!lastJump);lastJump=j;
}
std::string inputJSON(){Input i;{std::lock_guard<std::mutex> lk(inputMutex);i=input;input.dx=input.dy=0;input.jump=false;input.pointer.clear();input.keys.clear();}std::ostringstream j;j<<"{\"active\":"<<(i.active?"true":"false")<<",\"x\":"<<i.x<<",\"z\":"<<i.z<<",\"dx\":"<<i.dx<<",\"dy\":"<<i.dy<<",\"jump\":"<<(i.jump?"true":"false")<<",\"distance\":"<<orbitSetting.load()<<",\"sensitivity\":"<<sensitivitySetting.load()<<",\"fov\":"<<fovSetting.load()<<",\"pointer\":[";bool first=true;for(auto& e:i.pointer){if(!first)j<<",";first=false;j<<"{\"x\":"<<e.x<<",\"y\":"<<e.y<<",\"button\":"<<e.button<<",\"down\":"<<(e.down?"true":"false")<<"}";}j<<"],\"keys\":[";first=true;for(auto& e:i.keys){if(!first)j<<",";first=false;j<<"{\"vk\":"<<e.vk<<",\"down\":"<<(e.down?"true":"false")<<",\"repeat\":"<<(e.repeat?"true":"false")<<"}";}j<<"]}";return j.str();}
HINTERNET openSocket(HINTERNET conn,const wchar_t* path){
 Http req{WinHttpOpenRequest(conn,L"GET",path,nullptr,WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,0)};
 if(!req.h||!WinHttpSetOption(req.h,WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET,nullptr,0)||!WinHttpSendRequest(req.h,WINHTTP_NO_ADDITIONAL_HEADERS,0,WINHTTP_NO_REQUEST_DATA,0,0,0)||!WinHttpReceiveResponse(req.h,nullptr))return nullptr;
 return WinHttpWebSocketCompleteUpgrade(req.h,0);
}
std::atomic<unsigned> receivedCamera{0},receivedGeometry{0},receivedPose{0},receivedMoving{0};std::atomic<bool> nativeInputOnline{false};
std::atomic<uint64_t> cameraArrival{0};
uint64_t nowMs(){return uint64_t(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());}
void nativeInput(){
 Http session{WinHttpOpen(L"LumenGPU/0.7 input",WINHTTP_ACCESS_TYPE_NO_PROXY,WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0)};if(!session.h)return;
 WinHttpSetTimeouts(session.h,500,500,500,500);Http conn{WinHttpConnect(session.h,L"127.0.0.1",8765,0)};if(!conn.h)return;
 while(!stop){
  Http ws{openSocket(conn.h,L"/api/native-input-ws")};if(!ws.h){nativeInputOnline=false;std::this_thread::sleep_for(200ms);continue;}
  nativeInputOnline=true;
  while(!stop){auto body=inputJSON();if(WinHttpWebSocketSend(ws.h,WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE,body.data(),DWORD(body.size()))!=NO_ERROR)break;std::this_thread::sleep_for(8ms);}
  nativeInputOnline=false;inputHttp.store(0);
 }
}
void nativeReceive(int channel){
 const bool geometry=channel!=0;
 Http session{WinHttpOpen(L"LumenGPU/0.7 view",WINHTTP_ACCESS_TYPE_NO_PROXY,WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0)};if(!session.h)return;
 WinHttpSetTimeouts(session.h,500,500,500,1000);Http conn{WinHttpConnect(session.h,L"127.0.0.1",8765,0)};if(!conn.h)return;
 while(!stop){
  Http ws{openSocket(conn.h,channel==0?L"/api/native-pose-ws":channel==1?L"/api/native-world-ws":L"/api/native-moving-ws")};
  if(!ws.h){if(!geometry){std::lock_guard<std::mutex> lk(mtx);connected=false;}std::this_thread::sleep_for(200ms);continue;}
  DWORD timeout=1000;WinHttpSetOption(ws.h,WINHTTP_OPTION_RECEIVE_TIMEOUT,&timeout,sizeof(timeout));
  bool first=true;uint64_t prev=0,prevPose=0;
  try{while(!stop){
   std::vector<unsigned char> data;WINHTTP_WEB_SOCKET_BUFFER_TYPE type;DWORD got=0;unsigned char tmp[16384];
   do{if(WinHttpWebSocketReceive(ws.h,tmp,sizeof(tmp),&got,&type)!=NO_ERROR||type==WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE)throw std::runtime_error("socket closed");if(type!=WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE&&type!=WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE)throw std::runtime_error("unexpected packet");data.insert(data.end(),tmp,tmp+got);if(data.size()>4000000)throw std::runtime_error("packet size");}while(type==WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE&&!stop);
   if(stop)break;Scene s=parse(data);uint64_t key=geometry?s.revision:s.seq;
   if(first||key!=prev){
    std::lock_guard<std::mutex> lk(mtx);
    if(channel==1){incoming.parts=std::move(s.parts);++incoming.revision;++receivedGeometry;}
    else if(channel==2){incomingMoving=std::move(s.parts);++incoming.revision;++receivedMoving;}
    else{if(first||s.revision!=prevPose){incomingCharacter=std::move(s.parts);++incoming.revision;++incoming.poseRevision;++receivedPose;prevPose=s.revision;}
     incoming.p=s.p;incoming.r=s.r;incoming.u=s.u;incoming.f=s.f;incoming.fov=s.fov;incoming.sun=s.sun;incoming.clock=s.clock;incoming.sunSize=s.sunSize;incoming.brightness=s.brightness;incoming.celestial=s.celestial;incoming.firstPerson=s.firstPerson;if(memcmp(incoming.skySlots,s.skySlots,sizeof(s.skySlots))||memcmp(incoming.skyBasis,s.skyBasis,sizeof(s.skyBasis))){memcpy(incoming.skySlots,s.skySlots,sizeof(s.skySlots));memcpy(incoming.skyBasis,s.skyBasis,sizeof(s.skyBasis));++incoming.revision;}incoming.seq=s.seq;connected=s.seq!=0;if(connected){++receivedCamera;cameraArrival.store(nowMs());}}
    first=false;prev=key;
   }
  }}catch(...){}
  if(!geometry){std::lock_guard<std::mutex> lk(mtx);connected=false;}
  if(!stop)std::this_thread::sleep_for(100ms);
 }
}
struct HUDItem{float x,y,w,h,cx,cy,cw,ch,size,border,round;uint32_t bg,fg,bc,ax,ay;std::string text;};
std::mutex hudMutex;std::vector<HUDItem> hudItems;
bool showHUD=true;
std::vector<HUDItem> parseHUD(const std::vector<unsigned char>& b){
 if(b.size()<8||memcmp(b.data(),"LGH1",4))throw std::runtime_error("HUD magic");size_t off=4;
 auto read=[&](auto& v){if(off+sizeof(v)>b.size())throw std::runtime_error("HUD truncated");memcpy(&v,b.data()+off,sizeof(v));off+=sizeof(v);};
 uint32_t n;read(n);if(n>256)throw std::runtime_error("HUD count");std::vector<HUDItem> out;out.reserve(n);
 for(uint32_t i=0;i<n;++i){HUDItem v{};read(v.x);read(v.y);read(v.w);read(v.h);read(v.cx);read(v.cy);read(v.cw);read(v.ch);read(v.size);read(v.border);read(v.round);read(v.bg);read(v.fg);read(v.bc);read(v.ax);read(v.ay);uint32_t len;read(len);if(len>1024||off+len>b.size())throw std::runtime_error("HUD text");v.text.assign(reinterpret_cast<const char*>(b.data()+off),len);off+=len;out.push_back(std::move(v));}
 if(off!=b.size())throw std::runtime_error("HUD trailing bytes");return out;
}
void hudNetwork(){
 Http session{WinHttpOpen(L"LumenGPU HUD",WINHTTP_ACCESS_TYPE_NO_PROXY,WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0)};if(!session.h)return;
 WinHttpSetTimeouts(session.h,500,500,500,1000);Http conn{WinHttpConnect(session.h,L"127.0.0.1",8765,0)};if(!conn.h)return;
 while(!stop){Http ws{openSocket(conn.h,L"/api/native-hud-ws")};if(!ws.h){std::this_thread::sleep_for(250ms);continue;}
 DWORD timeout=1000;WinHttpSetOption(ws.h,WINHTTP_OPTION_RECEIVE_TIMEOUT,&timeout,sizeof(timeout));
 try{while(!stop){std::vector<unsigned char> b;unsigned char tmp[16384];DWORD got;WINHTTP_WEB_SOCKET_BUFFER_TYPE type;
 do{if(WinHttpWebSocketReceive(ws.h,tmp,sizeof(tmp),&got,&type)!=NO_ERROR||(type!=WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE&&type!=WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE))throw std::runtime_error("HUD socket");b.insert(b.end(),tmp,tmp+got);if(b.size()>300000)throw std::runtime_error("HUD size");}while(type==WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE&&!stop);
 auto items=parseHUD(b);std::lock_guard<std::mutex> lk(hudMutex);hudItems=std::move(items);
 }}catch(...){} {std::lock_guard<std::mutex> lk(hudMutex);hudItems.clear();}if(!stop)std::this_thread::sleep_for(200ms);
 }
}
void drawGameHUD(UINT w,UINT h){
 if(!showHUD)return;std::lock_guard<std::mutex> lk(hudMutex);auto* dl=ImGui::GetBackgroundDrawList();auto* font=ImGui::GetFont();
 for(auto& v:hudItems){
 ImVec2 a(v.x*w,v.y*h),b((v.x+v.w)*w,(v.y+v.h)*h);
 dl->PushClipRect(ImVec2(v.cx*w,v.cy*h),ImVec2((v.cx+v.cw)*w,(v.cy+v.ch)*h),true);
 if(v.bg>>24)dl->AddRectFilled(a,b,v.bg,v.round*h);
 if(v.border>0)dl->AddRect(a,b,v.bc,v.round*h,0,std::max(1.f,v.border*h));
 if(!v.text.empty()&&(v.fg>>24)){float size=std::clamp(v.size*h,5.f,128.f);ImVec2 extent=font->CalcTextSizeA(size,1e6f,0,v.text.c_str());
 ImVec2 q(a.x+(v.ax==0?0:v.ax==2?b.x-a.x-extent.x:(b.x-a.x-extent.x)*.5f),a.y+(v.ay==0?0:v.ay==2?b.y-a.y-extent.y:(b.y-a.y-extent.y)*.5f));
 dl->PushClipRect(a,b,true);dl->AddText(font,size,q,v.fg,v.text.c_str());dl->PopClipRect();}
 dl->PopClipRect();
 }
}
// Independent local HTTP worker: asset transfers never block input polling.
void meshNetwork(){
 Http session{WinHttpOpen(L"LumenGPU/0.5 mesh",WINHTTP_ACCESS_TYPE_NO_PROXY,WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0)};if(!session.h)return;
 WinHttpSetTimeouts(session.h,1000,1000,1000,1000);
 Http conn{WinHttpConnect(session.h,L"127.0.0.1",8765,0)};if(!conn.h)return;
 std::unordered_map<uint32_t,std::chrono::steady_clock::time_point> retry,texRetry;
 while(!stop){
  std::unordered_set<uint32_t> ids,texIDs;{std::lock_guard<std::mutex> lk(mtx);if(connected)for(auto list:{&incoming.parts,&incomingMoving,&incomingCharacter})for(auto& p:*list){if(p.shape>=3&&p.shape<=16777215)ids.insert(uint32_t(p.shape));if(p.tex[0]>=1&&p.tex[0]<=128)texIDs.insert(uint32_t(p.tex[0]));for(int k=1;k<=3;++k)if(p.extra[k]>=1&&p.extra[k]<=128)texIDs.insert(uint32_t(p.extra[k]));for(int k=0;k<4;++k)if(p.cloth[k]>=1&&p.cloth[k]<=128)texIDs.insert(uint32_t(p.cloth[k]));}if(connected)for(auto id:incoming.skySlots)if(id>=1&&id<=128)texIDs.insert(id);}
  for(uint32_t id:ids){if(stop)break;
   {std::lock_guard<std::mutex> lk(meshMutex);if(downloadedMeshes.count(id)||downloadedMeshes.size()>=256)continue;}
   auto now=std::chrono::steady_clock::now();if(retry.count(id)&&now<retry[id])continue;retry[id]=now+2s;
   try{
    std::wstring route=L"/api/mesh?id="+std::to_wstring(id);
    Http req{WinHttpOpenRequest(conn.h,L"GET",route.c_str(),nullptr,WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,0)};
    if(!req.h||!WinHttpSendRequest(req.h,WINHTTP_NO_ADDITIONAL_HEADERS,0,WINHTTP_NO_REQUEST_DATA,0,0,0)||!WinHttpReceiveResponse(req.h,nullptr))continue;
    DWORD status=0,sz=sizeof(status);if(!WinHttpQueryHeaders(req.h,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,WINHTTP_HEADER_NAME_BY_INDEX,&status,&sz,WINHTTP_NO_HEADER_INDEX)||status!=200)continue;
    std::vector<unsigned char> data;unsigned char tmp[8192];DWORD got=0;
    do{if(!WinHttpReadData(req.h,tmp,sizeof(tmp),&got))throw std::runtime_error("mesh read");data.insert(data.end(),tmp,tmp+got);if(data.size()>1920008)throw std::runtime_error("mesh size");}while(got&&!stop);
    auto verts=std::make_shared<const MeshData>(parseMeshData(data));
    {std::lock_guard<std::mutex> lk(meshMutex);downloadedMeshes.emplace(id,verts);++meshEpoch;}
   }catch(...){}
   break; // at most one asset transfer before yielding
  }
  for(uint32_t id:texIDs){if(stop)break;
   {std::lock_guard<std::mutex> lk(meshMutex);if(downloadedTextures.count(id))continue;}
   auto now=std::chrono::steady_clock::now();if(texRetry.count(id)&&now<texRetry[id])continue;texRetry[id]=now+2s;
   try{
    std::wstring route=L"/api/texture?id="+std::to_wstring(id);
    Http req{WinHttpOpenRequest(conn.h,L"GET",route.c_str(),nullptr,WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,0)};
    if(!req.h||!WinHttpSendRequest(req.h,WINHTTP_NO_ADDITIONAL_HEADERS,0,WINHTTP_NO_REQUEST_DATA,0,0,0)||!WinHttpReceiveResponse(req.h,nullptr))continue;
    DWORD status=0,sz=sizeof(status);if(!WinHttpQueryHeaders(req.h,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,WINHTTP_HEADER_NAME_BY_INDEX,&status,&sz,WINHTTP_NO_HEADER_INDEX)||status!=200)continue;
    std::vector<unsigned char> data;unsigned char tmp[8192];DWORD got=0;
    do{if(!WinHttpReadData(req.h,tmp,sizeof(tmp),&got))throw std::runtime_error("texture read");data.insert(data.end(),tmp,tmp+got);if(data.size()>8+1024*1024*4)throw std::runtime_error("texture size");}while(got&&!stop);
    if(data.size()<8||memcmp(data.data(),"LGT1",4))continue;
    uint32_t side=0;memcpy(&side,data.data()+4,4);if((side!=256&&side!=512&&side!=1024)||data.size()!=8+size_t(side)*side*4)continue;
    auto pix=std::make_shared<std::vector<uint32_t>>(size_t(side)*side);memcpy(pix->data(),data.data()+8,pix->size()*4);
    {std::lock_guard<std::mutex> lk(meshMutex);downloadedTextures.emplace(id,pix);++meshEpoch;}
   }catch(...){}
   break;
  }
  std::this_thread::sleep_for(30ms);
 }
}
int bounces=2,spp=1; bool accum=true,forceDemo=false,resetHistory=true,fullscreen=false,smoothCamera=false; RECT restore{}; DWORD oldstyle=0;
bool reservedKey(WPARAM w){return w==VK_F1||w==VK_F2||w==VK_F11||w==VK_ESCAPE;}
void keyEvent(WPARAM w,LPARAM l,bool down){
 int vk=int(w);if(vk==VK_SHIFT)vk=int(MapVirtualKeyW((UINT(l)>>16)&255,MAPVK_VSC_TO_VK_EX));
 if(vk==VK_CONTROL)vk=(l&(1L<<24))?VK_RCONTROL:VK_LCONTROL;
 if(vk==VK_MENU)vk=(l&(1L<<24))?VK_RMENU:VK_LMENU;
 bool repeat=down&&(l&(1L<<30));if(repeat&&vk!=VK_BACK&&vk!=VK_DELETE&&vk!=VK_LEFT&&vk!=VK_RIGHT&&vk!=VK_UP&&vk!=VK_DOWN)return;
 std::lock_guard<std::mutex> lk(inputMutex);if(input.keys.size()<96)input.keys.push_back({vk,down,repeat});
}
LRESULT CALLBACK wnd(HWND h,UINT m,WPARAM w,LPARAM l){
 if(uiReady&&!captured&&uiVisible&&m!=WM_KEYDOWN&&m!=WM_DESTROY&&m!=WM_KILLFOCUS) ImGui_ImplWin32_WndProcHandler(h,m,w,l);
 if(m==WM_DESTROY){releaseInput();PostQuitMessage(0);return 0;}
 if(m==WM_KILLFOCUS){releaseInput();return 0;}
 if(m==WM_CAPTURECHANGED&&rightDrag){endDrag();return 0;}
 if(m==WM_MOUSEWHEEL&&captured){float delta=float(short(HIWORD(w)))/WHEEL_DELTA;float d=orbitSetting.load();if(delta<0&&d<=.75f)d=1.f;d=std::clamp(d*std::pow(1.25f,-delta),.5f,40.f);if(delta>0&&d<.8f)d=.5f;orbitSetting.store(d);return 0;}
 if(m==WM_LBUTTONDOWN||m==WM_LBUTTONUP){if(captured){if(m==WM_LBUTTONDOWN)SetCapture(h);else if(!rightDrag)ReleaseCapture();pointerEvent(h,1,m==WM_LBUTTONDOWN,l);}else if(m==WM_LBUTTONDOWN)SetFocus(h);return 0;}
 if(captured&&(m==WM_RBUTTONDOWN||m==WM_RBUTTONUP)){bool down=m==WM_RBUTTONDOWN;pointerEvent(h,2,down,l);if(down&&!mouseLocked){rightDrag=true;GetCursorPos(&dragAnchor);SetCapture(h);}else if(!down){if(rightDrag&&!mouseLocked)SetCursorPos(dragAnchor.x,dragAnchor.y);endDrag();if(!(GetAsyncKeyState(VK_LBUTTON)&0x8000))ReleaseCapture();}return 0;}
 if(captured&&(m==WM_MBUTTONDOWN||m==WM_MBUTTONUP)){pointerEvent(h,3,m==WM_MBUTTONDOWN,l);return 0;}
 if(captured&&(m==WM_KEYDOWN||m==WM_KEYUP||m==WM_SYSKEYDOWN||m==WM_SYSKEYUP)&&!reservedKey(w)){keyEvent(w,l,m==WM_KEYDOWN||m==WM_SYSKEYDOWN);return 0;}
 if(m==WM_KEYDOWN){if(w==VK_F1){if(!(l&(1L<<30))){if(captured){releaseInput();uiVisible=true;}else uiVisible=!uiVisible;}return 0;}if(uiReady&&uiVisible&&!captured){ImGui_ImplWin32_WndProcHandler(h,m,w,l);if(ImGui::GetIO().WantTextInput)return 0;}if(w==VK_F2){if(!(l&(1L<<30)))captureInput(h);return 0;}if(w==VK_ESCAPE&&captured){releaseInput();return 0;}if(w==VK_F3){if(!(l&(1L<<30))){debugView=(debugView+1)%6;resetHistory=true;}return 0;}if(w==VK_F6){if(!(l&(1L<<30))){smoothCamera=!smoothCamera;resetHistory=true;}return 0;}if(w==VK_F4){exposure=std::max(-4.f,exposure-.5f);resetHistory=true;return 0;}if(w==VK_F5){exposure=std::min(4.f,exposure+.5f);resetHistory=true;return 0;}if(captured&&(w=='W'||w=='A'||w=='S'||w=='D'||w==VK_SPACE))return 0;switch(w){case VK_ESCAPE:DestroyWindow(h);break;case 'B':bounces=(bounces+1)%13;resetHistory=true;break;case 'S':spp=spp==1?2:spp==2?4:1;resetHistory=true;break;case 'A':accum=!accum;resetHistory=true;break;case 'R':resetHistory=true;break;case 'D':forceDemo=!forceDemo;resetHistory=true;break;case VK_F11:if(!fullscreen){GetWindowRect(h,&restore);oldstyle=DWORD(GetWindowLongPtr(h,GWL_STYLE));MONITORINFO mi{sizeof(mi)};GetMonitorInfo(MonitorFromWindow(h,MONITOR_DEFAULTTONEAREST),&mi);SetWindowLongPtr(h,GWL_STYLE,WS_POPUP|WS_VISIBLE);SetWindowPos(h,HWND_TOP,mi.rcMonitor.left,mi.rcMonitor.top,mi.rcMonitor.right-mi.rcMonitor.left,mi.rcMonitor.bottom-mi.rcMonitor.top,SWP_FRAMECHANGED); }else{SetWindowLongPtr(h,GWL_STYLE,oldstyle);SetWindowPos(h,nullptr,restore.left,restore.top,restore.right-restore.left,restore.bottom-restore.top,SWP_FRAMECHANGED|SWP_NOZORDER);}fullscreen=!fullscreen;break;}return 0;}
 return DefWindowProc(h,m,w,l);
}
struct F4{float x,y,z,w;}; F4 f4(V v,float w=0){return {v.x,v.y,v.z,w};}
struct Mat{F4 colorMetal,roughEmit,ax,ay,az,scaleSpec,emitColor,tex0,tex1,extra0,extra1,cloth0,cloth1;};static_assert(sizeof(Mat)==208);
static bool generatedPBR=true,proceduralStuds=true,localLightNEE=true,mipFiltering=true;
static bool renderParticles=true,customSky=true;static unsigned skyFacesReady=0,skyFacesRequested=0;
static bool frameGen=false;static int upscaleMode=1;static float upscaleSharpness=.35f,realFPS=0,presentFPS=0,generatedFPS=0;static float normalStrength=1.f,roughnessStrength=1.f,fireflyLimit=8.f,reflectionStrength=1.f;

std::vector<uint32_t> loadSunPixels(const std::filesystem::path& path){
 std::vector<uint32_t> pixels(128*128);
 for(int y=0;y<128;++y)for(int x=0;x<128;++x){
  float u=(x+.5f)/64-1,v=(y+.5f)/64-1,r=std::sqrt(u*u+v*v);
  unsigned a=unsigned(std::clamp((1-r)*64,0.f,1.f)*255+.5f),g=unsigned(255-18*std::min(r,1.f)),b=unsigned(255-50*std::min(r,1.f));
  pixels[y*128+x]=255u|(g<<8)|(b<<16)|(a<<24);
 }
 if(!std::filesystem::exists(path))return pixels;
 HRESULT hr=CoInitializeEx(nullptr,COINIT_MULTITHREADED);bool uninit=SUCCEEDED(hr);
 {
 ComPtr<IWICImagingFactory> factory;ComPtr<IWICBitmapDecoder> decoder;ComPtr<IWICBitmapFrameDecode> frame;ComPtr<IWICBitmapScaler> scaler;ComPtr<IWICFormatConverter> converter;
 std::vector<uint32_t> custom(128*128);
 if(SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)))&&
 SUCCEEDED(factory->CreateDecoderFromFilename(path.c_str(),nullptr,GENERIC_READ,WICDecodeMetadataCacheOnLoad,&decoder))&&
 SUCCEEDED(decoder->GetFrame(0,&frame))&&SUCCEEDED(factory->CreateBitmapScaler(&scaler))&&
 SUCCEEDED(scaler->Initialize(frame.Get(),128,128,WICBitmapInterpolationModeFant))&&SUCCEEDED(factory->CreateFormatConverter(&converter))&&
 SUCCEEDED(converter->Initialize(scaler.Get(),GUID_WICPixelFormat32bppRGBA,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom))&&
 SUCCEEDED(converter->CopyPixels(nullptr,128*4,UINT(custom.size()*4),reinterpret_cast<BYTE*>(custom.data()))))pixels=std::move(custom);
 }
 if(uninit)CoUninitialize();return pixels;
}
struct Params { F4 dims,eye,right,up,forward,sun,options,quality,switches,display,environment; }; static_assert(sizeof(Params)==176);
struct Renderer {
 UINT W,H; HWND hwnd; ComPtr<IDXGIFactory6> factory; ComPtr<ID3D12Device5> dev; ComPtr<ID3D12CommandQueue> queue; ComPtr<ID3D12CommandAllocator> alloc; ComPtr<ID3D12GraphicsCommandList4> cmd; ComPtr<IDXGISwapChain3> swap; ComPtr<ID3D12Fence> fence; HANDLE event=nullptr; UINT64 serial=0;
 ComPtr<ID3D12RootSignature> root; ComPtr<ID3D12PipelineState> pso,resolvePso,wavePso; ComPtr<ID3D12DescriptorHeap> heap,rtvHeap;UINT rtvStep=0; ComPtr<ID3D12Resource> blas,sphereBlas,cylinderBlas,tlas,materials,hist,out,guide,albedo,waveA,waveB,sunPixels; std::wstring gpu;size_t skippedEnclosing=0,meshInstances=0,meshFallback=0;
 ComPtr<ID3D12RootSignature> fgRoot;ComPtr<ID3D12PipelineState> flowPso,interpolatePso;ComPtr<ID3D12DescriptorHeap> fgHeap;ComPtr<ID3D12Resource> fgPrevious,fgCurrent,fgMotion;bool fgValid=false,fgAvailable=false;V fgEye{},fgForward{};float fgFov=0;UINT fgStep=0;
 ComPtr<ID3D12Resource> tlasScratch,tlasInstances;std::vector<UINT64> lastAddresses;unsigned refits=0,refitTotal=0,rebuildTotal=0;float tlasMs=0;
 struct MeshGPU{ComPtr<ID3D12Resource> as;UINT normalOffset=0,uvOffset=0;};std::unordered_map<uint32_t,MeshGPU> meshBLAS;MeshGPU wedgeGPU,cornerGPU,headGPU,particleGPU;std::unordered_map<unsigned,MeshGPU> trussGPU;std::vector<V> meshNormals{{0,1,0}};ComPtr<ID3D12Resource> meshNormalBuffer;std::vector<uint32_t> atlas;std::unordered_map<uint32_t,UINT> textureOffsets;UINT lightStart=0,lightCount=0,particleCount=0;
 Renderer(HWND h,UINT w,UINT hh):W(w),H(hh),hwnd(h){}
 ~Renderer(){if(uiReady){uiReady=false;ImGui_ImplDX12_Shutdown();ImGui_ImplWin32_Shutdown();ImGui::DestroyContext();}if(event)CloseHandle(event);}
 ComPtr<ID3D12Resource> buffer(UINT64 n,D3D12_HEAP_TYPE heapType,D3D12_RESOURCE_FLAGS flags,D3D12_RESOURCE_STATES state){D3D12_HEAP_PROPERTIES hp{};hp.Type=heapType;hp.CreationNodeMask=hp.VisibleNodeMask=1;D3D12_RESOURCE_DESC d{};d.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;d.Width=n;d.Height=1;d.DepthOrArraySize=1;d.MipLevels=1;d.SampleDesc.Count=1;d.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;d.Flags=flags;ComPtr<ID3D12Resource> r;check(dev->CreateCommittedResource(&hp,D3D12_HEAP_FLAG_NONE,&d,state,nullptr,IID_PPV_ARGS(&r)),"buffer");return r;}
 ComPtr<ID3D12Resource> upload(const void* p,size_t n){auto r=buffer(n,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_FLAG_NONE,D3D12_RESOURCE_STATE_GENERIC_READ);void* dst;D3D12_RANGE read{0,0};check(r->Map(0,&read,&dst),"map");memcpy(dst,p,n);r->Unmap(0,nullptr);return r;}
 void begin(){check(alloc->Reset(),"allocator reset");check(cmd->Reset(alloc.Get(),nullptr),"command reset");}
 void submit(){check(cmd->Close(),"close command");ID3D12CommandList* lists[]={cmd.Get()};queue->ExecuteCommandLists(1,lists);check(queue->Signal(fence.Get(),++serial),"signal");if(fence->GetCompletedValue()<serial){check(fence->SetEventOnCompletion(serial,event),"fence event");if(WaitForSingleObject(event,10000)!=WAIT_OBJECT_0)throw std::runtime_error("GPU timeout");}check(dev->GetDeviceRemovedReason(),"GPU device removed");}
 void transition(ID3D12Resource* r,D3D12_RESOURCE_STATES a,D3D12_RESOURCE_STATES b){D3D12_RESOURCE_BARRIER x{};x.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;x.Transition={r,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,a,b};cmd->ResourceBarrier(1,&x);}
 void uav(ID3D12Resource* r){D3D12_RESOURCE_BARRIER b{};b.Type=D3D12_RESOURCE_BARRIER_TYPE_UAV;b.UAV.pResource=r;cmd->ResourceBarrier(1,&b);}
 ComPtr<ID3D12Resource> build(D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS inputs){D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO info{};dev->GetRaytracingAccelerationStructurePrebuildInfo(&inputs,&info);if(!info.ResultDataMaxSizeInBytes||!info.ScratchDataSizeInBytes)throw std::runtime_error("AS prebuild failed");auto result=buffer(info.ResultDataMaxSizeInBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE);auto scratch=buffer(info.ScratchDataSizeInBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC d{};d.Inputs=inputs;d.DestAccelerationStructureData=result->GetGPUVirtualAddress();d.ScratchAccelerationStructureData=scratch->GetGPUVirtualAddress();begin();cmd->BuildRaytracingAccelerationStructure(&d,0,nullptr);uav(result.Get());submit();return result;}
 void init(const std::filesystem::path& shader){check(CreateDXGIFactory2(0,IID_PPV_ARGS(&factory)),"DXGI factory");
 for(UINT i=0;;++i){ComPtr<IDXGIAdapter1>a;if(factory->EnumAdapterByGpuPreference(i,DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,IID_PPV_ARGS(&a))==DXGI_ERROR_NOT_FOUND)break;if(!a)continue;DXGI_ADAPTER_DESC1 ad{};a->GetDesc1(&ad);if(ad.Flags&DXGI_ADAPTER_FLAG_SOFTWARE)continue;ComPtr<ID3D12Device5> candidate;if(FAILED(D3D12CreateDevice(a.Get(),D3D_FEATURE_LEVEL_12_0,IID_PPV_ARGS(&candidate))))continue;D3D12_FEATURE_DATA_D3D12_OPTIONS5 op{};D3D12_FEATURE_DATA_SHADER_MODEL sm{D3D_SHADER_MODEL_6_5};if(SUCCEEDED(candidate->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS5,&op,sizeof(op)))&&op.RaytracingTier>=D3D12_RAYTRACING_TIER_1_1&&SUCCEEDED(candidate->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL,&sm,sizeof(sm)))&&sm.HighestShaderModel>=D3D_SHADER_MODEL_6_5){dev=candidate;gpu=ad.Description;break;}}
 if(!dev)throw std::runtime_error("No DXR 1.1 / Shader Model 6.5 GPU found. Update Windows and GPU driver.");
 D3D12_FEATURE_DATA_FORMAT_SUPPORT fmt{DXGI_FORMAT_R8G8B8A8_UNORM};check(dev->CheckFeatureSupport(D3D12_FEATURE_FORMAT_SUPPORT,&fmt,sizeof(fmt)),"format support");if(!(fmt.Support2&D3D12_FORMAT_SUPPORT2_UAV_TYPED_STORE))throw std::runtime_error("RGBA8 UAV stores unsupported");
 D3D12_COMMAND_QUEUE_DESC q{};q.Type=D3D12_COMMAND_LIST_TYPE_DIRECT;check(dev->CreateCommandQueue(&q,IID_PPV_ARGS(&queue)),"queue");check(dev->CreateCommandAllocator(q.Type,IID_PPV_ARGS(&alloc)),"allocator");check(dev->CreateCommandList(0,q.Type,alloc.Get(),nullptr,IID_PPV_ARGS(&cmd)),"command list");check(cmd->Close(),"initial close");check(dev->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)),"fence");event=CreateEvent(nullptr,FALSE,FALSE,nullptr);if(!event)throw std::runtime_error("fence event creation");
 DXGI_SWAP_CHAIN_DESC1 sd{};sd.Width=W;sd.Height=H;sd.Format=DXGI_FORMAT_R8G8B8A8_UNORM;sd.SampleDesc.Count=1;sd.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;sd.BufferCount=2;sd.SwapEffect=DXGI_SWAP_EFFECT_FLIP_DISCARD;sd.Scaling=DXGI_SCALING_STRETCH;ComPtr<IDXGISwapChain1> sc;check(factory->CreateSwapChainForHwnd(queue.Get(),hwnd,&sd,nullptr,nullptr,&sc),"swapchain");check(sc.As(&swap),"swapchain3");factory->MakeWindowAssociation(hwnd,DXGI_MWA_NO_ALT_ENTER);
 D3D12_DESCRIPTOR_RANGE range{};range.RangeType=D3D12_DESCRIPTOR_RANGE_TYPE_UAV;range.NumDescriptors=1;range.BaseShaderRegister=1;
 D3D12_ROOT_PARAMETER p[11]{};p[0].ParameterType=D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS;p[0].Constants={0,0,44};for(int i=1;i<=2;++i){p[i].ParameterType=D3D12_ROOT_PARAMETER_TYPE_SRV;p[i].Descriptor.ShaderRegister=i-1;}p[3].ParameterType=D3D12_ROOT_PARAMETER_TYPE_UAV;p[3].Descriptor.ShaderRegister=0;p[4].ParameterType=D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;p[4].DescriptorTable={1,&range};D3D12_ROOT_SIGNATURE_DESC rs{};for(int i=5;i<=6;++i){p[i].ParameterType=D3D12_ROOT_PARAMETER_TYPE_UAV;p[i].Descriptor.ShaderRegister=i-3;}p[7].ParameterType=D3D12_ROOT_PARAMETER_TYPE_SRV;p[7].Descriptor.ShaderRegister=2;for(int i=8;i<=9;++i){p[i].ParameterType=D3D12_ROOT_PARAMETER_TYPE_UAV;p[i].Descriptor.ShaderRegister=i-4;}p[10].ParameterType=D3D12_ROOT_PARAMETER_TYPE_SRV;p[10].Descriptor.ShaderRegister=3;rs.NumParameters=11;rs.pParameters=p;ComPtr<ID3DBlob> blob,err;check(D3D12SerializeRootSignature(&rs,D3D_ROOT_SIGNATURE_VERSION_1,&blob,&err),"root signature serialize");check(dev->CreateRootSignature(0,blob->GetBufferPointer(),blob->GetBufferSize(),IID_PPV_ARGS(&root)),"root signature");
 std::ifstream f(shader,std::ios::binary);std::vector<char> bytes((std::istreambuf_iterator<char>(f)),{});if(bytes.empty())throw std::runtime_error("Missing trace.cso; build/package again");D3D12_COMPUTE_PIPELINE_STATE_DESC ps{};ps.pRootSignature=root.Get();ps.CS={bytes.data(),bytes.size()};check(dev->CreateComputePipelineState(&ps,IID_PPV_ARGS(&pso)),"DXR compute pipeline");
 std::ifstream rf(shader.parent_path()/L"resolve.cso",std::ios::binary);std::vector<char> rb((std::istreambuf_iterator<char>(rf)),{});if(rb.empty())throw std::runtime_error("Missing resolve.cso");ps.CS={rb.data(),rb.size()};check(dev->CreateComputePipelineState(&ps,IID_PPV_ARGS(&resolvePso)),"denoiser pipeline");
 std::ifstream wf(shader.parent_path()/L"wavelet.cso",std::ios::binary);std::vector<char> wb((std::istreambuf_iterator<char>(wf)),{});if(wb.empty())throw std::runtime_error("Missing wavelet.cso");ps.CS={wb.data(),wb.size()};check(dev->CreateComputePipelineState(&ps,IID_PPV_ARGS(&wavePso)),"wavelet pipeline");
 hist=buffer(UINT64(W)*H*16,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
 guide=buffer(UINT64(W)*H*16,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);albedo=buffer(UINT64(W)*H*16,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
 waveA=buffer(UINT64(W)*H*16,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);waveB=buffer(UINT64(W)*H*16,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);atlas=loadSunPixels(shader.parent_path()/L"sun.png");sunPixels=upload(atlas.data(),atlas.size()*sizeof(uint32_t));
 D3D12_HEAP_PROPERTIES hp{};hp.Type=D3D12_HEAP_TYPE_DEFAULT;hp.CreationNodeMask=hp.VisibleNodeMask=1;D3D12_RESOURCE_DESC td{};td.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;td.Width=W;td.Height=H;td.DepthOrArraySize=1;td.MipLevels=1;td.Format=sd.Format;td.SampleDesc.Count=1;td.Flags=D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;check(dev->CreateCommittedResource(&hp,D3D12_HEAP_FLAG_NONE,&td,D3D12_RESOURCE_STATE_UNORDERED_ACCESS,nullptr,IID_PPV_ARGS(&out)),"output texture");D3D12_DESCRIPTOR_HEAP_DESC hd{};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;hd.NumDescriptors=2;hd.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;check(dev->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&heap)),"descriptor heap");dev->CreateUnorderedAccessView(out.Get(),nullptr,nullptr,heap->GetCPUDescriptorHandleForHeapStart());
 initFrameGen(shader,td,hp);
 D3D12_DESCRIPTOR_HEAP_DESC rd{};rd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV;rd.NumDescriptors=2;check(dev->CreateDescriptorHeap(&rd,IID_PPV_ARGS(&rtvHeap)),"RTV heap");rtvStep=dev->GetDescriptorHandleIncrementSize(rd.Type);
 for(UINT i=0;i<2;++i){ComPtr<ID3D12Resource> bb;check(swap->GetBuffer(i,IID_PPV_ARGS(&bb)),"UI backbuffer");auto h=rtvHeap->GetCPUDescriptorHandleForHeapStart();h.ptr+=SIZE_T(i)*rtvStep;dev->CreateRenderTargetView(bb.Get(),nullptr,h);}
 IMGUI_CHECKVERSION();ImGui::CreateContext();ImGui::StyleColorsDark();ImGui::GetIO().IniFilename=nullptr;ImGui_ImplWin32_Init(hwnd);auto cpu=heap->GetCPUDescriptorHandleForHeapStart();auto gpuHandle=heap->GetGPUDescriptorHandleForHeapStart();UINT step=dev->GetDescriptorHandleIncrementSize(hd.Type);cpu.ptr+=step;gpuHandle.ptr+=step;if(!ImGui_ImplDX12_Init(dev.Get(),2,sd.Format,heap.Get(),cpu,gpuHandle))throw std::runtime_error("ImGui DX12 initialization failed");uiReady=true;
 // Unit cube, two triangles per face, in +X,-X,+Y,-Y,+Z,-Z order.
 std::vector<V> verts;for(int face=0;face<6;++face){int axis=face/2,j=(axis+1)%3,k=(axis+2)%3;auto v=[&](float b,float c){float a[3]{};a[axis]=face%2?-.5f:.5f;a[j]=b;a[k]=c;return V{a[0],a[1],a[2]};};auto a=v(-.5f,-.5f),b=v(.5f,-.5f),c=v(.5f,.5f),d=v(-.5f,.5f);verts.insert(verts.end(),{a,b,c,a,c,d});}auto vb=upload(verts.data(),verts.size()*sizeof(V));D3D12_RAYTRACING_GEOMETRY_DESC g{};g.Type=D3D12_RAYTRACING_GEOMETRY_TYPE_TRIANGLES;g.Flags=D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE;g.Triangles.VertexFormat=DXGI_FORMAT_R32G32B32_FLOAT;g.Triangles.VertexCount=UINT(verts.size());g.Triangles.VertexBuffer={vb->GetGPUVirtualAddress(),sizeof(V)};D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS bi{};bi.Type=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;bi.Flags=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;bi.DescsLayout=D3D12_ELEMENTS_LAYOUT_ARRAY;bi.NumDescs=1;bi.pGeometryDescs=&g;blas=build(bi);
 auto primitive=[&](const std::vector<V>& v){auto gpuVerts=upload(v.data(),v.size()*sizeof(V));auto geom=g;geom.Triangles.VertexCount=UINT(v.size());geom.Triangles.VertexBuffer={gpuVerts->GetGPUVirtualAddress(),sizeof(V)};auto input=bi;input.pGeometryDescs=&geom;return build(input);};
 std::vector<V> sv,cv;constexpr float pi=3.14159265359f;constexpr int slices=24,rings=12;
 auto sphere=[](float phi,float th)->V{return {.5f*std::sin(th)*std::cos(phi),.5f*std::cos(th),.5f*std::sin(th)*std::sin(phi)};};
 for(int j=0;j<rings;++j)for(int i=0;i<slices;++i){float a=2*pi*i/slices,b=2*pi*(i+1)/slices,t=pi*j/rings,u=pi*(j+1)/rings;V v0=sphere(a,t),v1=sphere(b,t),v2=sphere(b,u),v3=sphere(a,u);if(j>0)sv.insert(sv.end(),{v0,v1,v2});if(j<rings-1)sv.insert(sv.end(),{v0,v2,v3});}
 for(int i=0;i<slices;++i){float a=2*pi*i/slices,b=2*pi*(i+1)/slices;V l0{-.5f,.5f*std::cos(a),.5f*std::sin(a)},l1{-.5f,.5f*std::cos(b),.5f*std::sin(b)},r0{.5f,l0.y,l0.z},r1{.5f,l1.y,l1.z};cv.insert(cv.end(),{l0,l1,r1,l0,r1,r0,V{-.5f,0,0},l1,l0,V{.5f,0,0},r0,r1});}
 sphereBlas=primitive(sv);cylinderBlas=primitive(cv);wedgeGPU=makeTriangleMesh(primitives::wedge(false));cornerGPU=makeTriangleMesh(primitives::wedge(true));headGPU=makeTriangleMesh(classicHead());particleGPU=makeTriangleMesh({{-.5f,-.5f,0},{.5f,-.5f,0},{.5f,.5f,0},{-.5f,-.5f,0},{.5f,.5f,0},{-.5f,.5f,0}});meshNormalBuffer=upload(meshNormals.data(),meshNormals.size()*sizeof(V));
 }
 void initFrameGen(const std::filesystem::path& shader,const D3D12_RESOURCE_DESC& td,const D3D12_HEAP_PROPERTIES& hp){
  try{
   D3D12_DESCRIPTOR_RANGE ranges[2]{};ranges[0].RangeType=D3D12_DESCRIPTOR_RANGE_TYPE_SRV;ranges[0].NumDescriptors=2;ranges[0].BaseShaderRegister=0;ranges[1].RangeType=D3D12_DESCRIPTOR_RANGE_TYPE_UAV;ranges[1].NumDescriptors=1;ranges[1].BaseShaderRegister=0;
   D3D12_ROOT_PARAMETER p[4]{};p[0].ParameterType=D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS;p[0].Constants={0,0,4};
   for(int i=1;i<=2;++i){p[i].ParameterType=D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;p[i].DescriptorTable={1,&ranges[i-1]};}
   p[3].ParameterType=D3D12_ROOT_PARAMETER_TYPE_UAV;p[3].Descriptor.ShaderRegister=1;
   D3D12_ROOT_SIGNATURE_DESC rs{};rs.NumParameters=4;rs.pParameters=p;ComPtr<ID3DBlob> blob,err;
   check(D3D12SerializeRootSignature(&rs,D3D_ROOT_SIGNATURE_VERSION_1,&blob,&err),"frame gen root serialize");
   check(dev->CreateRootSignature(0,blob->GetBufferPointer(),blob->GetBufferSize(),IID_PPV_ARGS(&fgRoot)),"frame gen root");
   auto makePso=[&](const wchar_t* name,ComPtr<ID3D12PipelineState>& target){
    std::ifstream f(shader.parent_path()/name,std::ios::binary);std::vector<char> bytes((std::istreambuf_iterator<char>(f)),{});
    if(bytes.empty())throw std::runtime_error("Missing frame generation shader");
    D3D12_COMPUTE_PIPELINE_STATE_DESC ps{};ps.pRootSignature=fgRoot.Get();ps.CS={bytes.data(),bytes.size()};check(dev->CreateComputePipelineState(&ps,IID_PPV_ARGS(&target)),"frame gen PSO");
   };
   makePso(L"estimateMotion.cso",flowPso);makePso(L"interpolateFrame.cso",interpolatePso);
   D3D12_DESCRIPTOR_HEAP_DESC hd{};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;hd.NumDescriptors=3;hd.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;check(dev->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&fgHeap)),"frame gen descriptors");
   fgStep=dev->GetDescriptorHandleIncrementSize(hd.Type);
   auto desc=td;desc.Flags=D3D12_RESOURCE_FLAG_NONE;
   check(dev->CreateCommittedResource(&hp,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,nullptr,IID_PPV_ARGS(&fgPrevious)),"previous frame");
   check(dev->CreateCommittedResource(&hp,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,nullptr,IID_PPV_ARGS(&fgCurrent)),"current frame");
   fgMotion=buffer(UINT64((W+15)/16)*((H+15)/16)*32,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
   fgAvailable=true;
  }catch(...){fgAvailable=false;}
 }
 void generateFrame(){
  auto cpu=fgHeap->GetCPUDescriptorHandleForHeapStart();
  D3D12_SHADER_RESOURCE_VIEW_DESC srv{};srv.Format=DXGI_FORMAT_R8G8B8A8_UNORM;srv.ViewDimension=D3D12_SRV_DIMENSION_TEXTURE2D;srv.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;srv.Texture2D.MipLevels=1;
  dev->CreateShaderResourceView(fgPrevious.Get(),&srv,cpu);cpu.ptr+=fgStep;dev->CreateShaderResourceView(fgCurrent.Get(),&srv,cpu);cpu.ptr+=fgStep;dev->CreateUnorderedAccessView(out.Get(),nullptr,nullptr,cpu);
  ID3D12DescriptorHeap* hs[]={fgHeap.Get()};cmd->SetDescriptorHeaps(1,hs);cmd->SetComputeRootSignature(fgRoot.Get());auto gpu=fgHeap->GetGPUDescriptorHandleForHeapStart();
  UINT constants[]={W,H,(W+15)/16,(H+15)/16};
  cmd->SetComputeRoot32BitConstants(0,4,constants,0);cmd->SetComputeRootDescriptorTable(1,gpu);gpu.ptr+=2*fgStep;cmd->SetComputeRootDescriptorTable(2,gpu);cmd->SetComputeRootUnorderedAccessView(3,fgMotion->GetGPUVirtualAddress());
  cmd->SetPipelineState(flowPso.Get());cmd->Dispatch((constants[2]+7)/8,(constants[3]+7)/8,1);uav(fgMotion.Get());
  cmd->SetPipelineState(interpolatePso.Get());cmd->Dispatch((W+7)/8,(H+7)/8,1);uav(out.Get());
 }
 void presentFrom(ID3D12Resource* source,D3D12_RESOURCE_STATES state){
  ComPtr<ID3D12Resource> back;check(swap->GetBuffer(swap->GetCurrentBackBufferIndex(),IID_PPV_ARGS(&back)),"backbuffer");
  transition(source,state,D3D12_RESOURCE_STATE_COPY_SOURCE);transition(back.Get(),D3D12_RESOURCE_STATE_PRESENT,D3D12_RESOURCE_STATE_COPY_DEST);cmd->CopyResource(back.Get(),source);
  if(uiReady){
   transition(back.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_RENDER_TARGET);auto h=rtvHeap->GetCPUDescriptorHandleForHeapStart();h.ptr+=SIZE_T(swap->GetCurrentBackBufferIndex())*rtvStep;cmd->OMSetRenderTargets(1,&h,FALSE,nullptr);
   ID3D12DescriptorHeap* hs[]={heap.Get()};cmd->SetDescriptorHeaps(1,hs);ImGui_ImplDX12_RenderDrawData(ImGui::GetDrawData(),cmd.Get());transition(back.Get(),D3D12_RESOURCE_STATE_RENDER_TARGET,D3D12_RESOURCE_STATE_PRESENT);
  }else transition(back.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_PRESENT);
  transition(source,D3D12_RESOURCE_STATE_COPY_SOURCE,state);submit();check(swap->Present(1,0),"present");
 }
 void invalidateFrameGen(){fgValid=false;}
 static std::vector<V> classicHead(){
  // Rounded cylinder profile, unit dimensions, outward winding.
  constexpr float pi=3.14159265359f;constexpr int n=32;
  const float ys[]={-.5f,-.48f,-.43f,-.35f,.35f,.43f,.48f,.5f};
  const float rs[]={.33f,.41f,.47f,.5f,.5f,.47f,.41f,.33f};
  std::vector<V> v;auto point=[&](int j,int i){float a=2*pi*i/n;return V{rs[j]*std::cos(a),ys[j],rs[j]*std::sin(a)};};
  for(int i=0;i<n;++i){
   for(int j=0;j<7;++j){auto a=point(j,i),b=point(j,i+1),c=point(j+1,i+1),d=point(j+1,i);v.insert(v.end(),{a,d,c,a,c,b});}
   v.insert(v.end(),{V{0,-.5f,0},point(0,i),point(0,i+1),V{0,.5f,0},point(7,i+1),point(7,i)});
  }
  return v;
 }
 MeshGPU makeTriangleMesh(const std::vector<V>& v){
  auto vb=upload(v.data(),v.size()*sizeof(V));D3D12_RAYTRACING_GEOMETRY_DESC g{};g.Type=D3D12_RAYTRACING_GEOMETRY_TYPE_TRIANGLES;g.Flags=D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE;g.Triangles.VertexFormat=DXGI_FORMAT_R32G32B32_FLOAT;g.Triangles.VertexCount=UINT(v.size());g.Triangles.VertexBuffer={vb->GetGPUVirtualAddress(),sizeof(V)};
  D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS bi{};bi.Type=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;bi.Flags=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;bi.DescsLayout=D3D12_ELEMENTS_LAYOUT_ARRAY;bi.NumDescs=1;bi.pGeometryDescs=&g;
  MeshGPU m;m.as=build(bi);m.normalOffset=UINT(meshNormals.size());for(size_t i=0;i<v.size();i+=3){auto n=triangleNormal(v[i],v[i+1],v[i+2]);for(int k=0;k<4;++k)meshNormals.push_back(n);meshNormals.push_back({0,0,0});meshNormals.push_back({0,0,0});}return m;
 }
 void prepareMeshes(const Scene& s){
  bool changed=false;
  for(auto& p:s.parts)if(p.shape>=-5&&p.shape<=-3){unsigned key=primitives::trussKey(p.shape,p.s.y);if(!trussGPU.count(key)){unsigned n=primitives::bays(p.s.y),style=unsigned(-p.shape)-3;if(meshNormals.size()>2500000){n=1;}trussGPU.emplace(key,makeTriangleMesh(primitives::truss(n,style)));changed=true;}}
  std::unordered_set<uint32_t> wanted;for(auto& p:s.parts)if(p.shape>=3&&p.shape<=16777215)wanted.insert(uint32_t(p.shape));
  for(auto id:wanted){if(meshBLAS.count(id))continue;
   std::shared_ptr<const MeshData> data;{std::lock_guard<std::mutex> lk(meshMutex);auto it=downloadedMeshes.find(id);if(it!=downloadedMeshes.end())data=it->second;}if(!data)continue;const auto* v=&data->positions;
   auto vb=upload(v->data(),v->size()*sizeof(V));D3D12_RAYTRACING_GEOMETRY_DESC g{};g.Type=D3D12_RAYTRACING_GEOMETRY_TYPE_TRIANGLES;g.Flags=D3D12_RAYTRACING_GEOMETRY_FLAG_OPAQUE;g.Triangles.VertexFormat=DXGI_FORMAT_R32G32B32_FLOAT;g.Triangles.VertexCount=UINT(v->size());g.Triangles.VertexBuffer={vb->GetGPUVirtualAddress(),sizeof(V)};
   D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS bi{};bi.Type=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL;bi.Flags=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;bi.DescsLayout=D3D12_ELEMENTS_LAYOUT_ARRAY;bi.NumDescs=1;bi.pGeometryDescs=&g;
   MeshGPU m;m.as=build(bi);m.normalOffset=UINT(meshNormals.size());
   for(size_t i=0;i<v->size();i+=3){
     auto g=triangleNormal((*v)[i],(*v)[i+1],(*v)[i+2]);meshNormals.push_back(g);
     for(int k=0;k<3;++k){V n=data->normals.size()==v->size()?data->normals[i+k]:g;float len=std::sqrt(n.x*n.x+n.y*n.y+n.z*n.z);meshNormals.push_back(len>.01f?n:g);}
     V t{},b{};if(data->uv.size()==v->size()){
      auto a=(*v)[i],p=(*v)[i+1],q=(*v)[i+2];auto u=data->uv[i],w=data->uv[i+1],z=data->uv[i+2];
      float x=w.x-u.x,y=w.y-u.y,j=z.x-u.x,k=z.y-u.y,det=x*k-y*j;
      if(std::fabs(det)>1e-8f){t={(k*(p.x-a.x)-y*(q.x-a.x))/det,(k*(p.y-a.y)-y*(q.y-a.y))/det,(k*(p.z-a.z)-y*(q.z-a.z))/det};b={(x*(q.x-a.x)-j*(p.x-a.x))/det,(x*(q.y-a.y)-j*(p.y-a.y))/det,(x*(q.z-a.z)-j*(p.z-a.z))/det};}
     }meshNormals.push_back(t);meshNormals.push_back(b);
    }
   if(data->uv.size()==v->size()){m.uvOffset=UINT(meshNormals.size());meshNormals.insert(meshNormals.end(),data->uv.begin(),data->uv.end());}
   meshBLAS.emplace(id,std::move(m));changed=true;
  }
  if(changed)meshNormalBuffer=upload(meshNormals.data(),meshNormals.size()*sizeof(V));
 }
 void prepareTextures(const Scene& s){
  bool changed=false;std::unordered_set<uint32_t> wanted;for(const auto& p:s.parts){if(p.tex[0]>=1&&p.tex[0]<=128)wanted.insert(uint32_t(p.tex[0]));for(int k=1;k<=3;++k)if(p.extra[k]>=1&&p.extra[k]<=128)wanted.insert(uint32_t(p.extra[k]));for(int k=0;k<4;++k)if(p.cloth[k]>=1&&p.cloth[k]<=128)wanted.insert(uint32_t(p.cloth[k]));}for(auto id:s.skySlots)if(id>=1&&id<=128)wanted.insert(id);
  for(auto id:wanted){if(textureOffsets.count(id))continue;
   std::shared_ptr<const std::vector<uint32_t>> data;{std::lock_guard<std::mutex> lk(meshMutex);auto it=downloadedTextures.find(id);if(it!=downloadedTextures.end())data=it->second;}
   if(!data||textureOffsets.size()>=128)continue;
   unsigned baseSide=data->size()==1024*1024?1024:data->size()==512*512?512:data->size()==256*256?256:0;if(!baseSide)continue;
   // 4-dword alignment keeps offsets exactly representable in float materials up to 256 MiB.
   while(atlas.size()%4)atlas.push_back(0);
   textureOffsets.emplace(id,UINT(atlas.size()));atlas.push_back(baseSide);atlas.insert(atlas.end(),data->begin(),data->end());
    size_t start=atlas.size()-data->size();for(unsigned side=baseSide;side>1;side/=2){
     unsigned next=side/2;size_t nextStart=atlas.size();atlas.reserve(nextStart+next*next);
     for(unsigned y=0;y<next;++y)for(unsigned x=0;x<next;++x){
      size_t a=start+size_t(y*2)*side+x*2;uint32_t v[4]={atlas[a],atlas[a+1],atlas[a+side],atlas[a+side+1]},out=0;
      for(unsigned shift=0;shift<32;shift+=8){unsigned sum=0;for(auto q:v)sum+=(q>>shift)&255u;out|=((sum+2)/4)<<shift;}
      atlas.push_back(out);
     }start=nextStart;
    }changed=true;
  }
  if(changed)sunPixels=upload(atlas.data(),atlas.size()*sizeof(uint32_t));
 }
 void scene(const Scene& s){prepareMeshes(s);prepareTextures(s);meshInstances=meshFallback=0;std::vector<Mat> ms;std::vector<D3D12_RAYTRACING_INSTANCE_DESC> instances;auto add=[&](const Part& p,UINT mask){D3D12_RAYTRACING_INSTANCE_DESC d{};for(int i=0;i<3;++i){d.Transform[i][0]=p.r[i]*p.s.x;d.Transform[i][1]=p.u[i]*p.s.y;d.Transform[i][2]=p.b[i]*p.s.z;d.Transform[i][3]=p.p[i];}d.InstanceID=UINT(ms.size());d.InstanceMask=mask;d.Flags=D3D12_RAYTRACING_INSTANCE_FLAG_TRIANGLE_CULL_DISABLE;float actualShape=p.shape;float normalOffset=0,uvOffset=0;ID3D12Resource* geometry=blas.Get();if(p.extra[6]==4){geometry=particleGPU.as.Get();actualShape=3;normalOffset=float(particleGPU.normalOffset);}else if(p.shape==1)geometry=sphereBlas.Get();else if(p.shape==2)geometry=cylinderBlas.Get();else if(p.shape==-6||p.shape==-1||p.shape==-2||(p.shape>=-5&&p.shape<=-3)){const MeshGPU* m=p.shape==-6?&headGPU:p.shape==-1?&wedgeGPU:p.shape==-2?&cornerGPU:&trussGPU.at(primitives::trussKey(p.shape,p.s.y));geometry=m->as.Get();actualShape=3;normalOffset=float(m->normalOffset);}else if(p.shape>=3){auto it=meshBLAS.find(uint32_t(p.shape));if(it!=meshBLAS.end()){geometry=it->second.as.Get();actualShape=3;normalOffset=float(it->second.normalOffset);uvOffset=float(it->second.uvOffset);++meshInstances;}else{actualShape=0;++meshFallback;}}d.AccelerationStructure=geometry->GetGPUVirtualAddress();instances.push_back(d);float texOffset=0;auto ti=textureOffsets.find(uint32_t(p.tex[0]));if(ti!=textureOffsets.end()&&(p.extra[6]==4||(p.tex[1]==0&&actualShape==3&&uvOffset>0)||(p.tex[1]>=1&&(actualShape==0||actualShape==3))))texOffset=float(ti->second);
 auto mapOffset=[&](float id){auto it=textureOffsets.find(uint32_t(id));return it==textureOffsets.end()?0.f:float(it->second);};
  ms.push_back({f4(p.c,p.metal),{p.rough,p.emit,p.transmission,p.ior},f4(p.r,actualShape),f4(p.u,normalOffset),f4(p.b,uvOffset),f4(p.s,p.specular),f4(p.emissionColor),{texOffset,p.tex[1],p.tex[0]>0?p.tex[2]:1.f,p.tex[0]>0?p.tex[3]:1.f},{p.tex[4],p.tex[5],p.tex[6],p.tex[7]},{p.extra[0],mapOffset(p.extra[1]),mapOffset(p.extra[2]),mapOffset(p.extra[3])},{p.extra[4],p.extra[5],p.extra[6]==4?4.f:0.f,p.extra[7]},{mapOffset(p.cloth[0]),mapOffset(p.cloth[1]),mapOffset(p.cloth[2]),mapOffset(p.cloth[3])},{p.cloth[4],p.cloth[5],p.cloth[6],0}});};skippedEnclosing=0;particleCount=0;for(size_t i=0;i<s.parts.size();++i){auto& p=s.parts[i];if(p.extra[6]==4){if(particleCount<64){add(p,4u);++particleCount;}continue;}if(p.extra[6]>0)continue;Part proxy=p;if(proxy.shape>=3&&!meshBLAS.count(uint32_t(proxy.shape)))proxy.shape=0;if(!glass)proxy.transmission=0;if(!hiddenAvatar(s,i)&&enclosingOpaque(proxy,s.p)){++skippedEnclosing;continue;}add(p,instanceVisibility(s,i));}if(ms.empty())add({{0,0,0},{1,0,0},{0,1,0},{0,0,1},{1,1,1},{0,0,0},0,1,0},0);Mat environmentMat{};float offsets[6]{};skyFacesReady=skyFacesRequested=0;for(int i=0;i<6;++i){if(s.skySlots[i])++skyFacesRequested;auto it=textureOffsets.find(s.skySlots[i]);if(it!=textureOffsets.end()){offsets[i]=float(it->second);++skyFacesReady;}}if(customSky&&skyFacesReady>0){environmentMat.colorMetal={offsets[0],offsets[1],offsets[2],offsets[3]};environmentMat.roughEmit={offsets[4],offsets[5],1,0};environmentMat.ax={s.skyBasis[0],s.skyBasis[1],s.skyBasis[2],0};environmentMat.ay={s.skyBasis[3],s.skyBasis[4],s.skyBasis[5],0};environmentMat.az={s.skyBasis[6],s.skyBasis[7],s.skyBasis[8],0};}ms.push_back(environmentMat);lightStart=UINT(ms.size());lightCount=0;for(const auto& p:s.parts){if(p.extra[6]<1||p.extra[6]>3||lightCount>=64)continue;Mat l{};l.colorMetal=f4(p.c);l.roughEmit={p.s.x,p.emit,0,0};l.ax=f4(p.p);l.ay=f4(p.b);l.extra1={0,0,p.extra[6],p.extra[7]};ms.push_back(l);++lightCount;}materials=upload(ms.data(),ms.size()*sizeof(Mat));
 auto start=std::chrono::steady_clock::now();
 UINT64 bytes=instances.size()*sizeof(instances[0]);std::vector<UINT64> addresses;addresses.reserve(instances.size());for(auto& d:instances)addresses.push_back(d.AccelerationStructure);
 bool update=tlas&&addresses==lastAddresses&&refits<120;
 if(!tlasInstances||tlasInstances->GetDesc().Width<bytes)tlasInstances=buffer(bytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_FLAG_NONE,D3D12_RESOURCE_STATE_GENERIC_READ);
 void* mapped=nullptr;D3D12_RANGE empty{0,0};check(tlasInstances->Map(0,&empty,&mapped),"TLAS map");memcpy(mapped,instances.data(),size_t(bytes));tlasInstances->Unmap(0,nullptr);
 D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_INPUTS bi{};bi.Type=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL;bi.Flags=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_ALLOW_UPDATE|D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PREFER_FAST_TRACE;bi.DescsLayout=D3D12_ELEMENTS_LAYOUT_ARRAY;bi.NumDescs=UINT(instances.size());bi.InstanceDescs=tlasInstances->GetGPUVirtualAddress();
 D3D12_RAYTRACING_ACCELERATION_STRUCTURE_PREBUILD_INFO info{};dev->GetRaytracingAccelerationStructurePrebuildInfo(&bi,&info);
 if(!info.ResultDataMaxSizeInBytes||!info.ScratchDataSizeInBytes)throw std::runtime_error("TLAS prebuild");
 if(!tlas||tlas->GetDesc().Width<info.ResultDataMaxSizeInBytes){tlas=buffer(info.ResultDataMaxSizeInBytes,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_RAYTRACING_ACCELERATION_STRUCTURE);update=false;}
 UINT64 scratch=std::max(info.ScratchDataSizeInBytes,info.UpdateScratchDataSizeInBytes);
 if(!tlasScratch||tlasScratch->GetDesc().Width<scratch)tlasScratch=buffer(scratch,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
 D3D12_BUILD_RAYTRACING_ACCELERATION_STRUCTURE_DESC desc{};desc.Inputs=bi;desc.DestAccelerationStructureData=tlas->GetGPUVirtualAddress();desc.ScratchAccelerationStructureData=tlasScratch->GetGPUVirtualAddress();
 if(update){desc.Inputs.Flags|=D3D12_RAYTRACING_ACCELERATION_STRUCTURE_BUILD_FLAG_PERFORM_UPDATE;desc.SourceAccelerationStructureData=desc.DestAccelerationStructureData;++refits;++refitTotal;}else{refits=0;++rebuildTotal;}
 begin();uav(tlas.Get());uav(tlasScratch.Get());cmd->BuildRaytracingAccelerationStructure(&desc,0,nullptr);uav(tlas.Get());submit();lastAddresses=std::move(addresses);
 tlasMs=std::chrono::duration<float,std::milli>(std::chrono::steady_clock::now()-start).count();
 }
 
 unsigned render(const Scene& s,unsigned frame,unsigned count){UINT rw=std::max(1u,UINT(W*renderScale)),rh=std::max(1u,UINT(H*renderScale));Params p{{float(rw),float(rh),float(frame%100000),float(count)},f4(s.p,tanf(s.fov*.00872664626f)),f4(s.r),f4(s.u),f4(s.f),f4(s.sun),{float(bounces),float(spp),exposure,float(debugView)},{rayDistance,skyStrength,sunStrength,ambientStrength},{gi?1.f:0.f,reflections?1.f:0.f,glass?1.f:0.f,float(tonemap)},{float(W),float(H),denoise&&debugView==0?denoiseStrength:0.f,float(filterRadius)},{reflectionStrength,1.f,std::clamp(s.brightness/2.f,0.f,5.f),-1.f}};p.environment.w=-1.f-float(lightStart*512u+(localLightNEE?lightCount:0u)+(generatedPBR?128u:0u)+(proceduralStuds?256u:0u));p.right.w=mipFiltering?normalStrength:-normalStrength-.001f;p.up.w=roughnessStrength;p.forward.w=fireflyLimit;p.sun.w=sunRadius;float diameter=followSunSize?s.sunSize:visualSunSize;if(s.celestial>0&&diameter>0)p.environment.y=cosf(std::clamp(diameter,.01f,179.f)*.00872664626f);begin();cmd->SetPipelineState(pso.Get());cmd->SetComputeRootSignature(root.Get());ID3D12DescriptorHeap* heaps[]={heap.Get()};cmd->SetDescriptorHeaps(1,heaps);cmd->SetComputeRoot32BitConstants(0,44,&p,0);cmd->SetComputeRootShaderResourceView(1,tlas->GetGPUVirtualAddress());cmd->SetComputeRootShaderResourceView(2,materials->GetGPUVirtualAddress());cmd->SetComputeRootShaderResourceView(7,meshNormalBuffer->GetGPUVirtualAddress());cmd->SetComputeRootUnorderedAccessView(3,hist->GetGPUVirtualAddress());cmd->SetComputeRootDescriptorTable(4,heap->GetGPUDescriptorHandleForHeapStart());cmd->SetComputeRootUnorderedAccessView(5,guide->GetGPUVirtualAddress());cmd->SetComputeRootUnorderedAccessView(6,albedo->GetGPUVirtualAddress());cmd->SetComputeRootUnorderedAccessView(8,waveA->GetGPUVirtualAddress());cmd->SetComputeRootUnorderedAccessView(9,waveB->GetGPUVirtualAddress());cmd->SetComputeRootShaderResourceView(10,sunPixels->GetGPUVirtualAddress());cmd->Dispatch((rw+7)/8,(rh+7)/8,1);uav(hist.Get());uav(guide.Get());uav(albedo.Get());if(denoise&&debugView==0&&denoiseMode==1){cmd->SetPipelineState(wavePso.Get());for(int pass=0;pass<wavePasses;++pass){p.environment.w=float(pass);cmd->SetComputeRoot32BitConstants(0,44,&p,0);cmd->Dispatch((rw+7)/8,(rh+7)/8,1);uav(waveA.Get());uav(waveB.Get());}}p.right.w=float(upscaleMode);p.up.w=upscaleSharpness;p.forward.w=renderParticles&&debugView==0?float(particleCount):0.f;cmd->SetComputeRoot32BitConstants(0,44,&p,0);
 cmd->SetPipelineState(resolvePso.Get());cmd->Dispatch((W+7)/8,(H+7)/8,1);
 bool enable=frameGen&&fgAvailable&&debugView==0;
 if(!enable){fgValid=false;presentFrom(out.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS);return 1;}
 float dx=s.p.x-fgEye.x,dy=s.p.y-fgEye.y,dz=s.p.z-fgEye.z;
 float dot=s.f.x*fgForward.x+s.f.y*fgForward.y+s.f.z*fgForward.z;
 bool interpolate=fgValid&&dx*dx+dy*dy+dz*dz<36.f&&dot>.8f&&std::fabs(s.fov-fgFov)<5.f;
 transition(out.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE);transition(fgCurrent.Get(),D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_COPY_DEST);cmd->CopyResource(fgCurrent.Get(),out.Get());transition(fgCurrent.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);transition(out.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
 if(interpolate){
  generateFrame();presentFrom(out.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
  begin();presentFrom(fgCurrent.Get(),D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
 }else presentFrom(out.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
 std::swap(fgPrevious,fgCurrent);fgEye=s.p;fgForward=s.f;fgFov=s.fov;fgValid=true;return interpolate?2u:1u;
 }

};
void settingsUI(HWND hwnd,UINT w,UINT h,size_t parts,bool live,float fps,float sync){
 if(!uiReady)return;
 ImGui_ImplDX12_NewFrame();ImGui_ImplWin32_NewFrame();auto& io=ImGui::GetIO();RECT r{};GetClientRect(hwnd,&r);POINT mouse{};if(GetCursorPos(&mouse)&&ScreenToClient(hwnd,&mouse)&&r.right>0&&r.bottom>0&&GetForegroundWindow()==hwnd)io.AddMousePosEvent(float(mouse.x)*w/r.right,float(mouse.y)*h/r.bottom);io.DisplaySize=ImVec2(float(w),float(h));io.DisplayFramebufferScale=ImVec2(1,1);ImGui::NewFrame();if(live)drawGameHUD(w,h);if(!uiVisible||captured){ImGui::Render();return;}
 ImGui::SetNextWindowPos(ImVec2(8,8),ImGuiCond_FirstUseEver);ImGui::SetNextWindowSize(ImVec2(std::min(360.f,float(w)-16),std::min(330.f,float(h)-16)),ImGuiCond_FirstUseEver);bool changed=false;
 if(ImGui::Begin("LUMEN GPU / 0.9",&uiVisible)){ImGui::Text("%.0f real / %.0f output FPS | %.0f sync Hz",fps,presentFPS,sync);ImGui::Text("%zu parts | %.0f generated FPS",parts,generatedFPS);ImGui::TextUnformatted(live?"Studio connected":"Demo scene");
 if(ImGui::BeginTabBar("tabs")){
 if(ImGui::BeginTabItem("Path tracing")){changed|=ImGui::SliderFloat("Render scale",&renderScale,.25f,1.f,"%.2f");ImGui::Text("Internal: %u x %u",unsigned(w*renderScale),unsigned(h*renderScale));changed|=ImGui::Checkbox("GPU denoiser",&denoise);const char* filters[]={"Original spatial","A-trous wavelet"};changed|=ImGui::Combo("Denoiser",&denoiseMode,filters,2);if(denoiseMode==1)changed|=ImGui::SliderInt("Wavelet passes",&wavePasses,1,4);changed|=ImGui::SliderFloat("Denoise strength",&denoiseStrength,.1f,2.f);changed|=ImGui::SliderInt("Filter radius",&filterRadius,1,3);changed|=ImGui::SliderInt("SPP",&spp,1,8);changed|=ImGui::SliderInt("Bounces",&bounces,0,12);changed|=ImGui::Checkbox("Global illumination",&gi);changed|=ImGui::Checkbox("Reflections",&reflections);changed|=ImGui::Checkbox("Glass / refraction",&glass);changed|=ImGui::Checkbox("Accumulation",&accum);changed|=ImGui::SliderFloat("Ray distance",&rayDistance,100,50000,"%.0f studs",ImGuiSliderFlags_Logarithmic);if(ImGui::Button("Reset samples"))changed=true;ImGui::EndTabItem();}
 if(ImGui::BeginTabItem("Lighting")){changed|=ImGui::SliderFloat("Exposure",&exposure,-4,4);changed|=ImGui::SliderFloat("Sky",&skyStrength,0,4);changed|=ImGui::Checkbox("Custom Roblox skybox",&customSky);ImGui::Text("Sky faces: %u / 6 ready",skyFacesReady);ImGui::Text("Live local lights: %u / 64",lightCount);if(skyFacesReady<6)ImGui::TextDisabled("Missing faces use procedural sky");changed|=ImGui::SliderFloat("Sun",&sunStrength,0,4);changed|=ImGui::SliderFloat("Sun shadow radius",&sunRadius,0,.08f,"%.3f");changed|=ImGui::Checkbox("Follow Roblox sun size",&followSunSize);if(!followSunSize)changed|=ImGui::SliderFloat("Visual sun size",&visualSunSize,0,30,"%.1f deg");changed|=ImGui::SliderFloat("Ambient",&ambientStrength,0,.5f);changed|=ImGui::Checkbox("Local light NEE",&localLightNEE);const char* tones[]={"ACES","Reinhard","Linear"};changed|=ImGui::Combo("Tonemapper",&tonemap,tones,3);const char* views[]={"Path traced","Albedo","Normals","Sky only","Direct sun visibility","Sky visibility (up)"};changed|=ImGui::Combo("Debug",&debugView,views,6);ImGui::EndTabItem();}
 if(ImGui::BeginTabItem("Display")){
  changed|=ImGui::SliderFloat("Internal render scale",&renderScale,.25f,1.f,"%.2f");const char* modes[]={"Bilinear","Lumen edge-aware","Nearest"};changed|=ImGui::Combo("Upscaler",&upscaleMode,modes,3);
  if(upscaleMode==1)changed|=ImGui::SliderFloat("Upscale sharpness",&upscaleSharpness,0,1);
  changed|=ImGui::Checkbox("Frame generation 2x (experimental)",&frameGen);
  ImGui::Text("Real %.0f | Generated %.0f | Output %.0f",realFPS,generatedFPS,presentFPS);
  ImGui::TextUnformatted("2x interpolation adds presentation latency.");ImGui::TextUnformatted("Launch with 1920 1080 for 1080p output.");ImGui::EndTabItem();
 }
 if(ImGui::BeginTabItem("Materials")){changed|=ImGui::Checkbox("Generated PBR",&generatedPBR);changed|=ImGui::SliderFloat("Generated normal strength",&normalStrength,0,2);changed|=ImGui::SliderFloat("Generated roughness strength",&roughnessStrength,0,2);changed|=ImGui::SliderFloat("Generated reflection strength",&reflectionStrength,0,2);changed|=ImGui::Checkbox("Procedural studs",&proceduralStuds);changed|=ImGui::Checkbox("Textured particles",&renderParticles);changed|=ImGui::Checkbox("Texture mip filtering",&mipFiltering);changed|=ImGui::SliderFloat("Firefly luminance clamp",&fireflyLimit,0,40,"%.1f (0 off)");ImGui::EndTabItem();}
 if(ImGui::BeginTabItem("Game")){float d=orbitSetting.load(),s=sensitivitySetting.load(),f=fovSetting.load();if(ImGui::SliderFloat("Camera distance",&d,.5f,40))orbitSetting.store(d);ImGui::SameLine();ImGui::TextUnformatted(d<=.75f?"First person":"Third person");if(ImGui::Button("First person"))orbitSetting.store(.5f);ImGui::SameLine();if(ImGui::Button("Third person"))orbitSetting.store(10.f);ImGui::TextUnformatted("Scroll to zoom; hold RMB to orbit in place");ImGui::Checkbox("Game HUD",&showHUD);if(ImGui::SliderFloat("Mouse sensitivity",&s,.1f,5))sensitivitySetting.store(s);if(ImGui::SliderFloat("FOV",&f,35,110))fovSetting.store(f);ImGui::Checkbox("Camera + avatar smoothing",&smoothCamera);if(ImGui::Checkbox("Demo scene",&forceDemo))changed=true;ImGui::TextUnformatted("F2 = capture controls; Esc = release");ImGui::TextUnformatted("F1 = settings; F11 = fullscreen");ImGui::Text("Native input WS: %s",nativeInputOnline.load()?"online":"offline");auto arrival=cameraArrival.load();auto current=nowMs();ImGui::Text("Last camera arrival: %llu ms ago",(unsigned long long)(arrival&&current>=arrival?current-arrival:0));ImGui::EndTabItem();}ImGui::EndTabBar();}}
 ImGui::End();ImGui::Render();if(changed)resetHistory=true;
}
// Smooth between authoritative camera packets without changing game physics.
V blendV(V a,V b,float k){return {a.x+(b.x-a.x)*k,a.y+(b.y-a.y)*k,a.z+(b.z-a.z)*k};}
V crossV(V a,V b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
float dist2(V a,V b){float x=a.x-b.x,y=a.y-b.y,z=a.z-b.z;return x*x+y*y+z*z;}
V unitV(V v,V fallback){float n=std::sqrt(v.x*v.x+v.y*v.y+v.z*v.z);if(n<.0001f)return fallback;return {v.x/n,v.y/n,v.z/n};}
void smoothView(Scene& target,const Scene& previous,float dt){if(dist2(target.p,previous.p)>100.f||dist2(target.f,previous.f)>1.5f)return;float k=1.f-std::exp(-std::clamp(dt,0.f,.1f)*38.f);if(dist2(previous.p,target.p)>1e-5f)target.p=blendV(previous.p,target.p,k);if(dist2(previous.f,target.f)>1e-7f||dist2(previous.u,target.u)>1e-7f){target.f=unitV(blendV(previous.f,target.f,k),target.f);target.r=unitV(crossV(target.f,blendV(previous.u,target.u,k)),target.r);target.u=unitV(crossV(target.r,target.f),target.u);}}
// Optional paired smoothing: the camera and avatar use the same factor.
// Snap rather than interpolate on layout changes or teleports.
bool smoothPair(Scene& target,const Scene& previous,float dt){
 if(target.firstPerson!=previous.firstPerson||target.characterCount!=previous.characterCount||dist2(target.p,previous.p)>100.f||dist2(target.f,previous.f)>1.5f)return false;
 size_t n=target.characterCount,a=target.parts.size()-n,b=previous.parts.size()-n;
 for(size_t i=0;i<n;++i){auto& x=target.parts[a+i];auto& y=previous.parts[b+i];if(x.shape!=y.shape||dist2(x.s,y.s)>1e-6f||dist2(x.p,y.p)>100.f)return false;}
 smoothView(target,previous,dt);float k=1.f-std::exp(-std::clamp(dt,0.f,.1f)*38.f);
 bool changed=false;
 for(size_t i=0;i<n;++i){auto& x=target.parts[a+i];auto& y=previous.parts[b+i];
  if(dist2(x.p,y.p)>1e-6f||dist2(x.r,y.r)>1e-7f||dist2(x.u,y.u)>1e-7f){
   x.p=blendV(y.p,x.p,k);x.r=unitV(blendV(y.r,x.r,k),x.r);x.b=unitV(crossV(x.r,blendV(y.u,x.u,k)),x.b);x.u=unitV(crossV(x.b,x.r),x.u);changed=true;
  }
 }
 return changed;
}
int main(int argc,char** argv){std::thread net,geometryNet,movingNet,inputNet,meshNet,hudNet;try{UINT w=1280,h=720;if(argc==3){int a=std::stoi(argv[1]),b=std::stoi(argv[2]);if(a<160||a>1920||b<90||b>1080)throw std::runtime_error("Resolution must be 160x90 to 1920x1080");w=a;h=b;}wchar_t exe[32768];GetModuleFileNameW(nullptr,exe,32768);auto path=std::filesystem::path(exe).parent_path()/L"trace.cso";
 WNDCLASSW wc{};wc.lpfnWndProc=wnd;wc.hInstance=GetModuleHandle(nullptr);wc.lpszClassName=L"LumenNativeDXR";wc.hCursor=LoadCursor(nullptr,IDC_ARROW);RegisterClassW(&wc);HWND hwnd=CreateWindowW(wc.lpszClassName,L"LUMEN GPU 0.9.9 - initializing",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,1000,650,nullptr,nullptr,wc.hInstance,nullptr);if(!hwnd)throw std::runtime_error("Window creation failed");ShowWindow(hwnd,SW_SHOW);Renderer r(hwnd,w,h);r.init(path);net=std::thread(nativeReceive,0);geometryNet=std::thread(nativeReceive,1);movingNet=std::thread(nativeReceive,2);inputNet=std::thread(nativeInput);meshNet=std::thread(meshNetwork);hudNet=std::thread(hudNetwork);Scene s=demo(),d=s;bool oldLive=false,first=true;uint64_t rev=0,guardSignature=0,lastMeshEpoch=0;unsigned frame=0,count=0,frames=0,presents=0;auto stamp=std::chrono::steady_clock::now();auto lastFrame=stamp;uint64_t lastSeq=0;unsigned packets=0;float displayedFPS=0,displayedSync=0;bool quit=false;while(!quit){MSG msg;while(PeekMessage(&msg,nullptr,0,0,PM_REMOVE)){if(msg.message==WM_QUIT){quit=true;break;}TranslateMessage(&msg);DispatchMessage(&msg);}if(quit)break;sampleInput(hwnd);if(IsIconic(hwnd)){std::this_thread::sleep_for(50ms);continue;}Scene next;bool live=false;{std::lock_guard<std::mutex> lk(mtx);live=connected&&!forceDemo;if(live){next=incoming;size_t character=std::min<size_t>(64,incomingCharacter.size());size_t moving=std::min<size_t>(1024,incomingMoving.size());if(next.parts.size()>16384-character-moving)next.parts.resize(16384-character-moving);next.parts.insert(next.parts.end(),incomingMoving.begin(),incomingMoving.begin()+moving);next.parts.insert(next.parts.end(),incomingCharacter.begin(),incomingCharacter.begin()+character);next.characterCount=character;}}if(!live)next=d;
 auto tick=std::chrono::steady_clock::now();float dt=std::chrono::duration<float>(tick-lastFrame).count();lastFrame=tick;
 if(live && next.seq!=lastSeq){lastSeq=next.seq;++packets;}
 bool interpolated=false;if(live&&oldLive&&!first&&smoothCamera)interpolated=smoothPair(next,s,dt);
 // Restore raw pose on the first frame after smoothing is disabled.
 static bool previousSmoothing=false;bool smoothingChanged=previousSmoothing!=smoothCamera;previousSmoothing=smoothCamera;
 settingsUI(hwnd,w,h,next.parts.size(),live,displayedFPS,displayedSync);
 if(first||live!=oldLive||resetHistory||next.firstPerson!=s.firstPerson)r.invalidateFrameGen();
 static bool lastCustomSky=customSky;bool skyToggleChanged=lastCustomSky!=customSky;lastCustomSky=customSky;
 uint64_t signature=enclosingSignature(next,glass);
 uint64_t newMeshEpoch=meshEpoch.load();if(first||live!=oldLive||next.revision!=rev||signature!=guardSignature||newMeshEpoch!=lastMeshEpoch||interpolated||smoothingChanged||skyToggleChanged||next.firstPerson!=s.firstPerson){lastMeshEpoch=newMeshEpoch;r.scene(next);count=0;first=false;rev=next.revision;guardSignature=signature;oldLive=live;}
 if(memcmp(&s.p,&next.p,12)||memcmp(&s.r,&next.r,12)||memcmp(&s.u,&next.u,12)||memcmp(&s.f,&next.f,12)||s.fov!=next.fov||memcmp(&s.sun,&next.sun,12)||s.sunSize!=next.sunSize||s.brightness!=next.brightness||s.celestial!=next.celestial||resetHistory||!accum){count=0;resetHistory=false;}s=std::move(next);presents+=r.render(s,frame++,count);count=std::min(count+1,1024u);++frames;auto now=std::chrono::steady_clock::now();float sec=std::chrono::duration<float>(now-stamp).count();if(sec>=.5f){displayedFPS=frames/sec;realFPS=displayedFPS;presentFPS=presents/sec;generatedFPS=(presents-frames)/sec;displayedSync=receivedCamera.exchange(0)/sec;float poseHz=receivedPose.exchange(0)/sec;float movingHz=receivedMoving.exchange(0)/sec;float worldHz=receivedGeometry.exchange(0)/sec;Input keyState;{std::lock_guard<std::mutex> lk(inputMutex);keyState=input;}std::wostringstream title;title<<L"LUMEN GPU 0.9.9 | DXR 1.1 | "<<r.gpu<<L" | "<<UINT(w*renderScale)<<L"x"<<UINT(h*renderScale)<<L" -> "<<w<<L"x"<<h<<L" | "<<int(realFPS+.5f)<<L" real / "<<int(presentFPS+.5f)<<L" output FPS ("<<int(generatedFPS+.5f)<<L" gen) | "<<int(displayedSync+.5f)<<L" recv Hz / "<<int(packets/sec+.5f)<<L" shown Hz | pose "<<int(poseHz+.5f)<<L" Hz | move "<<int(movingHz+.5f)<<L" / world "<<int(worldHz+.5f)<<L" Hz | "<<(live?L"Studio":L"Demo")<<L" | F2 "<<(captured?L"ON":L"OFF")<<L" WS "<<(nativeInputOnline.load()?L"ON":L"OFF")<<L" ["<<keyState.x<<L","<<keyState.z<<L"] | "<<s.parts.size()<<L" boxes | skip "<<r.skippedEnclosing<<L" | mesh "<<r.meshInstances<<L" / pending "<<r.meshFallback<<L" | TLAS "<<r.tlasMs<<L"ms R"<<r.refitTotal<<L"/B"<<r.rebuildTotal<<L" | "<<spp<<L" SPP / "<<bounces<<L" bounces | F3 "<<debugView<<L" EV "<<exposure<<L" | F6 smoothing "<<(smoothCamera?L"ON":L"OFF");SetWindowTextW(hwnd,title.str().c_str());stamp=now;frames=0;presents=0;packets=0;}}
 stop=true;if(net.joinable())net.join();if(geometryNet.joinable())geometryNet.join();if(movingNet.joinable())movingNet.join();if(inputNet.joinable())inputNet.join();if(meshNet.joinable())meshNet.join();if(hudNet.joinable())hudNet.join();return 0;}catch(const std::exception& e){stop=true;if(net.joinable())net.join();if(geometryNet.joinable())geometryNet.join();if(movingNet.joinable())movingNet.join();if(inputNet.joinable())inputNet.join();if(meshNet.joinable())meshNet.join();if(hudNet.joinable())hudNet.join();MessageBoxA(nullptr,e.what(),"LUMEN GPU DXR error",MB_OK|MB_ICONERROR);return 1;}}
