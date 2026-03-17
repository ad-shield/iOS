# AdShield iOS SDK

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
AdShield.configure(endpoint: "https://your-endpoint.example.com/config")
AdShield.measure()
```

- `configure()` — Sets the config endpoint URL. Contact Ad-Shield (dev@ad-shield.io) to obtain your endpoint.
- `measure()` — Detects ad blockers and reports results. Runs in the background.

## License

Copyright (c) 2024-present Ad-Shield Inc. All rights reserved.

This software is proprietary and confidential. No part of this software may be reproduced, distributed, modified, reverse-engineered, or used in any form without prior written permission from Ad-Shield Inc.

This software is provided "as is" without warranty of any kind. Ad-Shield Inc. shall not be liable for any damages arising from the use of this software.

Unauthorized use, copying, or distribution of this software is strictly prohibited and may result in legal action.
