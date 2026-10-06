#import "DeviceWatcher.h"
#import <AppKit/AppKit.h>
#import <IOBluetooth/IOBluetooth.h>

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

- (BOOL)isBluetoothTargetConnected {
    NSArray *devices = [IOBluetoothDevice pairedDevices];
    for (IOBluetoothDevice *dev in devices) {
        if ([dev.name containsString:_targetDevicePattern]) {
            return [dev isConnected];
        }
    }
    return NO;
}

- (BOOL)checkCurrentState {
    BOOL connected = [self isBluetoothTargetConnected];
    _isTargetConnected = connected;
    return connected;
}

- (void)onDeviceAttached:(IOHIDDeviceRef)device {
    if (_isSystemSleeping) return;
    if (![self isTargetDevice:device]) return;
    
    NSString *name = [self getProductName:device];
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - _lastChangeTime < 2.5) {
        NSLog(@"[DeviceWatcher] 处于切换冷却期 (%.1fs < 2.5s)，忽略附着事件 [%@]", now - _lastChangeTime, name);
        return;
    }
    
    // 关键校验：必须通过 IOBluetooth 确认目标蓝牙物理链路确实在线！
    // 杜绝在 Windows 打字或休眠唤醒时，macOS BLE 产生偶发后台嗅探的幽灵伪连接事件
    if (![self isBluetoothTargetConnected]) {
        NSLog(@"[DeviceWatcher] 忽略伪挂载事件 [%@]: Bluetooth 物理链路并未连接", name);
        return;
    }
    
    NSLog(@"[DeviceWatcher] 检测到目标设备物理在线: %@", name);
    
    if (!_isTargetConnected) {
        // 二次确认防抖 (300ms 缓冲)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            if (![self isBluetoothTargetConnected]) {
                NSLog(@"[DeviceWatcher] 300ms 防抖未通过，忽略偶发连接信号");
                return;
            }
            NSTimeInterval innerNow = [[NSDate date] timeIntervalSince1970];
            if (innerNow - self->_lastChangeTime < 2.5) {
                NSLog(@"[DeviceWatcher] 冷却防抖未通过 (%.1fs < 2.5s)，忽略偶发连接信号", innerNow - self->_lastChangeTime);
                return;
            }
            if (!self->_isTargetConnected) {
                self->_isTargetConnected = YES;
                self->_lastChangeTime = [[NSDate date] timeIntervalSince1970];
                NSLog(@"[DeviceWatcher] 确认目标设备已稳定连回 Mac，触发切回 Mac (Type-C)！");
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    if (self.onStateChanged) {
                        self.onStateChanged(YES, name);
                    }
                });
            }
        });
    }
}

- (void)onDeviceRemoved:(IOHIDDeviceRef)device {
    if (_isSystemSleeping) return;
    if (![self isTargetDevice:device]) return;
    
    NSString *name = [self getProductName:device];
    NSLog(@"[DeviceWatcher] 检测到目标设备断开信号: %@", name);
    
    if (_isTargetConnected) {
        // 延时 200ms 确认是否物理断开 (避免多子接口注销顺序造成的误判)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            if ([self isBluetoothTargetConnected]) {
                NSLog(@"[DeviceWatcher] 目标设备仍在线，忽略子接口注销");
                return;
            }
            if (self->_isTargetConnected) {
                self->_isTargetConnected = NO;
                self->_lastChangeTime = [[NSDate date] timeIntervalSince1970];
                NSLog(@"[DeviceWatcher] 确认目标设备已真正切离 Mac，立即触发切往 Windows (DP)！");
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    if (self.onStateChanged) {
                        self.onStateChanged(NO, name);
                    }
                });
            }
        });
    }
}

@end
