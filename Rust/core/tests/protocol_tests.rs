use whoof_core::protocol::{
    COMMAND_GET_HELLO, DataPacketBodySummary, DeviceType, FrameAccumulator, Gen4SensorData,
    I16SeriesSummary, PACKET_TYPE_COMMAND_RESPONSE, PACKET_TYPE_EVENT, PACKET_TYPE_HISTORICAL_DATA,
    PACKET_TYPE_REALTIME_DATA, PACKET_TYPE_REALTIME_RAW_DATA, ParsedPayload,
    build_command_frame, build_gen4_command_frame, build_gen4_payload_frame, build_v5_command_frame,
    build_v5_payload_frame, parse_frame, parse_frame_hex,
};

const GET_HELLO_FRAME: &str = "aa0108000001e67123019101363e5c8d";

#[test]
fn parses_hand_derived_goose_v5_get_hello_frame() {
    let parsed = parse_frame_hex(DeviceType::Goose, GET_HELLO_FRAME).unwrap();

    assert_eq!(parsed.raw_len, 16);
    assert_eq!(parsed.header_len, 8);
    assert_eq!(parsed.declared_len, 8);
    assert_eq!(parsed.payload_hex, "23019101");
    assert_eq!(parsed.packet_type, Some(35));
    assert_eq!(parsed.packet_type_name.as_deref(), Some("COMMAND"));
    assert_eq!(parsed.sequence, Some(1));
    assert_eq!(parsed.command_or_event, Some(145));
    assert!(parsed.header_crc_valid);
    assert!(parsed.payload_crc_valid);
    assert!(parsed.warnings.is_empty());
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::Command {
            command: Some(145),
            command_name: Some("GET_HELLO".to_string()),
            data_offset: 3,
            data_hex: "01".to_string(),
            warnings: Vec::new(),
        })
    );
}

#[test]
fn builder_matches_existing_python_command_builder_fixture() {
    let frame = build_v5_command_frame(1, COMMAND_GET_HELLO, &[1]);

    assert_eq!(hex::encode(frame), GET_HELLO_FRAME);
}

/// Golden vectors generated independently from the openwhoop reference codec
/// (`WhoopPacket::framed_packet`, the Gen4/Harvard framing). These pin the
/// Goose Gen4 builder byte-for-byte to the reference implementation so a WHOOP
/// 4.0 strap receives exactly the frames it expects.
#[test]
fn gen4_builder_matches_openwhoop_golden_vectors() {
    // (sequence, command, data, expected_hex) — seq is 0 for all sync commands.
    let cases: [(u8, u8, &[u8], &str); 6] = [
        (0, 35, &[0x00], "aa0800a823002300ada86a2d"), // hello_harvard (GetHelloHarvard)
        (0, 76, &[0x00], "aa0800a823004c00c5df0fcf"), // get_name (GetAdvertisingNameHarvard)
        (0, 96, &[], "aa07006b230060f340f888"),       // enter_high_freq_sync
        (0, 22, &[0x00], "aa0800a8230016001b6a5b8f"), // history_start (SendHistoricalData)
        (0, 34, &[0x00], "aa0800a823002200ec997134"), // get_data_range (GetDataRange)
        (0, 68, &[0x00], "aa0800a823004400cd55d607"), // run_alarm_now (RunAlarm)
    ];
    for (seq, cmd, data, expected) in cases {
        let frame = build_gen4_command_frame(seq, cmd, data);
        assert_eq!(
            hex::encode(&frame),
            expected,
            "gen4 frame mismatch for cmd {cmd}"
        );
        // build_command_frame must route Gen4 to the Harvard builder.
        assert_eq!(build_command_frame(DeviceType::Gen4, seq, cmd, data), frame);
    }
}

