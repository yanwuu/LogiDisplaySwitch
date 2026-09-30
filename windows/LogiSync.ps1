<#
    LogiSync.ps1 - Windows 端罗技优联/Bolt键鼠显示器无感联动最终优化版
    硬件拓扑已锁定:
      - 键盘 MX Keys: 优联槽位 0x01 (Feature 0x09)
      - 鼠标 MX Master 3: 优联槽位 0x04 (Feature 0x09)
      - 通信接口: PID 0xC52B, UsagePage 0xFF00, outLen 20
#>
param(
    [switch]$Test,
    [switch]$Watch,
    [switch]$SwitchToMac,
    [int]$MacInput = 27,
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

    // 向鼠标(槽位 0x04)与键盘(槽位 0x01)以及其他所有槽位直接发送精准切通道指令
    public static int SwitchDevices(int targetChannel) {
        byte hostVal = (byte)(targetChannel - 1);
        int successCount = 0;
        var ifaces = GetUnifyingInterfaces();

        // 诊断明确查明:
        // 键盘 MX Keys: 槽位 0x01, ChangeHost Feature 0x09
        // 鼠标 MX Master 3: 槽位 0x04, ChangeHost Feature 0x09
        // 冗余探测槽位: 0x02, 0x03, 0x05, 0x06, 0xFF
        byte[] slots = new byte[] { 0x04, 0x01, 0x02, 0x03, 0x05, 0x06, 0xFF };
        byte[] feats = new byte[] { 0x09, 0x08, 0x0A };

        foreach (var iface in ifaces) {
            try {
                using (var h = CreateFileW(iface.Path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero)) {
                    if (h.IsInvalid) continue;
                    using (var stream = new FileStream(h, FileAccess.ReadWrite, 1, true)) {
                        int outLen = iface.OutLen;
                        byte[] frame = new byte[outLen];

                        foreach (byte didx in slots) {
                            foreach (byte feat in feats) {
                                Array.Clear(frame, 0, frame.Length);
                                frame[0] = 0x11; // Long Report ID
                                frame[1] = didx; // 设备槽位
                                frame[2] = feat; // 特性索引 (0x09)
                                frame[3] = (byte)((1 << 4) | 0x0A); // Function 1 (setHost), SW_ID 0x0A
                                frame[4] = hostVal; // 0=Mac, 1=Win

                                try {
                                    // 严禁调用 stream.Flush()，Windows HID 不支持 FlushFileBuffers
                                    stream.Write(frame, 0, outLen);
                                    successCount++;
                                    Thread.Sleep(30);
                                } catch {}
                            }
                        }
                    }
                }
            } catch {}
        }
        return successCount;
    }

    // 监测键盘 (槽位 0x01) 是否在线响应
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
                        frame[5] = 0x14;

                        try {
                            stream.Write(frame, 0, outLen);
                        } catch { return false; }

                        byte[] buf = new byte[inLen];
                        var task = stream.ReadAsync(buf, 0, inLen);
                        if (Task.WaitAny(new Task[] { task }, 150) == 0 && !task.IsFaulted && task.Result > 0) {
                            if (buf.Length >= 5 && buf[1] == 0x01 && buf[2] == 0x00 && buf[4] != 0) {
                                return true;
                            }
                        }
                    }
                }
            } catch {}
        }
        return false;
    }
}

public class MonitorController {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct PHYSICAL_MONITOR {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint pdwNumberOfPhysicalMonitors);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint dwPhysicalMonitorArraySize, [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool SetVCPFeature(IntPtr hMonitor, byte bVCPCode, uint dwNewValue);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool DestroyPhysicalMonitor(IntPtr hMonitor);

    public static bool SwitchInput(uint inputCode) {
        List<IntPtr> hMonitors = new List<IntPtr>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr hMon, IntPtr hdc, IntPtr rc, IntPtr data) {
            hMonitors.Add(hMon);
            return true;
        }, IntPtr.Zero);

        bool anySuccess = false;
        foreach (IntPtr hMon in hMonitors) {
            uint count = 0;
            if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, out count) && count > 0) {
                PHYSICAL_MONITOR[] phys = new PHYSICAL_MONITOR[count];
                if (GetPhysicalMonitorsFromHMONITOR(hMon, count, phys)) {
                    foreach (var p in phys) {
                        if (SetVCPFeature(p.hPhysicalMonitor, 0x60, inputCode)) {
                            anySuccess = true;
                        }
                        DestroyPhysicalMonitor(p.hPhysicalMonitor);
                    }
                }
            }
        }
        return anySuccess;
    }
}
'@

# 测试入口
if ($Test) {
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host '  LogiSync 诊断与测试模式 (硬件槽位直通版)' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '已根据硬件报告精准定位:' -ForegroundColor Green
    Write-Host '  * 键盘 MX Keys: 槽位 0x01, 特性通道 0x09' -ForegroundColor White
    Write-Host '  * 鼠标 MX Master 3: 槽位 0x04, 特性通道 0x09' -ForegroundColor White
    Write-Host ''
    Write-Host '1. 正在将 MX Master 3 鼠标切回通道 1 (Mac)...' -ForegroundColor Yellow
    $cnt = [LogiController]::SwitchDevices(1)
    Write-Host "   [+] 切换数据包发送完毕 (共发送 $cnt 次)！请观察 MX Master 3 指示灯是否跳至 1." -ForegroundColor Green

    Write-Host ''
    Write-Host "2. 正在将显示器切回 Mac (Type-C $MacInput)..." -ForegroundColor Yellow
    $dOk = [MonitorController]::SwitchInput($MacInput)
    if ($dOk) {
        Write-Host '   [+] 显示器 DDC/CI 切换指令发送成功!' -ForegroundColor Green
    } else {
        Write-Host '   [-] 显示器切换指令未收到 DDC/CI 确认，请检查显示器 OSD 菜单.' -ForegroundColor Red
    }

    Write-Host ''
    Write-Host '测试完成。' -ForegroundColor Cyan
    exit 0
}

# 快捷单次切回 Mac
if ($SwitchToMac) {
    [LogiController]::SwitchDevices(1) | Out-Null
    Start-Sleep -Milliseconds 120
    [MonitorController]::SwitchInput($MacInput) | Out-Null
    exit 0
}

# 后台静默守护进程
if ($Watch) {
    $isArmed = $false
    $onlineStreak = 0
    $offlineStreak = 0

    while ($true) {
        Start-Sleep -Milliseconds 450
        try {
            $isKbdOnline = [LogiController]::CheckKeyboardOnline()

            if ($isKbdOnline) {
                $onlineStreak++
                $offlineStreak = 0

                # 键盘在 Windows 稳定连接 2 秒以上激活布防
                if (-not $isArmed -and $onlineStreak -ge 4) {
                    $isArmed = $true
                }
            } else {
                $offlineStreak++
                $onlineStreak = 0

                # 在布防状态下，键盘连续 3 次离线确认（约1.3秒），触发切回 Mac
                if ($isArmed -and $offlineStreak -ge 3) {
                    # 1. 切鼠标回通道 1 (Mac)
                    [LogiController]::SwitchDevices(1) | Out-Null
                    Start-Sleep -Milliseconds 120
                    # 2. 切显示器回 Mac (Type-C)
                    [MonitorController]::SwitchInput($MacInput) | Out-Null

                    # 3. 退出警戒，进入冷静期
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
