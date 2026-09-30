#import <Cocoa/Cocoa.h>
#import "DeviceWatcher.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) DeviceWatcher *watcher;

@end