#[test]
fn gen4_builder_round_trips_through_gen4_parser() {
    let frame = build_gen4_command_frame(7, 22, &[0x00]);
    let parsed = parse_frame(DeviceType::Gen4, &frame).unwrap();

    assert_eq!(parsed.header_len, 4);
    assert!(parsed.header_crc_valid, "gen4 header crc8 should validate");
    assert!(parsed.payload_crc_valid, "gen4 payload crc32 should validate");
    assert_eq!(parsed.packet_type_name.as_deref(), Some("COMMAND"));
    assert_eq!(parsed.sequence, Some(7));
    assert_eq!(parsed.command_or_event, Some(22));
}

#[test]
fn gen4_and_gen5_framing_differ_for_same_command() {
    let gen4 = build_command_frame(DeviceType::Gen4, 0, 22, &[0x00]);
    let gen5 = build_command_frame(DeviceType::Goose, 0, 22, &[0x00]);
    assert_ne!(gen4, gen5, "gen4 (4-byte/crc8) must differ from gen5 (8-byte/crc16)");
    assert_eq!(gen4[1], 0x08); // gen4 length LSB at byte 1
    assert_eq!(gen5[1], 0x01); // gen5 flags byte at byte 1
}

/// Build a Gen4 historical-data frame from a payload of `len` bytes with the
/// given `(offset, byte)` overrides, framed with the Harvard header so it round
/// trips through `parse_frame(DeviceType::Gen4, ..)`.
fn gen4_history_frame(k: u8, len: usize, fields: &[(usize, u8)]) -> Vec<u8> {
    let mut payload = vec![0u8; len];
    payload[0] = whoof_core::protocol::PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = k;
    for &(offset, value) in fields {
        payload[offset] = value;
    }
    build_gen4_payload_frame(&payload)
}

fn gen4_history_summary(frame: &[u8]) -> DataPacketBodySummary {
    let parsed = parse_frame(DeviceType::Gen4, frame).unwrap();
    let ParsedPayload::DataPacket {
        body_summary: Some(summary),
        ..
    } = parsed.parsed_payload.unwrap()
    else {
        panic!("expected a Gen4 data packet");
    };
    summary
}

/// Gen4 generic history packets carry the heart rate at payload[17], the RR
/// count at [18], and up to four RR intervals from [19]. Offsets mirror the
/// openwhoop `parse_historical_packet_generic` layout (+3 prefix).
#[test]
fn gen4_generic_history_decodes_heart_rate_and_rr() {
    // bpm=62, rr_count=1, rr[0]=837ms (0x0345 LE).
    let frame = gen4_history_frame(9, 27, &[(17, 62), (18, 1), (19, 0x45), (20, 0x03)]);
    match gen4_history_summary(&frame) {
        DataPacketBodySummary::Gen4History {
            bpm,
            rr_intervals_ms,
            rr_count,
            sensor,
            ..
        } => {
            assert_eq!(bpm, Some(62));
            assert_eq!(rr_count, Some(1));
            assert_eq!(rr_intervals_ms, vec![837]);
            assert_eq!(sensor, None, "k=9 is not a sensor packet");
        }
        other => panic!("expected Gen4History, got {other:?}"),
    }
}

/// Gen4 V12/V24 sensor packets additionally carry raw DSP fields (SpO2 red/IR,
/// skin temperature, respiratory rate, signal quality, PPG, skin contact).
#[test]
fn gen4_v24_sensor_history_decodes_raw_dsp_fields() {
    let frame = gen4_history_frame(
        24,
        80,
        &[
            (17, 70),   // bpm
            (18, 0),    // rr_count
            (29, 0x01), // ppg_green = 1
            (51, 1),    // skin_contact = 1
            (64, 0x34), // spo2_red = 0x1234 = 4660
            (65, 0x12),
            (68, 0xB8), // skin_temp_raw = 0x0BB8 = 3000
            (69, 0x0B),
            (76, 0x10), // resp_rate_raw = 16
            (78, 0xFF), // signal_quality = 255
        ],
    );
    match gen4_history_summary(&frame) {
        DataPacketBodySummary::Gen4History {
            bpm,
            rr_intervals_ms,
            sensor,
            ..
        } => {
            assert_eq!(bpm, Some(70));
            assert!(rr_intervals_ms.is_empty());
            assert_eq!(
                sensor,
                Some(Gen4SensorData {
                    ppg_green: 1,
                    ppg_red_ir: 0,
                    spo2_red: 4660,
                    spo2_ir: 0,
                    skin_temp_raw: 3000,
                    ambient_light: 0,
                    led_drive_1: 0,
                    led_drive_2: 0,
                    resp_rate_raw: 16,
                    signal_quality: 255,
                    skin_contact: 1,
                })
            );
        }
        other => panic!("expected Gen4History, got {other:?}"),
    }
}

