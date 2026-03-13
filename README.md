# AdShield iOS SDK (Source)

Source code for the Ad-Shield iOS SDK. This is the **private** source repository.

Publishers consume the SDK via the **public release manifest** at `mobile/ios-release/`, which distributes a pre-built XCFramework binary (no source code exposure).

## Building the XCFramework

```bash
cd mobile/ios
chmod +x scripts/build-xcframework.sh
./scripts/build-xcframework.sh
```

Output: `dist/AdShield.xcframework.zip` + checksum.

Upload the zip to CDN and update the checksum in `mobile/ios-release/Package.swift`.

## Development

```bash
# Run tests
cd mobile/ios
swift test
```

## License

Proprietary. Copyright Ad-Shield Inc.
