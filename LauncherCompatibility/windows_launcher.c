/* Scoped Wine launcher companion. Never injects into the game or unrelated apps. */
#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#include <windows.h>
#include <winternl.h>
#include <tlhelp32.h>
#include <wchar.h>
#include <stdio.h>
#include <stdlib.h>
typedef NTSTATUS (NTAPI *QUERY_PROCESS)(HANDLE,PROCESSINFOCLASS,PVOID,ULONG,PULONG);
static DWORD injected[1024],family[1024];static unsigned injected_count,family_count;
static HANDLE family_handles[1024];
static DWORD root_pid;static BOOL root_visible;
static BOOL CALLBACK visible_host(HWND window,LPARAM unused){DWORD pid;WCHAR cls[64];GetWindowThreadProcessId(window,&pid);GetClassNameW(window,cls,64);if(pid==root_pid && !wcscmp(cls,L"Tauri Window") && (IsWindowVisible(window)||IsIconic(window)))root_visible=TRUE;return TRUE;}
static void finish_browsers(void){for(unsigned i=1;i<family_count;i++)if(family_handles[i]){if(WaitForSingleObject(family_handles[i],50)==WAIT_TIMEOUT)TerminateProcess(family_handles[i],0);CloseHandle(family_handles[i]);}}
static int game_wait(void) {
    WCHAR controls[32768]={0},ticket[33],request[32768],temporary[32768],result[32768],heartbeat[32768];
    DWORD length=GetEnvironmentVariableW(L"MNM_WEBVIEW_CONTROL_DIR",controls,32768);
    if(!length || length>=32768)return ERROR_INVALID_PARAMETER;
    swprintf(ticket,33,L"%08lx%08lx%016llx",GetCurrentProcessId(),GetCurrentThreadId(),GetTickCount64());
    if(swprintf(request,32768,L"%ls\\game-request-%ls.msg",controls,ticket)<0 ||
       swprintf(temporary,32768,L"%ls.tmp",request)<0 ||
       swprintf(result,32768,L"%ls\\game-result-%ls.txt",controls,ticket)<0 ||
       swprintf(heartbeat,32768,L"%ls\\heartbeat.txt",controls)<0)return ERROR_INVALID_PARAMETER;
    HANDLE file=CreateFileW(temporary,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
    if(file==INVALID_HANDLE_VALUE)return ERROR_ACCESS_DENIED;
    DWORD written=0;BOOL ok=WriteFile(file,"play",4,&written,NULL);CloseHandle(file);
    if(!ok || written!=4 || !MoveFileExW(temporary,request,MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(temporary);return ERROR_WRITE_FAULT;
    }
    ULONGLONG deadline=GetTickCount64()+300000;BOOL started=FALSE;
    for(;;) {
        file=CreateFileW(result,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
        if(file!=INVALID_HANDLE_VALUE) {
            char value[64]={0};DWORD count=0;ReadFile(file,value,sizeof(value)-1,&count,NULL);CloseHandle(file);
            if(!strcmp(value,"started"))started=TRUE;
            if(!strncmp(value,"exit:",5)) { int status=atoi(value+5);DeleteFileW(result);return status; }
        }
        if(!started && GetTickCount64()>deadline){DeleteFileW(request);return ERROR_TIMEOUT;}
        WIN32_FILE_ATTRIBUTE_DATA info;
        if(GetFileAttributesExW(heartbeat,GetFileExInfoStandard,&info)) {
            FILETIME now;GetSystemTimeAsFileTime(&now);ULARGE_INTEGER current,last;
            current.LowPart=now.dwLowDateTime;current.HighPart=now.dwHighDateTime;
            last.LowPart=info.ftLastWriteTime.dwLowDateTime;last.HighPart=info.ftLastWriteTime.dwHighDateTime;
            if(current.QuadPart>last.QuadPart && current.QuadPart-last.QuadPart>600000000ULL)return ERROR_CANCELLED;
        } else if(started)return ERROR_CANCELLED;
        if(GetFileAttributesW(controls)==INVALID_FILE_ATTRIBUTES)return ERROR_CANCELLED;
        Sleep(100);
    }
}
static BOOL CALLBACK close_host(HWND window,LPARAM pid){DWORD owner=0;GetWindowThreadProcessId(window,&owner);if(owner==(DWORD)pid && GetWindow(window,GW_OWNER)==NULL)PostMessageW(window,WM_CLOSE,0,0);return TRUE;}
static BOOL CALLBACK show_host(HWND window,LPARAM pid){DWORD owner=0;WCHAR cls[64]={0};GetWindowThreadProcessId(window,&owner);GetClassNameW(window,cls,64);if(owner==(DWORD)pid && !wcscmp(cls,L"Tauri Window")){ShowWindow(window,SW_RESTORE);SetForegroundWindow(window);}return TRUE;}
static int contains(DWORD *ids,unsigned n,DWORD pid){for(unsigned i=0;i<n;i++)if(ids[i]==pid)return 1;return 0;}
static int browser_command(HANDLE process){
    QUERY_PROCESS query=(void*)GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"NtQueryInformationProcess");
    PROCESS_BASIC_INFORMATION info;ULONG size=0;ULONG_PTR parameters=0;UNICODE_STRING command;SIZE_T read;
    if(!query || query(process,ProcessBasicInformation,&info,sizeof(info),&size))return 0;
    if(!ReadProcessMemory(process,(BYTE*)info.PebBaseAddress+0x20,&parameters,sizeof(parameters),&read))return 0;
    if(!ReadProcessMemory(process,(BYTE*)parameters+0x70,&command,sizeof(command),&read) || command.Length>32766)return 0;
    WCHAR text[16384]={0};
    if(!ReadProcessMemory(process,command.Buffer,text,command.Length,&read))return 0;
    return wcsstr(text,L"--webview-exe-name=mnm_launcher.exe") &&
        (!wcsstr(text,L"--type=") || wcsstr(text,L"--type=gpu-process"));
}
static int attach(DWORD pid,LPCWSTR dll,int check_browser){
    HANDLE process=OpenProcess(PROCESS_CREATE_THREAD|PROCESS_QUERY_INFORMATION|PROCESS_VM_OPERATION|PROCESS_VM_WRITE|PROCESS_VM_READ,FALSE,pid);
    if(!process)return 0;
    if(check_browser && !browser_command(process)){CloseHandle(process);return 0;}
    SIZE_T size=(wcslen(dll)+1)*sizeof(WCHAR);
    void *remote=VirtualAllocEx(process,NULL,size,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    int ok=0;
    if(remote && WriteProcessMemory(process,remote,dll,size,NULL)){
        HANDLE thread=CreateRemoteThread(process,NULL,0,(LPTHREAD_START_ROUTINE)GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"LoadLibraryW"),remote,0,NULL);
        if(thread){
            DWORD status=0;
            if(WaitForSingleObject(thread,5000)==WAIT_OBJECT_0){GetExitCodeThread(thread,&status);ok=status!=0;}
            // An unresolved load retains its buffer until process exit rather
            // than freeing memory a still-running loader thread could access.
            else remote=NULL;
            CloseHandle(thread);
        }
    }
    if(remote)VirtualFreeEx(process,remote,0,MEM_RELEASE);
    CloseHandle(process);return ok;
}
static int launcher_main(int argc,wchar_t **argv){
    if(argc==2 && !wcscmp(argv[1],L"--game-wait"))return game_wait();
    if(argc==3 && (!wcscmp(argv[1],L"--close") || !wcscmp(argv[1],L"--show"))){
        if(!wcslen(argv[2]) || wcsspn(argv[2],L"0123456789abcdefABCDEF")!=wcslen(argv[2]) || wcslen(argv[2])>40)return 2;
        wchar_t name[128];swprintf(name,128,!wcscmp(argv[1],L"--close")?L"Local\\MnMWebViewStop_%ls":L"Local\\MnMWebViewShow_%ls",argv[2]);
        HANDLE event=OpenEventW(EVENT_MODIFY_STATE,FALSE,name);if(!event)return 0;
        SetEvent(event);CloseHandle(event);return 0;
    }
    if(argc!=3 || wcschr(argv[1],L'"') || wcschr(argv[2],L'"'))return 2;
    wchar_t dll[32768],command[32768],session[48]={0};
    DWORD len=GetModuleFileNameW(NULL,dll,32768);
    if(!len || len>=32768)return 3;
    wchar_t *slash=wcsrchr(dll,L'\\');if(!slash)return 3;
    wcscpy(slash+1,L"MnMWebViewBridge.dll");
    if(GetFileAttributesW(dll)==INVALID_FILE_ATTRIBUTES)return 4;
    DWORD session_len=GetEnvironmentVariableW(L"MNM_WEBVIEW_BRIDGE_SESSION",session,48);
    if(!session_len || session_len>=48 || wcsspn(session,L"0123456789abcdefABCDEF")!=wcslen(session))swprintf(session,48,L"%lx",GetCurrentProcessId());
    SetEnvironmentVariableW(L"MNM_WEBVIEW_BRIDGE_SESSION",session);
    wchar_t event_name[128];swprintf(event_name,128,L"Local\\MnMWebViewStop_%ls",session);
    HANDLE stop=CreateEventW(NULL,TRUE,FALSE,event_name);
    swprintf(event_name,128,L"Local\\MnMWebViewShow_%ls",session);
    HANDLE show=CreateEventW(NULL,TRUE,FALSE,event_name);
    // Prefix-local ownership: a reopened Mac app first asks the previous
    // launcher session to close, rather than starting two WebViews together.
    HANDLE owner=CreateMutexW(NULL,FALSE,L"Local\\MnMOfficialLauncherOwner");
    HANDLE restart=CreateEventW(NULL,TRUE,FALSE,L"Local\\MnMOfficialLauncherRestart");
    DWORD ownership=owner?WaitForSingleObject(owner,0):WAIT_FAILED;
    if(ownership==WAIT_TIMEOUT){if(restart)SetEvent(restart);ownership=WaitForSingleObject(owner,10000);}
    if(ownership!=WAIT_OBJECT_0 && ownership!=WAIT_ABANDONED){if(owner)CloseHandle(owner);if(restart)CloseHandle(restart);return ERROR_BUSY;}
    if(restart)ResetEvent(restart);
    if(swprintf(command,32768,L"\"%ls\" --stinky-cheese",argv[1])<0)return 2;
    STARTUPINFOW startup={0};startup.cb=sizeof(startup);PROCESS_INFORMATION child={0};
    // Install the host bridge before its WebView2 environment is created.
    // Polling after launch races the loader and misses controller callbacks.
    if(!CreateProcessW(argv[1],command,NULL,NULL,FALSE,CREATE_SUSPENDED,NULL,argv[2],&startup,&child))return 5;
    if(attach(child.dwProcessId,dll,FALSE))injected[injected_count++]=child.dwProcessId;
    ResumeThread(child.hThread);
    CloseHandle(child.hThread);family[family_count++]=child.dwProcessId;
    root_pid=child.dwProcessId;BOOL seen_window=FALSE,closing=FALSE;ULONGLONG close_started=0;
    while(WaitForSingleObject(child.hProcess,100)==WAIT_TIMEOUT){
        root_visible=FALSE;EnumWindows(visible_host,0);if(root_visible)seen_window=TRUE;
        if(!closing && ((seen_window && !root_visible) || (stop && WaitForSingleObject(stop,0)==WAIT_OBJECT_0) || (restart && WaitForSingleObject(restart,0)==WAIT_OBJECT_0))) {
            closing=TRUE;close_started=GetTickCount64();EnumWindows(close_host,(LPARAM)child.dwProcessId);
        }
        // Give the official launcher time to dispose WebView2 normally. If its
        // window is gone but a worker keeps it alive, finish this exact process.
        if(closing && GetTickCount64()-close_started>5000){TerminateProcess(child.hProcess,0);break;}
        if(show && WaitForSingleObject(show,0)==WAIT_OBJECT_0){EnumWindows(show_host,(LPARAM)child.dwProcessId);ResetEvent(show);}
        HANDLE snapshot=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);PROCESSENTRY32W entry={0};entry.dwSize=sizeof(entry);
        if(snapshot==INVALID_HANDLE_VALUE)continue;
        if(Process32FirstW(snapshot,&entry))do{
            int host=entry.th32ProcessID==child.dwProcessId;
            if(!host && (_wcsicmp(entry.szExeFile,L"msedgewebview2.exe") || !contains(family,family_count,entry.th32ParentProcessID)))continue;
            if(!contains(family,family_count,entry.th32ProcessID) && family_count<1024){family[family_count]=entry.th32ProcessID;family_handles[family_count]=OpenProcess(PROCESS_TERMINATE|SYNCHRONIZE,FALSE,entry.th32ProcessID);family_count++;}
            if(contains(injected,injected_count,entry.th32ProcessID))continue;
            if(attach(entry.th32ProcessID,dll,!host) && injected_count<1024)injected[injected_count++]=entry.th32ProcessID;
        }while(Process32NextW(snapshot,&entry));
        CloseHandle(snapshot);
    }
    WaitForSingleObject(child.hProcess,1000);DWORD status=1;GetExitCodeProcess(child.hProcess,&status);finish_browsers();CloseHandle(child.hProcess);if(stop)CloseHandle(stop);if(show)CloseHandle(show);if(restart)CloseHandle(restart);ReleaseMutex(owner);CloseHandle(owner);return closing?0:(int)status;
}

// A GUI-subsystem helper must not allocate a Wine console. Preserve the CRT's
// Unicode argument parsing for normal launch, show/close, and game-wait modes.
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,LPWSTR command,int show) {
    return launcher_main(__argc,__wargv);
}