/// The same byte layout under Gen5 framing must NOT take the Gen4 history path;
/// k=24 stays a Gen5 normal-history marker summary.
#[test]
fn gen5_does_not_use_gen4_history_decoder() {
    let mut payload = vec![0u8; 27];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 24;
    payload[17] = 62;
    let frame = build_v5_payload_frame(&payload);
    match gen5_history_summary(&frame) {
        DataPacketBodySummary::NormalHistory { marker_value, .. } => {
            assert_eq!(marker_value, Some(62));
        }
        other => panic!("expected Gen5 NormalHistory, got {other:?}"),
    }
}

fn gen5_history_summary(frame: &[u8]) -> DataPacketBodySummary {
    let parsed = parse_frame(DeviceType::Goose, frame).unwrap();
    let ParsedPayload::DataPacket {
        body_summary: Some(summary),
        ..
    } = parsed.parsed_payload.unwrap()
    else {
        panic!("expected a Gen5 data packet");
    };
    summary
}

#[test]
fn deframer_reassembles_split_v5_frame_and_drops_prefix_noise() {
    let frame = hex::decode(GET_HELLO_FRAME).unwrap();
    let mut accumulator = FrameAccumulator::new(DeviceType::Goose);

    let first = accumulator.feed(&[0x00, 0x01, frame[0], frame[1], frame[2]]);
    assert!(first.frames.is_empty());
    assert_eq!(first.dropped_prefix_len, 2);
    assert_eq!(first.buffered_len, 3);

    let second = accumulator.feed(&frame[3..]);
    assert_eq!(second.frames, vec![frame]);
    assert_eq!(second.buffered_len, 0);
}

#[test]
fn payload_crc_mismatch_preserves_parseable_header_with_warning() {
    let mut frame = hex::decode(GET_HELLO_FRAME).unwrap();
    let last = frame.len() - 1;
    frame[last] ^= 0xff;

    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert!(parsed.header_crc_valid);
    assert!(!parsed.payload_crc_valid);
    assert_eq!(parsed.packet_type, Some(35));
    assert!(
        parsed
            .warnings
            .contains(&"payload_crc_mismatch".to_string())
    );
}

#[test]
fn malformed_length_fails_safely() {
    let mut frame = hex::decode(GET_HELLO_FRAME).unwrap();
    frame[2] = 0x04;
    frame[3] = 0x00;

    let error = parse_frame(DeviceType::Goose, &frame).unwrap_err();
    assert!(error.to_string().contains("declared length"));
}

#[test]
fn parses_generic_command_response_payload_contract() {
    let frame = build_v5_payload_frame(&[
        PACKET_TYPE_COMMAND_RESPONSE,
        9,
        COMMAND_GET_HELLO,
        1,
        0,
        0xaa,
        0xbb,
        0xcc,
    ]);
    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert_eq!(parsed.packet_type_name.as_deref(), Some("COMMAND_RESPONSE"));
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::CommandResponse {
            response_to_command: Some(COMMAND_GET_HELLO),
            response_to_command_name: Some("GET_HELLO".to_string()),
            origin_sequence: Some(1),
            result_code: Some(0),
            data_offset: 5,
            data_hex: "aabbcc".to_string(),
            warnings: Vec::new(),
        })
    );
}

