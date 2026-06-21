import Darwin
import Foundation
import SwiftUI
import UIKit

@MainActor
final class HealthDataStore: ObservableObject {
  @Published var algorithmDefinitions: [HealthAlgorithmDefinition]
  @Published var referenceDefinitions: [HealthAlgorithmDefinition]
  @Published var selectedAlgorithmByFamily: [String: String]
  @Published var catalogStatus = "Metric catalog not loaded"
  @Published var catalogSource = HealthDataSource.unavailable("metric registry not loaded")
  @Published var packetInputStatus = "No run"
  @Published var packetScoreStatus = "No run"
  @Published var bandSleepImportStatus = "No band sync yet"
  @Published var externalSleepImportStatus = "External sleep imports disabled"
  @Published var referenceRunStatusByFamily: [String: String] = [:]
  @Published var primarySleepDetail: PrimarySleepDetail?
  @Published var calibrationTargetFamily = "recovery"
  @Published var calibrationLabelsImported = false
  @Published var calibrationRunComplete = false
  @Published var heartRateHourlyRanges: [HeartRateHourlyRange] = []
  @Published var heartRateTimelineStatus = "No HR samples stored"

  let bridge = WhoofRustBridge()
  let heartRateSeriesStore = HeartRateSeriesStore.shared
  var attemptedCatalogLoad = false
  var previewMissingData = false
  var packetInputReports: [String: [String: Any]] = [:]
  var packetScoreReports: [String: [String: Any]] = [:]
  var referenceComparisonReports: [String: [String: Any]] = [:]
  var packetInputRefreshWorkItem: DispatchWorkItem?
  var packetInputRunID: UUID?
  var packetInputIsRunning = false
  var heartRateTimelineRefreshID: UUID?
  var heartRateSeriesUpdateObserver: NSObjectProtocol?
  // Memoizes stressAlgorithmSummary, which is O(day's HR samples) and was the
  // hottest symbol in an on-device Time Profiler trace — it is invoked several
  // times per render (view bodies, energyBankAlgorithmSummary, landingSnapshots).
  // Keyed by a cheap sample-set signature so it self-invalidates when HR data
  // changes. Not @Published: mutating it must not trigger view invalidation.
  var stressSummaryCache: [String: StressAlgorithmSummary] = [:]
  let packetInputQueue = DispatchQueue(label: "com.whoof.swift.health.packet-inputs", qos: .utility)
  let heartRateTimelineQueue = DispatchQueue(label: "com.whoof.swift.health.heart-rate-timeline", qos: .utility)
  lazy var databasePath = HealthDataStore.defaultDatabasePath()

  static let liveHRVRMSSDDefaultsKey = "goose.swift.liveHRVRMSSD"
  static let liveHRVRRIntervalCountDefaultsKey = "goose.swift.liveHRVRRIntervalCount"
  static let liveHRVRMSSDSampleCountDefaultsKey = "goose.swift.liveHRVRMSSDSampleCount"
  static let liveHRVUpdatedAtDefaultsKey = "goose.swift.liveHRVUpdatedAt"
  static let liveHRVSourceDefaultsKey = "goose.swift.liveHRVSource"
  static let restingHeartRateEstimateBPMDefaultsKey = "goose.swift.restingHeartRateEstimateBPM"
  static let restingHeartRateEstimateSampleCountDefaultsKey = "goose.swift.restingHeartRateEstimateSampleCount"
  static let restingHeartRateEstimateUpdatedAtDefaultsKey = "goose.swift.restingHeartRateEstimateUpdatedAt"
  static let restingHeartRateEstimateSourceDefaultsKey = "goose.swift.restingHeartRateEstimateSource"

