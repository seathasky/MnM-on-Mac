/* Only the configured game's process creation is redirected. The official
 * launcher, WebView, authentication, downloads, and repair remain untouched. */
static BOOL (WINAPI *real_createprocess)(LPCWSTR,LPWSTR,LPSECURITY_ATTRIBUTES,
    LPSECURITY_ATTRIBUTES,BOOL,DWORD,LPVOID,LPCWSTR,LPSTARTUPINFOW,LPPROCESS_INFORMATION);
static BOOL WINAPI bridge_createprocess(LPCWSTR app,LPWSTR command,LPSECURITY_ATTRIBUTES pa,
    LPSECURITY_ATTRIBUTES ta,BOOL inherit,DWORD flags,LPVOID environment,LPCWSTR directory,
    LPSTARTUPINFOW startup,LPPROCESS_INFORMATION process) {
    WCHAR expected[32768]={0},candidate[32768]={0},full[32768]={0},helper[32768]={0};
    if(!host || !footer_enabled() || !GetEnvironmentVariableW(L"MNM_GAME_EXE",expected,32768))
        return real_createprocess(app,command,pa,ta,inherit,flags,environment,directory,startup,process);
    if(app) {
        if(wcslen(app)>=32768)return real_createprocess(app,command,pa,ta,inherit,flags,environment,directory,startup,process);
        wcscpy(candidate,app);
    } else if(command) {
        LPCWSTR start=command;while(*start==L' ')start++;
        BOOL quoted=*start==L'"';if(quoted)start++;
        LPCWSTR end=start;while(*end && (quoted?*end!=L'"':*end!=L' '))end++;
        size_t length=end-start;if(length>=32768)return real_createprocess(app,command,pa,ta,inherit,flags,environment,directory,startup,process);
        wmemcpy(candidate,start,length);candidate[length]=0;
    }
    DWORD length=GetFullPathNameW(candidate,32768,full,NULL);
    if(!length || length>=32768 || _wcsicmp(full,expected))
        return real_createprocess(app,command,pa,ta,inherit,flags,environment,directory,startup,process);
    length=GetEnvironmentVariableW(L"MNM_PLAY_HELPER",helper,32768);
    if(!length || length>=32768 || wcschr(helper,L'"')){SetLastError(ERROR_FILE_NOT_FOUND);return FALSE;}
    WCHAR handoff[32768];if(swprintf(handoff,32768,L"\"%ls\" --game-wait",helper)<0){SetLastError(ERROR_INVALID_PARAMETER);return FALSE;}
    /* The helper inherits only the launcher's private control channel. Account
     * tokens are not copied to command files or compatibility logs. */
    return real_createprocess(helper,handoff,pa,ta,inherit,flags,NULL,directory,startup,process);
}
