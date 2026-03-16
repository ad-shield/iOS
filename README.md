# AdShield iOS SDK

Ad-Shield mobile SDK for iOS. Detects ad blocking and reports results.

## Installation

Add the dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ad-shield/iOS.git", from: "2.0.0"),
]
```

Then add `"AdShield"` to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "AdShield", package: "iOS"),
    ]
)
```

## Usage

```swift
// In your App init() or AppDelegate
AdShield.configure(endpoint: "https://your-endpoint.example.com/config")
AdShield.measure()
```

- `configure()` — Sets the config endpoint URL. Contact Ad-Shield (dev@ad-shield.io) to obtain your endpoint.
- `measure()` — Fetches config, detects ad blockers, and reports results. Runs in the background.

## How it works

1. Checks if enough time has passed since the last transmission (`transmissionIntervalMs`)
2. Fetches encrypted config from the configured endpoint
3. Probes ad-related URLs to detect ad blocking (with retries)
4. Sends structured results to the reporting endpoints defined in config
5. All work runs on a background thread — never blocks the main thread

## Requirements

- iOS 13.0+
- Swift 5.9+

## API

```swift
public enum AdShield {
    static func configure(endpoint: String)
    static func measure()
}
```

| Method | Description |
|--------|-------------|
| `configure(endpoint:)` | Sets the config endpoint. Must be called before `measure()`. |
| `measure()` | Runs detection and reporting. Safe to call multiple times — skips if within TTL. |

## Data Collection

This SDK collects limited, non-personal data solely for the purpose of ad block detection. Collected data includes: a randomly generated device identifier (UUID), app bundle ID, OS version, locale, SDK version, and URL accessibility results. **No personally identifiable information (PII) is collected.** The SDK does not access contacts, location, photos, or any other sensitive data.

## License

Proprietary. Copyright Ad-Shield Inc.
