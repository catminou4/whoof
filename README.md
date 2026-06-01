# Goose Swift

Native SwiftUI MVP for Goose.

Scope for the first slice:

- iOS 26 minimum target.
- Minimal onboarding gate.
- CoreBluetooth scan/connect for WHOOP Gen 4/5 GATT services.
- Send the read-only `GET_HELLO` client frame and show sent/received bytes.
- Link the existing Goose Rust core through the same JSON-over-C bridge.

Build with Xcode by opening `GooseSwift.xcodeproj`, or from this directory:

```sh
xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -destination 'generic/platform=iOS Simulator' build
```

