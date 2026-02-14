#!/bin/sh

# Build the application
odin build . -out:liteman -o:speed

# Detect OS
OS="$(uname)"
if [ "$OS" = "Darwin" ]; then
    echo "Packaging for macOS..."
    rm -rf Liteman.app
    mkdir -p Liteman.app/Contents/MacOS
    mkdir -p Liteman.app/Contents/Resources

    # Move binary
    mv liteman Liteman.app/Contents/MacOS/

    # Copy resources
    cp -r resources Liteman.app/Contents/MacOS/

    # Create Info.plist
    cat > Liteman.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>liteman</string>
    <key>CFBundleIdentifier</key>
    <string>com.kru.liteman</string>
    <key>CFBundleName</key>
    <string>Liteman</string>
    <key>CFBundleIconFile</key>
    <string>liteman.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

    echo "Created Liteman.app"

elif [ "$OS" = "Linux" ]; then
    echo "Packaging for Linux..."
    
    # Create .desktop file
    cat > liteman.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Liteman
Exec=$(pwd)/liteman
Icon=$(pwd)/resources/liteman.png
Terminal=false
Categories=Development;
EOF

    chmod +x liteman.desktop
    echo "Created liteman.desktop"
fi
