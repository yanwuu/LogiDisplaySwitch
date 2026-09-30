#import "AppDelegate.h"
#import "DisplayBridge.h"
#import "MouseSwitch.h"

#define DEFAULT_TARGET_DEVICE   @"MX Keys"
#define DEFAULT_WIN_INPUT       16
#define DEFAULT_MAC_INPUT       27
#define LAUNCH_AGENT_LABEL      @"io.github.logidisplayswitch"

@interface AppDelegate ()

@property (nonatomic, strong) NSTextField *displayStatusLabel;
@property (nonatomic, strong) NSTextField *deviceStatusLabel;
@property (nonatomic, strong) NSTextField *logStatusLabel;
@property (nonatomic, strong) NSTextField *targetField;
@property (nonatomic, strong) NSTextField *winInputField;
@property (nonatomic, strong) NSTextField *macInputField;
@property (nonatomic, strong) NSButton *autoSwitchCheckbox;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self setupStatusItem];
    [self setupMainWindow];
    [self setupWatcher];
    [self refreshHardwareStatus];
}

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"🖥️ LogiSwitch";
    
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"打开控制面板..." action:@selector(showMainWindow) keyEquivalent:@"o"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"切至 Windows (DP 16)" action:@selector(switchToWindows) keyEquivalent:@"w"];
    [menu addItemWithTitle:@"切至 Mac (Type-C 27)" action:@selector(switchToMac) keyEquivalent:@"m"];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出 LogiDisplaySwitch" action:@selector(terminate:) keyEquivalent:@"q"];
    
    self.statusItem.menu = menu;
}

- (void)setupMainWindow {
    NSRect frame = NSMakeRect(0, 0, 480, 430);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"LogiDisplaySwitch - 罗技键鼠显示器联动控制面板";
    self.window.releasedWhenClosed = NO;
    [self.window center];
    
    NSView *contentView = self.window.contentView;
    
    // 标题
    NSTextField *titleLabel = [self createLabel:@"罗技键鼠联动显示器控制面板" frame:NSMakeRect(20, 380, 440, 28) bold:YES size:18];
    [contentView addSubview:titleLabel];
    
    // 硬件状态 Box
    NSBox *statusBox = [[NSBox alloc] initWithFrame:NSMakeRect(20, 260, 440, 110)];
    statusBox.title = @"硬件状态实时监测";
    
    self.displayStatusLabel = [self createLabel:@"显示器: 正在探测..." frame:NSMakeRect(15, 55, 410, 20) bold:NO size:13];
    self.deviceStatusLabel = [self createLabel:@"目标键鼠: 正在探测..." frame:NSMakeRect(15, 25, 410, 20) bold:NO size:13];
    
    [statusBox.contentView addSubview:self.displayStatusLabel];
    [statusBox.contentView addSubview:self.deviceStatusLabel];
    [contentView addSubview:statusBox];
    
    // 手动快速控制
    NSBox *actionBox = [[NSBox alloc] initWithFrame:NSMakeRect(20, 160, 440, 90)];
    actionBox.title = @"手动快捷切屏";
    
    NSButton *btnToWin = [NSButton buttonWithTitle:@"💻 立即切到 Windows (DP)" target:self action:@selector(switchToWindows)];
    btnToWin.frame = NSMakeRect(20, 18, 190, 36);
    btnToWin.bezelStyle = NSBezelStyleRegularSquare;
    
    NSButton *btnToMac = [NSButton buttonWithTitle:@"🍎 立即切到 Mac (Type-C)" target:self action:@selector(switchToMac)];
    btnToMac.frame = NSMakeRect(230, 18, 190, 36);
    btnToMac.bezelStyle = NSBezelStyleRegularSquare;
    
    [actionBox.contentView addSubview:btnToWin];
    [actionBox.contentView addSubview:btnToMac];
    [contentView addSubview:actionBox];
    
    // 高级设置与自启
    NSBox *configBox = [[NSBox alloc] initWithFrame:NSMakeRect(20, 50, 440, 100)];
    configBox.title = @"参数配置 & 开机自启";
    
    NSTextField *lblTarget = [self createLabel:@"监听关键字:" frame:NSMakeRect(15, 48, 80, 20) bold:NO size:12];
    self.targetField = [[NSTextField alloc] initWithFrame:NSMakeRect(95, 48, 90, 22)];
    self.targetField.stringValue = DEFAULT_TARGET_DEVICE;
    
    NSTextField *lblWin = [self createLabel:@"Win(DP):" frame:NSMakeRect(195, 48, 65, 20) bold:NO size:12];
    self.winInputField = [[NSTextField alloc] initWithFrame:NSMakeRect(260, 48, 45, 22)];
    self.winInputField.stringValue = [NSString stringWithFormat:@"%d", DEFAULT_WIN_INPUT];
    
    NSTextField *lblMac = [self createLabel:@"Mac(TypeC):" frame:NSMakeRect(315, 48, 75, 20) bold:NO size:12];
    self.macInputField = [[NSTextField alloc] initWithFrame:NSMakeRect(390, 48, 40, 22)];
    self.macInputField.stringValue = [NSString stringWithFormat:@"%d", DEFAULT_MAC_INPUT];
    
    self.autoSwitchCheckbox = [NSButton checkboxWithTitle:@"开机后台自动监听键鼠（1/2 键无感自动切屏）" target:self action:@selector(toggleAutoSwitch:)];
    self.autoSwitchCheckbox.frame = NSMakeRect(15, 15, 380, 22);
    self.autoSwitchCheckbox.state = [self isLaunchAgentInstalled] ? NSControlStateValueOn : NSControlStateValueOff;
    
    [configBox.contentView addSubview:lblTarget];
    [configBox.contentView addSubview:self.targetField];
    [configBox.contentView addSubview:lblWin];
    [configBox.contentView addSubview:self.winInputField];
    [configBox.contentView addSubview:lblMac];
    [configBox.contentView addSubview:self.macInputField];
    [configBox.contentView addSubview:self.autoSwitchCheckbox];
    [contentView addSubview:configBox];
    
    // 底部状态提示
    self.logStatusLabel = [self createLabel:@"就绪" frame:NSMakeRect(25, 15, 430, 20) bold:NO size:11];
    self.logStatusLabel.textColor = [NSColor secondaryLabelColor];
    [contentView addSubview:self.logStatusLabel];
    
    [self.window makeKeyAndOrderFront:nil];
}

