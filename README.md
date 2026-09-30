# LogiDisplaySwitch 🖥️ 🖱️ ⌨️

**罗技键鼠与显示器双向无感联动切换系统 (macOS & Windows 双平台)**

> **一键按键盘，鼠标与显示器全自动同步联动！**  
> 告别将鼠标翻底盘摸盲按切换键，告别手动按显示器边框 OSD 菜单。零硬件 KVM 成本，打造丝滑的双机协作体验。

---

## 💡 痛点与诞生背景

在日常使用 **Mac + Windows 双电脑共用一台显示器** 和 **罗技 MX 系列键鼠（MX Keys + MX Master 3）** 的场景下：
1. **键盘切换很方便，但鼠标反人类**：
   - **MX Keys 键盘** 正面有清晰的 `1` / `2` / `3` Easy-Switch 键，单手一按即切。
   - **MX Master 3 鼠标** 的切换按键却设计在**鼠标底盘**，每次切换都要将鼠标翻过来按底部的通道键。
2. **显示器还需要手动切源**：
   - 键盘切过去后，还需要伸手去按显示器边框的物理 OSD 按钮，在 Type-C / DP / HDMI 之间反复切换。
3. **官方软件的局限性**：
   - **Logitech Flow**：依赖局域网，在公司 VPN、防火墙或不同网段下经常断连，且无法切换显示器物理输入源。
   - **Logi Options+ Enhanced Easy-Switch**：仅支持较新的 Logi Bolt 接收器设备，**不支持保有量极大的经典优联（Unifying）接收器**，且同样不支持控制显示器。

**LogiDisplaySwitch** 彻底解决了上述所有痛点：
- ⌨️ **在键盘按下 `2`（从 Mac 去 Windows）**：
  - Mac 后台瞬时向鼠标发送蓝牙 HID++ 指令，**MX Master 3 自动切至通道 2**；
  - 同时 Mac 原生调用 DDC/CI 向显示器发送指令，**屏幕自动切至 DP 输入源**！
- ⌨️ **在键盘按下 `1`（从 Windows 回 Mac）**：
  - 键盘蓝牙连回 Mac，Mac 原生内核监听瞬间触发，**屏幕自动切回 Type-C 输入源**；
  - 同时 Windows 后台监听到键盘切回 Mac，瞬间向优联接收器发送指令，**MX Master 3 自动切回通道 1**！
  - **极致纯粹架构**：显示器切源全权由键盘状态与 Mac 联动负责，Windows 专职切鼠标，彻底杜绝双端软控抢总线与切屏回弹！

---

## 🌟 核心技术亮点

- ⚡ **原生极致性能，零臃肿依赖**：
  - **macOS 端**：纯原生 Objective-C + IOKit / IOHIDManager 底层开发，无任何 Electron、Python 或第三方运行库依赖，常驻内存仅约 10MB。
  - **Windows 端**：单文件绿色架构，基于 Win32 API + C# 动态内存编译 + P/Invoke，无需安装任何额外运行时，无需管理员权限，后台静默守护，无黑框闪烁。
- 🖱️ **深度穿透 Logitech HID++ 2.0 协议**：
  - 直发底层 `ChangeHost`（Feature `0x1814`）功能码，切换响应时间 **< 5ms**。
  - **攻克优联/Bolt接收器常驻在线难题**：针对 USB 接收器物理常插导致操作系统无法感知无线设备离线的底层痛点，自主研发了基于射频心跳的槽位探测与双向握手防抖状态机，彻底消除切屏回弹黑屏。
- 📺 **全自动软控 DDC/CI 显示器切源**：
  - Mac 端原生兼容 Apple Silicon (M1/M2/M3/M4) 全系列架构的 DisplayServices / I2C 通信。
  - Windows 端基于微软官方 `dxva2.dll` 驱动层 API 控制 VCP 0x60 输入源寄存器。
- 🔕 **全自动开机自启**：
  - 双端均提供一键后台守护安装，开机自启无感运行。

---

## 🛠️ 推荐硬件连接拓扑

| 设备 | 通道 1 (Mac) | 通道 2 (Windows) |
| :--- | :--- | :--- |
| **MX Keys 键盘** | 蓝牙 (Bluetooth) | 优联 (Unifying) / Bolt 接收器 |
| **MX Master 3 鼠标** | 蓝牙 (Bluetooth) | 优联 (Unifying) / Bolt 接收器 |
| **显示器输入接口** | **Type-C** (VCP 值: 27) | **DisplayPort / DP** (VCP 值: 16) |

*(注：输入源数值可在配置中按需自定义，如 HDMI 通常为 17)*

---

## 🚀 快速上手使用

### 🍎 1. macOS 端安装与部署

1. 打开 Mac 终端，进入项目目录，运行一键安装：
   ```bash
   ./dist/LogiDisplaySwitch --install
   ```
2. **系统权限设置**：
   - 首次运行时 macOS 会弹出提示，请前往 `系统设置 -> 隐私与安全性 -> 辅助功能`，勾选允许 `LogiDisplaySwitch`。
