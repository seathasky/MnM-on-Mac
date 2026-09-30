/* Temporary child overlay. The official launcher executable stays unchanged. */
static HWND loading_window;
static BOOL loading_finished;
static LRESULT CALLBACK loading_proc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    if(msg==WM_ERASEBKGND)return 1;
    if(msg==WM_PAINT) {
        PAINTSTRUCT paint;HDC dc=BeginPaint(hwnd,&paint);RECT area;GetClientRect(hwnd,&area);
        HBRUSH background=CreateSolidBrush(RGB(25,25,25));FillRect(dc,&area,background);DeleteObject(background);
        UINT dpi=footer_dpi;if(!dpi)dpi=96;
        int titleHeight=MulDiv(21,dpi,96),detailHeight=MulDiv(14,dpi,96);
        HFONT title=CreateFontW(-titleHeight,0,0,0,FW_SEMIBOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,ANTIALIASED_QUALITY,0,L"Arial");
        HFONT detail=CreateFontW(-detailHeight,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,ANTIALIASED_QUALITY,0,L"Arial");
        HGDIOBJ previous=SelectObject(dc,title);SetBkMode(dc,TRANSPARENT);SetTextColor(dc,RGB(235,235,235));
        int cy=area.bottom/2;RECT line={0,cy-titleHeight,area.right,cy+titleHeight};
        DrawTextW(dc,L"Loading official launcher...",-1,&line,DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX);
        SelectObject(dc,detail);SetTextColor(dc,RGB(170,170,170));
        line.top=cy+titleHeight;line.bottom=line.top+detailHeight*3;
        DrawTextW(dc,L"Please wait while Monsters and Memories starts.",-1,&line,DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX);
        SelectObject(dc,previous);DeleteObject(title);DeleteObject(detail);EndPaint(hwnd,&paint);return 0;
    }
    return DefWindowProcW(hwnd,msg,wp,lp);
}
static void loading_update(HWND root) {
    if(loading_finished)return;
    if(!loading_window) {
        WNDCLASSW cls={0};cls.lpfnWndProc=loading_proc;cls.hInstance=GetModuleHandleW(NULL);cls.lpszClassName=L"MnMLauncherLoading";
        RegisterClassW(&cls);
        loading_window=real_create(0,cls.lpszClassName,L"Loading official launcher",WS_CHILD|WS_VISIBLE,0,0,1,1,root,NULL,cls.hInstance,NULL);
    }
    RECT area;real_getclientrect(root,&area);
    int footer=footer_window?MulDiv(FOOTER_HEIGHT,footer_dpi,96):0;
    SetWindowPos(loading_window,HWND_TOP,0,0,area.right,area.bottom-footer,SWP_NOACTIVATE|SWP_SHOWWINDOW);
}
static void loading_complete(void) {
    loading_finished=TRUE;
    if(loading_window){DestroyWindow(loading_window);loading_window=NULL;}
}
