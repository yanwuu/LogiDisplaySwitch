<#
    LogiSync.ps1 - Windows 端罗技鼠标跟随键盘专用极速联动服务
    架构设计:
      - 显示器切源: 由键盘与 Mac 联动全权负责 (键盘切离 Mac 切 DP，键盘连回 Mac 切 Type-C)
      - Windows 核心使命: 专职负责让 MX Master 3 鼠标跟随键盘通道 (键盘回 Mac 时鼠标毫秒级切回 Mac)
      - 彻底移除 Windows 端对显示器的软控，杜绝切屏回弹与误切
#>
param(
    [switch]$Test,
    [switch]$Watch,
    [switch]$SwitchToMac,
    [int]$TargetMouseChannel = 1
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.IO;
using System.Threading.Tasks;
using System.Threading;

public class LogiController {
    const int  DIGCF_PRESENT = 0x02, DIGCF_DEVICEINTERFACE = 0x10;
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_RW = 0x03, OPEN_EXISTING = 3, FILE_FLAG_OVERLAPPED = 0x40000000;
    const int  HIDP_STATUS_SUCCESS = 0x00110000;

    [StructLayout(LayoutKind.Sequential)]
    struct GUID { public uint a; public ushort b, c; [MarshalAs(UnmanagedType.ByValArray, SizeConst=8)] public byte[] d; }

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public GUID guid; public int flags; public IntPtr reserved; }

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct SP_DEVICE_INTERFACE_DETAIL_DATA_W {
        public int cbSize;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=512)] public string DevicePath;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDD_ATTRIBUTES { public int Size; public ushort Vid, Pid, Ver; }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS {
        public ushort Usage, UsagePage, InputLen, OutputLen, FeatureLen;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] Reserved;
        public ushort LinkNodes, InBtn, InVal, InIdx, OutBtn, OutVal, OutIdx, FtBtn, FtVal, FtIdx;
    }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(ref GUID g);
    [DllImport("hid.dll")] static extern bool HidD_GetAttributes(SafeFileHandle h, ref HIDD_ATTRIBUTES a);
    [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr pp);
    [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr pp);
    [DllImport("hid.dll")] static extern int  HidP_GetCaps(IntPtr pp, ref HIDP_CAPS c);
    [DllImport("hid.dll", CharSet=CharSet.Unicode)] static extern bool HidD_GetProductString(SafeFileHandle h, char[] buf, int len);

    [DllImport("setupapi.dll", CharSet=CharSet.Unicode)]
    static extern IntPtr SetupDiGetClassDevsW(ref GUID g, IntPtr e, IntPtr w, int f);
    [DllImport("setupapi.dll")]
    static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref GUID g, int i, ref SP_DEVICE_INTERFACE_DATA a);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode)]
    static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr s, ref SP_DEVICE_INTERFACE_DATA a, ref SP_DEVICE_INTERFACE_DETAIL_DATA_W d, int size, IntPtr req, IntPtr info);
    [DllImport("setupapi.dll")]
    static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFileW(string path, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll")]
    public static extern uint GetTickCount();

    // 获取距离上一次用户在 Windows 上打字或移动鼠标的毫秒数
    public static uint GetIdleTimeMs() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (GetLastInputInfo(ref lii)) {
            uint now = GetTickCount();
            if (now >= lii.dwTime) return now - lii.dwTime;
        }
        return 0;
    }

    public class HidIface {
        public string Path;
        public ushort UsagePage, Usage, Pid, InLen, OutLen;
    }

    public static List<HidIface> GetUnifyingInterfaces() {
        var list = new List<HidIface>();
        var guid = new GUID();
        HidD_GetHidGuid(ref guid);
        IntPtr set = SetupDiGetClassDevsW(ref guid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        try {
            var did = new SP_DEVICE_INTERFACE_DATA();
            did.cbSize = Marshal.SizeOf(did);
            for (int i = 0; SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref did); i++) {
                var detail = new SP_DEVICE_INTERFACE_DETAIL_DATA_W();
                detail.cbSize = IntPtr.Size == 8 ? 8 : 6;
                if (!SetupDiGetDeviceInterfaceDetailW(set, ref did, ref detail, Marshal.SizeOf(detail), IntPtr.Zero, IntPtr.Zero)) continue;

                using (var h = CreateFileW(detail.DevicePath, 0, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero)) {
                    if (h.IsInvalid) continue;
                    var attrs = new HIDD_ATTRIBUTES(); attrs.Size = Marshal.SizeOf(attrs);
                    if (!HidD_GetAttributes(h, ref attrs) || attrs.Vid != 0x046D) continue;

                    IntPtr pp;
                    if (!HidD_GetPreparsedData(h, out pp)) continue;
                    var caps = new HIDP_CAPS();
                    HidP_GetCaps(pp, ref caps);
                    HidD_FreePreparsedData(pp);

                    if (caps.UsagePage >= 0xFF00 && caps.OutputLen >= 20) {
                        list.Add(new HidIface {
                            Path = detail.DevicePath,
                            UsagePage = caps.UsagePage,
                            Usage = caps.Usage,
                            Pid = attrs.Pid,
                            InLen = caps.InputLen,
                            OutLen = caps.OutputLen
                        });
                    }
                }
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
        return list;
    }

    // 毫秒级极速切鼠标 (优先瞬发 MX Master 3 槽位 0x04 与 0x02，严格杜绝下发键盘 0x01)
    public static int SwitchDevices(int targetChannel) {
        byte hostVal = (byte)(targetChannel - 1);
        int successCount = 0;
        var ifaces = GetUnifyingInterfaces();

        foreach (var iface in ifaces) {
            try {
                using (var h = CreateFileW(iface.Path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero)) {
                    if (h.IsInvalid) continue;
                    using (var stream = new FileStream(h, FileAccess.ReadWrite, 1, true)) {
                        int outLen = iface.OutLen;
                        if (outLen < 20) continue;

                        // 1. 第一拍极速直发目标鼠标 MX Master 3 (通常为槽位 0x04 或 0x02)，0 延迟下发！
                        // 注意: 绝不包含 0x01 (键盘)！键盘是唯一物理主控，严禁软件倒切键盘导致切屏回弹！
                        byte[] prioritySlots = new byte[] { 0x04, 0x02 };
                        foreach (byte slot in prioritySlots) {
                            byte[] frame = new byte[outLen];
                            frame[0] = 0x11;
                            frame[1] = slot;
                            frame[2] = 0x09; // Feature 0x09 (ChangeHost)
                            frame[3] = (byte)((1 << 4) | 0x0A);
                            frame[4] = hostVal;
                            try {
                                stream.Write(frame, 0, outLen);
                                successCount++;
                            } catch {}
                        }

                        // 2. 第二拍冗余补发鼠标候选槽位 (绝不包含 0x01 键盘槽位)
                        byte[] mouseSlots = new byte[] { 0x04, 0x02, 0x03, 0x05 };
                        byte[] feats = new byte[] { 0x09, 0x08, 0x0A, 0x07 };
                        foreach (byte slot in mouseSlots) {
                            foreach (byte feat in feats) {
                                byte[] frame = new byte[outLen];
                                frame[0] = 0x11;
                                frame[1] = slot;
                                frame[2] = feat;
                                frame[3] = (byte)((1 << 4) | 0x0A);
                                frame[4] = hostVal;
                                try {
                                    stream.Write(frame, 0, outLen);
                                    successCount++;
                                    Thread.Sleep(10);
                                } catch {}
                            }
                        }
                    }
                }
            } catch {}
        }
        return successCount;
    }

    // 监测键盘 (槽位 0x01) 是否在当前 Windows 接收器上在线
    public static bool CheckKeyboardOnline() {
        var ifaces = GetUnifyingInterfaces();
        foreach (var iface in ifaces) {
            try {
                using (var h = CreateFileW(iface.Path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero)) {
                    if (h.IsInvalid) continue;
                    using (var stream = new FileStream(h, FileAccess.ReadWrite, 1, true)) {
                        int outLen = iface.OutLen;
                        int inLen = iface.InLen;
                        if (outLen < 20 || inLen < 5) continue;

                        byte[] frame = new byte[outLen];
                        frame[0] = 0x11;
                        frame[1] = 0x01; // MX Keys 槽位 1
                        frame[2] = 0x00; // Root Feature
                        frame[3] = (byte)((0 << 4) | 0x0A);
                        frame[4] = 0x18;
                        frame[5] = 0x14; // Feature 0x1814 (ChangeHost)

                        // 尝试最多 2 次查询 (每次 300ms 超时)，消除无线丢包或键盘浅度省电唤醒延迟
                        for (int attempt = 0; attempt < 2; attempt++) {
                            try {
                                stream.Write(frame, 0, outLen);
                            } catch { continue; }

                            byte[] buf = new byte[inLen];
                            var task = stream.ReadAsync(buf, 0, inLen);
                            if (Task.WaitAny(new Task[] { task }, 300) == 0 && !task.IsFaulted && task.Result > 0) {
                                if (buf.Length >= 5 && buf[1] == 0x01 && buf[2] == 0x00 && buf[4] != 0) {
                                    return true;
                                }
                            }
                            Thread.Sleep(40);
                        }
                    }
                }
            } catch {}
        }
        return false;
    }
}
'@

# 测试入口
if ($Test) {
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  LogiSync 鼠标切通道测试模式' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    $idle = [LogiController]::GetIdleTimeMs()
    Write-Host "当前 Windows 键鼠空闲时间: $idle ms" -ForegroundColor White
    $isOnline = [LogiController]::CheckKeyboardOnline()
    Write-Host "MX Keys 键盘在 Win 在线状态: $isOnline" -ForegroundColor White
    Write-Host ''
    Write-Host '正在将 MX Master 3 鼠标切回通道 1 (Mac)...' -ForegroundColor Yellow
    $cnt = [LogiController]::SwitchDevices(1)
    Write-Host "   [+] 切换数据包发送完毕 (共发送 $cnt 次)！请观察 MX Master 3 指示灯是否跳至 1." -ForegroundColor Green
    Write-Host ''
    Write-Host '测试完成。' -ForegroundColor Cyan
    exit 0
}

# 快捷单次切鼠标回 Mac
if ($SwitchToMac) {
    [LogiController]::SwitchDevices(1) | Out-Null
    exit 0
}

# 后台静默守护进程: 纯鼠标通道跟随守护
if ($Watch) {
    $isArmed = $false
    $onlineStreak = 0
    $offlineStreak = 0

    while ($true) {
        Start-Sleep -Milliseconds 300
        try {
            $idleMs = [LogiController]::GetIdleTimeMs()

            # 1. 如果用户近期 (2秒内) 在 Windows 上有按键或鼠标移动，代表正在正常使用 Windows，绝对锁定不切
            if ($idleMs -lt 2000) {
                $offlineStreak = 0
                $onlineStreak++
                if (-not $isArmed -and $onlineStreak -ge 3) {
                    $isArmed = $true
                }
                continue
            }

            # 2. 用户手已停下 > 2秒，探测键盘是否已真正离开当前 Windows
            $isKbdOnline = [LogiController]::CheckKeyboardOnline()

            if ($isKbdOnline) {
                $onlineStreak++
                $offlineStreak = 0
                if (-not $isArmed -and $onlineStreak -ge 3) {
                    $isArmed = $true
                }
            } else {
                $offlineStreak++
                $onlineStreak = 0

                # 键盘离线门槛:
                # 只有此前处于已布防状态 ($isArmed = $true，即键盘曾活跃在 Win)
                # 并且连续检测 4 次（每次含 2 次重试与 300ms 间隔，共约 2 秒多持续离线），才认定键盘切走
                $neededStreak = 4

                if ($isArmed -and $offlineStreak -ge $neededStreak) {
                    # 确认键盘已切回 Mac！立即同步将 MX Master 3 鼠标切回通道 1 (Mac)
                    [LogiController]::SwitchDevices(1) | Out-Null

                    # 退出布防，进入 4 秒冷静期 (等待键盘重新切回 Windows)
                    $isArmed = $false
                    $offlineStreak = 0
                    $onlineStreak = 0
                    Start-Sleep -Milliseconds 4000
                }
            }
        } catch {
            Start-Sleep -Milliseconds 1000
        }
    }
}
