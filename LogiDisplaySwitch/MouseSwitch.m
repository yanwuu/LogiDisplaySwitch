#import "MouseSwitch.h"
#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>

#define LOGITECH_VID      0x046D
#define SW_ID             0x0A
#define REPORT_LONG       0x11

static int32_t prop_int(IOHIDDeviceRef dev, CFStringRef key) {
    CFTypeRef v = IOHIDDeviceGetProperty(dev, key);
    int32_t out = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)v, kCFNumberSInt32Type, &out);
    return out;
}

bool switchMouseToChannel(int channel) {
    if (channel < 1 || channel > 3) return false;

    uint8_t host = (uint8_t)(channel - 1);

    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!mgr) {
        NSLog(@"[MouseSwitch] ❌ IOHIDManagerCreate 失败");
        return false;
    }
    IOHIDManagerSetDeviceMatching(mgr, NULL);
    IOReturn mgrRet = IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
    if (mgrRet != kIOReturnSuccess) {
        NSLog(@"[MouseSwitch] ⚠️ IOHIDManagerOpen 状态: 0x%08x", mgrRet);
    }

    CFSetRef set = IOHIDManagerCopyDevices(mgr);
    if (!set) {
        NSLog(@"[MouseSwitch] ❌ 未扫描到任何 HID 设备");
        IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
        CFRelease(mgr);
        return false;
    }

    CFIndex count = CFSetGetCount(set);
    IOHIDDeviceRef *devices = (IOHIDDeviceRef *)calloc((size_t)count, sizeof(IOHIDDeviceRef));
    CFSetGetValues(set, (const void **)devices);

    bool switched = false;
    // MX Master 3 与常见罗技鼠标的 ChangeHost Feature Index 通常为 0x09，少数批次为 0x08 或 0x0A
    const uint8_t feat_candidates[] = { 0x09, 0x08, 0x0A, 0x07 };
    const uint8_t dev_candidates[]  = { 0xFF, 0x01, 0x02, 0x04 };

    for (CFIndex i = 0; i < count; i++) {
        IOHIDDeviceRef d = devices[i];
        int vid = prop_int(d, CFSTR(kIOHIDVendorIDKey));
        if (vid != LOGITECH_VID) continue;

        char name[128] = "";
        CFStringRef p = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductKey));
        if (p && CFGetTypeID(p) == CFStringGetTypeID())
            CFStringGetCString(p, name, sizeof(name), kCFStringEncodingUTF8);

        // 仅匹配鼠标设备（MX Master 3, MX Master, Anywhere 等）
        if (!strcasestr(name, "master") && !strcasestr(name, "mouse") && !strcasestr(name, "anywhere")) {
            continue;
        }

        NSLog(@"[MouseSwitch] 🔍 发现目标鼠标: [%s] (VID: 0x%04X)", name, vid);

        // 尝试打开单设备（若已由 Manager 打开则忽略错误，继续下发）
        IOReturn devOpenRet = IOHIDDeviceOpen(d, kIOHIDOptionsTypeNone);
        if (devOpenRet != kIOReturnSuccess) {
            NSLog(@"[MouseSwitch] ℹ️ IOHIDDeviceOpen [%s]: 0x%08x (由 Manager 统一托管，直接下发指令)", name, devOpenRet);
        }

        // 直接向鼠标下发 HID++ 2.0 ChangeHost (0x1814) 指令
        for (size_t f = 0; f < sizeof(feat_candidates); f++) {
            for (size_t dev_idx = 0; dev_idx < sizeof(dev_candidates); dev_idx++) {
                uint8_t frame[20];
                memset(frame, 0, sizeof(frame));
                frame[0] = REPORT_LONG;
                frame[1] = dev_candidates[dev_idx];
                frame[2] = feat_candidates[f];
                frame[3] = (uint8_t)((1 << 4) | SW_ID); // function 1 (setCurrentHost)
                frame[4] = host; // 0=Ch1, 1=Ch2, 2=Ch3

                IOReturn sret = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, REPORT_LONG, frame, 20);
                if (sret == kIOReturnSuccess) {
                    NSLog(@"[MouseSwitch] 🚀 成功向 [%s] 发送切通道指令 (feat=0x%02X, dev=0x%02X) -> 通道 %d (host=%d)！",
                          name, feat_candidates[f], dev_candidates[dev_idx], channel, host);
                    switched = true;
                }
            }
        }

        if (devOpenRet == kIOReturnSuccess) {
            IOHIDDeviceClose(d, kIOHIDOptionsTypeNone);
        }
    }

    free(devices);
    CFRelease(set);
    IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
    CFRelease(mgr);
    return switched;
}
