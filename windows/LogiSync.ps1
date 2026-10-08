<#
    LogiSync.ps1 - Windows 端罗技鼠标跟随键盘专用极速联动服务 (双引擎版)
    架构设计:
      - 引擎 1 (主引擎): 局域网 UDP 瞬发接收 (监听 52417 端口)，Mac 切回时 0ms 瞬时联动切鼠标
      - 引擎 2 (辅引擎): 本地智能 HID++ 槽位自识别 (MX Keys 与 MX Master 3) + 键盘在线探针
      - 核心铁律: 绝对不下发键盘槽位 (杜绝切屏回弹)，解除鼠标晃动对看门狗的死锁
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
using System.Net;
using System.Net.Sockets;
using System.Text;

public class LogiController {
    const int  DIGCF_PRESENT = 0x02, DIGCF_DEVICEINTERFACE = 0x10;
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_RW = 0x03, OPEN_EXISTING = 3, FILE_FLAG_OVERLAPPED = 0x40000000;

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
        public string ProdName;
        public ushort UsagePage, Usage, Pid, InLen, OutLen;
    }

    public static byte CachedKbdSlot = 0x01;
    public static byte CachedMouseSlot = 0x02;
    public static string DetectedKbdName = "";
    public static string DetectedMouseName = "";
    public static DateTime LastUdpSwitch = DateTime.MinValue;

    private static UdpClient _udpListener = null;
    private static Thread _udpThread = null;
    private static bool _udpRunning = false;

    public static void StartUdpListener() {
        if (_udpRunning) return;
        _udpRunning = true;
        _udpThread = new Thread(() => {
            try {
                _udpListener = new UdpClient();
                _udpListener.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
                _udpListener.Client.Bind(new IPEndPoint(IPAddress.Any, 52417));
                _udpListener.EnableBroadcast = true;
                IPEndPoint remoteEP = new IPEndPoint(IPAddress.Any, 0);
                while (_udpRunning) {
                    byte[] data = _udpListener.Receive(ref remoteEP);
                    if (data != null && data.Length > 0) {
                        string msg = Encoding.ASCII.GetString(data);
                        if (msg.StartsWith("LOGI:SWITCH_TO_MAC")) {
                            if ((DateTime.UtcNow - LastUdpSwitch).TotalSeconds > 2.0) {
                                LastUdpSwitch = DateTime.UtcNow;
                                Console.WriteLine("[LogiSync] 收到 Mac 局域网 UDP 瞬发切鼠指令！立即将鼠标切回 Mac (通道 1)...");
                                SwitchDevices(1);
                            }
                        }
                    }
                }
            } catch {}
        });
        _udpThread.IsBackground = true;
        _udpThread.Start();
    }

    public static void StopUdpListener() {
        _udpRunning = false;
        if (_udpListener != null) {
            try { _udpListener.Close(); } catch {}
            _udpListener = null;
        }
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
                        char[] prodBuf = new char[128];
                        string prodName = "";
                        if (HidD_GetProductString(h, prodBuf, 128)) {
                            prodName = new string(prodBuf).TrimEnd('\0').Trim();
                        }
                        list.Add(new HidIface {
                            Path = detail.DevicePath,
                            ProdName = prodName,
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

    public static void DetectDevices() {
        var ifaces = GetUnifyingInterfaces();
        byte[] probeSlots = new byte[] { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0xFF };

        foreach (var iface in ifaces) {
            string lowerIface = iface.ProdName.ToLower();
            if (lowerIface.Contains("key") || lowerIface.Contains("craft")) {
                DetectedKbdName = iface.ProdName;
            }
            if (lowerIface.Contains("master") || lowerIface.Contains("mouse") || lowerIface.Contains("anywhere")) {
                DetectedMouseName = iface.ProdName;
            }

            try {
                using (var h = CreateFileW(iface.Path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero)) {
                    if (h.IsInvalid) continue;
                    using (var stream = new FileStream(h, FileAccess.ReadWrite, 1, true)) {
                        int outLen = iface.OutLen;
                        int inLen = iface.InLen;
                        if (outLen < 20 || inLen < 5) continue;

                        foreach (byte s in probeSlots) {
                            byte[] frame = new byte[outLen];
                            frame[0] = 0x11;
                            frame[1] = s;
                            frame[2] = 0x00; // Root
                            frame[3] = 0x00; // getFeature
                            frame[4] = 0x00;
                            frame[5] = 0x05; // 0x0005: DEVICE_NAME
                            try { stream.Write(frame, 0, outLen); } catch { continue; }

                            byte[] buf = new byte[inLen];
                            var task = stream.ReadAsync(buf, 0, inLen);
                            if (Task.WaitAny(new Task[] { task }, 100) == 0 && !task.IsFaulted && task.Result > 0) {
                                if (buf.Length >= 5 && buf[1] == s && buf[2] == 0x00 && buf[4] != 0) {
                                    byte nameFeat = buf[4];
                                    byte[] nameReq = new byte[outLen];
                                    nameReq[0] = 0x11;
                                    nameReq[1] = s;
                                    nameReq[2] = nameFeat;
                                    nameReq[3] = (byte)((1 << 4) | 0x0A); // getDeviceName
                                    nameReq[4] = 0x00;
                                    try { stream.Write(nameReq, 0, outLen); } catch { continue; }

                                    byte[] nameBuf = new byte[inLen];
                                    var nameTask = stream.ReadAsync(nameBuf, 0, inLen);
                                    if (Task.WaitAny(new Task[] { nameTask }, 100) == 0 && !nameTask.IsFaulted && nameTask.Result > 0) {
                                        string devName = "";
                                        for (int b = 5; b < nameBuf.Length && nameBuf[b] != 0; b++) {
                                            devName += (char)nameBuf[b];
                                        }
                                        devName = devName.Trim();
                                        string lower = devName.ToLower();
                                        if (lower.Contains("key") || lower.Contains("craft") || lower.Contains("k38") || lower.Contains("k78") || lower.Contains("k85")) {
                                            CachedKbdSlot = s;
                                            DetectedKbdName = devName;
                                        } else if (lower.Contains("master") || lower.Contains("mouse") || lower.Contains("anywhere") || lower.Contains("lift") || lower.Contains("m72")) {
                                            CachedMouseSlot = s;
                                            DetectedMouseName = devName;
                                        }
                                    }
                                }
                            }
                            Thread.Sleep(15);
                        }
                    }
                }
            } catch {}
        }
    }

    public static int SwitchDevices(int targetChannel) {
        byte hostVal = (byte)(targetChannel - 1);
        int successCount = 0;
        var ifaces = GetUnifyingInterfaces();

        // 构造候选鼠标槽位列表:
        // 包含 0xFF (蓝牙/直连), CachedMouseSlot, 0x04, 0x02, 0x03, 0x05, 0x01
        // 严格排除: CachedKbdSlot (绝对不下发键盘槽位，防止键盘倒切回弹)
        List<byte> slotsToSend = new List<byte>();
        slotsToSend.Add(0xFF);
        if (CachedMouseSlot != 0 && CachedMouseSlot != CachedKbdSlot && !slotsToSend.Contains(CachedMouseSlot)) {
            slotsToSend.Add(CachedMouseSlot);
        }
        byte[] defaults = new byte[] { 0x04, 0x02, 0x03, 0x05, 0x01 };
        foreach (byte s in defaults) {
            if (s != CachedKbdSlot && !slotsToSend.Contains(s)) {
                slotsToSend.Add(s);
            }
        }

        byte[] feats = new byte[] { 0x09, 0x08, 0x0A, 0x07 };

        foreach (var iface in ifaces) {
            string lowerIface = iface.ProdName.ToLower();
            if (lowerIface.Contains("key") || lowerIface.Contains("craft")) continue;

            try {
                using (var h = CreateFileW(iface.Path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero)) {
                    if (h.IsInvalid) continue;
                    using (var stream = new FileStream(h, FileAccess.ReadWrite, 1, true)) {
                        int outLen = iface.OutLen;
                        if (outLen < 20) continue;

                        foreach (byte slot in slotsToSend) {
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
                                    Thread.Sleep(5);
                                } catch {}
                            }
                        }
                    }
                }
            } catch {}
        }
        return successCount;
    }

    public static bool CheckKeyboardOnline() {
        var ifaces = GetUnifyingInterfaces();
        byte targetKbd = CachedKbdSlot != 0 ? CachedKbdSlot : (byte)0x01;

        foreach (var iface in ifaces) {
            string lowerIface = iface.ProdName.ToLower();
            if (lowerIface.Contains("master") || lowerIface.Contains("mouse") || lowerIface.Contains("anywhere")) continue;

            try {
                using (var h = CreateFileW(iface.Path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero)) {
                    if (h.IsInvalid) continue;
                    using (var stream = new FileStream(h, FileAccess.ReadWrite, 1, true)) {
                        int outLen = iface.OutLen;
                        int inLen = iface.InLen;
                        if (outLen < 20 || inLen < 5) continue;

                        byte[] frame = new byte[outLen];
                        frame[0] = 0x11;
                        frame[1] = targetKbd;
                        frame[2] = 0x00; // Root Feature
                        frame[3] = (byte)((0 << 4) | 0x0A);
                        frame[4] = 0x18;
                        frame[5] = 0x14; // Feature 0x1814 (ChangeHost)

                        for (int attempt = 0; attempt < 2; attempt++) {
                            try {
                                stream.Write(frame, 0, outLen);
                            } catch { continue; }

                            byte[] buf = new byte[inLen];
                            var task = stream.ReadAsync(buf, 0, inLen);
                            if (Task.WaitAny(new Task[] { task }, 250) == 0 && !task.IsFaulted && task.Result > 0) {
                                if (buf.Length >= 5 && buf[1] == targetKbd && buf[2] == 0x00 && buf[4] != 0) {
                                    return true;
                                }
                            }
                            Thread.Sleep(30);
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
    Write-Host '  LogiSync 罗技键鼠槽位与联动测试模式' -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '正在探测当前连接的罗技硬件与槽位...' -ForegroundColor Yellow
    [LogiController]::DetectDevices()
    
    $kbdName = if ([LogiController]::DetectedKbdName) { [LogiController]::DetectedKbdName } else { "默认槽位" }
    $mouseName = if ([LogiController]::DetectedMouseName) { [LogiController]::DetectedMouseName } else { "默认槽位" }
    
    Write-Host "  [+] 键盘槽位: Slot 0x$([LogiController]::CachedKbdSlot.ToString('X2')) ($kbdName)" -ForegroundColor Green
    Write-Host "  [+] 鼠标槽位: Slot 0x$([LogiController]::CachedMouseSlot.ToString('X2')) ($mouseName)" -ForegroundColor Green
    Write-Host ''
    
    $idle = [LogiController]::GetIdleTimeMs()
    Write-Host "当前 Windows 键鼠空闲时间: $idle ms" -ForegroundColor White
    $isOnline = [LogiController]::CheckKeyboardOnline()
    Write-Host "键盘在 Windows 在线状态: $isOnline" -ForegroundColor White
    Write-Host ''
    
    Write-Host '正在测试将鼠标切换至通道 1 (Mac)...' -ForegroundColor Yellow
    $cnt = [LogiController]::SwitchDevices(1)
    Write-Host "  [+] 指令已下发完毕 (成功发送 $cnt 次数据包)！" -ForegroundColor Green
    Write-Host '  [+] 请观察 MX Master 3 鼠标指示灯是否跳至 1.' -ForegroundColor Green
    Write-Host ''
    Write-Host '测试完成。' -ForegroundColor Cyan
    exit 0
}

# 快捷单次切鼠标回 Mac
if ($SwitchToMac) {
    [LogiController]::DetectDevices()
    [LogiController]::SwitchDevices(1) | Out-Null
    exit 0
}

# 后台静默守护进程: 双引擎键鼠联动守护
if ($Watch) {
    # 1. 启动局域网 UDP 极速监听引擎 (Mac 切回时 0ms 瞬发响应)
    [LogiController]::StartUdpListener()

    # 2. 初始化硬件槽位自识别
    [LogiController]::DetectDevices()

    $isArmed = $false
    $onlineStreak = 0
    $offlineStreak = 0
    $detectCounter = 0

    while ($true) {
        Start-Sleep -Milliseconds 300
        try {
            $detectCounter++
            # 每隔约 60 秒刷新一次槽位探测，适应热插拔
            if ($detectCounter -gt 200) {
                $detectCounter = 0
                [LogiController]::DetectDevices()
            }

            # 探测键盘在线状态
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

                # 键盘离线判定:
                # 1. 键盘此前已在 Win 布防 ($isArmed = $true)
                # 2. 连续 2 次确认离线 (~500ms)
                # 3. 并且用户近期 (30秒内) 在当前电脑有活动 (避免用户挂机离开导致键盘休眠误切)
                $idleMs = [LogiController]::GetIdleTimeMs()
                if ($isArmed -and $offlineStreak -ge 2 -and $idleMs -lt 30000) {
                    # 检查是否最近 2 秒内刚被 UDP 切换过 (避免重复触发)
                    $lastUdpSec = ([DateTime]::UtcNow - [LogiController]::LastUdpSwitch).TotalSeconds
                    if ($lastUdpSec -gt 2.0) {
                        Write-Host "[LogiSync] 检测到键盘已切往 Mac，本地联动切换鼠标至通道 1..."
                        [LogiController]::SwitchDevices(1) | Out-Null
                    }

                    # 退出布防，进入 4 秒冷静期
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
