#ifndef DeviceWatcher_h
#define DeviceWatcher_h

#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>

typedef void (^DeviceStateChangeBlock)(BOOL isConnected, NSString *deviceName);

@interface DeviceWatcher : NSObject

@property (nonatomic, copy) NSString *targetDevicePattern;
@property (nonatomic, copy) DeviceStateChangeBlock onStateChanged;
@property (nonatomic, readonly) BOOL isTargetConnected;

- (instancetype)initWithTargetPattern:(NSString *)pattern;
- (void)startWatching;
- (void)stopWatching;
- (BOOL)checkCurrentState;

@end

#endif /* DeviceWatcher_h */
