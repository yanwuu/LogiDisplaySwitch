#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "==> 编译 m1ddc 静态库..."
cd m1ddc-src && make lib CFLAGS="-Wall -Werror -Wextra -fmodules -fmodules-cache-path=.module_cache" > /dev/null && cd ..

echo "==> 编译 Object 文件 (DisplayBridge, DeviceWatcher, AppDelegate, MouseSwitch)..."
clang -c LogiDisplaySwitch/DisplayBridge.m -o LogiDisplaySwitch/DisplayBridge.o -I m1ddc-src/library -I m1ddc-src/headers -fmodules -fmodules-cache-path=.module_cache
clang -c LogiDisplaySwitch/DeviceWatcher.m -o LogiDisplaySwitch/DeviceWatcher.o -fobjc-arc -fmodules -fmodules-cache-path=.module_cache
clang -c LogiDisplaySwitch/AppDelegate.m -o LogiDisplaySwitch/AppDelegate.o -fobjc-arc -fmodules -fmodules-cache-path=.module_cache
clang -c LogiDisplaySwitch/MouseSwitch.m -o LogiDisplaySwitch/MouseSwitch.o -fobjc-arc -fmodules -fmodules-cache-path=.module_cache

echo "==> 链接 LogiDisplaySwitch 可执行程序..."
clang -fobjc-arc -fmodules -fmodules-cache-path=.module_cache \
  LogiDisplaySwitch/main.m \
  LogiDisplaySwitch/AppDelegate.o \
  LogiDisplaySwitch/DeviceWatcher.o \
  LogiDisplaySwitch/DisplayBridge.o \
  LogiDisplaySwitch/MouseSwitch.o \
  m1ddc-src/library/libm1ddc.a \
  -framework CoreDisplay -framework CoreGraphics -framework Foundation -framework IOKit -framework AppKit -framework IOBluetooth \
  -o LogiDisplaySwitch/LogiDisplaySwitch

echo "==> 构建 LogiDisplaySwitch.app 应用程序包..."
APP_DIR="dist/LogiDisplaySwitch.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp LogiDisplaySwitch/Info.plist "$APP_DIR/Contents/Info.plist"
cp LogiDisplaySwitch/LogiDisplaySwitch "$APP_DIR/Contents/MacOS/LogiDisplaySwitch"
cp LogiDisplaySwitch/LogiDisplaySwitch dist/LogiDisplaySwitch
codesign -s - -f dist/LogiDisplaySwitch
codesign -s - -f --deep "$APP_DIR"

echo "✅ 打包完成！输出位置："
echo "   - 应用包: dist/LogiDisplaySwitch.app"
echo "   - 命令行: dist/LogiDisplaySwitch"
