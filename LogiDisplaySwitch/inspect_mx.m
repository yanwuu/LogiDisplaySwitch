#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>

int main() {
    @autoreleasepool {
        IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        IOHIDManagerSetDeviceMatching(manager, NULL);
        IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
        
        CFSetRef deviceSet = IOHIDManagerCopyDevices(manager);
        if (deviceSet) {
            CFIndex count = CFSetGetCount(deviceSet);
            const void *values[count];
            CFSetGetValues(deviceSet, values);
            int mxCount = 0;
            for (CFIndex i = 0; i < count; i++) {
                IOHIDDeviceRef dev = (IOHIDDeviceRef)values[i];
                CFStringRef prop = IOHIDDeviceGetProperty(dev, CFSTR(kIOHIDProductKey));
                if (prop && [(__bridge NSString *)prop isEqualToString:@"MX Keys"]) {
                    mxCount++;
                    NSLog(@"MX Keys Handle [%d]: %p", mxCount, dev);
                }
            }
            NSLog(@"Total 'MX Keys' HID handles: %d", mxCount);
            CFRelease(deviceSet);
        }
        CFRelease(manager);
    }
    return 0;
}
