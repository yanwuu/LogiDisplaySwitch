#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

typedef CFTypeRef IOAVServiceRef;

#import "DisplayBridge.h"
#import "../m1ddc-src/library/libm1ddc.h"

static DisplayInfos gDisplays[MAX_DISPLAYS];
static CGDisplayCount gDisplayCount = 0;

static void refreshDisplays(void) {
    gDisplayCount = getOnlineDisplayInfos(gDisplays);
}

int getConnectedDisplayCount(void) {
    refreshDisplays();
    return (int)gDisplayCount;
}

const char* getDisplayName(int displayIndex) {
    refreshDisplays();
    if (displayIndex < 1 || displayIndex > (int)gDisplayCount) {
        return "Unknown";
    }
    NSString *name = gDisplays[displayIndex - 1].productName;
    return name ? [name UTF8String] : "Unknown";
}

int setDisplayInput(int displayIndex, int inputValue) {
    refreshDisplays();
    if (gDisplayCount == 0) {
        return -1;
    }
    int idx = (displayIndex >= 1 && displayIndex <= (int)gDisplayCount) ? (displayIndex - 1) : 0;
    DDCTransport transport = getDisplayDDCTransport(&gDisplays[idx]);
    if (!transport.service) {
        return -2;
    }
    
    DDCPacket packet = createDDCPacket(INPUT);
    prepareDDCWrite(&packet, (UInt16)inputValue);
    
    // 连续发送2次，间隔50ms，极大提高显示器硬件MCU对切源指令的接收率
    IOReturn err = performDDCWriteAtChipAddress(transport.service, transport.chipAddress, &packet);
    usleep(50000); // 50ms
    err = performDDCWriteAtChipAddress(transport.service, transport.chipAddress, &packet);
    
    return (err == kIOReturnSuccess) ? 0 : (int)err;
}
