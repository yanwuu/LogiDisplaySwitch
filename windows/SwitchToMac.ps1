# LogiDisplaySwitch - Windows 端免依赖 DDC/CI 切屏脚本
param(
    [int]$InputCode = 27 # 默认 27 (Type-C)
)

$Source = @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

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
"@

try {
    Add-Type -TypeDefinition $Source -Language CSharp
} catch {
}

[MonitorController]::SwitchInput($InputCode)