- (NSTextField *)createLabel:(NSString *)text frame:(NSRect)frame bold:(BOOL)bold size:(CGFloat)size {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    label.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    return label;
}

- (void)showMainWindow {
    if (!self.window) {
        [self setupMainWindow];
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)setupWatcher {
    NSString *pattern = self.targetField.stringValue.length > 0 ? self.targetField.stringValue : DEFAULT_TARGET_DEVICE;
    self.watcher = [[DeviceWatcher alloc] initWithTargetPattern:pattern];
    
    __weak typeof(self) weakSelf = self;
    self.watcher.onStateChanged = ^(BOOL isConnected, NSString *deviceName) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf refreshHardwareStatus];
            if (isConnected) {
                [weakSelf switchToMac];
            } else {
                [weakSelf switchToWindows];
            }
        });
    };
    [self.watcher startWatching];
}

- (void)refreshHardwareStatus {
    int count = getConnectedDisplayCount();
    if (count > 0) {
        self.displayStatusLabel.stringValue = [NSString stringWithFormat:@"显示器: 🟢 已就绪 - %s (共 %d 台)", getDisplayName(1), count];
    } else {
        self.displayStatusLabel.stringValue = @"显示器: 🔴 未检测到支持 DDC 的显示器";
    }
    
    BOOL connected = [self.watcher checkCurrentState];
    if (connected) {
        self.deviceStatusLabel.stringValue = [NSString stringWithFormat:@"目标键鼠: 🟢 在线 [%@] (当前正在控制 Mac)", self.targetField.stringValue];
    } else {
        self.deviceStatusLabel.stringValue = [NSString stringWithFormat:@"目标键鼠: ⚪ 离线 [%@] (已切往 Windows 或未连接)", self.targetField.stringValue];
    }
}

