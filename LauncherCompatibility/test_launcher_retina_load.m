/* Exercise the actual packaged dylib in a Cocoa-free host with Wine's ABI. */
#import <Foundation/Foundation.h>
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
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
        do {
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            [controller setRetinaMode:0];
        } while(controller.mode!=1 && [deadline timeIntervalSinceNow]>0);
        assert(controller.mode==1);
        puts("Packaged Retina dylib loaded and retained mapping successfully.");
    }
}
