/* Session tokens are passed in memory, never interpolated into a shell or
 * written into the launcher control directory. */
static BOOL game_token_valid(LPCWSTR token) {
    if(!token || !*token || wcslen(token)>16000)return FALSE;
    for(LPCWSTR p=token;*p;p++) {
        if(!((*p>=L'a' && *p<=L'z') || (*p>=L'A' && *p<=L'Z') ||
             (*p>=L'0' && *p<=L'9') || *p==L'.' || *p==L'_' || *p==L'-' || *p==L'='))return FALSE;
    }
    return TRUE;
}
