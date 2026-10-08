#import <Cocoa/Cocoa.h>
#import "DisplayBridge.h"
#import "DeviceWatcher.h"
#import "MouseSwitch.h"
#import "NetSync.h"
#import "AppDelegate.h"

#define DEFAULT_TARGET_DEVICE   @"MX Keys"
#define DEFAULT_WIN_INPUT       16      // DisplayPort (ViewSonic VX2880-4K-HDU: 16)
#define DEFAULT_MAC_INPUT       27      // Type-C (ViewSonic VX2880-4K-HDU: 27)
#define LAUNCH_AGENT_LABEL      @"io.github.logidisplayswitch"

static void printUsage(const char *prog) {
    printf("LogiDisplaySwitch - 罗技键鼠联动显示器自动切换工具 (Mac + Win)\n\n");
    printf("用法:\n");
    printf("  %s [选项]\n\n", prog);
    printf("选项:\n");
    printf("  --gui                启动图形界面控制面板 (默认若双击启动)\n");
    printf("  --watch              启动纯命令行后台监听模式 (检测到键鼠切换时自动切屏)\n");
    printf("  --to-win, -w         立即将显示器切换到 Windows (DP 接口, 代码 %d)，并同步切鼠标\n", DEFAULT_WIN_INPUT);
    printf("  --to-mac, -m         立即将显示器切换到 Mac (Type-C 接口, 代码 %d)，并同步切鼠标\n", DEFAULT_MAC_INPUT);
    printf("  --mouse <channel>    立即将罗技鼠标 (MX Master 3) 切换至指定通道 (1, 2, 3)\n");
    printf("  --status, -s         查询当前显示器和罗技设备连接状态\n");
    printf("  --install            安装并开机自启后台守护服务 (LaunchAgent)\n");
    printf("  --uninstall          停止并卸载后台守护服务\n");
    printf("  --target <name>      指定要监听的设备名称关键字 (默认: %s)\n", [DEFAULT_TARGET_DEVICE UTF8String]);
    printf("  --win-input <num>    指定 Windows 输入源代码 (默认: %d)\n", DEFAULT_WIN_INPUT);
    printf("  --mac-input <num>    指定 Mac 输入源代码 (默认: %d)\n", DEFAULT_MAC_INPUT);
    printf("  --help, -h           显示帮助信息\n\n");
}

static void printStatus(NSString *targetPattern) {
    printf("================ 硬件连接状态 ================\n");
    int count = getConnectedDisplayCount();
    printf("已检测到的显示器数量: %d\n", count);
    for (int i = 1; i <= count; i++) {
        printf("  [%d] %s\n", i, getDisplayName(i));
    }
    
    DeviceWatcher *watcher = [[DeviceWatcher alloc] initWithTargetPattern:targetPattern];
    [watcher startWatching];
    BOOL connected = [watcher checkCurrentState];
    printf("目标设备 [%s] 当前状态: %s\n",
           [targetPattern UTF8String],
           connected ? "已连接 (当前在 Mac)" : "未连接 / 已切到其他电脑");
    [watcher stopWatching];
    printf("==============================================\n");
}

