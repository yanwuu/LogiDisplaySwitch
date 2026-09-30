#import "DeviceWatcher.h"
#import <AppKit/AppKit.h>

@interface DeviceWatcher () {
    IOHIDManagerRef _hidManager;
    BOOL _isSystemSleeping;
    NSTimeInterval _lastChangeTime;
}
@property (nonatomic, assign) BOOL isTargetConnected;

- (void)onDeviceAttached:(IOHIDDeviceRef)device;
- (void)onDeviceRemoved:(IOHIDDeviceRef)device;

@end

static void HandleDeviceMatching(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    DeviceWatcher *watcher = (__bridge DeviceWatcher *)context;
    [watcher onDeviceAttached:device];
}

static void HandleDeviceRemoval(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    DeviceWatcher *watcher = (__bridge DeviceWatcher *)context;
    [watcher onDeviceRemoved:device];
}

@implementation DeviceWatcher

- (instancetype)initWithTargetPattern:(NSString *)pattern {
    self = [super init];
    if (self) {
        _targetDevicePattern = [pattern copy];
        _isSystemSleeping = NO;
        _isTargetConnected = NO;
        _lastChangeTime = 0;
        
        [self setupSleepNotifications];
    }
    return self;
}

- (void)dealloc {
    [self stopWatching];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

- (void)setupSleepNotifications {
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(systemWillSleep:)
                                                               name:NSWorkspaceWillSleepNotification
                                                             object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(systemDidWake:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];
}

- (void)systemWillSleep:(NSNotification *)note {
    NSLog(@"[DeviceWatcher] 系统准备进入休眠，暂停切屏监听");
    _isSystemSleeping = YES;
}

- (void)systemDidWake:(NSNotification *)note {
    NSLog(@"[DeviceWatcher] 系统已唤醒，2秒后恢复切屏监听");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_isSystemSleeping = NO;
        [self checkCurrentState];
    });
}

- (void)startWatching {
    if (_hidManager) return;
    
    _hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(_hidManager, NULL);
    
    IOHIDManagerRegisterDeviceMatchingCallback(_hidManager, HandleDeviceMatching, (__bridge void *)self);
    IOHIDManagerRegisterDeviceRemovalCallback(_hidManager, HandleDeviceRemoval, (__bridge void *)self);
    
    IOHIDManagerScheduleWithRunLoop(_hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(_hidManager, kIOHIDOptionsTypeNone);
    
    [self checkCurrentState];
}

- (void)stopWatching {
    if (_hidManager) {
        IOHIDManagerUnscheduleFromRunLoop(_hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDManagerClose(_hidManager, kIOHIDOptionsTypeNone);
        CFRelease(_hidManager);
        _hidManager = NULL;
    }
}

- (NSString *)getProductName:(IOHIDDeviceRef)device {
    CFStringRef prop = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    if (prop) {
        return (__bridge NSString *)prop;
    }
    return @"";
}

- (BOOL)isTargetDevice:(IOHIDDeviceRef)device {
    NSString *name = [self getProductName:device];
    if ([name containsString:_targetDevicePattern]) {
        return YES;
    }
    return NO;
}

- (BOOL)checkCurrentState {
    if (!_hidManager) return NO;
    
    BOOL found = NO;
    CFSetRef deviceSet = IOHIDManagerCopyDevices(_hidManager);
    if (deviceSet) {
        CFIndex count = CFSetGetCount(deviceSet);
        const void *values[count];
        CFSetGetValues(deviceSet, values);
        for (CFIndex i = 0; i < count; i++) {
            IOHIDDeviceRef dev = (IOHIDDeviceRef)values[i];
            if ([self isTargetDevice:dev]) {
                found = YES;
                break;
            }
        }
        CFRelease(deviceSet);
    }
    
    _isTargetConnected = found;
    return found;
}

- (void)onDeviceAttached:(IOHIDDeviceRef)device {
    if (_isSystemSleeping) return;
    if (![self isTargetDevice:device]) return;
    
    NSString *name = [self getProductName:device];
    NSLog(@"[DeviceWatcher] 检测到目标设备已连接: %@", name);
    
    if (!_isTargetConnected) {
        _isTargetConnected = YES;
        _lastChangeTime = [[NSDate date] timeIntervalSince1970];
        NSLog(@"[DeviceWatcher] 确认目标设备已连回 Mac，触发切回 Mac (Type-C)！");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            if (self.onStateChanged) {
                self.onStateChanged(YES, name);
            }
        });
    }
}

- (void)onDeviceRemoved:(IOHIDDeviceRef)device {
    if (_isSystemSleeping) return;
    if (![self isTargetDevice:device]) return;
    
    NSString *name = [self getProductName:device];
    NSLog(@"[DeviceWatcher] 检测到目标设备已断开: %@", name);
    
    if (_isTargetConnected) {
        _isTargetConnected = NO;
        _lastChangeTime = [[NSDate date] timeIntervalSince1970];
        NSLog(@"[DeviceWatcher] 确认目标设备已切离 Mac，立即触发切往 Windows (DP)！");
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            if (self.onStateChanged) {
                self.onStateChanged(NO, name);
            }
        });
    }
}

@end
