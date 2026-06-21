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

- [x] **device_type boundary fix (iteration 2) — the unblocker.**
  `parse_device_type` (bridge.rs) accepted only `GEN_4`/`Gen4`/`gen4`, but Swift
  sends `GEN4` (`GooseBLETypes.rustDeviceType`). Every live Gen4 frame failed
  device-type parsing → never decoded as Gen4. Added `GEN4` to `parse_device_type`
  and `expected_device_type` (capture_import.rs). This single fix is what makes
  all the Gen4 decode reachable in production.
- [x] **capture_import device_type** — `capture_sqlite_frame_input` no longer
  hardcodes `DeviceType::Goose`; it auto-detects via new
  `protocol::detect_device_type_from_frame` (Gen4 4-byte/crc8 vs Gen5 8-byte/crc16),
  falling back to Goose. Live notification path already forwards `GEN4`.
- [x] **metric_features consumption (iteration 2)** — HR feature
  (`heart_rate_plan_from_row`) and HRV feature (`HrvPlan` is now an enum:
  `R17` + `Gen4Direct`; `hrv_plan_from_row` / `hrv_feature_from_plan`) consume
  `Gen4History`. `gen4_history` added to `trusted_frames_for_summary_kinds` for HR
  and HRV. Gen4 RR intervals (already ms) bypass the i16 byte-read path.
  Tests: `gen4_heart_rate_feature_extraction_promotes_owned_gen4_history`,
  `gen4_hrv_feature_extraction_builds_rmssd_from_gen4_rr_intervals`
  (metric_features_tests.rs) — verify decode → feature → rmssd end-to-end. Green.
- [x] **realtime misparse guard** — Gen4 history decode now gated to historical
  packet types (`is_historical_data_packet_type`) so a Gen4 realtime type-40
  packet is not misread as a K-history packet.

- [x] **Gen4 IMU/motion from big packets (≥1188) (iteration 3) — DONE, golden-verified.**
  New `DataPacketBodySummary::Gen4Motion { bpm, axes, .. }` +
  `parse_gen4_imu_body_summary`: accel/gyro at payload offsets 88/288/488/691/891/1091
  (openwhoop 85/285/485/688/888/1088 + 3 prefix), 100 samples/axis, i16
  **big-endian** via new `summarize_i16_series_endian` / `read_i16_be`. Endianness
  threaded through the motion feature: `MotionPlan.big_endian`, `accumulate_axis`
  honors it, `motion_plan_from_row` + `heart_rate_plan_from_row` handle Gen4Motion,
  `gen4_motion` added to motion + HR trusted-summary-kind lists, and to
  bridge/capture_correlation/export body-summary dispatch. Verified against the
  openwhoop golden WHOOP 4.0 frame (test
  `gen4_imu_history_decodes_big_endian_against_openwhoop_golden_frame`,
  tests/data/gen4_imu_openwhoop_golden.hex): bpm 62, accelerometer_x[0] = -4095
  raw BE (= -2.184 g x 1875). Feeds strain / steps / sleep-stage motion.

- [x] **Gen4 realtime HR (iteration 4) — DONE.** `parse_gen4_realtime_payload`
  decodes type-40 packets: timestamp seconds from payload[2..6], bpm at payload[8]
  (openwhoop `parse_realtime_hr`), surfaced as a `Gen4History` body tagged
  `gen4_realtime` so the HR feature consumes it. Routed before the data-packet arm
  in `parse_payload` (Gen4 only). Test:
  `gen4_realtime_packet_decodes_heart_rate_at_offset_8`.

### Phase 0 — COMPLETE for Gen4 decode
All Gen4 packet paths now decode: per-second history (HR/RR/sensor), high-rate IMU
motion (big-endian), and realtime HR. Device-type boundary fixed across all 5
parsers. 24 protocol tests + Gen4 HR/HRV/IMU feature tests green.

## Phase 1 — vitals completion (semantics-gated, honest)
- [x] Gen4 raw DSP decoded + surfaced as sensor-sample candidates
  (spo2_red/ir, skin_temp_raw, resp_rate_raw, signal_quality) flagged
  `raw_unverified_units`.
- [ ] **SpO2 %** — needs red/IR ratio calibration; raw values only, NOT promoted
  (no fabricated %).
- [ ] **Respiratory rate / skin temp absolute units** — raw scale unverified vs
  real Gen4 captures; `value_semantics_verified=false`, blocked from recovery
  score promotion. Recovery score therefore still reports
  `provided_resp_temp_inputs_missing` until units are verified against the band.
  (Deliberately not fake-promoted — project rule: no fabricated metric values.)

## Phase 2 — UI stubs → real (Swift; needs on-device build verification)
- [x] HR zones — `HeartRateZoneDurationMinutes` store aggregation; live
  `StrainV2ZoneMeter` now renders real per-zone minutes + total (was hardcoded
  "0 min"). Legacy `HeartRateZonesSection` also made data-driven.
- [x] Exercise duration — `strainDurationDisplayText(for:)` sums today's activity
  session durations via new `totalExerciseDurationMinutes` (was "--").
- [ ] Sleep-window respiratory rate.

## Phase 3 — persistence/quality
- [x] **Energy Bank + Stress daily persistence (iteration 5).** New generic
  `daily_named_metrics` store table (date_key, metric_name, value, unit,
  source_kind, confidence, provenance) + `upsert_daily_named_metric` /
  `daily_named_metrics_between` (store.rs) + bridge methods
  `metrics.write_daily_named_metric` / `metrics.read_daily_named_metrics`. Swift
  `persistDailyEnergyAndStressMetrics()` writes energy_bank_percent/charged/drained
  + stress_score each packet-input refresh; `dailyNamedMetricSeries(...)` reads them
  back for trends. Was in-memory only (lost on restart, empty trends). Rust
  round-trip + replace unit-tested (`daily_named_metrics_round_trip_and_replace`).
  Note: pre-existing `bridge_tests` failures (ui_coverage audit, step-estimate
  inputs_json) are unrelated — they fail identically on HEAD.
- [x] **Trend rendering wired (iteration 6).** `trendMergingPersistedSeries` swaps
  the Energy Bank / Stress fallback trend's points for the persisted multi-day
  series (`persistedTrendPoints`, last 14 days) once ≥2 days are stored; keeps the
  fallback (and its labels/analysis) otherwise — zero regression before data
  accumulates. Wired into `stressSnapshot` + `energyBankSnapshot`. Full write →
  store → read → render loop now closed. (On-device visual confirmation still
  pending — needs the app running over multiple days.)
- [ ] Stress activity masking (split activity vs non-activity stress).
- [ ] Sleep stages from band data vs heuristic.

## Verification status
- Rust core: all touched suites green (lib, protocol, metric_features, export,
  capture_import, capture_correlation). `command_tests` fails pre-existing on a
  missing generated doc, unrelated.
- Swift: edited following existing patterns; NOT yet compiled here (needs Xcode
  per [[goose-gen4-port]] build notes). Reviewed by an adversarial agent pass.
