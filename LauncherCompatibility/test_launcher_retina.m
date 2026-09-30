#define MNM_RETINA_TEST
#include "launcher_retina.m"
#include <assert.h>
@interface WineApplicationController : NSObject
@property int mode;
- (void)setRetinaMode:(int)mode;
@end
@implementation WineApplicationController
- (void)setRetinaMode:(int)mode {self.mode=mode;}
@end
int main(void) {
    @autoreleasepool {
        WineApplicationController *controller=[WineApplicationController new];
        assert(!retina_install());
        [controller setRetinaMode:0];assert(controller.mode==0);
        setenv("MNM_LAUNCHER_RETINA_LOCK","1",1);
        setenv("MNM_WEBVIEW_BRIDGE_SESSION","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",1);
        setenv("WINEPREFIX","/private/tmp/mnm-retina-test/Prefix",1);
        assert(!retina_install()); // Never change a game prefix.
        setenv("WINEPREFIX","/private/tmp/mnm-retina-test/Prefix-Launcher",1);
        assert(retina_install());assert(retina_install());
        for(int change=0;change<20;change++) {
            [controller setRetinaMode:change%2];assert(controller.mode==1);
        }
        puts("Retina mapping tests passed (scope, game exclusion, ABI, repeated display changes).");
    }
}
