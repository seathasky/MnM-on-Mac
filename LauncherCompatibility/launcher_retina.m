/* Scoped to the private launcher process tree. Wine 10 normally disables
 * Retina when a display mode differs from the mode at Wine startup. Keeping
 * its existing setter in Retina mode preserves the same 2x coordinate mapping
 * for Cocoa windows, child views, GDI surfaces and mouse events. No game hook.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <mach-o/dyld.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

static void (*retina_original)(id,SEL,int);
static BOOL retina_installed;
static BOOL retina_scope(void) {
    const char *enabled=getenv("MNM_LAUNCHER_RETINA_LOCK");
    const char *prefix=getenv("WINEPREFIX");
    const char *session=getenv("MNM_WEBVIEW_BRIDGE_SESSION");
    const char *suffix="/Prefix-Launcher";
    return enabled && !strcmp(enabled,"1") && prefix && prefix[0]=='/'
        && strlen(prefix)>strlen(suffix)
        && !strcmp(prefix+strlen(prefix)-strlen(suffix),suffix)
        && session && strlen(session)==32
        && strspn(session,"0123456789abcdefABCDEF")==32;
}
static void retina_trace(const char *message) {
    const char *path=getenv("MNM_LAUNCHER_NATIVE_LOG");
    if(!path || path[0]!='/')return;
    int fd=open(path,O_WRONLY|O_APPEND|O_NOFOLLOW);
    if(fd>=0){write(fd,message,strlen(message));close(fd);}
}
static void retina_set(id object,SEL selector,int mode) {
    static BOOL reported;
    if(!mode && !reported){reported=YES;retina_trace("native: retained Retina mapping after display change\n");}
    retina_original(object,selector,1);
}
static BOOL retina_install(void) {
    if(retina_installed)return YES;
    if(!retina_scope())return NO;
    Class controller=objc_getClass("WineApplicationController");
    Method method=class_getInstanceMethod(controller,sel_registerName("setRetinaMode:"));
    if(!method || method_getNumberOfArguments(method)!=3)return NO;
    // Verify the exact Wine 10 ABI before touching an implementation.
    char *result=method_copyReturnType(method),*argument=method_copyArgumentType(method,2);
    BOOL compatible=result && argument && !strcmp(result,"v") && !strcmp(argument,"i");
    free(result);free(argument);
    if(!compatible)return NO;
    retina_original=(void*)method_getImplementation(method);
    method_setImplementation(method,(IMP)retina_set);
    retina_installed=YES;
    retina_trace("native: launcher Retina mapping lock installed\n");
    return YES;
}
#ifndef MNM_RETINA_TEST
static void retina_image(const struct mach_header *header,intptr_t slide) {
    // ObjC classes may not be registered yet inside a dyld image callback.
    // Install after loading, on Wine's Cocoa thread, never under the loader lock.
    dispatch_async(dispatch_get_main_queue(),^{retina_install();});
}
__attribute__((constructor)) static void retina_start(void) {
    if(retina_scope())_dyld_register_func_for_add_image(retina_image);
}
#endif