  init() {
    algorithmDefinitions = []
    referenceDefinitions = []
    selectedAlgorithmByFamily = [:]
    primarySleepDetail = nil
    refreshHeartRateTimeline()
    heartRateSeriesUpdateObserver = NotificationCenter.default.addObserver(
      forName: HeartRateSeriesStore.didUpdateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.refreshHeartRateTimeline()
      }
    }
  }

  deinit {
    if let heartRateSeriesUpdateObserver {
      NotificationCenter.default.removeObserver(heartRateSeriesUpdateObserver)
    }
  }

  static func defaultDatabasePath() -> String {
    let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let directory = baseDirectory.appendingPathComponent("WhoofSwift", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("goose.sqlite").path
  }

  var usesSampleData: Bool {
    false
  }

  var localDataSupportsExport: Bool {
    !packetInputReports.isEmpty || !packetScoreReports.isEmpty || !referenceComparisonReports.isEmpty
  }

  var localHealthExportText: String {
    [
      "Whoof Health Export",
      "Catalog: \(catalogStatus)",
      "Band sleep import: \(bandSleepImportStatus)",
      "HealthKit metric import: disabled; profile weight only",
      "Packet inputs: \(packetInputStatus)",
      "Packet scores: \(packetScoreStatus)",
      "Readiness: \(metricInputReadinessSummary())",
      "Sleep: \(sleepFeatureScoreSummary())",
      "Recovery: \(recoveryFeatureScoreSummary())",
      "Strain: \(strainFeatureScoreSummary())",
      "Stress: \(stressFeatureScoreSummary())",
    ].joined(separator: "\n")
  }

  func loadBridgeCatalogsIfNeeded() {
    guard !attemptedCatalogLoad else {
      return
    }
    attemptedCatalogLoad = true
    refreshBridgeCatalogs()
  }

  func refreshPacketInputsIfNeeded() {
    guard packetInputReports.isEmpty, packetInputStatus == "No run" else {
      return
    }
    runPacketInputs()
  }

  func refreshHeartRateTimeline(for date: Date = Date()) {
    let refreshID = UUID()
    heartRateTimelineRefreshID = refreshID
    let store = heartRateSeriesStore
    heartRateTimelineQueue.async { [weak self] in
      let snapshot = store.timelineSnapshot(forDayContaining: date)
      Task { @MainActor in
        guard let self,
              self.heartRateTimelineRefreshID == refreshID else {
          return
        }
        self.heartRateHourlyRanges = snapshot.ranges
        self.heartRateTimelineStatus = snapshot.status
      }
    }
  }

  func heartRateHourlyTimelineRows(maxRows: Int = 8) -> [HealthSummaryRow] {
    let ranges = Array(heartRateHourlyRanges.suffix(maxRows)).reversed()
    guard !ranges.isEmpty else {
      return []
    }

    return ranges.map { range in
      let hour = range.hourStart.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)))
      return HealthSummaryRow(
        "HR \(hour)",
        value: "\(range.minBPM)-\(range.maxBPM) bpm | avg \(range.averageBPM) | \(range.sampleCount) samples",
        source: .live("BLE heart-rate sample store"),
        systemImage: "heart"
      )
    }
  }

  func refreshPacketInputsAfterCapture() {
    packetInputRefreshWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.runPacketInputs()
    }
    packetInputRefreshWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
  }

  func refreshBridgeCatalogs() {
    // The three catalog reads are pure Rust FFI (no device or DB state), but
    // each is a synchronous round-trip. Running them inline blocked the main
    // thread on every tab open (loadBridgeCatalogsIfNeeded fires from 7 view
    // .onAppear sites). Do the FFI off-main on a private bridge instance, then
    // parse + apply on the main actor — mirroring refreshHeartRateTimeline.
    packetInputQueue.async { [weak self] in
      let bridge = WhoofRustBridge()
      let outcome: Result<(Any, Any, Any), Error>
      do {
        let algorithmsValue = try bridge.requestValue(method: "metrics.built_in_definitions")
        let referencesValue = try bridge.requestValue(method: "metrics.reference_definitions")
        let preferencesValue = try bridge.requestValue(method: "metrics.default_preferences")
        outcome = .success((algorithmsValue, referencesValue, preferencesValue))
      } catch {
        outcome = .failure(error)
      }
      Task { @MainActor in
        self?.applyBridgeCatalogs(outcome)
      }
    }
  }

  private func applyBridgeCatalogs(_ outcome: Result<(Any, Any, Any), Error>) {
    switch outcome {
    case .success(let (algorithmsValue, referencesValue, preferencesValue)):
      let parsedAlgorithms = Self.algorithmRows(from: algorithmsValue)
        .map { HealthAlgorithmDefinition(row: $0, source: .bridge("metrics.built_in_definitions")) }
      let parsedReferences = Self.algorithmRows(from: referencesValue)
        .map { HealthAlgorithmDefinition(row: $0, source: .bridge("metrics.reference_definitions")) }
      let parsedPreferences = Self.preferenceRows(from: preferencesValue)

      if !parsedAlgorithms.isEmpty {
        algorithmDefinitions = parsedAlgorithms
      }
      if !parsedReferences.isEmpty {
        referenceDefinitions = parsedReferences
      }
      if !parsedPreferences.isEmpty {
        selectedAlgorithmByFamily = parsedPreferences
      } else {
        selectedAlgorithmByFamily = Dictionary(
          uniqueKeysWithValues: algorithmDefinitions.map { ($0.family, $0.id) }
        )
      }
      catalogSource = .bridge("Rust metric registry")
      catalogStatus = "Bridge catalog loaded"
    case .failure(let error):
      algorithmDefinitions = []
      referenceDefinitions = []
      selectedAlgorithmByFamily = [:]
      catalogSource = .unavailable("Rust catalog unavailable")
      catalogStatus = "Metric catalog unavailable: \(Self.shortError(error))"
    }
  }

  func selectAlgorithm(_ algorithmID: String, for family: String) {
    selectedAlgorithmByFamily[family] = algorithmID
  }

  func runPacketInputs(completion: (() -> Void)? = nil) {
    guard !packetInputIsRunning else {
      packetInputStatus = "Packet-derived input extraction already running..."
      completion?()
      return
    }
    packetInputRefreshWorkItem?.cancel()
    let runID = UUID()
    packetInputRunID = runID
    packetInputIsRunning = true
    let databasePath = databasePath
    packetInputStatus = "Extracting packet-derived inputs..."

    packetInputQueue.async { [weak self] in
      let result = HealthDataStore.packetInputBridgeReports(databasePath: databasePath)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.packetInputRunID == runID else {
          return
        }
        self.packetInputIsRunning = false
        switch result {
        case .success(let reports):
          self.packetInputReports = reports
          self.packetInputStatus = "Bridge packet-derived inputs extracted"
        case .failure(let error):
          self.packetInputStatus = "Bridge input extraction blocked: \(HealthDataStore.shortError(error))"
        }
        completion?()
      }
    }
  }

  func markBandSleepSyncRequested(automatic: Bool, canSync: Bool, detail: String) {
    if canSync {
      bandSleepImportStatus = automatic ? "Auto-syncing band sleep packets..." : "Syncing band sleep packets..."
    } else {
      bandSleepImportStatus = "Band sync unavailable: \(detail)"
    }
  }

  func markBandSleepSyncFailed(_ detail: String) {
    bandSleepImportStatus = "Band sync failed: \(detail)"
  }

  func refreshSleepAfterBandSync(packetCount: Int) {
    bandSleepImportStatus = "Band sync captured \(packetCount) packets | extracting sleep inputs..."
    runPacketInputs { [weak self] in
      guard let self else {
        return
      }
      self.runSleepScore()
      self.bandSleepImportStatus = "Band sync captured \(packetCount) packets | \(self.packetScoreStatus)"
    }
  }
}