static void installLaunchAgent(const char *binaryPath, NSString *target, int winIn, int macIn) {
    NSString *homeDir = NSHomeDirectory();
    NSString *agentDir = [homeDir stringByAppendingPathComponent:@"Library/LaunchAgents"];
    [[NSFileManager defaultManager] createDirectoryAtPath:agentDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *plistPath = [agentDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", LAUNCH_AGENT_LABEL]];
    NSString *logPath = [homeDir stringByAppendingPathComponent:@"Library/Logs/LogiDisplaySwitch.log"];
    
    NSString *plistContent = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"
        @"<dict>\n"
        @"    <key>Label</key>\n"
        @"    <string>%@</string>\n"
        @"    <key>ProgramArguments</key>\n"
        @"    <array>\n"
        @"        <string>%s</string>\n"
        @"        <string>--watch</string>\n"
        @"        <string>--target</string>\n"
        @"        <string>%@</string>\n"
        @"        <string>--win-input</string>\n"
        @"        <string>%d</string>\n"
        @"        <string>--mac-input</string>\n"
        @"        <string>%d</string>\n"
        @"    </array>\n"
        @"    <key>RunAtLoad</key>\n"
        @"    <true/>\n"
        @"    <key>KeepAlive</key>\n"
        @"    <true/>\n"
        @"    <key>LimitLoadToSessionType</key>\n"
        @"    <string>Aqua</string>\n"
        @"    <key>ProcessType</key>\n"
        @"    <string>Interactive</string>\n"
        @"    <key>StandardOutPath</key>\n"
        @"    <string>%@</string>\n"
        @"    <key>StandardErrorPath</key>\n"
        @"    <string>%@</string>\n"
        @"</dict>\n"
        @"</plist>\n",
        LAUNCH_AGENT_LABEL, binaryPath, target, winIn, macIn, logPath, logPath];
        
    NSError *error = nil;
    [plistContent writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        printf("写入 LaunchAgent 失败: %s\n", [[error localizedDescription] UTF8String]);
        return;
    }
    
    system([[NSString stringWithFormat:@"launchctl unload \"%@\" 2>/dev/null", plistPath] UTF8String]);
    system([[NSString stringWithFormat:@"launchctl load \"%@\"", plistPath] UTF8String]);
    
    printf("✅ 成功安装开机自启后台守护进程！\n");
    printf("   配置文件: %s\n", [plistPath UTF8String]);
    printf("   日志输出: %s\n", [logPath UTF8String]);
}

static void uninstallLaunchAgent() {
    NSString *homeDir = NSHomeDirectory();
    NSString *plistPath = [homeDir stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"Library/LaunchAgents/%@.plist", LAUNCH_AGENT_LABEL]];
                           
    system([[NSString stringWithFormat:@"launchctl unload \"%@\" 2>/dev/null", plistPath] UTF8String]);
    [[NSFileManager defaultManager] removeItemAtPath:plistPath error:nil];
    printf("✅ 已停止并卸载后台服务：%s\n", [LAUNCH_AGENT_LABEL UTF8String]);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *targetDevice = DEFAULT_TARGET_DEVICE;
        int winInput = DEFAULT_WIN_INPUT;
        int macInput = DEFAULT_MAC_INPUT;
        BOOL doWatch = NO;
        BOOL doStatus = NO;
        BOOL doToWin = NO;
        BOOL doToMac = NO;
        BOOL doInstall = NO;
        BOOL doUninstall = NO;
        BOOL doGui = NO;
        int mouseChannel = 0;
        
        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printUsage(argv[0]);
                return 0;
            } else if ([arg isEqualToString:@"--status"] || [arg isEqualToString:@"-s"]) {
                doStatus = YES;
            } else if ([arg isEqualToString:@"--to-win"] || [arg isEqualToString:@"-w"]) {
                doToWin = YES;
            } else if ([arg isEqualToString:@"--to-mac"] || [arg isEqualToString:@"-m"]) {
                doToMac = YES;
            } else if ([arg isEqualToString:@"--mouse"] && i + 1 < argc) {
                mouseChannel = atoi(argv[++i]);
            } else if ([arg isEqualToString:@"--watch"]) {
                doWatch = YES;
            } else if ([arg isEqualToString:@"--gui"]) {
                doGui = YES;
            } else if ([arg isEqualToString:@"--install"]) {
                doInstall = YES;
            } else if ([arg isEqualToString:@"--uninstall"]) {
                doUninstall = YES;
            } else if ([arg isEqualToString:@"--target"] && i + 1 < argc) {
                targetDevice = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--win-input"] && i + 1 < argc) {
                winInput = atoi(argv[++i]);
            } else if ([arg isEqualToString:@"--mac-input"] && i + 1 < argc) {
                macInput = atoi(argv[++i]);
            }
        }
        
        if (mouseChannel > 0) {
            printf("正在通过 HID++ 将罗技鼠标切换至通道 %d...\n", mouseChannel);
            bool ok = switchMouseToChannel(mouseChannel);
            printf("%s\n", ok ? "✅ 鼠标切换成功！" : "❌ 未找到支持 ChangeHost 的鼠标设备");
            return ok ? 0 : 1;
        }

        if (doInstall) {
            char resolvedPath[PATH_MAX];
            const char *appPath = "/Applications/LogiDisplaySwitch.app/Contents/MacOS/LogiDisplaySwitch";
            if (access(appPath, X_OK) == 0) {
                strncpy(resolvedPath, appPath, sizeof(resolvedPath));
            } else {
                realpath(argv[0], resolvedPath);
            }
            installLaunchAgent(resolvedPath, targetDevice, winInput, macInput);
            return 0;
        }
        
        if (doUninstall) {
            uninstallLaunchAgent();
            return 0;
        }
        
        if (doStatus) {
            printStatus(targetDevice);
            return 0;
        }
        
        if (doToWin) {
            broadcastSwitchSignal("LOGI:SWITCH_TO_WIN");
            printf("1. 正在将 MX Master 3 鼠标切换至通道 2 (Windows)...\n");
            switchMouseToChannel(2);
            
            printf("2. 正在切换显示器至 Windows (DP, 输入源代码: %d)...\n", winInput);
            int res = setDisplayInput(1, winInput);
            if (res == 0) {
                printf("✅ 成功发送切屏指令！\n");
            } else {
                printf("❌ 切屏指令发送失败 (错误码: %d)\n", res);
            }
            return res;
        }
        
        if (doToMac) {
            broadcastSwitchSignal("LOGI:SWITCH_TO_MAC");
            printf("1. 正在将 MX Master 3 鼠标切换至通道 1 (Mac)...\n");
            switchMouseToChannel(1);
            
            printf("2. 正在切换显示器至 Mac (Type-C, 输入源代码: %d)...\n", macInput);
            int res = setDisplayInput(1, macInput);
            if (res == 0) {
                printf("✅ 成功发送切屏指令！\n");
            } else {
                printf("❌ 切屏指令发送失败 (错误码: %d)\n", res);
            }
            return res;
        }
        
        if (doWatch) {
            NSLog(@"==================================================");
            NSLog(@"LogiDisplaySwitch 启动成功，进入纯命令行后台监听模式");
            NSLog(@"监听设备关键字: %@", targetDevice);
            NSLog(@"Windows 输入源: %d (DP)", winInput);
            NSLog(@"Mac 输入源:     %d (Type-C)", macInput);
            NSLog(@"==================================================");
            
            DeviceWatcher *watcher = [[DeviceWatcher alloc] initWithTargetPattern:targetDevice];
            watcher.onStateChanged = ^(BOOL isConnected, NSString *deviceName) {
                if (isConnected) {
                    NSLog(@"🎉 罗技设备 [%@] 切回 Mac，正在联动切换鼠标和显示器至 Mac...", deviceName);
                    // 1. 发送局域网即时通知，让 Windows 上的 LogiSync 立即放行鼠标
                    broadcastSwitchSignal("LOGI:SWITCH_TO_MAC");
                    
                    // 2. 同步尝试在 Mac 本地切鼠标 (若鼠标已在 Mac)
                    NSLog(@"🖱️ 正在命令 MX Master 3 鼠标切换到通道 1 (Mac)...");
                    switchMouseToChannel(1);
                    
                    // 3. 缓冲 100ms
                    usleep(100000);
                    
                    // 4. 切换显示器至 Type-C
                    NSLog(@"🖥️ 正在切换显示器至 Type-C (%d)...", macInput);
                    int ret = setDisplayInput(1, macInput);
                    if (ret == 0) {
                        NSLog(@"✅ 显示器已切回 Mac (Type-C)");
                    } else {
                        NSLog(@"⚠️ 发送 DDC 切屏指令失败: %d", ret);
                    }
                } else {
                    NSLog(@"🚀 罗技设备 [%@] 切往 Windows (通道 2)...", deviceName);
                    // 1. 发送局域网切往 Win 信号
                    broadcastSwitchSignal("LOGI:SWITCH_TO_WIN");
                    
                    // 2. 核心关键：在切屏的同时，立即通过 HID++ 发送指令让 MX Master 3 也切到通道 2！
                    NSLog(@"🖱️ 正在自动命令 MX Master 3 鼠标切换到通道 2 (Windows)...");
                    bool mouseOk = switchMouseToChannel(2);
                    if (mouseOk) {
                        NSLog(@"✅ 鼠标已成功联动切往通道 2！");
                    } else {
                        NSLog(@"ℹ️ 鼠标未在 Mac 上响应（可能已切走或未连接）");
                    }
                    
                    // 3. 缓冲 150ms 保证蓝牙切离总线稳定
                    usleep(150000);
                    
                    // 4. 切换显示器至 Windows DP
                    NSLog(@"🖥️ 正在切换显示器至 DP (%d)...", winInput);
                    int ret = setDisplayInput(1, winInput);
                    if (ret == 0) {
                        NSLog(@"✅ 显示器已切往 Windows (DP)");
                    } else {
                        NSLog(@"⚠️ 发送 DDC 切屏指令失败: %d", ret);
                    }
                }
            };
            
            [watcher startWatching];
            CFRunLoopRun();
            return 0;
        }
        
        // 默认模式：启动完整 GUI 图形界面
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
