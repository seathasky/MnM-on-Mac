/* Startup stages only. Never record commands, URLs, rendered content or tokens. */
static void startup_trace(const char *stage) {
    WCHAR path[32768];
    DWORD count=GetEnvironmentVariableW(L"MNM_LAUNCHER_DIAGNOSTICS",path,32768);
    if(!count || count>=32768)return;
    HANDLE file=CreateFileW(path,FILE_APPEND_DATA,FILE_SHARE_READ|FILE_SHARE_WRITE,
                            NULL,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if(file==INVALID_HANDLE_VALUE)return;
    char line[384];
    int length=snprintf(line,sizeof(line),"tick=%llu pid=%lu %s\r\n",
        (unsigned long long)GetTickCount64(),(unsigned long)GetCurrentProcessId(),stage);
    if(length>0 && length<(int)sizeof(line)){DWORD written;WriteFile(file,line,(DWORD)length,&written,NULL);}
    CloseHandle(file);
}