3. **日常指令与手动控制**：
   ```bash
   # 查看当前键鼠与显示器状态
   ./dist/LogiDisplaySwitch --status

   # 手动测试切往 Windows (切鼠标通道 2 + 屏幕切 DP)
   ./dist/LogiDisplaySwitch --to-win

   # 手动测试切回 Mac (切鼠标通道 1 + 屏幕切 Type-C)
   ./dist/LogiDisplaySwitch --to-mac

   # 卸载后台开机自启
   ./dist/LogiDisplaySwitch --uninstall
   ```

---

### 🪟 2. Windows 端安装与部署 (单文件一键运行)

Windows 端已完全封装为**单个免安装绿色批处理文件**：`dist/LogiDisplaySwitch.bat`。

1. 将 `dist/LogiDisplaySwitch.bat` 复制到 Windows 电脑上任何位置。
2. 双击运行 `LogiDisplaySwitch.bat`：
   ```text
   ==============================================================
     LogiDisplaySwitch - 罗技键鼠显示器双向联动 (Windows 单文件版)
   ==============================================================

    [1] 一键安装并立即在后台静默运行 (开机自启, 无黑框) [推荐]
    [2] 立即测试切回 Mac (切鼠标1 + 切显示器Type-C)
    [3] 停止并卸载后台服务
   ```
3. **建议初次运行先输入 `2` 测试**：查看鼠标指示灯是否跳回 1、显示器是否切回 Mac。
4. 确认正常后，再次运行**直接敲回车（选择 1）**，程序将在后台静默自启守护，无黑框、免维护。

---

## 📁 代码工程架构

```text
.
├── LogiDisplaySwitch/                  # macOS 端原生源码 (Objective-C)
│   ├── main.m                          # 主控制入口、CLI 解析与守护调度
│   ├── MouseSwitch.h / .m              # IOKit HID++ 2.0 ChangeHost 鼠标硬件直切引擎
│   ├── MonitorSwitch.h / .m            # DDC/CI 屏幕切源调度
│   ├── DDC.h / .m                      # Apple Silicon / Intel 显卡 I2C DDC 通信协议实现
│   └── KeyboardWatcher.h / .m          # IOHIDManager 键盘切离高频硬件监听器
├── dist/                               # 编译打包成品
│   ├── LogiDisplaySwitch               # macOS 原生命令行二进制
│   ├── LogiDisplaySwitch.app           # macOS 原生 App 封装
│   ├── LogiDisplaySwitch.bat           # Windows 端纯 GBK 编码单文件一键免依赖运行包
│   └── LogiDiag.bat                    # Windows 端硬件槽位抓包与通信诊断工具
├── windows/                            # Windows 端核心引擎与脚本
│   ├── LogiSync.ps1                    # Windows 统一核心引擎 (HID++穿透 + DXVA2切屏 + 状态机)
│   ├── RunSilent.vbs                   # Windows 静默启动代理 (隐藏 CMD 窗口)
│   └── LogiDisplaySwitch.bat           # 包含 Base64 自解压安装逻辑的 Windows 引导脚本
├── package_mac.sh                      # macOS 端编译与打包发布脚本
├── LICENSE                             # 开源协议文件 (MIT)
└── README.md                           # 项目说明文档
```

---

## 🤝 致谢与引用的开源项目 (Acknowledgements)

本项目在研发过程中参考并引用了开源社区优秀项目与文档，向以下开源先驱致以由衷的敬意与感谢：

1. **[waydabber/m1ddc](https://github.com/waydabber/m1ddc)** (MIT License)
   - 作者：**waydabber**
   - 贡献：为 Apple Silicon (M1/M2/M3/M4) 架构提供了卓越的原生 DDC/CI 底层通讯实现，解决了 macOS 下免外部驱动软控显示器输入源的核心难题。
   - 参考路径：`m1ddc-src/` 与 `LogiDisplaySwitch/DDC.m`

2. **[marcocosta97/mxswitch](https://github.com/marcocosta97/mxswitch)** (MIT License)
   - 作者：**marcocosta97** (及早期贡献者 gh2o)
   - 贡献：提供了通过 Windows Win32 HID API (P/Invoke) 发送罗技 HID++ 2.0 `ChangeHost`（Feature `0x1814`）数据帧的基础思路与实现。
   - 参考路径：`mxswitch-src/`

3. **[pwr-Solaar/Solaar](https://github.com/pwr-Solaar/Solaar)** (GPLv2 License)
   - 作者：**Solaar 维护者团队**
   - 贡献：Linux 社区中最详尽的罗技无线协议逆向文档，其对优联接收器（Unifying）多设备配对槽位（Pairing Registers `0xB5`, `0x41`）以及 HID++ 2.0 报表结构的解析，为解决优联接收器多设备穿透识别提供了不可或缺的参考规范。

4. **[kfix/ddcctl](https://github.com/kfix/ddcctl)** (MIT License)
   - 作者：**kfix**
   - 贡献：早期 macOS DDC/CI 协议通信概念验证项目。

---

## 📜 开源协议

本项目采用 **[MIT License](LICENSE)** 开源协议。欢迎提交 Issue、PR，或者 Star ⭐️ 支持！
