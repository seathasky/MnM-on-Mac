/* Scoped to the private launcher process tree. Wine 10 normally disables
 * Retina when a display mode differs from the mode at Wine startup. Keeping
 * its existing setter in Retina mode preserves the same 2x coordinate mapping
 * for Cocoa windows, child views, GDI surfaces and mouse events.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <mach-o/dyld.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#ifndef MNM_RETINA_TEST
#import <AppKit/AppKit.h>
#include <crt_externs.h>
#include <dlfcn.h>
#include "dock_role.h"
#endif

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
static NSString *dock_badge;
static NSImage *dock_base_icon;
static NSImage *dock_composite;
static void (*original_icon_setter)(id, SEL, id);

static const char *dock_role(void) {
    const char *expected = getenv("MNM_GAME_DOCK_PREFIX");
    const char *prefix = getenv("WINEPREFIX");
    BOOL game = expected && prefix && prefix[0] == '/' && !strcmp(prefix, expected);
    return mnm_dock_role(retina_scope(), game, *_NSGetArgc(), *_NSGetArgv());
}

static NSImage *make_badged_icon(NSImage *icon, NSString *letter) {
    BOOL launcher = [letter isEqualToString:@"L"];
    NSColor *color = launcher ? [NSColor colorWithSRGBRed:0.12 green:0.35 blue:0.90 alpha:1]
                              : [NSColor colorWithSRGBRed:0.83 green:0.12 blue:0.16 alpha:1];
    return [NSImage imageWithSize:NSMakeSize(512, 512) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [icon drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                fraction:1 respectFlipped:YES hints:nil];
        CGFloat scale = MIN(NSWidth(bounds), NSHeight(bounds)) / 512;
        CGFloat side = 176 * scale;
        CGFloat inset = 24 * scale;
        NSRect badge = NSMakeRect(NSMaxX(bounds) - side - inset, NSMinY(bounds) + inset, side, side);
        [[NSColor colorWithWhite:0.08 alpha:0.9] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(badge, -7 * scale, -7 * scale)
                                       xRadius:44 * scale yRadius:44 * scale] fill];
        [color setFill];
        [[NSBezierPath bezierPathWithRoundedRect:badge xRadius:37 * scale yRadius:37 * scale] fill];
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:side * 0.67 weight:NSFontWeightHeavy],
            NSForegroundColorAttributeName: NSColor.whiteColor
        };
        NSSize text = [letter sizeWithAttributes:attributes];
        [letter drawAtPoint:NSMakePoint(NSMidX(badge) - text.width / 2, NSMidY(badge) - text.height / 2)
             withAttributes:attributes];
        return YES;
    }];
}

static NSImage *badged_icon(NSImage *icon) {
    if (!icon || !dock_badge || icon == dock_composite) return icon;
    if (icon == dock_base_icon) return dock_composite;
    NSImage *replacement = make_badged_icon(icon, dock_badge);
    if (!replacement) return icon;
    [dock_base_icon release];
    dock_base_icon = [icon retain];
    [dock_composite release];
    dock_composite = [replacement retain];
    return dock_composite;
}

static void set_window_icon(NSApplication *app, SEL command, NSImage *icon) {
    if ([NSThread isMainThread]) {
        original_icon_setter(app, command, badged_icon(icon));
    } else {
        original_icon_setter(app, command, icon);
        dispatch_async(dispatch_get_main_queue(), ^{
            original_icon_setter(app, command, badged_icon(app.applicationIconImage));
        });
    }
}

static void install_dock_badge(void) {
    if (original_icon_setter) return;
    const char *role = dock_role();
    if (!role) return;
    Method setter = class_getInstanceMethod(objc_getClass("NSApplication"), @selector(setApplicationIconImage:));
    if (!setter || method_getNumberOfArguments(setter) != 3) return;
    char *result = method_copyReturnType(setter), *argument = method_copyArgumentType(setter, 2);
    BOOL compatible = result && argument && !strcmp(result, "v") && !strcmp(argument, "@");
    free(result);
    free(argument);
    if (!compatible) return;
    dock_badge = [[NSString alloc] initWithUTF8String:role];
    original_icon_setter = (void *)method_getImplementation(setter);
    method_setImplementation(setter, (IMP)set_window_icon);
    NSApplication *__unsafe_unretained *application = dlsym(RTLD_DEFAULT, "NSApp");
    if (application && *application)
        original_icon_setter(*application, @selector(setApplicationIconImage:), badged_icon((*application).applicationIconImage));
}

static void retina_image(const struct mach_header *header,intptr_t slide) {
    // ObjC classes may not be registered yet inside a dyld image callback.
    // Install after loading, on Wine's Cocoa thread, never under the loader lock.
    dispatch_async(dispatch_get_main_queue(), ^{
        retina_install();
        install_dock_badge();
    });
}
__attribute__((constructor)) static void retina_start(void) {
    if (retina_scope() || dock_role()) _dyld_register_func_for_add_image(retina_image);
}
#endif
