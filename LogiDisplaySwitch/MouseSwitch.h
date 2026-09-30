#ifndef MouseSwitch_h
#define MouseSwitch_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// 将罗技 MX Master 3 等鼠标通过 HID++ 协议切换至指定通道 (1, 2, 3)
// 成功返回 true，未找到设备或失败返回 false
bool switchMouseToChannel(int channel);

#ifdef __cplusplus
}
#endif

#endif /* MouseSwitch_h */
