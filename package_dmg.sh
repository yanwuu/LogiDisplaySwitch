#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "==> 1. 编译全部源码..."
cd m1ddc-src && make lib CFLAGS="-Wall -Werror -Wextra -fmodules -fmodules-cache-path=.module_cache" > /dev/null && cd ..

clang -c LogiDisplaySwitch/DisplayBridge.m -o LogiDisplaySwitch/DisplayBridge.o -I m1ddc-src/library -I m1ddc-src/headers -fmodules -fmodules-cache-path=.module_cache
clang -c LogiDisplaySwitch/DeviceWatcher.m -o LogiDisplaySwitch/DeviceWatcher.o -fobjc-arc -fmodules -fmodules-cache-path=.module_cache
clang -c LogiDisplaySwitch/AppDelegate.m -o LogiDisplaySwitch/AppDelegate.o -fobjc-arc -fmodules -fmodules-cache-path=.module_cache
clang -c LogiDisplaySwitch/MouseSwitch.m -o LogiDisplaySwitch/MouseSwitch.o -fobjc-arc -fmodules -fmodules-cache-path=.module_cache

clang -fobjc-arc -fmodules -fmodules-cache-path=.module_cache \
  LogiDisplaySwitch/main.m \
  LogiDisplaySwitch/AppDelegate.o \
  LogiDisplaySwitch/DeviceWatcher.o \
  LogiDisplaySwitch/DisplayBridge.o \
  LogiDisplaySwitch/MouseSwitch.o \
  m1ddc-src/library/libm1ddc.a \
  -framework CoreDisplay -framework CoreGraphics -framework Foundation -framework IOKit -framework AppKit -framework IOBluetooth \
  -o LogiDisplaySwitch/LogiDisplaySwitch

codesign -s - -f LogiDisplaySwitch/LogiDisplaySwitch

echo "==> 2. 构造 LogiDisplaySwitch.app..."
APP_DIR="dist/LogiDisplaySwitch.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp LogiDisplaySwitch/Info.plist "$APP_DIR/Contents/Info.plist"
cp LogiDisplaySwitch/LogiDisplaySwitch "$APP_DIR/Contents/MacOS/LogiDisplaySwitch"
cp LogiDisplaySwitch/LogiDisplaySwitch dist/LogiDisplaySwitch
codesign -s - -f dist/LogiDisplaySwitch
codesign -s - -f --deep "$APP_DIR"

echo "==> 3. 制作标准 .dmg 安装包..."
DMG_STAGING="dist/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

DMG_OUTPUT="dist/LogiDisplaySwitch-macOS.dmg"
rm -f "$DMG_OUTPUT" "${DMG_OUTPUT}.iso.dmg"

hdiutil makehybrid -hfs -hfs-volume-name "LogiDisplaySwitch" -o "${DMG_OUTPUT}.iso" "$DMG_STAGING" > /dev/null
mv "${DMG_OUTPUT}.iso.dmg" "$DMG_OUTPUT"
rm -rf "$DMG_STAGING"

echo "✅ DMG 打包完成！"
echo "   文件路径: $DMG_OUTPUT (文件大小: $(ls -lh "$DMG_OUTPUT" | awk '{print $5}'))"