#[test]
fn parses_event_header_and_preserves_unknown_event_body() {
    let frame = build_v5_payload_frame(&[
        PACKET_TYPE_EVENT,
        2,
        17,
        0,
        0x04,
        0x03,
        0x02,
        0x01,
        0x06,
        0x05,
        0,
        0,
        0xde,
        0xad,
        0xbe,
        0xef,
    ]);
    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert_eq!(parsed.packet_type_name.as_deref(), Some("EVENT"));
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::Event {
            event_id: Some(17),
            event_name: Some("TEMPERATURE_LEVEL".to_string()),
            timestamp_seconds: Some(0x01020304),
            timestamp_subseconds: Some(0x0506),
            data_offset: 12,
            data_hex: "deadbeef".to_string(),
            warnings: Vec::new(),
        })
    );
}

#[test]
fn parses_history_packet_stable_header_and_hr_marker() {
    let frame = build_v5_payload_frame(&[
        PACKET_TYPE_HISTORICAL_DATA,
        18,
        1,
        0x04,
        0x03,
        0x02,
        0x01,
        0x44,
        0x33,
        0x22,
        0x11,
        0x66,
        0x55,
        0xaa,
        0x4d,
        0xbb,
        0xcc,
        0xdd,
        0xee,
        0xff,
    ]);
    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert_eq!(parsed.packet_type_name.as_deref(), Some("HISTORICAL_DATA"));
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::DataPacket {
            packet_k: Some(18),
            domain: Some("normal_history_with_hr_marker".to_string()),
            status_or_stream: Some(1),
            counter_or_page: Some(0x01020304),
            timestamp_seconds: Some(0x11223344),
            timestamp_subseconds: Some(0x5566),
            hr_marker_offset: Some(14),
            hr_present_marker: Some(0x4d),
            body_offset: 13,
            body_hex: "aa4dbbccddeeff".to_string(),
            body_summary: Some(DataPacketBodySummary::NormalHistory {
                hr_present: Some(true),
                marker_offset: Some(14),
                marker_value: Some(0x4d),
            }),
            warnings: Vec::new(),
        })
    );
}

