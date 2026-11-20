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
static RECT footer_work_areas[16];
static int footer_work_count;
static BOOL footer_state_changed=TRUE;
static void footer_read_state(void) {
    static ULONGLONG next;ULONGLONG now=GetTickCount64();if(now<next)return;next=now+250;
    if(!footer_controls[0] || !footer_window)return;
    WCHAR path[32768];if(swprintf(path,32768,L"%ls\\state.txt",footer_controls)<0)return;
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if(file==INVALID_HANDLE_VALUE)return;
    char data[2049]={0};DWORD count=0;BOOL read=ReadFile(file,data,2048,&count,NULL);CloseHandle(file);
    if(!read || !count || count>=2048)return;
    static char previous[2049];
    if(!strcmp(previous,data))return;
    memcpy(previous,data,sizeof(previous));footer_state_changed=TRUE;
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
    footer_work_count=0;
    for(int i=0;i<16;i++) {
        char key[24];snprintf(key,sizeof(key),"\nwork%d=",i);entry=strstr(data,key);
        int x,y,width,height;
        if(!entry || sscanf(entry+strlen(key),"%d,%d,%d,%d",&x,&y,&width,&height)!=4)break;
        if(x<-100000 || x>100000 || y<-100000 || y>100000 || width<100 || width>32768 || height<100 || height>32768)break;
        footer_work_areas[footer_work_count++]=(RECT){x,y,x+width,y+height};
    }
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
static void footer_gear(HDC dc,int cx,int cy,COLORREF color) {
    // Draw shapes, not a Unicode glyph: this works without any symbol fonts.
    static const POINT spokes[8]={{0,-8},{6,-6},{8,0},{6,6},{0,8},{-6,6},{-8,0},{-6,-6}};
    HPEN pen=CreatePen(PS_SOLID,2,color);HGDIOBJ previous=SelectObject(dc,pen);
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
enum FooterAction {
    FOOTER_NONE, FOOTER_GRAPHICS, FOOTER_OPTIONS, FOOTER_FOLDER,
    FOOTER_WINE, FOOTER_DISCORD, FOOTER_ABOUT, FOOTER_LEGAL, FOOTER_UPDATE,
    FOOTER_ACTION_COUNT
};

static enum FooterAction footer_hover;

static RECT footer_action_bounds(enum FooterAction action, int width) {
    switch(action) {
    case FOOTER_GRAPHICS: return (RECT){88, 9, 313, 39};
    case FOOTER_OPTIONS:  return (RECT){321, 9, 422, 39};
    case FOOTER_FOLDER:   return (RECT){width-250, 9, width-138, 39};
    case FOOTER_WINE:     return (RECT){width-130, 9, width-18, 39};
    case FOOTER_DISCORD:  return (RECT){width-257, 49, width-153, 79};
    case FOOTER_ABOUT:    return (RECT){width-145, 49, width-85, 79};
    case FOOTER_LEGAL:    return (RECT){width-77, 49, width-18, 79};
    case FOOTER_UPDATE:   return (RECT){width-441, 49, width-271, 79};
    default: return (RECT){0};
    }
}

static BOOL footer_action_enabled(enum FooterAction action) {
    switch(action) {
    case FOOTER_NONE: return FALSE;
    case FOOTER_GRAPHICS:
    case FOOTER_OPTIONS: return !footer_busy;
    case FOOTER_UPDATE: return footer_update_available;
    default: return TRUE;
    }
}

static enum FooterAction footer_hit(HWND window, LPARAM coordinates, int *width) {
    RECT bounds;
    if(!real_getclientrect(window, &bounds)) return FOOTER_NONE;
    *width = MulDiv(bounds.right, 96, footer_dpi);
    POINT point = {
        MulDiv((short)LOWORD(coordinates), 96, footer_dpi),
        MulDiv((short)HIWORD(coordinates), 96, footer_dpi)
    };
    for(enum FooterAction action = FOOTER_GRAPHICS; action < FOOTER_ACTION_COUNT; ++action) {
        RECT button = footer_action_bounds(action, *width);
        if(footer_action_enabled(action) && PtInRect(&button, point)) return action;
    }
    return FOOTER_NONE;
}

static void footer_surface(HDC dc, RECT bounds, COLORREF fill, COLORREF edge, int radius) {
    HBRUSH brush = CreateSolidBrush(fill);
    HPEN pen = CreatePen(PS_SOLID, 1, edge);
    HGDIOBJ oldbrush = SelectObject(dc, brush), oldpen = SelectObject(dc, pen);
    RoundRect(dc, bounds.left, bounds.top, bounds.right, bounds.bottom, radius, radius);
    SelectObject(dc, oldbrush);
    SelectObject(dc, oldpen);
    DeleteObject(brush);
    DeleteObject(pen);
}

static void footer_text(HDC dc, LPCWSTR text, RECT bounds, COLORREF color, UINT alignment) {
    SetTextColor(dc, color);
    DrawTextW(dc, text, -1, &bounds, DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX | DT_END_ELLIPSIS | alignment);
}

static void footer_chevron(HDC dc, int x, int y, COLORREF color) {
    HPEN pen = CreatePen(PS_SOLID, 2, color);
    HGDIOBJ original = SelectObject(dc, pen);
    MoveToEx(dc, x-4, y-2, NULL);
    LineTo(dc, x, y+2);
    LineTo(dc, x+5, y-3);
    SelectObject(dc, original);
    DeleteObject(pen);
}

static void footer_draw_action(HDC dc, enum FooterAction action, int width, LPCWSTR title) {
    RECT bounds = footer_action_bounds(action, width);
    BOOL enabled = footer_action_enabled(action);
    BOOL hover = enabled && action == footer_hover;
    COLORREF text = enabled ? RGB(234, 235, 239) : RGB(126, 130, 140);
    COLORREF fill = hover ? RGB(58, 63, 76) : RGB(40, 43, 51);
    COLORREF edge = hover ? RGB(100, 111, 135) : RGB(67, 72, 84);
    if(action == FOOTER_UPDATE) {
        text = RGB(210, 230, 255);
        fill = hover ? RGB(45, 76, 127) : RGB(34, 57, 96);
        edge = RGB(67, 111, 177);
    }
    footer_surface(dc, bounds, fill, edge, 10);
    if(action == FOOTER_DISCORD) {
        footer_discord_logo(dc, bounds.left+9, bounds.top+6, RGB(156, 167, 255));
        bounds.left += 32;
    } else if(action == FOOTER_OPTIONS) {
        footer_gear(dc, bounds.left+17, (bounds.top+bounds.bottom)/2, text);
        bounds.left += 29;
    } else if(action == FOOTER_GRAPHICS || action == FOOTER_WINE) {
        footer_chevron(dc, bounds.right-13, (bounds.top+bounds.bottom)/2, text);
        bounds.right -= 22;
        bounds.left += 10;
    }
    footer_text(dc, title, bounds, text, action == FOOTER_GRAPHICS ? DT_LEFT : DT_CENTER);
}

static void footer_dock_label(HDC dc, int x, LPCWSTR badge, LPCWSTR label, COLORREF color, int width) {
    RECT chip = {x, 55, x+18, 73};
    footer_surface(dc, chip, color, color, 5);
    footer_text(dc, badge, chip, RGB(255, 255, 255), DT_CENTER);
    footer_text(dc, label, (RECT){x+23, 49, x+width, 79}, RGB(177, 183, 196), DT_LEFT);
}

static UINT footer_popup(HWND window, HMENU menu, RECT anchor) {
    if(!menu) return 0;
    SetForegroundWindow(footer_root);
    POINT point = {MulDiv(anchor.left, footer_dpi, 96), MulDiv(anchor.bottom+2, footer_dpi, 96)};
    ClientToScreen(window, &point);
    UINT selection = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, point.x, point.y, 0, window, NULL);
    DestroyMenu(menu);
    PostMessageW(footer_root, WM_NULL, 0, 0);
    return selection;
}

static LRESULT CALLBACK footer_proc(HWND window, UINT message, WPARAM w, LPARAM l) {
    if(message == WM_ERASEBKGND) return 1;
    if(message == WM_PAINT) {
        PAINTSTRUCT paint;
        HDC dc = BeginPaint(window, &paint);
        RECT bounds;
        if(!real_getclientrect(window, &bounds) || bounds.right <= 0 || bounds.bottom <= 0) {
            EndPaint(window, &paint);
            return 0;
        }
        HBRUSH background = CreateSolidBrush(RGB(28, 30, 36));
        FillRect(dc, &bounds, background);
        DeleteObject(background);

        int width = MulDiv(bounds.right, 96, footer_dpi);
        SetMapMode(dc, MM_ANISOTROPIC);
        SetWindowExtEx(dc, width, FOOTER_HEIGHT, NULL);
        SetViewportExtEx(dc, bounds.right, bounds.bottom, NULL);
        RECT status = {0, 44, width, FOOTER_HEIGHT};
        HBRUSH statusFill = CreateSolidBrush(RGB(22, 24, 29));
        FillRect(dc, &status, statusFill);
        DeleteObject(statusFill);
        HPEN separator = CreatePen(PS_SOLID, 1, RGB(56, 61, 73));
        HGDIOBJ previousPen = SelectObject(dc, separator);
        MoveToEx(dc, 0, 0, NULL);
        LineTo(dc, width, 0);
        MoveToEx(dc, 0, 44, NULL);
        LineTo(dc, width, 44);
        SelectObject(dc, previousPen);
        DeleteObject(separator);

        HGDIOBJ previousFont = SelectObject(dc, footer_font);
        SetBkMode(dc, TRANSPARENT);
        footer_text(dc, L"Graphics", (RECT){18, 9, 84, 39}, RGB(177, 183, 196), DT_LEFT);
        LPCWSTR renderer = !wcscmp(footer_backend, L"metal") ? L"DXMT"
            : !wcscmp(footer_backend, L"dxvk") ? L"DXVK (Experimental)" : L"D3DMetal (Recommended)";
        footer_draw_action(dc, FOOTER_GRAPHICS, width, renderer);
        footer_draw_action(dc, FOOTER_OPTIONS, width, L"Settings");
        footer_draw_action(dc, FOOTER_FOLDER, width, L"Game Folder");
        footer_draw_action(dc, FOOTER_WINE, width, L"Wine Config");
        footer_draw_action(dc, FOOTER_DISCORD, width, L"Discord");
        footer_draw_action(dc, FOOTER_ABOUT, width, L"About");
        footer_draw_action(dc, FOOTER_LEGAL, width, L"Legal");

        SelectObject(dc, footer_version_font);
        footer_text(dc, L"Dock icons", (RECT){18, 49, 85, 79}, RGB(177, 183, 196), DT_LEFT);
        footer_dock_label(dc, 91, L"L", L"Launcher", RGB(31, 89, 230), 86);
        footer_dock_label(dc, 181, L"G", L"Game", RGB(212, 31, 41), 69);
        if(footer_update_available) {
            footer_draw_action(dc, FOOTER_UPDATE, width, L"App Update Available");
        } else {
            WCHAR version[64];
            swprintf(version, 64, L"MnM on Mac %ls", footer_version);
            footer_text(dc, version, footer_action_bounds(FOOTER_UPDATE, width), RGB(177, 183, 196), DT_RIGHT);
        }
        SelectObject(dc, previousFont);
        EndPaint(window, &paint);
        return 0;
    }
    if(message == WM_MOUSEMOVE || message == WM_MOUSELEAVE) {
        int width = 0;
        enum FooterAction hover = message == WM_MOUSEMOVE ? footer_hit(window, l, &width) : FOOTER_NONE;
        if(message == WM_MOUSEMOVE && footer_hover == FOOTER_NONE && hover != FOOTER_NONE) {
            TRACKMOUSEEVENT tracking = {sizeof(tracking), TME_LEAVE, window, 0};
            TrackMouseEvent(&tracking);
        }
        if(hover != footer_hover) {
            footer_hover = hover;
            InvalidateRect(window, NULL, FALSE);
        }
        return 0;
    }
    if(message == WM_LBUTTONUP) {
        int width = 0;
        enum FooterAction action = footer_hit(window, l, &width);
        switch(action) {
        case FOOTER_GRAPHICS: {
            HMENU menu = CreatePopupMenu();
            if(!menu) break;
            AppendMenuW(menu, MF_STRING | (!wcscmp(footer_backend, L"d3dmetal") ? MF_CHECKED : 0), 1, L"D3DMetal (Recommended)");
            AppendMenuW(menu, MF_STRING | (!wcscmp(footer_backend, L"metal") ? MF_CHECKED : 0), 2, L"DXMT");
            AppendMenuW(menu, MF_STRING | (!wcscmp(footer_backend, L"dxvk") ? MF_CHECKED : 0), 3, L"DXVK (Experimental)");
            UINT selected = footer_popup(window, menu, footer_action_bounds(action, width));
            if(selected) footer_command(selected == 1 ? "graphics:d3dmetal" : selected == 2 ? "graphics:metal" : "graphics:dxvk");
            break;
        }
        case FOOTER_WINE: {
            HMENU menu = CreatePopupMenu();
            if(!menu) break;
            AppendMenuW(menu, MF_STRING, 1, L"Wine Config");
            AppendMenuW(menu, MF_STRING, 2, L"Open Registry");
            UINT selected = footer_popup(window, menu, footer_action_bounds(action, width));
            if(selected) footer_command(selected == 1 ? "wine-config" : "wine-registry");
            break;
        }
        case FOOTER_OPTIONS: footer_command("options"); break;
        case FOOTER_FOLDER: footer_command("game-folder"); break;
        case FOOTER_DISCORD: footer_command("discord"); break;
        case FOOTER_ABOUT: footer_command("about"); break;
        case FOOTER_LEGAL: footer_command("legal"); break;
        case FOOTER_UPDATE: footer_command("app-update"); break;
        default: break;
        }
        return 0;
    }
    return DefWindowProcW(window, message, w, l);
}
static void footer_attach(HWND root) {
    if(footer_window || !footer_enabled())return;
    RECT client,outer;if(!real_getclientrect(root,&client) || !GetWindowRect(root,&outer))return;
    UINT (WINAPI *getdpi)(HWND)=(void*)GetProcAddress(GetModuleHandleW(L"user32.dll"),"GetDpiForWindow");
    footer_dpi=getdpi?getdpi(root):96;if(footer_dpi<96 || footer_dpi>384)footer_dpi=96;
    // Use the window's coordinate DPI, not the display's backing-pixel ratio.
    // A DPI-unaware Wine window can use 96-DPI coordinates on Retina.
    int reserved=MulDiv(FOOTER_HEIGHT,footer_dpi,96);
    WNDCLASSW klass={0};klass.lpfnWndProc=footer_proc;klass.hInstance=GetModuleHandleW(NULL);
    klass.hCursor=LoadCursorW(NULL,IDC_ARROW);klass.lpszClassName=L"MnMMacControls";
    if(!RegisterClassW(&klass) && GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)return;
    footer_font=CreateFontW(-14,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,L"Arial");
    footer_version_font=CreateFontW(-12,0,0,0,FW_BOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,L"Arial");
    GetEnvironmentVariableW(L"MNM_GRAPHICS_BACKEND",footer_backend,32);
    GetEnvironmentVariableW(L"MNM_APP_VERSION",footer_version,32);
    GetEnvironmentVariableW(L"MNM_WEBVIEW_CONTROL_DIR",footer_controls,32768);
    SetPropW(root,L"MnMMacFooterHeight",(HANDLE)(ULONG_PTR)reserved);
    footer_root=root;
    SetWindowPos(root,HWND_NOTOPMOST,0,0,outer.right-outer.left,outer.bottom-outer.top+reserved,SWP_NOMOVE|SWP_NOACTIVATE);
    footer_window=real_create(0,L"MnMMacControls",L"MnM on Mac controls",WS_CHILD|WS_VISIBLE,
        0,client.bottom,client.right,reserved,root,NULL,klass.hInstance,NULL);
    if(footer_window)footer_command("opened");
    if(!footer_window)RemovePropW(root,L"MnMMacFooterHeight");
}
static BOOL WINAPI bridge_getclientrect(HWND hwnd,LPRECT bounds) {
    BOOL result=real_getclientrect(hwnd,bounds);
    ULONG_PTR reserved=(ULONG_PTR)GetPropW(hwnd,L"MnMMacFooterHeight");
    if(result && reserved>0 && reserved<=FOOTER_HEIGHT*4 && bounds->bottom>(LONG)reserved)bounds->bottom-=(LONG)reserved;
    return result;
}