- (void)switchToWindows {
    int winCode = [self.winInputField.stringValue intValue];
    if (winCode <= 0) winCode = DEFAULT_WIN_INPUT;
    
    // 1. 同步切鼠标通道 2
    switchMouseToChannel(2);
    self.logStatusLabel.stringValue = [NSString stringWithFormat:@"已切鼠标通道2，正在切换显示器至 Windows (DP %d)...", winCode];
    
    // 2. 缓冲 150ms 给蓝牙总线
    usleep(150000);
    
    // 3. 切显示器
    int res = setDisplayInput(1, winCode);
    if (res == 0) {
        self.logStatusLabel.stringValue = @"✅ 成功切到 Windows (DP & 鼠标已切通道2)";
    } else {
        self.logStatusLabel.stringValue = [NSString stringWithFormat:@"❌ 切屏失败 (错误码 %d)", res];
    }
}

- (void)switchToMac {
    int macCode = [self.macInputField.stringValue intValue];
    if (macCode <= 0) macCode = DEFAULT_MAC_INPUT;
    
    // 1. 同步切鼠标通道 1
    switchMouseToChannel(1);
    self.logStatusLabel.stringValue = [NSString stringWithFormat:@"已切鼠标通道1，正在切换显示器至 Mac (Type-C %d)...", macCode];
    
    // 2. 缓冲 100ms
    usleep(100000);
    
    // 3. 切显示器
    int res = setDisplayInput(1, macCode);
    if (res == 0) {
        self.logStatusLabel.stringValue = @"✅ 成功切到 Mac (Type-C & 鼠标已切通道1)";
    } else {
        self.logStatusLabel.stringValue = [NSString stringWithFormat:@"❌ 切屏失败 (错误码 %d)", res];
    }
}

- (BOOL)isLaunchAgentInstalled {
    NSString *plistPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Library/LaunchAgents/%@.plist", LAUNCH_AGENT_LABEL]];
    return [[NSFileManager defaultManager] fileExistsAtPath:plistPath];
}

- (void)toggleAutoSwitch:(NSButton *)sender {
    NSString *homeDir = NSHomeDirectory();
    NSString *plistPath = [homeDir stringByAppendingPathComponent:[NSString stringWithFormat:@"Library/LaunchAgents/%@.plist", LAUNCH_AGENT_LABEL]];
    NSString *binaryPath = [[NSBundle mainBundle] executablePath];
    
    if (sender.state == NSControlStateValueOn) {
        NSString *logPath = [homeDir stringByAppendingPathComponent:@"Library/Logs/LogiDisplaySwitch.log"];
        int winCode = [self.winInputField.stringValue intValue] ?: DEFAULT_WIN_INPUT;
        int macCode = [self.macInputField.stringValue intValue] ?: DEFAULT_MAC_INPUT;
        NSString *target = self.targetField.stringValue ?: DEFAULT_TARGET_DEVICE;
        
        NSString *plistContent = [NSString stringWithFormat:
            @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            @"<plist version=\"1.0\">\n"
            @"<dict>\n"
            @"    <key>Label</key>\n"
            @"    <string>%@</string>\n"
            @"    <key>ProgramArguments</key>\n"
            @"    <array>\n"
            @"        <string>%@</string>\n"
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
            @"    <key>StandardOutPath</key>\n"
            @"    <string>%@</string>\n"
            @"    <key>StandardErrorPath</key>\n"
            @"    <string>%@</string>\n"
            @"</dict>\n"
            @"</plist>\n",
            LAUNCH_AGENT_LABEL, binaryPath, target, winCode, macCode, logPath, logPath];
            
        [plistContent writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        system([[NSString stringWithFormat:@"launchctl load \"%@\" 2>/dev/null", plistPath] UTF8String]);
        self.logStatusLabel.stringValue = @"✅ 已启用开机自启自动监听服务";
    } else {
        system([[NSString stringWithFormat:@"launchctl unload \"%@\" 2>/dev/null", plistPath] UTF8String]);
        [[NSFileManager defaultManager] removeItemAtPath:plistPath error:nil];
        self.logStatusLabel.stringValue = @"已关闭并卸载开机自启监听服务";
    }
}

@end
