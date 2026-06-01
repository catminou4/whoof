import Foundation
import HealthKit

struct ImportedSleepStage {
  let stage: String
  let startDate: Date
  let endDate: Date
  let confidence: Double?

  var durationMinutes: Double {
    max(0, endDate.timeIntervalSince(startDate) / 60)
  }
}

struct ImportedPrimarySleep {
  let id: String
  let startDate: Date
  let endDate: Date
  let asleepMinutes: Double
  let timeInBedMinutes: Double
  let stages: [ImportedSleepStage]
}

struct HealthKitSleepImportBatch {
  let sessions: [[String: Any]]
  let stages: [[String: Any]]
  let latestPrimarySleep: ImportedPrimarySleep?

  var isEmpty: Bool {
    sessions.isEmpty && stages.isEmpty
  }
}

enum HealthKitSleepImporter {
  static func recentSleepHistory(dayCount: Int = 14) async throws -> HealthKitSleepImportBatch {
    guard HKHealthStore.isHealthDataAvailable(),
      let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    else {
      throw HealthKitSleepImporterError.unavailable
    }

    let store = HKHealthStore()
    try await requestAuthorization(store: store, readTypes: [sleepType])

    let endDate = Date()
    let startDate = Calendar.current.date(byAdding: .day, value: -dayCount, to: endDate) ?? endDate
    let samples = try await sleepSamples(store: store, type: sleepType, startDate: startDate, endDate: endDate)

    return makeBatch(from: samples)
  }

  private static func requestAuthorization(store: HKHealthStore, readTypes: Set<HKObjectType>) async throws {
    let _: Void = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      store.requestAuthorization(toShare: [], read: readTypes) { success, error in
        if let error {
          continuation.resume(throwing: error)
        } else if success {
          continuation.resume()
        } else {
          continuation.resume(throwing: HealthKitSleepImporterError.authorizationDenied)
        }
      }
    }
  }

  private static func sleepSamples(
    store: HKHealthStore,
    type: HKCategoryType,
    startDate: Date,
    endDate: Date
  ) async throws -> [HKCategorySample] {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKCategorySample], Error>) in
      let predicate = HKQuery.predicateForSamples(
        withStart: startDate,
        end: endDate,
        options: [.strictEndDate]
      )
      let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
      let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: samples as? [HKCategorySample] ?? [])
      }
      store.execute(query)
    }
  }

  private static func makeBatch(from samples: [HKCategorySample]) -> HealthKitSleepImportBatch {
    let stages = samples.compactMap(stageRecord)
    let windows = sleepWindows(from: samples, stages: stages)
    let sessions = windows.map(sessionPayload)
    let stagePayloads = windows.flatMap(stagePayloads)
    let primarySleep = windows.max { $0.endDate < $1.endDate }?.primarySleep

    return HealthKitSleepImportBatch(
      sessions: sessions,
      stages: stagePayloads,
      latestPrimarySleep: primarySleep
    )
  }

  private static func sleepWindows(from samples: [HKCategorySample], stages: [HealthKitSleepStageRecord]) -> [HealthKitSleepWindow] {
    let inBedSamples = samples.filter { HKCategoryValueSleepAnalysis(rawValue: $0.value) == .inBed }

    if !inBedSamples.isEmpty {
      return inBedSamples.map { sample in
        let sleepID = "healthkit-\(sample.uuid.uuidString)"
        return HealthKitSleepWindow(
          id: sleepID,
          platformRecordID: sample.uuid.uuidString,
          startDate: sample.startDate,
          endDate: sample.endDate,
          stages: stages.filter { stage in
            stage.startDate >= sample.startDate && stage.endDate <= sample.endDate
          }
        )
      }
    }

    let groupedStages = Dictionary(grouping: stages, by: sleepDateKey)
    return groupedStages.values.compactMap { stageGroup in
      guard let startDate = stageGroup.map(\.startDate).min(),
        let endDate = stageGroup.map(\.endDate).max()
      else {
        return nil
      }

      let sleepID = "healthkit-\(sleepDateKey(for: startDate))"
      return HealthKitSleepWindow(
        id: sleepID,
        platformRecordID: nil,
        startDate: startDate,
        endDate: endDate,
        stages: stageGroup.sorted { $0.startDate < $1.startDate }
      )
    }
    .sorted { $0.endDate > $1.endDate }
  }

  private static func stageRecord(from sample: HKCategorySample) -> HealthKitSleepStageRecord? {
    guard let stage = stageKind(for: sample.value) else {
      return nil
    }
    return HealthKitSleepStageRecord(
      id: "healthkit-\(sample.uuid.uuidString)",
      stage: stage,
      sampleUUID: sample.uuid.uuidString,
      startDate: sample.startDate,
      endDate: sample.endDate,
      confidence: 0.86
    )
  }

  private static func stageKind(for value: Int) -> String? {
    guard let value = HKCategoryValueSleepAnalysis(rawValue: value) else {
      return nil
    }

    switch value {
    case .awake:
      return "awake"
    case .asleepREM:
      return "rem"
    case .asleepDeep:
      return "deep"
    case .asleepCore, .asleep, .asleepUnspecified:
      return "core"
    case .inBed:
      return nil
    @unknown default:
      return nil
    }
  }

  private static func sessionPayload(for window: HealthKitSleepWindow) -> [String: Any] {
    var payload: [String: Any] = [
      "sleep_id": window.id,
      "source": "healthkit",
      "platform": "healthkit",
      "start_time_unix_ms": unixMilliseconds(window.startDate),
      "end_time_unix_ms": unixMilliseconds(window.endDate),
      "timezone": TimeZone.current.identifier,
      "stage_summary": window.stageSummary,
      "confidence": window.confidence,
      "provenance": [
        "source": "HealthKit",
        "stage_count": window.stages.count,
        "imported_by": "GooseSwift",
      ],
    ]
    if let platformRecordID = window.platformRecordID {
      payload["platform_record_id"] = platformRecordID
    }
    return payload
  }

  private static func stagePayloads(for window: HealthKitSleepWindow) -> [[String: Any]] {
    window.stages.map { stage in
      [
        "stage_id": stage.id,
        "sleep_id": window.id,
        "stage_kind": stage.stage,
        "start_time_unix_ms": unixMilliseconds(stage.startDate),
        "end_time_unix_ms": unixMilliseconds(stage.endDate),
        "confidence": stage.confidence,
        "provenance": [
          "source": "HealthKit",
          "sample_uuid": stage.sampleUUID,
          "imported_by": "GooseSwift",
        ],
      ]
    }
  }

  private static func sleepDateKey(for date: Date) -> String {
    let anchor = Calendar.current.date(byAdding: .hour, value: -12, to: date) ?? date
    let components = Calendar.current.dateComponents([.year, .month, .day], from: anchor)
    return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  private static func sleepDateKey(for stage: HealthKitSleepStageRecord) -> String {
    sleepDateKey(for: stage.startDate)
  }

  private static func unixMilliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}

