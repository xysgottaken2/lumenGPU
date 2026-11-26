"""LumenSSPT v0.1 — standalone visible-frame renderer; no Roblox integration."""
import argparse
import math
from pathlib import Path
import struct
import subprocess
import threading
import time
import sys
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent
HEADER = struct.Struct('<5I7f')
STATS = struct.Struct('<3fI')


def exact_read(pipe, n):
    data = bytearray()
    while len(data) < n:
        part = pipe.read(n-len(data))
        if not part:
            raise RuntimeError('DXR worker exited. See its error in the console.')
        data.extend(part)
    return data


class DXR:
    def __init__(self):
        self.proc = subprocess.Popen([str(ROOT/'build'/'LumenSSPT.exe'), str(ROOT/'build'/'trace.cso')],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
        try:
            if exact_read(self.proc.stdout, 4) != b'LSS1':
                raise RuntimeError('Invalid DXR worker protocol')
        except Exception:
            self.close()
            raise

    def render(self, rgb, z, frame, args, aspect):
        h, w = z.shape
        c = rgb.astype(np.uint32)
        packed = c[:,:,0] | (c[:,:,1] << 8) | (c[:,:,2] << 16)
        packet = HEADER.pack(w,h,frame & 0xffffffff,args.spp,args.bounces,
                             math.tan(math.radians(args.fov)/2),aspect,args.range,
                             args.gi,args.reflection,args.ao,0.)
        packet += np.ascontiguousarray(z,dtype='<f4').tobytes()+packed.astype('<u4').tobytes()
        data = memoryview(packet)
        while data:
            n = self.proc.stdin.write(data)
            if not n: raise RuntimeError('DXR worker input closed')
            data = data[n:]
        stats = STATS.unpack(exact_read(self.proc.stdout, STATS.size))
        effects = np.frombuffer(exact_read(self.proc.stdout,w*h*16),dtype='<f4').reshape(h,w,4).copy()
        return np.nan_to_num(effects,nan=0.,posinf=0.,neginf=0.),stats

    def close(self):
        if self.proc.poll() is None:
            try:
                self.proc.stdin.close()
                self.proc.wait(timeout=3)
            except (OSError,subprocess.TimeoutExpired):
                self.proc.kill(); self.proc.wait()
        if self.proc.stdout: self.proc.stdout.close()


class DepthModel:
    def __init__(self,args):
        import onnxruntime as ort
        if 'DmlExecutionProvider' not in ort.get_available_providers():
            raise RuntimeError('DirectML unavailable. Install onnxruntime-directml with Setup.ps1.')
        if not args.model.is_file(): raise FileNotFoundError(f'Model not found: {args.model}; run Setup.ps1 first.')
        opts = ort.SessionOptions(); opts.enable_mem_pattern = False
        opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        self.session = ort.InferenceSession(str(args.model),sess_options=opts,
                    providers=[('DmlExecutionProvider',{'device_id':args.dml_device}),'CPUExecutionProvider'])
        inp = self.session.get_inputs()[0]; self.name = inp.name
        self.h = inp.shape[-2] if isinstance(inp.shape[-2],int) else args.depth_h
        self.w = inp.shape[-1] if isinstance(inp.shape[-1],int) else args.depth_w
        self.mean = np.array([.485,.456,.406],np.float32)
        self.std = np.array([.229,.224,.225],np.float32)
        self.lo = self.hi = None
        print(f'Depth: {self.w}x{self.h}; providers: {self.session.get_providers()}',flush=True)

    def __call__(self,rgb,size):
        x = cv2.resize(rgb,(self.w,self.h),interpolation=cv2.INTER_CUBIC).astype(np.float32)/255.
        x = np.ascontiguousarray(((x-self.mean)/self.std).transpose(2,0,1)[None])
        raw = np.squeeze(self.session.run(None,{self.name:x})[0]).astype(np.float32)
        if raw.ndim != 2: raise ValueError(f'Unexpected depth output {raw.shape}')
        raw = np.nan_to_num(raw,nan=0.,posinf=0.,neginf=0.)
        lo,hi = np.percentile(raw,[2,98]); span = max(float(hi-lo),1e-5)
        if self.lo is None or abs(lo-self.lo)+abs(hi-self.hi)>span*.5:
            self.lo,self.hi=float(lo),float(hi)
        else:
            self.lo=.8*self.lo+.2*lo; self.hi=.8*self.hi+.2*hi
        inv = np.clip((raw-self.lo)/max(self.hi-self.lo,1e-5),0,1)
        inv = cv2.resize(inv,size,interpolation=cv2.INTER_AREA)
        return (1/(.08+.92*inv)).astype(np.float32)


class Temporal:
    def __init__(self): self.rgb=self.z=self.fx=None
    def apply(self,rgb,z,fx,weight,denoise):
        if denoise:
            xp=np.pad(fx,((1,1),(1,1),(0,0)),mode='edge')
            zp=np.pad(z,1,mode='edge'); cp=np.pad(rgb.astype(np.float32)/255.,((1,1),(1,1),(0,0)),mode='edge')
            center=rgb.astype(np.float32)/255.; h,w=z.shape
            accum=np.zeros_like(fx); weights=np.zeros_like(z)
            for dy in range(3):
                for dx in range(3):
                    zd=zp[dy:dy+h,dx:dx+w]; cd=cp[dy:dy+h,dx:dx+w]
                    q=np.exp(-np.abs(zd-z)/(np.maximum(z,.01)*.045)-np.mean(abs(cd-center),axis=2)*9)
                    if dx==1 and dy==1:q*=2
                    accum+=xp[dy:dy+h,dx:dx+w]*q[:,:,None]; weights+=q
            fx=accum/np.maximum(weights[:,:,None],1e-6)
        if self.fx is not None and self.fx.shape==fx.shape and weight>0:
            delta=np.mean(abs(rgb.astype(np.float32)-self.rgb),axis=2)/255.
            dz=abs(z-self.z)/np.maximum(z,.01)
            stable=(delta<.035)&(dz<.045)
            if stable.mean()>.55:
                a=(stable.astype(np.float32)*weight)[:,:,None]
                fx=fx*(1-a)+self.fx*a
        self.rgb=rgb.astype(np.float32); self.z=z.copy(); self.fx=fx.copy()
        return fx


def composite(rgb,fx):
    up=cv2.resize(fx,(rgb.shape[1],rgb.shape[0]),interpolation=cv2.INTER_LINEAR)
    linear=(rgb.astype(np.float32)/255.)**2.2
    enhanced=linear*(1-np.clip(up[:,:,3:4],0,.7)) + up[:,:,:3]*(1-linear)
    return np.uint8(np.clip(enhanced,0,1)**(1/2.2)*255+.5)


def demo_frame(w=960,h=540):
    yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
    u=2*(xx+.5)/w-1; v=1-2*(yy+.5)/h
    z=np.full((h,w),7.,np.float32); rgb=np.full((h,w,3),[148,154,164],np.uint8)
    wall=np.where(u<-.01,-2.4/(u*.7*(w/h)-1e-8),1e4)
    floor=np.where(v<-.01,-1.6/(v*.7-1e-8),1e4)
    mask=wall<z; z[mask]=wall[mask]; rgb[mask]=[238,48,36]
    mask=floor<z; z[mask]=floor[mask]; rgb[mask]=[135,138,143]
    box=(u>.12)&(u<.44)&(v>-.35)&(v<.12)&(z>3.8)
    z[box]=3.8; rgb[box]=[40,190,100]
    return rgb,z


def parse():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--window',default='Roblox',help='Target window title substring (not desktop capture)')
    p.add_argument('--demo',action='store_true',help='Synthetic scene; no capture or AI required')
    p.add_argument('--width',type=int,default=160); p.add_argument('--height',type=int,default=90)
    p.add_argument('--depth-w',type=int,default=280); p.add_argument('--depth-h',type=int,default=168)
    p.add_argument('--model',type=Path,default=ROOT/'models'/'depth.onnx'); p.add_argument('--dml-device',type=int,default=0)
    p.add_argument('--spp',type=int,default=1); p.add_argument('--bounces',type=int,default=1)
    p.add_argument('--fov',type=float,default=70,help='Assumed vertical field of view in degrees')
    p.add_argument('--range',type=float,default=3.5); p.add_argument('--gi',type=float,default=.65)
    p.add_argument('--reflection',type=float,default=.0); p.add_argument('--ao',type=float,default=.35)
    p.add_argument('--history',type=float,default=.8); p.add_argument('--no-denoise',action='store_true')
    p.add_argument('--preview-width',type=int,default=960); p.add_argument('--fps-cap',type=float,default=30)
    a=p.parse_args()
    if not (2<=a.width<=640 and 2<=a.height<=360 and 1<=a.spp<=8 and 1<=a.bounces<=3 and 20<=a.fov<=120 and 0<a.range<=100 and 0<=a.history<1 and 0<a.fps_cap<=120 and 160<=a.preview_width<=1920 and all(0<=x<=2 for x in (a.gi,a.reflection,a.ao)) and 14<=a.depth_w<=518 and 14<=a.depth_h<=518 and a.depth_w%14==0 and a.depth_h%14==0): p.error('Invalid renderer settings; see --help (depth dimensions must be multiples of 14).')
    if not a.demo and not a.window.strip(): p.error('A specific window title is required')
    return a


def main():
    a=parse(); cv2.setNumThreads(2)
    engine=DXR(); control=None; temporal=Temporal()
    try:
        model=None if a.demo else DepthModel(a)
        lock=threading.Lock(); closed=threading.Event(); latest=[None,0]
        if not a.demo:
            from windows_capture import WindowsCapture
            capture=WindowsCapture(cursor_capture=False,window_name=a.window)
            @capture.event
            def on_frame_arrived(frame,capture_control):
                buf=frame.frame_buffer
                with lock:
                    latest[0]=np.ascontiguousarray(buf[:,:,:3][:,:,::-1]); latest[1]+=1
            @capture.event
            def on_closed(): closed.set()
            control=capture.start_free_threaded()
        name='LumenSSPT v0.1 | separate preview'; cv2.namedWindow(name,cv2.WINDOW_NORMAL)
        last=-1; frameid=0; previous=time.perf_counter(); avg=0.; compare=False; view=0
        started=time.perf_counter()
        print('Q/Esc: quit | B: original/enhanced | D: depth | F: effects | T: toggle temporal',flush=True)
        while not closed.is_set():
            tick=time.perf_counter()
            if a.demo: rgb,truth=demo_frame(); seq=frameid
            else:
                with lock: rgb,seq=latest
                if rgb is None or seq==last:
                    if rgb is None and tick-started>15: raise RuntimeError('No capture frames. Check the window title and keep the target open.')
                    if cv2.waitKey(10)&255 in (27,ord('q')): break
                    if cv2.getWindowProperty(name,cv2.WND_PROP_VISIBLE)<1:break
                    continue
            last=seq
            if rgb.shape[1]>a.preview_width:
                rgb=cv2.resize(rgb,(a.preview_width,max(1,round(rgb.shape[0]*a.preview_width/rgb.shape[1]))),interpolation=cv2.INTER_AREA)
            small=cv2.resize(rgb,(a.width,a.height),interpolation=cv2.INTER_AREA)
            t=time.perf_counter(); z=cv2.resize(truth,(a.width,a.height),interpolation=cv2.INTER_NEAREST) if a.demo else model(rgb,(a.width,a.height)); depthms=(time.perf_counter()-t)*1000
            fx,stats=engine.render(small,z,frameid,a,rgb.shape[1]/rgb.shape[0])
            fx=temporal.apply(small,z,fx,a.history,not a.no_denoise)
            if view==1:
                d=np.uint8(np.clip((1/z-.08)/.92,0,1)*255); display=cv2.cvtColor(cv2.resize(d,(rgb.shape[1],rgb.shape[0])),cv2.COLOR_GRAY2RGB)
            elif view==2: display=np.uint8(np.clip(cv2.resize(fx[:,:,:3],(rgb.shape[1],rgb.shape[0]))*3,0,1)**(1/2.2)*255)
            else: display=rgb.copy() if compare else composite(rgb,fx)
            frameid+=1; now=time.perf_counter(); instant=1/max(now-previous,.0001); previous=now; avg=instant if avg==0 else avg*.9+instant*.1
            status=f'SSPT {avg:.1f} fps | depth {depthms:.1f} ms | DXR {stats[1]:.1f} ms | mesh {stats[0]:.1f} ms | {stats[3]} tris'
            cv2.putText(display,status,(8,20),cv2.FONT_HERSHEY_SIMPLEX,.48,(0,0,0),3,cv2.LINE_AA)
            cv2.putText(display,status,(8,20),cv2.FONT_HERSHEY_SIMPLEX,.48,(255,255,255),1,cv2.LINE_AA)
            cv2.imshow(name,cv2.cvtColor(display,cv2.COLOR_RGB2BGR))
            delay=max(1,int((1/a.fps_cap-(time.perf_counter()-tick))*1000)); key=cv2.waitKey(delay)&255
            if key in (27,ord('q')) or cv2.getWindowProperty(name,cv2.WND_PROP_VISIBLE)<1: break
            if key==ord('b'): compare=not compare;view=0
            if key==ord('d'): view=0 if view==1 else 1
            if key==ord('f'): view=0 if view==2 else 2
            if key==ord('t'): a.history=0 if a.history else .8;temporal=Temporal()
    finally:
        if control is not None:
            try: control.stop();control.wait()
            except Exception: pass
        engine.close();cv2.destroyAllWindows()

if __name__=='__main__':
    try:main()
    except Exception as exc:
        print(f'LumenSSPT: {exc}',file=sys.stderr);sys.exit(1)
