# AdShield iOS SDK

## Installation

Add the dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ad-shield/iOS.git", from: "2.0.2"),
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
AdShield.configure(endpoint: "https://example.ad-shield.io/config") // Contact Ad-Shield to obtain your endpoint
AdShield.measure()
```

Contact Ad-Shield to obtain your endpoint URL.

## Sample App

See [iOS-sample](https://github.com/ad-shield/iOS-sample) for a working example.

## License

Copyright (c) 2026-present Ad-Shield Inc. All rights reserved.

This software is proprietary and confidential. No part of this software may be reproduced, distributed, modified, reverse-engineered, or used in any form without prior written permission from Ad-Shield Inc.

This software is provided "as is" without warranty of any kind. Ad-Shield Inc. shall not be liable for any damages arising from the use of this software.

Unauthorized use, copying, or distribution of this software is strictly prohibited and may result in legal action.
