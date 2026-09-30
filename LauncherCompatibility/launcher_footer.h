/* A child of the official host window, not an overlapping desktop panel.
 * Keep its web content's original client size; reserve additional space below.
 * Commands contain only predefined UI actions, never credentials or pixels.
 */
#define FOOTER_HEIGHT 88
static HWND footer_window, footer_root;
static UINT footer_dpi=96;
static WCHAR footer_backend[32]=L"d3dmetal", footer_version[32]=L"2.0.0";
static WCHAR footer_controls[32768];
static HFONT footer_font, footer_version_font;
static BOOL footer_busy, footer_update_available;
static void footer_read_state(void) {
    static ULONGLONG next;ULONGLONG now=GetTickCount64();if(now<next)return;next=now+250;
    if(!footer_controls[0] || !footer_window)return;
    WCHAR path[32768];if(swprintf(path,32768,L"%ls\\state.txt",footer_controls)<0)return;
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if(file==INVALID_HANDLE_VALUE)return;
    char data[513]={0};DWORD count=0;BOOL read=ReadFile(file,data,512,&count,NULL);CloseHandle(file);
    if(!read || !count || count>=512)return;
    char backend[32]={0},version[32]={0};char *entry=strstr(data,"backend=");
    if(entry && sscanf(entry,"backend=%31[^\n]",backend)==1 && (!strcmp(backend,"metal") || !strcmp(backend,"d3dmetal") || !strcmp(backend,"dxvk")))
        MultiByteToWideChar(CP_UTF8,0,backend,-1,footer_backend,32);
    entry=strstr(data,"version=");
    if(entry && sscanf(entry,"version=%31[^\n]",version)==1 && strspn(version,"0123456789.")==strlen(version))
        MultiByteToWideChar(CP_UTF8,0,version,-1,footer_version,32);
    footer_busy=strstr(data,"busy=1\n")!=NULL;
    footer_update_available=strstr(data,"update=1\n")!=NULL;
    entry=strstr(data,"scale=");int scale;
    if(entry && sscanf(entry,"scale=%d",&scale)==1 && (scale==0 || scale==60 || scale==70 || scale==80 || scale==90 || scale==100 || scale==125))scale_requested=scale;
    InvalidateRect(footer_window,NULL,FALSE);
}
static BOOL footer_enabled(void) {
    WCHAR value[4]={0};
    return GetEnvironmentVariableW(L"MNM_WEBVIEW_FOOTER",value,4)==1 && value[0]==L'1';
}
static void footer_command(const char *command) {
    if(!footer_controls[0])return;
    WCHAR target[32768],temporary[32768];
    static LONG sequence;
    LONG n=InterlockedIncrement(&sequence);
    if(swprintf(target,32768,L"%ls\\request-%lu-%ld.msg",footer_controls,GetCurrentProcessId(),n)<0)return;
    if(swprintf(temporary,32768,L"%ls.tmp",target)<0)return;
    HANDLE file=CreateFileW(temporary,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
    if(file==INVALID_HANDLE_VALUE)return;
    DWORD written=0;BOOL ok=WriteFile(file,command,(DWORD)strlen(command),&written,NULL);
    CloseHandle(file);
    if(!ok || written!=strlen(command) || !MoveFileExW(temporary,target,MOVEFILE_WRITE_THROUGH))DeleteFileW(temporary);
}
static void footer_label(HDC dc,LPCWSTR text,int x,int y,int width,COLORREF color) {
    RECT bounds={x,y,x+width,y+24};SetTextColor(dc,color);
    DrawTextW(dc,text,-1,&bounds,DT_SINGLELINE|DT_VCENTER|DT_LEFT|DT_NOPREFIX);
}
static void footer_gear(HDC dc,int cx,int cy) {
    // Draw shapes, not a Unicode glyph: this works without any symbol fonts.
    static const POINT spokes[8]={{0,-8},{6,-6},{8,0},{6,6},{0,8},{-6,6},{-8,0},{-6,-6}};
    HPEN pen=CreatePen(PS_SOLID,2,RGB(94,200,103));HGDIOBJ previous=SelectObject(dc,pen);
    HGDIOBJ brush=SelectObject(dc,GetStockObject(NULL_BRUSH));
    for(int i=0;i<8;i++) {
        MoveToEx(dc,cx+spokes[i].x*5/8,cy+spokes[i].y*5/8,NULL);
        LineTo(dc,cx+spokes[i].x,cy+spokes[i].y);
    }
    Ellipse(dc,cx-6,cy-6,cx+6,cy+6);Ellipse(dc,cx-2,cy-2,cx+2,cy+2);
    SelectObject(dc,brush);SelectObject(dc,previous);DeleteObject(pen);
}
static POINT footer_logo_point(int x,int y,double px,double py) {
    POINT point={x+(LONG)(px*0.375+0.5),y+(LONG)(py*0.375+0.5)};return point;
}
static void footer_logo_curve(HDC dc,int x,int y,double a,double b,double c,double d,double e,double f) {
    POINT points[3]={footer_logo_point(x,y,a,b),footer_logo_point(x,y,c,d),footer_logo_point(x,y,e,f)};
    PolyBezierTo(dc,points,3);
}
static void footer_discord_logo(HDC dc,int x,int y,COLORREF color) {
    // Discord's official 64x48 Clyde symbol, scaled uniformly to 24x18.
    // Source: https://discord.com/branding (Symbol.svg), not a font glyph.
    HBRUSH brush=CreateSolidBrush(color);HGDIOBJ oldbrush=SelectObject(dc,brush);
    HGDIOBJ oldpen=SelectObject(dc,GetStockObject(NULL_PEN));int oldfill=SetPolyFillMode(dc,ALTERNATE);
    POINT start=footer_logo_point(x,y,40.575,0);BeginPath(dc);MoveToEx(dc,start.x,start.y,NULL);
#define C(a,b,c,d,e,f) footer_logo_curve(dc,x,y,a,b,c,d,e,f)
#define L(a,b) {POINT p=footer_logo_point(x,y,a,b);LineTo(dc,p.x,p.y);}
    C(39.9562,1.09866,39.4006,2.2352,38.8954,3.397);
    C(34.0967,2.67719,29.2096,2.67719,24.3982,3.397);
    C(23.9057,2.2352,23.3374,1.09866,22.7186,0);
    C(18.2104,0.770324,13.8157,2.12155,9.64839,4.02841);
    C(1.38951,16.2652,-0.845688,28.1863,0.265599,39.9432);
    C(5.10222,43.517,10.5197,46.2447,16.2909,47.9874);
    C(17.5916,46.2447,18.7407,44.3883,19.7257,42.4562);
    C(17.8568,41.7616,16.0509,40.8903,14.3208,39.88);
    C(14.7755,39.5517,15.2175,39.2107,15.6468,38.8824);
    C(25.7873,43.6559,37.5316,43.6559,47.6847,38.8824);
    C(48.1141,39.236,48.5561,39.577,49.0107,39.88);
    C(47.2806,40.9029,45.4748,41.7616,43.5931,42.4688);
    C(44.5781,44.4009,45.7273,46.2573,47.028,48);
    C(52.7991,46.2573,58.2167,43.5422,63.0533,39.9684);
    C(64.3666,26.3299,60.8055,14.5099,53.6452,4.04104);
    C(49.4905,2.13418,45.0959,0.782952,40.5876,0.0252565);L(40.575,0);CloseFigure(dc);
    start=footer_logo_point(x,y,21.1401,32.7072);MoveToEx(dc,start.x,start.y,NULL);
    C(18.0209,32.7072,15.4321,29.8785,15.4321,26.3804);
    C(15.4321,22.8824,17.9199,20.041,21.1275,20.041);
    C(24.3351,20.041,26.886,22.895,26.8354,26.3804);
    C(26.7849,29.8658,24.3224,32.7072,21.1401,32.7072);CloseFigure(dc);
    start=footer_logo_point(x,y,42.1788,32.7072);MoveToEx(dc,start.x,start.y,NULL);
    C(39.047,32.7072,36.4834,29.8785,36.4834,26.3804);
    C(36.4834,22.8824,38.9712,20.041,42.1788,20.041);
    C(45.3864,20.041,47.9246,22.895,47.8741,26.3804);
    C(47.8236,29.8658,45.3611,32.7072,42.1788,32.7072);CloseFigure(dc);
#undef C
#undef L
    EndPath(dc);FillPath(dc);SetPolyFillMode(dc,oldfill);
    SelectObject(dc,oldbrush);SelectObject(dc,oldpen);DeleteObject(brush);
}
static void footer_button(HDC dc,LPCWSTR text,int left,int right,COLORREF fill,COLORREF color) {
    HBRUSH brush=CreateSolidBrush(fill);HPEN pen=CreatePen(PS_SOLID,1,RGB(76,76,76));
    HGDIOBJ oldbrush=SelectObject(dc,brush),oldpen=SelectObject(dc,pen);
    RoundRect(dc,left,49,right,80,10,10);
    SelectObject(dc,oldbrush);SelectObject(dc,oldpen);DeleteObject(brush);DeleteObject(pen);
    BOOL discord=!wcscmp(text,L"Seathasky Dev Discord");
    if(discord)footer_discord_logo(dc,left+12,55,color);
    RECT label={left+(discord?44:8),49,right-8,80};SetTextColor(dc,color);
    DrawTextW(dc,text,-1,&label,DT_SINGLELINE|DT_VCENTER|DT_CENTER|DT_NOPREFIX);
}
static LRESULT CALLBACK footer_proc(HWND window,UINT message,WPARAM w,LPARAM l) {
    if(message==WM_ERASEBKGND)return 1;
    if(message==WM_PAINT) {
        PAINTSTRUCT paint;HDC dc=BeginPaint(window,&paint);RECT bounds;real_getclientrect(window,&bounds);
        HBRUSH background=CreateSolidBrush(RGB(29,29,29));FillRect(dc,&bounds,background);DeleteObject(background);
        int physical_width=bounds.right,physical_height=bounds.bottom;
        bounds.right=MulDiv(physical_width,96,footer_dpi);bounds.bottom=FOOTER_HEIGHT;
        SetMapMode(dc,MM_ANISOTROPIC);SetWindowExtEx(dc,bounds.right,FOOTER_HEIGHT,NULL);
        SetViewportExtEx(dc,physical_width,physical_height,NULL);
        HPEN line=CreatePen(PS_SOLID,1,RGB(65,65,65));HGDIOBJ oldpen=SelectObject(dc,line);
        MoveToEx(dc,0,0,NULL);LineTo(dc,bounds.right,0);SelectObject(dc,oldpen);DeleteObject(line);
        HGDIOBJ oldfont=SelectObject(dc,footer_font);SetBkMode(dc,TRANSPARENT);
        footer_label(dc,L"Graphics",20,13,70,RGB(215,215,215));
        HBRUSH field=CreateSolidBrush(RGB(53,53,53));HGDIOBJ oldbrush=SelectObject(dc,field);
        oldpen=SelectObject(dc,GetStockObject(NULL_PEN));RoundRect(dc,90,10,350,41,8,8);
        SelectObject(dc,oldpen);SelectObject(dc,oldbrush);DeleteObject(field);
        LPCWSTR renderer=!wcscmp(footer_backend,L"metal")?L"DXMT":!wcscmp(footer_backend,L"dxvk")?L"DXVK (Experimental)":L"D3DMetal (Recommended)";
        footer_label(dc,renderer,102,13,228,RGB(235,235,235));
        HPEN arrow=CreatePen(PS_SOLID,2,RGB(215,215,215));oldpen=SelectObject(dc,arrow);
        MoveToEx(dc,331,22,NULL);LineTo(dc,336,27);LineTo(dc,341,22);
        SelectObject(dc,oldpen);DeleteObject(arrow);
        footer_gear(dc,383,25);
        WCHAR version[64];swprintf(version,64,footer_update_available?L"App Update Available":L"MnM on Mac %ls",footer_version);
        SelectObject(dc,footer_version_font);
        RECT version_bounds={bounds.right-280,10,bounds.right-20,41};
        SetTextColor(dc,footer_update_available?RGB(94,200,103):RGB(215,215,215));
        DrawTextW(dc,version,-1,&version_bounds,DT_SINGLELINE|DT_VCENTER|DT_RIGHT|DT_NOPREFIX);
        SelectObject(dc,footer_font);
        footer_button(dc,L"Game Folder",90,220,RGB(45,45,45),RGB(235,235,235));
        footer_button(dc,L"Seathasky Dev Discord",bounds.right-396,bounds.right-171,RGB(45,45,45),RGB(88,101,242));
        footer_button(dc,L"About",bounds.right-156,bounds.right-88,RGB(45,45,45),RGB(255,140,45));
        footer_button(dc,L"Legal",bounds.right-78,bounds.right-20,RGB(45,45,45),RGB(255,140,45));
        SelectObject(dc,oldfont);EndPaint(window,&paint);return 0;
    }
    if(message==WM_LBUTTONUP) {
        int x=MulDiv((short)LOWORD(l),96,footer_dpi),y=MulDiv((short)HIWORD(l),96,footer_dpi);RECT bounds;real_getclientrect(window,&bounds);
        bounds.right=MulDiv(bounds.right,96,footer_dpi);
        if(y<46 && x>=bounds.right-280 && footer_update_available){footer_command("app-update");return 0;}
        if(y<46 && x<410 && footer_busy)return 0;
        if(y<46 && x>=90 && x<350) {
            HMENU menu=CreatePopupMenu();
            AppendMenuW(menu,MF_STRING|(!wcscmp(footer_backend,L"d3dmetal")?MF_CHECKED:0),1,L"D3DMetal (Recommended)");
            AppendMenuW(menu,MF_STRING|(!wcscmp(footer_backend,L"metal")?MF_CHECKED:0),2,L"DXMT");
            AppendMenuW(menu,MF_STRING|(!wcscmp(footer_backend,L"dxvk")?MF_CHECKED:0),3,L"DXVK (Experimental)");
            POINT point={MulDiv(90,footer_dpi,96),MulDiv(42,footer_dpi,96)};ClientToScreen(window,&point);
            UINT selected=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_NONOTIFY,point.x,point.y,0,window,NULL);
            DestroyMenu(menu);
            if(selected)footer_command(selected==1?"graphics:d3dmetal":selected==2?"graphics:metal":"graphics:dxvk");
        } else if(y<46 && x>=360 && x<410)footer_command("options");
        else if(y>=49 && y<80 && x>=bounds.right-396 && x<bounds.right-171)footer_command("discord");
        else if(y>=49 && y<80 && x>=90 && x<220)footer_command("game-folder");
        else if(y>=49 && y<80 && x>=bounds.right-156 && x<bounds.right-88)footer_command("about");
        else if(y>=49 && y<80 && x>=bounds.right-78 && x<bounds.right-20)footer_command("legal");
        return 0;
    }
    return DefWindowProcW(window,message,w,l);
}
static void footer_attach(HWND root) {
    if(footer_window || !footer_enabled())return;
    RECT client,outer;if(!real_getclientrect(root,&client) || !GetWindowRect(root,&outer))return;
    UINT (WINAPI *getdpi)(HWND)=(void*)GetProcAddress(GetModuleHandleW(L"user32.dll"),"GetDpiForWindow");
    footer_dpi=getdpi?getdpi(root):96;if(footer_dpi<96 || footer_dpi>384)footer_dpi=96;
    int reserved=MulDiv(FOOTER_HEIGHT,footer_dpi,96);
    WNDCLASSW klass={0};klass.lpfnWndProc=footer_proc;klass.hInstance=GetModuleHandleW(NULL);
    klass.hCursor=LoadCursorW(NULL,IDC_ARROW);klass.lpszClassName=L"MnMMacControls";
    if(!RegisterClassW(&klass) && GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)return;
    footer_font=CreateFontW(-14,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,L"Arial");
    footer_version_font=CreateFontW(-17,0,0,0,FW_BOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,L"Arial");
    GetEnvironmentVariableW(L"MNM_GRAPHICS_BACKEND",footer_backend,32);
    GetEnvironmentVariableW(L"MNM_APP_VERSION",footer_version,32);
    GetEnvironmentVariableW(L"MNM_WEBVIEW_CONTROL_DIR",footer_controls,32768);
    SetPropW(root,L"MnMMacFooterHeight",(HANDLE)(ULONG_PTR)reserved);
    footer_root=root;
    SetWindowPos(root,NULL,0,0,outer.right-outer.left,outer.bottom-outer.top+reserved,SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE);
    footer_window=real_create(0,L"MnMMacControls",L"MnM on Mac controls",WS_CHILD|WS_VISIBLE,
        0,client.bottom,client.right,reserved,root,NULL,klass.hInstance,NULL);
    if(!footer_window)RemovePropW(root,L"MnMMacFooterHeight");
}
static BOOL WINAPI bridge_getclientrect(HWND hwnd,LPRECT bounds) {
    BOOL result=real_getclientrect(hwnd,bounds);
    ULONG_PTR reserved=(ULONG_PTR)GetPropW(hwnd,L"MnMMacFooterHeight");
    if(result && reserved>0 && reserved<=FOOTER_HEIGHT*4 && bounds->bottom>(LONG)reserved)bounds->bottom-=(LONG)reserved;
    return result;
}
