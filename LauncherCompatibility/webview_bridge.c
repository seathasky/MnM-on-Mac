/* Wine compatibility bridge for the official Windows MnM launcher.
 * The mac driver cannot attach a cross-process child Cocoa view. This module
 * redirects only WebView2 software paint DCs to a shared DIB and presents them
 * on the official host's UI thread. No official executable is patched.
 */
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#include <string.h>
#define MAX_BYTES (3840*2160*4)
#define HEADER_BYTES 1024
#define TIMER_ID 0x4d4e4d
typedef struct {LONG width,height;volatile LONG version;LONG frames;ULONGLONG target;} FRAME;
static HANDLE mapping,mutex;static FRAME *frame;static BYTE *pixels;
static HDC paint_dc;static HBITMAP paint_bitmap;static LONG dc_w,dc_h;
static int browser,host;static HDC (WINAPI *real_getdc)(HWND);
static int (WINAPI *real_releasedc)(HWND,HDC);
static BOOL (WINAPI *real_getclientrect)(HWND,LPRECT);
static HWND (WINAPI *real_create)(DWORD,LPCWSTR,LPCWSTR,DWORD,int,int,int,int,HWND,HMENU,HINSTANCE,LPVOID);
static int scale_requested;
#include "launcher_footer.h"
#include "game_handoff.h"
#include "launcher_loading.h"
#include "launcher_scale.h"
static void logline(const char *s){OutputDebugStringA(s);}
static BOOL init_map(void){
    if(frame)return TRUE;
    wchar_t session[48]={0},map_name[128],mutex_name[128];
    DWORD len=GetEnvironmentVariableW(L"MNM_WEBVIEW_BRIDGE_SESSION",session,48);
    if(!len || len>=48)return FALSE;
    if(wcsspn(session,L"0123456789abcdefABCDEF")!=wcslen(session))return FALSE;
    swprintf(map_name,128,L"Local\\MnMWebViewFrame_%ls",session);
    swprintf(mutex_name,128,L"Local\\MnMWebViewMutex_%ls",session);
    mapping=CreateFileMappingW(INVALID_HANDLE_VALUE,NULL,PAGE_READWRITE,0,MAX_BYTES+HEADER_BYTES,map_name);
    if(!mapping)return FALSE;
    frame=MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,0);
    if(!frame)return FALSE;
    pixels=(BYTE*)frame+HEADER_BYTES;
    mutex=CreateMutexW(NULL,FALSE,mutex_name);
    return !!mutex;
}
static HDC WINAPI bridge_getdc(HWND hwnd){
    wchar_t klass[128]={0},root_class[128]={0};RECT r;
    if(hwnd)GetClassNameW(GetAncestor(hwnd,GA_ROOT),root_class,128);
    if(browser && hwnd && !wcscmp(root_class,L"Tauri Window") && GetClassNameW(hwnd,klass,128) && !wcsncmp(klass,L"Chrome_",7) && GetClientRect(hwnd,&r) && r.right>0 && r.bottom>0 && (ULONGLONG)r.right*r.bottom*4<=MAX_BYTES && init_map()){
        if(WaitForSingleObject(mutex,2000)==WAIT_OBJECT_0){
            if(!paint_dc || dc_w!=r.right || dc_h!=r.bottom){
                if(paint_dc)DeleteDC(paint_dc);
                if(paint_bitmap)DeleteObject(paint_bitmap);
                BITMAPINFO bi={0};bi.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);bi.bmiHeader.biWidth=r.right;bi.bmiHeader.biHeight=-r.bottom;bi.bmiHeader.biPlanes=1;bi.bmiHeader.biBitCount=32;
                void *bits=NULL;paint_dc=CreateCompatibleDC(NULL);
                paint_bitmap=CreateDIBSection(paint_dc,&bi,DIB_RGB_COLORS,&bits,mapping,HEADER_BYTES);
                if(paint_bitmap){SelectObject(paint_dc,paint_bitmap);dc_w=r.right;dc_h=r.bottom;}
            }
            if(paint_bitmap){if(!frame->frames)logline("MnM GDI bridge: captured browser DC\n");frame->width=dc_w;frame->height=dc_h;frame->target=(ULONG_PTR)hwnd;return paint_dc;}
            ReleaseMutex(mutex);
        }
    }
    return real_getdc(hwnd);
}
static int WINAPI bridge_releasedc(HWND hwnd,HDC dc){
    if(browser && paint_dc && dc==paint_dc){GdiFlush();InterlockedIncrement(&frame->version);InterlockedIncrement(&frame->frames);ReleaseMutex(mutex);return 1;}
    return real_releasedc(hwnd,dc);
}
static void CALLBACK present(HWND hwnd,UINT msg,UINT_PTR id,DWORD time){
    static LONG seen=-1;
    footer_attach(hwnd);
    footer_read_state();
    scale_update(hwnd);
    // WebView2 can create another child after the footer. Keep our controls
    // above it even while the browser is idle and emits no new frames.
    if(footer_window)SetWindowPos(footer_window,HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
    loading_update(hwnd);
    if(!init_map())return;
    if(!frame->width){RedrawWindow(hwnd,NULL,NULL,RDW_INVALIDATE|RDW_ALLCHILDREN);return;}
    if(frame->version==seen || WaitForSingleObject(mutex,0)!=WAIT_OBJECT_0)return;
    LONG w=frame->width,h=frame->height;
    if(w>0 && h>0 && (ULONGLONG)w*h*4<=MAX_BYTES){
        /* Dimensions only: expose rendering scale to scoped compatibility tests. */
        SetPropW(hwnd,L"MnMFrameWidth",(HANDLE)(ULONG_PTR)w);
        SetPropW(hwnd,L"MnMFrameHeight",(HANDLE)(ULONG_PTR)h);
        if(seen<0)loading_complete();
        HDC dc=real_getdc(hwnd);
        BITMAPINFO bi={0};bi.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);bi.bmiHeader.biWidth=w;bi.bmiHeader.biHeight=-h;bi.bmiHeader.biPlanes=1;bi.bmiHeader.biBitCount=32;
        StretchDIBits(dc,0,0,w,h,0,0,w,h,pixels,&bi,DIB_RGB_COLORS,SRCCOPY);
        real_releasedc(hwnd,dc);
        if(footer_window) {
            SetWindowPos(footer_window,HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
            RedrawWindow(footer_window,NULL,NULL,RDW_INVALIDATE|RDW_UPDATENOW);
        }
        if(seen<0){SetForegroundWindow(hwnd);footer_command("ready");}seen=frame->version;
    }
    ReleaseMutex(mutex);
}
static HWND WINAPI bridge_create(DWORD ex,LPCWSTR cls,LPCWSTR title,DWORD style,int x,int y,int w,int h,HWND parent,HMENU menu,HINSTANCE inst,LPVOID param){
    HWND hwnd=real_create(ex,cls,title,style,x,y,w,h,parent,menu,inst,param);
    if(host && hwnd && title && wcsstr(title,L"Monsters & Memories")){SetTimer(hwnd,TIMER_ID,33,present);logline("MnM GDI bridge: host timer installed\n");}
    return hwnd;
}
static void patch_slot(void **slot,void *value){DWORD protection;
    if(*slot==value)return;
    if(VirtualProtect(slot,sizeof(void*),PAGE_READWRITE,&protection)){InterlockedExchangePointer(slot,value);VirtualProtect(slot,sizeof(void*),protection,&protection);}
}
static void patch_module(HMODULE m){
    if(!m)return;
    BYTE *b=(BYTE*)m;IMAGE_DOS_HEADER *dos=(void*)b;IMAGE_NT_HEADERS64 *nt=(void*)(b+dos->e_lfanew);
    IMAGE_DATA_DIRECTORY dir=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if(dir.VirtualAddress){
        IMAGE_IMPORT_DESCRIPTOR *d=(void*)(b+dir.VirtualAddress);
        for(;d->Name;d++){
            const char *library=(char*)b+d->Name;
            BOOL user=!_stricmp(library,"user32.dll");
            BOOL kernel=host && (!_stricmp(library,"kernel32.dll") || !_stricmp(library,"kernelbase.dll") || !strncmp(library,"api-ms-win-core-processthreads-",29));
            if((!user && !kernel) || !d->OriginalFirstThunk)continue;
            IMAGE_THUNK_DATA64 *names=(void*)(b+d->OriginalFirstThunk),*slots=(void*)(b+d->FirstThunk);
            for(;names->u1.AddressOfData;names++,slots++){
                if(IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal))continue;
                char *name=(char*)((IMAGE_IMPORT_BY_NAME*)(b+names->u1.AddressOfData))->Name;
                void *fn=kernel?(!strcmp(name,"CreateProcessW")?(void*)bridge_createprocess:!strcmp(name,"GetProcAddress")?(void*)scale_getproc:NULL):!strcmp(name,"GetDC")?(void*)bridge_getdc:!strcmp(name,"ReleaseDC")?(void*)bridge_releasedc:!strcmp(name,"GetClientRect")?(void*)bridge_getclientrect:!strcmp(name,"CreateWindowExW")?(void*)bridge_create:NULL;
                if(fn)patch_slot((void**)&slots->u1.Function,fn);
            }
        }
    }
    /* WebView2 resolves several USER32 functions lazily. */
    dir=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT];
    if(dir.VirtualAddress){
        DWORD *d=(void*)(b+dir.VirtualAddress);
        for(;d[1];d+=8){
            if(!(d[0]&1) || _stricmp((char*)b+d[1],"user32.dll"))continue;
            IMAGE_THUNK_DATA64 *names=(void*)(b+d[4]),*slots=(void*)(b+d[3]);
            for(;names->u1.AddressOfData;names++,slots++){
                if(IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal))continue;
                char *name=(char*)((IMAGE_IMPORT_BY_NAME*)(b+names->u1.AddressOfData))->Name;
                void *fn=!strcmp(name,"GetDC")?(void*)bridge_getdc:!strcmp(name,"ReleaseDC")?(void*)bridge_releasedc:!strcmp(name,"GetClientRect")?(void*)bridge_getclientrect:NULL;
                if(fn)patch_slot((void**)&slots->u1.Function,fn);
            }
        }
    }
}
static BOOL CALLBACK find_host(HWND hwnd,LPARAM arg){
    DWORD pid=0;wchar_t cls[128]={0};GetWindowThreadProcessId(hwnd,&pid);GetClassNameW(hwnd,cls,128);
    if(pid==GetCurrentProcessId() && !wcscmp(cls,L"Tauri Window")){
        SetTimer(hwnd,TIMER_ID,33,present);logline("MnM GDI bridge: existing host timer installed\n");*(BOOL*)arg=TRUE;return FALSE;
    }
    return TRUE;
}
static DWORD WINAPI worker(void *unused){
    BOOL timer=FALSE;
    for(;;){
        if(host){patch_module(GetModuleHandleW(NULL));if(!timer)EnumWindows(find_host,(LPARAM)&timer);}
        if(browser){patch_module(GetModuleHandleW(L"msedge.dll"));patch_module(GetModuleHandleW(NULL));}
        Sleep(100);
    }
    return 0;
}
BOOL WINAPI DllMain(HINSTANCE inst,DWORD reason,LPVOID reserved){
    if(reason==DLL_PROCESS_ATTACH){
        wchar_t path[MAX_PATH]={0};GetModuleFileNameW(NULL,path,MAX_PATH);
        wchar_t *base=wcsrchr(path,L'\\');base=base?base+1:path;
        host=!_wcsicmp(base,L"mnm_launcher.exe");
        LPCWSTR command=GetCommandLineW();
        browser=!_wcsicmp(base,L"msedgewebview2.exe") && wcsstr(command,L"--webview-exe-name=mnm_launcher.exe")
            && (!wcsstr(command,L"--type=") || wcsstr(command,L"--type=gpu-process"));
        if(!host && !browser)return TRUE;
        HMODULE user=GetModuleHandleW(L"user32.dll");
        real_getdc=(void*)GetProcAddress(user,"GetDC");real_releasedc=(void*)GetProcAddress(user,"ReleaseDC");real_create=(void*)GetProcAddress(user,"CreateWindowExW");
        real_getclientrect=(void*)GetProcAddress(user,"GetClientRect");
        real_createprocess=(void*)GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"CreateProcessW");
        scale_real_getproc=(void*)GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"GetProcAddress");
        DisableThreadLibraryCalls(inst);
        if(host)patch_module(GetModuleHandleW(NULL));
        HANDLE t=CreateThread(NULL,0,worker,NULL,0,NULL);if(t)CloseHandle(t);
        logline(host?"MnM GDI bridge: host initialized\n":"MnM GDI bridge: browser initialized\n");
    }
    return TRUE;
}
