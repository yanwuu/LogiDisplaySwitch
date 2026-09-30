
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.IO;
using System.Threading.Tasks;

public class LogiDiag {
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

    [DllImport("kernel32.dll")]
    static extern int GetLastError();

    public class CollectionInfo {
        public string Path, Product;
        public ushort UsagePage, Usage, Pid, InLen, OutLen;
        public int OpenError;
    }

    public static List<CollectionInfo> EnumerateAll() {
        var list = new List<CollectionInfo>();
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

                    var name = new char[128];
                    HidD_GetProductString(h, name, 256);

                    var item = new CollectionInfo {
                        Path = detail.DevicePath,
                        Product = new string(name).TrimEnd((char)0),
                        UsagePage = caps.UsagePage,
                        Usage = caps.Usage,
                        Pid = attrs.Pid,
                        InLen = caps.InputLen,
                        OutLen = caps.OutputLen
                    };

                    // Test opening for RW
                    using (var hRW = CreateFileW(detail.DevicePath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero)) {
                        if (hRW.IsInvalid) {
                            item.OpenError = Marshal.GetLastWin32Error();
                        }
                    }
                    list.Add(item);
                }
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
        return list;
    }

    public static string TestProbeAndSwitch(CollectionInfo info, int targetChannel) {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("=== 正在测试接口: " + info.Product + " (PID: 0x" + info.Pid.ToString("X4") + " outLen: " + info.OutLen + ") ===");
        if (info.OpenError != 0) {
            sb.AppendLine("[-] 打开失败! Win32 错误码: " + info.OpenError);
            return sb.ToString();
        }

        using (var h = CreateFileW(info.Path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero)) {
            if (h.IsInvalid) {
                sb.AppendLine("[-] 句柄无效! Win32 错误码: " + Marshal.GetLastWin32Error());
                return sb.ToString();
            }

            using (var stream = new FileStream(h, FileAccess.ReadWrite, 1, true)) {
                byte[] reportIds = (info.OutLen >= 20) ? new byte[] { 0x11, 0x10 } : new byte[] { 0x10 };
                byte[] didxList = new byte[] { 1, 2, 3, 4, 5, 6, 0xFF };

                foreach (byte didx in didxList) {
                    foreach (byte rid in reportIds) {
                        int frameLen = (rid == 0x11) ? 20 : 7;
                        if (frameLen > info.OutLen) continue;

                        // Query 0x1814 (ChangeHost)
                        byte[] q = new byte[info.OutLen];
                        q[0] = rid; q[1] = didx; q[2] = 0x00; q[3] = 0x0A; q[4] = 0x18; q[5] = 0x14;
                        try {
                            stream.Write(q, 0, info.OutLen);
                            stream.Flush();

                            // Read reply
                            byte[] inBuf = new byte[info.InLen > 0 ? info.InLen : 32];
                            var task = stream.ReadAsync(inBuf, 0, inBuf.Length);
                            if (Task.WaitAny(new Task[] { task }, 200) == 0 && !task.IsFaulted && task.Result > 0) {
                                sb.AppendLine(string.Format("  [+] 槽位 0x{0:X2} 有响应! rid=0x{1:X2} 特性索引: 0x{2:X2} (回包前5字节: {3:X2} {4:X2} {5:X2} {6:X2} {7:X2})",
                                    didx, rid, inBuf[4], inBuf[0], inBuf[1], inBuf[2], inBuf[3], inBuf[4]));

                                // Now test switching this slot to targetChannel!
                                byte feat = inBuf[4];
                                byte[] sw = new byte[info.OutLen];
                                sw[0] = rid; sw[1] = didx; sw[2] = feat; sw[3] = (byte)((1 << 4) | 0x0A); sw[4] = (byte)(targetChannel - 1);
                                stream.Write(sw, 0, info.OutLen);
                                stream.Flush();
                                sb.AppendLine(string.Format("      >>> 已向槽位 0x{0:X2} 发送切通道指令 (host={1})！", didx, targetChannel - 1));
                            }
                        } catch (Exception ex) {
                            sb.AppendLine("      异常: " + ex.Message);
                        }
                    }
                }
            }
        }
        return sb.ToString();
    }
}
'@

$logFile = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop\LogiSwitch_Report.txt")
$outLines = @()

$outLines += "=========================================================="
$outLines += "  LogiSwitch 罗技优联/Bolt接收器深度通信诊断报告"
$outLines += "  时间: " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$outLines += "=========================================================="
$outLines += ""

Write-Host "正在扫描所有罗技 HID 集合..." -ForegroundColor Yellow
$colls = [LogiDiag]::EnumerateAll()
$outLines += "发现 $($colls.Count) 个罗技 HID 通信接口:"

foreach ($c in $colls) {
    $infoStr = "  * PID: 0x$($c.Pid.ToString('X4')) | UsagePage: 0x$($c.UsagePage.ToString('X4')):0x$($c.Usage.ToString('X4')) | in: $($c.InLen) out: $($c.OutLen) | 产品: $($c.Product) | 打开状态: $(if ($c.OpenError -eq 0) { '成功' } else { '失败(错误码 ' + $c.OpenError + ')' })"
    Write-Host $infoStr -ForegroundColor Cyan
    $outLines += $infoStr
}

$outLines += ""
$outLines += "开始针对各个接口进行槽位穿透与切通道测试 (切至通道 1):"

foreach ($c in $colls) {
    if ($c.UsagePage -ge 0xFF00 -and $c.OutLen -ge 7) {
        $res = [LogiDiag]::TestProbeAndSwitch($c, 1)
        Write-Host $res -ForegroundColor White
        $outLines += $res
    }
}

$outLines += ""
$outLines += "=========================================================="
$outLines += "诊断测试完毕！请查看 MX Master 3 底部指示灯是否跳回 1。"
$outLines += "报告已保存在桌面: $logFile"
$outLines += "=========================================================="

$outLines | Set-Content $logFile -Encoding UTF8
Write-Host ""
Write-Host "[+] 完整诊断报告已生成在桌面: LogiSwitch_Report.txt" -ForegroundColor Green
Write-Host "请查看 MX Master 3 底部指示灯有没有跳回 1！" -ForegroundColor Yellow
