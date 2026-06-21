# Whoof - Local Companion for WHOOP 4.0 and 5.0

**Alpha proof of concept. This build is for developers to evaluate whether a project of this scope is viable. It is not ready to use as an app for tracking personal health data yet.**

Whoof is a fork of [b-nnett/goose](https://github.com/b-nnett/goose) that adds **WHOOP 4.0 (Gen4 / "Harvard")** support on top of the original WHOOP 5.0 project: a Gen4 BLE command-frame builder, generation-aware characteristic routing, the Gen4 historical-sync handshake, and Gen4 historical packet decoding (heart rate, RR intervals, and V12/V24 raw DSP fields). The Gen4 protocol is ported from the [openwhoop](https://github.com/bWanShiTong/openwhoop) reference. It also includes performance work to reduce UI lag.

If you don't know what Xcode is, or how to build the Rust core, this build is not for you.

This build connects to WHOOP 4.0 and WHOOP 5.0 bands.

Whoof is a local-first WHOOP data and health metrics project. The iOS app connects to WHOOP bands over Bluetooth, routes packet data through the Whoof Rust core (`whoof-core`), and turns that data into daily health, recovery, sleep, strain, stress, cardio, energy, coach, and debug views. The Xcode target and source directory are still named `GooseSwift` from the upstream project; the product, bundle id (`com.madhursatija.whoof`), Rust crate, and Swift types are renamed to Whoof.

## Project Layout

```text
GooseSwift/                         SwiftUI app source
GooseWorkoutLiveActivityExtension/  Live Activity widget extension
Rust/                               iOS static library, headers, per-platform outputs
Scripts/build_ios_rust.sh           Xcode build phase for the Goose Rust core
docs/goose-swift-mvp/               MVP plans, contracts, and data-readiness docs
GooseSwift.xcodeproj                Xcode project
```

Key Swift entry points:

- `GooseSwiftApp.swift`: app lifecycle and deep-link handling.
- `RootView.swift`: onboarding gate and global sync toast host.
- `AppShellView.swift`: tab shell and shared health store wiring.
- `GooseAppModel.swift`: app state, BLE ownership, lifecycle, and bridge summaries.
- `GooseBLEClient.swift`: Bluetooth scan/connect/sync logic.
- `GooseRustBridge.swift`: Swift wrapper around the Rust C bridge.
- `HealthView.swift` and `Health*` files: health dashboards, metric pages, trends, and sheets.
- `CoachView.swift` and `Coach*` files: coach UI and chat support.
- `MoreView.swift`: operational/debug/settings surfaces.

This is an active prototype. Because the data pipeline is still evolving, some metrics appear as empty or unavailable until the app has a source for them.

## Independence

Goose is an independent project and is not affiliated with WHOOP. This repository does not include or reference source code owned by WHOOP. The app communicates with WHOOP 5.0 bands over Bluetooth using services and data exposed by the device, then parses and stores that local data through the Goose Rust core. Product names are used only to describe compatibility.

## Design Credit

The current health metric UI draws heavily from [Bevel](https://www.bevel.health/), especially the Sleep, Recovery, Strain, Stress, and trend-detail surfaces. Bevel is not affiliated with Goose; this credit is here because their product design has been a major visual reference.

## Current Scope

- SwiftUI app shell with Home, Health, Coach, and More tabs.
- Onboarding and persisted profile state.
- CoreBluetooth scan/connect/history-sync flows for WHOOP 4.0 and 5.0 bands.
- JSON-over-C bridge into the Whoof Rust core (`whoof-core`).
- Consumer health surfaces: Sleep, Recovery, Strain, Stress, Cardio Load, Energy
  Bank, and a grouped Health Monitor (Core Vitals / Heart Rate / Advanced HRV /
  Fitness).
- On-device metrics derived from RR intervals + IMU (no servers): HRV (RMSSD /
  SDNN / pNN50 / Poincaré SD1·SD2 / LF·HF), RSA respiratory rate, resting / mean /
  max heart rate, recovery, strain, stress, steps, a VO2 max estimate, and a
  relative skin-temperature trend. See [Metrics on WHOOP 4.0](#metrics-on-whoop-40).
- Apple Health two-way sync: broadcasts heart rate, HRV, resting HR, respiratory
  rate (and more) to Apple Health, and keeps body weight in sync.
- Coach surfaces that summarize local metrics and explain missing data.
- Developer-only surfaces (Connection Lab, Capture, Local Store, Raw Export,
  Algorithms, Debug) gated under More → Developer, kept out of the consumer flow.
- Workout Live Activity extension.

## Metrics on WHOOP 4.0

Everything is computed on-device from what the band exposes over Bluetooth (RR
intervals, IMU, and raw DSP fields). Nothing is fabricated: a metric stays
"Unavailable" with a next-step hint until it has real data.

| Metric | Status | Source |
| --- | --- | --- |
| Heart rate (live / resting / mean / max) | Works | Live BLE stream + sample store |
| HRV (RMSSD, SDNN, pNN50, SD1/SD2) | Works | RR intervals (live or synced) |
| Autonomic balance (LF/HF) | Works | Frequency-domain HRV over a ~1 min RR window |
| Respiratory rate | Works | RR-interval RSA |
| Recovery / Strain / Stress | Works | HRV + resting HR + sleep + HR zones |
| VO2 max | Estimate | Population heuristic (resting HR + age), labeled |
| Steps / cadence | Works (synced) | Gen4 IMU motion history |
| Sleep + stages | Works (synced) | Overnight motion + HR/HRV, labeled estimate |
| Skin-temperature trend | Works (synced) | Relative raw-ADC deviation, uncalibrated |
| SpO2 % | Not available | Gen4 emits DC-only PPG; no client-side derivation |
| Absolute skin temperature °C | Not available | No public thermistor calibration |

Live metrics populate within ~1–2 minutes of wearing a connected band. History
metrics (steps, sleep, skin-temp trend) require a sync (below).

## Getting Data Into The App

Two independent paths feed the metrics:

1. **Live stream** — connect the band (More → Device → Scan & Connect). Heart
   rate, HRV, respiratory rate, and the HR stats populate while worn.
2. **History sync** — More → Device → **Sync**. The band streams its stored
   history; Whoof mirrors the raw frames, then promotes them into the
   `decoded_frames` store that every metric reads. After a completed sync, the
   history metrics (steps, sleep, skin-temp trend, full recovery) populate.

If a card reads "Unavailable," its hint says which path it needs ("Wear band
~2 min" vs "Sync band").

## Requirements

- macOS with Xcode installed.
- iOS 26 SDK and an iOS 26 capable simulator/device.
- Apple Developer signing configured for the `com.madhursatija.whoof` bundle identifier.
- Rust and Cargo for building the Goose Rust core from the committed `Rust/core` source.
- iOS Rust targets installed with `rustup`; see the Rust Core Bridge section below.

Built Rust `.a` archives are generated locally during Xcode builds and are not committed. Set `GOOSE_SKIP_RUST_CORE_BUILD=1` only when the matching local archive already exists for the active Xcode platform.

## Build

Open `GooseSwift.xcodeproj` in Xcode and build the `GooseSwift` scheme, or build from the command line.

Simulator build:

```sh
xcodebuild \
  -project GooseSwift.xcodeproj \
  -scheme GooseSwift \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/goose-swift-deriveddata \
  build
```

Physical device build:

```sh
xcodebuild \
  -project GooseSwift.xcodeproj \
  -scheme GooseSwift \
  -configuration Debug \
  -destination 'platform=iOS,id=<device-id>' \
  -derivedDataPath /tmp/goose-swift-deriveddata-device \
  -allowProvisioningUpdates \
  build
```

List connected devices:

```sh
xcrun devicectl list devices
```

## Reinstall On A Device

After a successful physical-device build, reinstall and launch:

```sh
xcrun devicectl device uninstall app \
  --device <device-id> \
  com.madhursatija.whoof

xcrun devicectl device install app \
  --device <device-id> \
  /tmp/goose-swift-deriveddata-device/Build/Products/Debug-iphoneos/GooseSwift.app

xcrun devicectl device process launch \
  --device <device-id> \
  --terminate-existing \
  com.madhursatija.whoof
```

## Rust Core Bridge

The Rust bridge source is committed in `Rust/core`. Do not commit built `.a`
archives; Xcode generates them locally through `Scripts/build_ios_rust.sh`.

Prerequisites:

- Xcode command line tools.
- Rust via `rustup`.
- iOS Rust targets:

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
```

`Scripts/build_ios_rust.sh` builds `Rust/core` for the active Xcode platform:

- `iphoneos` -> `aarch64-apple-ios`
- `iphonesimulator` on Apple Silicon -> `aarch64-apple-ios-sim`
- `iphonesimulator` on Intel -> `x86_64-apple-ios`

Outputs are staged into:

```text
Rust/iphoneos/libgoose_core.a
Rust/iphonesimulator/libgoose_core.a
```

The Swift target links `Rust/$(PLATFORM_NAME)/libgoose_core.a` and reads the C
bridge header from `Rust/core/include/goose_core_bridge.h`. The default Cargo
target directory is `build/rust-target/goose-core`, so Rust build products stay
outside the committed source tree.

Manual builds:

```bash
# Simulator on Apple Silicon
PLATFORM_NAME=iphonesimulator CURRENT_ARCH=arm64 Scripts/build_ios_rust.sh

# Physical iPhone
PLATFORM_NAME=iphoneos CURRENT_ARCH=arm64 Scripts/build_ios_rust.sh
```

You normally do not need to run these by hand; the Xcode build phase runs the
script before compiling Swift.

## Data And Privacy

- Metric views show empty, stale, or unavailable states when a source is missing.
- Metric rows and trend sheets show where values came from when that information is available.
- Raw packet payloads stay in debug/export flows rather than everyday health views.
- Coach responses use the same local metric summaries shown in the app.
- Health and fitness data is local by default. Any future backend or AI feature will need its own consent flow and privacy notes.

## Documentation

Detailed implementation plans live in `docs/goose-swift-mvp/`:

- `Home.md`: Home tab contract and remaining work.
- `Health.md`: Health surfaces, metric pages, packet inputs, trends, and acceptance checks.
- `Coach.md`: Coach tab plan and chat architecture notes.
- `More.md`: operational settings/debug/capture/privacy surfaces.
- `CodexCoachServer.md`: viability notes for a future Codex-powered coach.
- `RemainingDataTodo.md`: unresolved data-source and persistence work.

Recovery-specific follow-up work is tracked in `recovery-todo.md`.

## Contributing

This project moves quickly, so small focused changes are easiest to review.

Want to talk to other contributors? [Join the group here](https://x.com/i/chat/group_join/g2061785795330019536/3SHQtt2O8f).

- Keep changes close to the feature or bug you are working on.
- Match the existing SwiftUI style before introducing new patterns.
- Build after touching Swift, Rust bridge, project, or signing settings.
- Check both empty and populated states for metric UI when possible.
- Keep user-facing health copy plain and careful. Avoid medical claims.
- Put debug tooling, packet details, and raw export behavior under More or Debug surfaces.
- Update the relevant MVP doc when a change completes or changes an open task.
- Mention any build warnings, skipped checks, or device-only assumptions in the PR notes.

## Development Notes

- Prefer small, typed Swift models over displaying raw summary strings.
- Keep Home, Health, Coach, and More routes modular enough to work independently.
- Metric pages should still look polished when data is missing.
- Before installing to a device, run a simulator or device build and check that the Rust library target matches the destination platform.
