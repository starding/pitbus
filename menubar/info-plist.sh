#!/bin/sh
# The menu bar app's Info.plist, shared by install.sh (built here) and package.sh (prebuilt for the package).
cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.pit.menubar</string>
  <key>CFBundleName</key><string>PitBus</string>
  <key>CFBundleExecutable</key><string>PitBus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>PitBus</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict></plist>
EOF
