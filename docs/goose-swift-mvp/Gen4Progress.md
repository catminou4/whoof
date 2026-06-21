# WHOOP 4.0 (Gen4) Build Progress

Goal: every metric tracked and rendered correctly for a WHOOP 4.0 ("Harvard" /
Gen4) strap — the only device the user has. App was built for WHOOP 5.0 (Gen5
"Goose"/"Maverick"); Gen4 support is being added phase by phase.

Reference truth for Gen4 packet layout: openwhoop repo
`bWanShiTong/openwhoop` @ `55c5c1e2e02d3822c33e258838a57bb7d9e2ca53`
(documented WHOOP 4.0 exclusively). Key file: `src/openwhoop-codec/src/whoop_data.rs`.
**Offset mapping: openwhoop `data[N]` == Goose/Whoof `payload[N+3]`** (Goose keeps
the 3-byte `[type, k, status]` prefix that openwhoop's WhoopPacket splits off).
Verified twice (bpm data[14]→payload[17]; V18 data[11]→payload[14]).

## Build / test (IMPORTANT)
Homebrew rustc is 1.93; crate `whoof-core` requires 1.94. Use the rustup stable
toolchain explicitly:
```
ST="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin"
cd Rust/core && RUSTC="$ST/rustc" "$ST/cargo" test --lib --test protocol_tests
```
Crate was renamed `goose-core` → `whoof-core` mid-project (lib `whoof_core`); bins
still `goose-*`. `command_tests` fails pre-existing on a missing generated doc
(`docs/generated/protocol-command-map.md`) — unrelated to Gen4 work.

## Phases
- [x] **Phase 0 — Gen4 decode foundation (core)**  *(iteration 1)*
  - Threaded `DeviceType` through `parse_payload` → `parse_data_packet_payload`
    → `parse_data_packet_body_summary` (was Gen5-hardcoded, ignored device_type).
  - New `DataPacketBodySummary::Gen4History { bpm, rr_intervals_ms, rr_count,
    sensor, .. }` + `Gen4SensorData` (raw ADC: ppg, spo2_red/ir, skin_temp_raw,
    resp_rate_raw, signal_quality, ambient, led_drive, skin_contact).
  - `parse_gen4_history_body_summary` decodes generic (bpm@17, rr_count@18,
    RR@19..27) and V12/V24 sensor packets; IMU/motion (data_len ≥ 1188) defers
    to the shared Gen5 motion path for now.
  - export.rs emits Gen4 sensor-sample rows (bpm u8; RR + DSP via new
    `sensor_u16_sample`; DSP flagged `raw_unverified_units`).
  - Tests: `gen4_generic_history_decodes_heart_rate_and_rr`,
    `gen4_v24_sensor_history_decodes_raw_dsp_fields`,
    `gen5_does_not_use_gen4_history_decoder` (protocol_tests.rs). All green.
  - Files: protocol.rs, bridge.rs, capture_correlation.rs, export.rs.

### Next (Phase 0/1 remainder)
- [ ] **device_type plumbing** — capture_import.rs hardcodes `DeviceType::Goose`
  (≈ line 1111 `capture_sqlite_frame_input`, `default_device_type()`); historical
  Gen4 imports must carry real device_type or they decode as Gen5. Confirm the
  Swift notification/historical path passes `GEN4` into `parse_frame` for the
  61080001 service. Without this, the Gen4 decoder above never runs in production.
- [ ] **Gen4 realtime HR (live)** — type 40 realtime: bpm @ payload[8]
  (openwhoop `parse_realtime_hr`: ts0=cmd, +3 ts, +2 subsec, bpm). Currently
  routed through the Gen5 data-packet parser.
- [ ] **metric_features consumption** — feed Gen4 bpm/RR into HR + HRV feature
  reports; map resp_rate_raw / skin_temp_raw / spo2 raw into recovery vitals
  (unblocks recovery score "provided_resp_temp_inputs_missing"). Verify raw→unit
  conversions before promoting to trusted scores.
- [ ] **Gen4 IMU/motion + RR from big packets** — openwhoop
  `parse_historical_packet_with_imu`: accel/gyro offsets 85/285/485/688/888/1088,
  100 samples i16 BE, ACC_SENS 1875, GYR_SENS 15, header_offset 20 + rr*2.
  Feeds strain / steps / sleep-stage motion.

## Phase 1 — vitals completion
- [ ] SpO2 decoder (Gen4 raw red/IR present; Gen5 K=18 has spo2_pct@payload[51]).
- [ ] Respiratory rate + skin temp unit verification → promote to score inputs.
- [ ] Wire resp+temp into recovery score.

## Phase 2 — UI stubs → real
- [ ] HR zones (HealthStressCharts.swift ~291 hardcoded 0 min).
- [ ] Exercise duration (HealthDataStore+Snapshots.swift ~395 hardcoded "--").
- [ ] Sleep-window respiratory rate.

## Phase 3 — persistence/quality
- [ ] Energy Bank daily ledger persistence.
- [ ] Stress daily-window persistence + activity masking.
- [ ] Sleep stages from band data vs heuristic.