#[test]
fn normal_history_zero_hr_marker_is_not_treated_as_hr_present() {
    let mut payload = vec![PACKET_TYPE_HISTORICAL_DATA, 9, 1];
    payload.extend_from_slice(&1u32.to_le_bytes());
    payload.extend_from_slice(&2u32.to_le_bytes());
    payload.extend_from_slice(&3u16.to_le_bytes());
    payload.resize(18, 0);
    payload[17] = 0;
    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.is_empty());
            assert_eq!(
                body_summary,
                Some(DataPacketBodySummary::NormalHistory {
                    hr_present: Some(false),
                    marker_offset: Some(17),
                    marker_value: Some(0),
                })
            );
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn parses_r17_optical_body_offsets_and_signed_sample_stats() {
    let mut payload = vec![0; 32];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 17;
    payload[2] = 1;
    put_u16(&mut payload, 13, (1 << 9) | (1 << 11));
    payload[15..=20].copy_from_slice(&[1, 2, 3, 4, 5, 6]);
    put_u16(&mut payload, 24, 3);
    put_i16(&mut payload, 26, 1000);
    put_i16(&mut payload, 28, -1000);
    put_i16(&mut payload, 30, 200);

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.is_empty());
            assert_eq!(
                body_summary,
                Some(DataPacketBodySummary::R17OpticalOrLabradorFiltered {
                    flags: Some(0x0a00),
                    flag_bit_9: Some(true),
                    flag_bit_11: Some(true),
                    channels_or_gain: vec![1, 2, 3, 4, 5, 6],
                    sample_count: Some(3),
                    samples: Some(I16SeriesSummary {
                        name: "r17_samples".to_string(),
                        offset: 26,
                        expected_count: 3,
                        parsed_count: 3,
                        min: Some(-1000),
                        max: Some(1000),
                        sum: 200,
                        preview: vec![1000, -1000, 200],
                    }),
                    warnings: Vec::new(),
                })
            );
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn r17_truncated_samples_warn_without_losing_available_values() {
    let mut payload = vec![0; 28];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 17;
    put_u16(&mut payload, 24, 4);
    put_i16(&mut payload, 26, -7);

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.contains(&"r17_samples_truncated".to_string()));
            let Some(DataPacketBodySummary::R17OpticalOrLabradorFiltered {
                samples,
                warnings: summary_warnings,
                ..
            }) = body_summary
            else {
                panic!("expected r17 body summary");
            };
            assert!(summary_warnings.contains(&"r17_samples_truncated".to_string()));
            assert_eq!(samples.unwrap().parsed_count, 1);
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn parses_k10_raw_motion_offsets_without_claiming_units() {
    let mut payload = vec![0; 1288];
    payload[0] = PACKET_TYPE_REALTIME_RAW_DATA;
    payload[1] = 10;
    payload[17] = 72;
    put_i16(&mut payload, 85, 1);
    put_i16(&mut payload, 87, -2);
    put_i16(&mut payload, 89, 3);
    put_i16(&mut payload, 1088, -10);
    put_i16(&mut payload, 1090, 20);

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.is_empty());
            let Some(DataPacketBodySummary::RawMotionK10 {
                heart_rate,
                axes,
                warnings: summary_warnings,
            }) = body_summary
            else {
                panic!("expected k10 body summary");
            };
            assert_eq!(heart_rate, Some(72));
            assert!(summary_warnings.is_empty());
            assert_eq!(axes.len(), 6);
            assert_eq!(axes[0].name, "accelerometer_x");
            assert_eq!(axes[0].expected_count, 100);
            assert_eq!(axes[0].parsed_count, 100);
            assert_eq!(axes[0].min, Some(-2));
            assert_eq!(axes[0].max, Some(3));
            assert_eq!(axes[0].sum, 2);
            assert_eq!(axes[5].name, "gyroscope_z");
            assert_eq!(axes[5].min, Some(-10));
            assert_eq!(axes[5].max, Some(20));
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn parses_k21_grouped_motion_offsets_and_counts() {
    let mut payload = vec![0; 1038];
    payload[0] = PACKET_TYPE_REALTIME_DATA;
    payload[1] = 21;
    put_u16(&mut payload, 14, 321);
    put_u16(&mut payload, 16, 3);
    put_u16(&mut payload, 622, 3);
    put_i16(&mut payload, 20, -1);
    put_i16(&mut payload, 22, 2);
    put_i16(&mut payload, 24, -3);
    put_i16(&mut payload, 1032, 50);
    put_i16(&mut payload, 1034, 60);
    put_i16(&mut payload, 1036, 70);

    let parsed = parse_frame(DeviceType::Goose, &build_v5_payload_frame(&payload)).unwrap();

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.is_empty());
            let Some(DataPacketBodySummary::RawMotionK21 {
                field_x,
                group_1_count,
                group_2_count,
                axes,
                warnings: summary_warnings,
            }) = body_summary
            else {
                panic!("expected k21 body summary");
            };
            assert_eq!(field_x, Some(321));
            assert_eq!(group_1_count, Some(3));
            assert_eq!(group_2_count, Some(3));
            assert!(summary_warnings.is_empty());
            assert_eq!(axes.len(), 6);
            assert_eq!(axes[0].name, "group_1_axis_0");
            assert_eq!(axes[0].preview, vec![-1, 2, -3]);
            assert_eq!(axes[0].sum, -2);
            assert_eq!(axes[5].name, "group_2_axis_2");
            assert_eq!(axes[5].preview, vec![50, 60, 70]);
            assert_eq!(axes[5].sum, 180);
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn truncated_long_motion_frame_keeps_partial_samples_with_quality_warnings() {
    let mut payload = vec![0; 1038];
    payload[0] = PACKET_TYPE_REALTIME_DATA;
    payload[1] = 21;
    put_u16(&mut payload, 14, 321);
    put_u16(&mut payload, 16, 100);
    put_i16(&mut payload, 20, -1);
    put_i16(&mut payload, 22, 2);
    put_i16(&mut payload, 24, -3);
    let mut frame = build_v5_payload_frame(&payload);
    frame.truncate(180);

    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert_eq!(parsed.raw_len, 180);
    assert!(parsed.declared_len > parsed.raw_len);
    assert!(!parsed.payload_crc_valid);
    assert_eq!(parsed.payload_crc_hex, "");
    assert!(parsed.warnings.contains(&"frame_truncated".to_string()));
    assert!(
        parsed
            .warnings
            .contains(&"payload_crc_unavailable_due_to_truncated_frame".to_string())
    );
    assert!(
        !parsed
            .warnings
            .contains(&"payload_crc_mismatch".to_string())
    );

    match parsed.parsed_payload.unwrap() {
        ParsedPayload::DataPacket {
            body_summary,
            warnings,
            ..
        } => {
            assert!(warnings.contains(&"group_1_axis_0_truncated".to_string()));
            let Some(DataPacketBodySummary::RawMotionK21 {
                axes,
                warnings: summary_warnings,
                ..
            }) = body_summary
            else {
                panic!("expected k21 body summary");
            };
            assert!(summary_warnings.contains(&"group_1_axis_0_truncated".to_string()));
            assert_eq!(axes[0].name, "group_1_axis_0");
            assert_eq!(axes[0].expected_count, 100);
            assert_eq!(axes[0].parsed_count, 76);
            assert_eq!(axes[0].preview[0..3], [-1, 2, -3]);
        }
        other => panic!("expected data packet, got {other:?}"),
    }
}

