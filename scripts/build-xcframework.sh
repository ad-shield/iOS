#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/xcframework"
OUTPUT_DIR="$PROJECT_DIR/dist"

rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

echo "Building for iOS device (arm64)..."
xcodebuild archive \
    -scheme AdShield \
    -destination "generic/platform=iOS" \
    -archivePath "$BUILD_DIR/ios-device.xcarchive" \
    -derivedDataPath "$BUILD_DIR/derived" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface"

echo "Building for iOS Simulator (arm64, x86_64)..."
xcodebuild archive \
    -scheme AdShield \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "$BUILD_DIR/ios-simulator.xcarchive" \
    -derivedDataPath "$BUILD_DIR/derived" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface"

echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -framework "$BUILD_DIR/ios-device.xcarchive/Products/Library/Frameworks/AdShield.framework" \
    -framework "$BUILD_DIR/ios-simulator.xcarchive/Products/Library/Frameworks/AdShield.framework" \
    -output "$OUTPUT_DIR/AdShield.xcframework"

echo "Zipping XCFramework..."
cd "$OUTPUT_DIR"
zip -r "AdShield.xcframework.zip" "AdShield.xcframework"

echo "Computing checksum..."
CHECKSUM=$(swift package compute-checksum "AdShield.xcframework.zip")
echo ""
echo "=========================================="
echo "XCFramework built successfully!"
echo "Output: $OUTPUT_DIR/AdShield.xcframework.zip"
echo "Checksum: $CHECKSUM"
echo "=========================================="
echo ""
echo "Update your release Package.swift binaryTarget with:"
echo "  url: \"https://cdn.ad-shield.io/sdk/ios/AdShield-1.0.0.xcframework.zip\""
echo "  checksum: \"$CHECKSUM\""