private struct HealthKitSleepStageRecord {
  let id: String
  let stage: String
  let sampleUUID: String
  let startDate: Date
  let endDate: Date
  let confidence: Double

  var durationMinutes: Double {
    max(0, endDate.timeIntervalSince(startDate) / 60)
  }
}

private struct HealthKitSleepWindow {
  let id: String
  let platformRecordID: String?
  let startDate: Date
  let endDate: Date
  let stages: [HealthKitSleepStageRecord]

  var confidence: Double {
    stages.isEmpty ? 0.75 : 0.86
  }

  var stageSummary: [String: Any] {
    var minutesByStage: [String: Double] = [:]
    for stage in stages {
      minutesByStage[stage.stage, default: 0] += stage.durationMinutes
    }
    guard !minutesByStage.isEmpty else {
      return [:]
    }
    return [
      "minutes_by_stage": minutesByStage,
      "stage_count": stages.count,
    ]
  }

  var primarySleep: ImportedPrimarySleep {
    let stageModels = stages.map { stage in
      ImportedSleepStage(
        stage: stage.stage,
        startDate: stage.startDate,
        endDate: stage.endDate,
        confidence: stage.confidence
      )
    }

    let asleepMinutes = stages
      .filter { $0.stage != "awake" }
      .reduce(0) { $0 + $1.durationMinutes }
    let fallbackMinutes = max(0, endDate.timeIntervalSince(startDate) / 60)

    return ImportedPrimarySleep(
      id: id,
      startDate: startDate,
      endDate: endDate,
      asleepMinutes: asleepMinutes > 0 ? asleepMinutes : fallbackMinutes,
      timeInBedMinutes: fallbackMinutes,
      stages: stageModels
    )
  }
}

enum HealthKitSleepImporterError: LocalizedError {
  case unavailable
  case authorizationDenied

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "HealthKit sleep analysis is unavailable on this device."
    case .authorizationDenied:
      return "HealthKit sleep read access was denied."
    }
  }
}