#[test]
fn truncated_non_data_frame_fails_instead_of_becoming_decoded_evidence() {
    let mut frame = build_v5_command_frame(1, COMMAND_GET_HELLO, &[1, 2, 3, 4, 5, 6, 7, 8]);
    frame.truncate(frame.len() - 3);

    let error = parse_frame(DeviceType::Goose, &frame).unwrap_err();

    assert!(error.to_string().contains("declared length"));
}

#[test]
fn short_data_packets_preserve_raw_body_and_warn() {
    let frame = build_v5_payload_frame(&[PACKET_TYPE_HISTORICAL_DATA, 18, 1, 2]);
    let parsed = parse_frame(DeviceType::Goose, &frame).unwrap();

    assert!(
        parsed
            .warnings
            .contains(&"data_packet_header_too_short".to_string())
    );
    assert!(
        parsed
            .warnings
            .contains(&"history_hr_marker_missing".to_string())
    );
    assert_eq!(
        parsed.parsed_payload,
        Some(ParsedPayload::DataPacket {
            packet_k: Some(18),
            domain: Some("normal_history_with_hr_marker".to_string()),
            status_or_stream: Some(1),
            counter_or_page: None,
            timestamp_seconds: None,
            timestamp_subseconds: None,
            hr_marker_offset: Some(14),
            hr_present_marker: None,
            body_offset: 4,
            body_hex: String::new(),
            body_summary: Some(DataPacketBodySummary::NormalHistory {
                hr_present: None,
                marker_offset: Some(14),
                marker_value: None,
            }),
            warnings: vec![
                "data_packet_header_too_short".to_string(),
                "history_hr_marker_missing".to_string(),
            ],
        })
    );
}

fn put_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}

fn put_i16(bytes: &mut [u8], offset: usize, value: i16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}
