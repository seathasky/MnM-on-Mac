/* Launcher-only WebView2 sizing. Stable COM ABI from Microsoft's WebView2 SDK
 * 1.0.3650.58 (ICoreWebView2Environment / ICoreWebView2Controller).
 * No script injection, browser debug port, or changes to the official EXE.
 */
static void patch_slot(void **slot,void *value);
static FARPROC (WINAPI *scale_real_getproc)(HMODULE,LPCSTR);
static void *scale_controller;
static int scale_applied;
static void *scale_zoom_applied;
static int scale_base_width,scale_base_height;
static UINT scale_base_dpi;
typedef struct {void **table;volatile LONG refs;void *original;BOOL environment;} SCALE_CALLBACK;
typedef HRESULT (WINAPI *SCALE_CREATE_CONTROLLER)(void*,HWND,void*);
typedef HRESULT (WINAPI *SCALE_CREATE_ENVIRONMENT)(LPCWSTR,LPCWSTR,void*,void*);
static SCALE_CREATE_CONTROLLER scale_real_controller;
static SCALE_CREATE_ENVIRONMENT scale_real_environment;
typedef HRESULT (WINAPI *SCALE_CREATE_INTERNAL)(BYTE,int,LPCWSTR,void*,void*);
static SCALE_CREATE_INTERNAL scale_real_internal;
typedef HRESULT (WINAPI *SCALE_CREATE_OPTIONS)(void*,HWND,void*,void*);
static SCALE_CREATE_OPTIONS scale_real_options;
static WNDPROC scale_original_proc;
static void **scale_table(void *object){return *(void***)object;}
static ULONG scale_addref(void *object){return ((ULONG(WINAPI*)(void*))scale_table(object)[1])(object);}
static ULONG scale_release(void *object){return ((ULONG(WINAPI*)(void*))scale_table(object)[2])(object);}
static LRESULT CALLBACK scale_host_proc(HWND hwnd,UINT message,WPARAM w,LPARAM l) {
    if(message==WM_DESTROY && scale_controller){void *controller=scale_controller;scale_controller=NULL;scale_release(controller);}
    return CallWindowProcW(scale_original_proc,hwnd,message,w,l);
}
static HRESULT WINAPI scale_query(SCALE_CALLBACK *self,REFIID iid,void **out) {
    static const GUID unknown={0,0,0,{0xc0,0,0,0,0,0,0,0x46}};
    static const GUID environment={0x4e8a3389,0xc9d8,0x4bd2,{0xb6,0xb5,0x12,0x4f,0xee,0x6c,0xc1,0x4d}};
    static const GUID controller={0x6c4819f3,0xc9b7,0x4260,{0x81,0x27,0xc9,0xf5,0xbd,0xe7,0xf6,0x8c}};
    if(!out)return E_POINTER;*out=NULL;
    if(memcmp(iid,&unknown,sizeof(GUID)) && memcmp(iid,self->environment?&environment:&controller,sizeof(GUID)))return E_NOINTERFACE;
    *out=self;InterlockedIncrement(&self->refs);return S_OK;
}
static ULONG WINAPI scale_callback_addref(SCALE_CALLBACK *self){return InterlockedIncrement(&self->refs);}
static ULONG WINAPI scale_callback_release(SCALE_CALLBACK *self){LONG refs=InterlockedDecrement(&self->refs);if(!refs){scale_release(self->original);HeapFree(GetProcessHeap(),0,self);}return refs;}
static SCALE_CALLBACK *scale_callback(void *original,BOOL environment);
static HRESULT WINAPI scale_create_options(void *environment,HWND parent,void *options,void *handler) {
    SCALE_CALLBACK *proxy=scale_callback(handler,FALSE);
    if(!proxy)return scale_real_options(environment,parent,options,handler);
    HRESULT result=scale_real_options(environment,parent,options,proxy);scale_callback_release(proxy);return result;
}
static HRESULT WINAPI scale_create_controller(void *environment,HWND parent,void *handler) {
    SCALE_CALLBACK *proxy=scale_callback(handler,FALSE);
    if(!proxy)return scale_real_controller(environment,parent,handler);
    HRESULT result=scale_real_controller(environment,parent,proxy);scale_callback_release(proxy);return result;
}
static HRESULT WINAPI scale_callback_invoke(SCALE_CALLBACK *self,HRESULT error,void *object) {
    if(SUCCEEDED(error) && object) {
        if(self->environment) {
            void **table=scale_table(object);
            if(table[3]!=(void*)scale_create_controller){scale_real_controller=(void*)table[3];patch_slot(&table[3],scale_create_controller);}
            // WRY uses Environment10's controller-with-options entry point.
            static const GUID environment10={0xee0eb9df,0x6f12,0x46ce,{0xb5,0x3f,0x3f,0x47,0xb9,0xc9,0x28,0xe0}};
            void *extended=NULL;
            if(SUCCEEDED(((HRESULT(WINAPI*)(void*,REFIID,void**))table[0])(object,&environment10,&extended)) && extended){
                void **options_table=scale_table(extended);
                if(options_table[21]!=(void*)scale_create_options){scale_real_options=(void*)options_table[21];patch_slot(&options_table[21],scale_create_options);}
                scale_release(extended);
            }
        } else if(!scale_controller){scale_addref(object);scale_controller=object;}
    }
    return ((HRESULT(WINAPI*)(void*,HRESULT,void*))scale_table(self->original)[3])(self->original,error,object);
}
static void *scale_callback_table[]={scale_query,scale_callback_addref,scale_callback_release,scale_callback_invoke};
static SCALE_CALLBACK *scale_callback(void *original,BOOL environment) {
    if(!original)return NULL;
    SCALE_CALLBACK *proxy=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*proxy));if(!proxy)return NULL;
    proxy->table=scale_callback_table;proxy->refs=1;proxy->original=original;proxy->environment=environment;scale_addref(original);return proxy;
}
static HRESULT WINAPI scale_create_environment(LPCWSTR browser,LPCWSTR data,void *options,void *handler) {
    SCALE_CALLBACK *proxy=scale_callback(handler,TRUE);
    if(!proxy)return scale_real_environment(browser,data,options,handler);
    HRESULT result=scale_real_environment(browser,data,options,proxy);scale_callback_release(proxy);return result;
}
static HRESULT WINAPI scale_create_internal(BYTE running,int type,LPCWSTR data,void *options,void *handler) {
    SCALE_CALLBACK *proxy=scale_callback(handler,TRUE);
    if(!proxy)return scale_real_internal(running,type,data,options,handler);
    HRESULT result=scale_real_internal(running,type,data,options,proxy);scale_callback_release(proxy);return result;
}
static FARPROC WINAPI scale_getproc(HMODULE module,LPCSTR name) {
    FARPROC result=scale_real_getproc(module,name);
    if((ULONG_PTR)name>65535 && !strcmp(name,"CreateCoreWebView2EnvironmentWithOptions") && result) {
        scale_real_environment=(void*)result;return (FARPROC)scale_create_environment;
    }
    // The official launcher statically links Microsoft's loader, which resolves
    // this documented EmbeddedBrowserWebView export rather than WebView2Loader.
    if((ULONG_PTR)name>65535 && !strcmp(name,"CreateWebViewEnvironmentWithOptionsInternal") && result) {
        scale_real_internal=(void*)result;return (FARPROC)scale_create_internal;
    }
    return result;
}
static void scale_update(HWND root) {
    SetPropW(root,L"MnMScaleController",(HANDLE)(ULONG_PTR)(scale_controller!=NULL));
    if(!footer_window)return;
    if(!scale_base_width) {
        RECT area;real_getclientrect(root,&area);
        scale_base_dpi=footer_dpi;scale_base_width=area.right;
        scale_base_height=area.bottom-MulDiv(FOOTER_HEIGHT,scale_base_dpi,96);
        scale_original_proc=(WNDPROC)SetWindowLongPtrW(root,GWLP_WNDPROC,(LONG_PTR)scale_host_proc);
    }
    MONITORINFO monitor={sizeof(monitor)};
    if(!GetMonitorInfoW(MonitorFromWindow(root,MONITOR_DEFAULTTONEAREST),&monitor))return;
    RECT outer,client;GetWindowRect(root,&outer);real_getclientrect(root,&client);
    int borderw=outer.right-outer.left-client.right,borderh=outer.bottom-outer.top-client.bottom;
    int margin=MulDiv(20,scale_base_dpi,96);
    int workw=monitor.rcWork.right-monitor.rcWork.left,workh=monitor.rcWork.bottom-monitor.rcWork.top;
    int fitw=(workw-margin-borderw)*100/scale_base_width;
    int fith=(workh-margin-borderh)*100/(scale_base_height+MulDiv(FOOTER_HEIGHT,scale_base_dpi,96));
    int percent=scale_requested?scale_requested:80;
    if(percent>fitw)percent=fitw;if(percent>fith)percent=fith;
    if(percent<10)percent=10;if(percent>125)percent=125;
    if(percent==scale_applied && scale_zoom_applied==scale_controller)return;
    int width=MulDiv(scale_base_width,percent,100),height=MulDiv(scale_base_height,percent,100);
    UINT dpi=MulDiv(scale_base_dpi,percent,100);int footer=MulDiv(FOOTER_HEIGHT,dpi,96);
    RECT bounds={0,0,width,height};
    if(scale_controller) {
        HRESULT result=((HRESULT(WINAPI*)(void*,RECT,double))scale_table(scale_controller)[11])(scale_controller,bounds,percent/100.0);
        if(FAILED(result))return;
    }
    footer_dpi=dpi;SetPropW(root,L"MnMMacFooterHeight",(HANDLE)(ULONG_PTR)footer);
    int x=outer.left,y=outer.top;
    if(x+width+borderw>monitor.rcWork.right)x=monitor.rcWork.right-width-borderw;
    if(y+height+footer+borderh>monitor.rcWork.bottom)y=monitor.rcWork.bottom-height-footer-borderh;
    if(x<monitor.rcWork.left)x=monitor.rcWork.left;if(y<monitor.rcWork.top)y=monitor.rcWork.top;
    SetWindowPos(root,NULL,x,y,width+borderw,height+footer+borderh,SWP_NOZORDER|SWP_NOACTIVATE);
    SetWindowPos(footer_window,HWND_TOP,0,height,width,footer,SWP_NOACTIVATE);
    // Reapply after WM_SIZE so the official host's resize handler cannot reset zoom.
    if(scale_controller)((HRESULT(WINAPI*)(void*,RECT,double))scale_table(scale_controller)[11])(scale_controller,bounds,percent/100.0);
    scale_zoom_applied=scale_controller;
    scale_applied=percent;SetPropW(root,L"MnMLauncherScale",(HANDLE)(ULONG_PTR)percent);
    RedrawWindow(root,NULL,NULL,RDW_INVALIDATE|RDW_ALLCHILDREN);
}
