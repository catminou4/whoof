import SwiftUI

enum HealthRoute: String, CaseIterable, Identifiable, Hashable {
  case healthMonitor
  case sleep
  case recovery
  case strain
  case stress
  case cardioLoad
  case energyBank
  case packetInputs
  case algorithms
  case referenceComparisons
  case calibration

  var id: String { rawValue }

  var title: String {
    switch self {
    case .healthMonitor: "Health Monitor"
    case .sleep: "Sleep"
    case .recovery: "Recovery"
    case .strain: "Strain"
    case .stress: "Stress"
    case .cardioLoad: "Cardio Load"
    case .energyBank: "Energy Bank"
    case .packetInputs: "Packet Inputs"
    case .algorithms: "Algorithms"
    case .referenceComparisons: "Reference Comparisons"
    case .calibration: "Calibration"
    }
  }

  var systemImage: String {
    switch self {
    case .healthMonitor: "heart.text.square"
    case .sleep: "bed.double"
    case .recovery: "battery.100percent"
    case .strain: "figure.run"
    case .stress: "waveform.path.ecg"
    case .cardioLoad: "heart.circle"
    case .energyBank: "bolt.circle"
    case .packetInputs: "square.stack.3d.up"
    case .algorithms: "function"
    case .referenceComparisons: "scalemass"
    case .calibration: "slider.horizontal.3"
    }
  }

  var deepLinkPath: String {
    "gooseswift://health/\(rawValue)"
  }
}

struct HealthMetricSnapshot: Identifiable {
  let id: String
  let route: HealthRoute
  let group: HealthMetricGroup
  let title: String
  let value: String
  let unit: String
  let status: String
  let freshness: String
  let provenance: String
  let source: HealthDataSource
  let systemImage: String
  let tint: Color
  let trend: HealthTrendModel

  var displayValue: String {
    unit.isEmpty ? value : "\(value) \(unit)"
  }
}

enum HealthMetricGroup: String, CaseIterable {
  case today = "Today"
  case vitals = "Vitals"
  case training = "Training"
  case algorithms = "Algorithms"
}

struct HealthTrendModel: Identifiable {
  let id: String
  let title: String
  let rangeLabel: String
  let summary: String
  let analysis: String
  let resources: [String]
  let points: [HealthTrendPoint]

  var hasData: Bool {
    !points.isEmpty
  }
}

struct HealthTrendPoint: Identifiable {
  let id = UUID()
  let label: String
  let value: Double
}

struct HealthDataSource: Equatable {
  enum Kind: String {
    case bridge = "Bridge"
    case live = "Live"
    case sample = "Sample"
    case unavailable = "Unavailable"
  }

  let kind: Kind
  let detail: String
  let isSample: Bool

  static func bridge(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .bridge, detail: detail, isSample: false)
  }

  static func live(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .live, detail: detail, isSample: false)
  }

  static func sample(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .sample, detail: detail, isSample: true)
  }

  static func unavailable(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .unavailable, detail: detail, isSample: false)
  }

  var label: String {
    "\(kind.rawValue): \(detail)"
  }
}

struct HealthSummaryRow: Identifiable {
  let id: String
  let label: String
  let value: String
  let status: String
  let source: HealthDataSource
  let systemImage: String

  init(
    _ label: String,
    value: String,
    status: String = "",
    source: HealthDataSource,
    systemImage: String = "circle"
  ) {
    self.id = label
    self.label = label
    self.value = value
    self.status = status
    self.source = source
    self.systemImage = systemImage
  }
}

struct HealthSleepStageSegment: Identifiable {
  let id: String
  let stage: String
  let startLabel: String
  let endLabel: String
  let durationMinutes: Double
  let confidence: Double?
  let source: HealthDataSource

  var displayStage: String {
    stage.capitalized
  }

  var durationText: String {
    HealthDataStore.minutesText(durationMinutes)
  }
}

struct PrimarySleepDetail: Identifiable {
  let id: String
  let dateLabel: String
  let startLabel: String
  let endLabel: String
  let durationText: String
  let timeInBedText: String
  let scoreText: String
  let qualityText: String
  let source: HealthDataSource
  let stages: [HealthSleepStageSegment]

  var scoreDisplayText: String {
    scoreText == "--" ? "--" : "\(scoreText)%"
  }
}

struct CardioLoadDay: Identifiable {
  let id: String
  let dateLabel: String
  let load: Double
  let status: String
  let durationText: String
  let percent: Double
  let source: HealthDataSource
}

struct EnergyStressPoint: Identifiable {
  let id: String
  let timeLabel: String
  let energy: Double
  let stress: Double
  let usage: Double
  let isSleepWindow: Bool
  let isChargeEvent: Bool
}

enum HealthPreviewState {
  case populated
  case missing
}

struct HealthAlgorithmDefinition: Identifiable {
  let id: String
  let displayName: String
  let family: String
  let status: String
  let provider: String
  let source: HealthDataSource

  init(row: [String: Any], source: HealthDataSource) {
    let algorithmID = row["algorithm_id"] as? String ?? row["id"] as? String ?? "unknown.algorithm"
    id = algorithmID
    displayName = row["display_name"] as? String ?? algorithmID
    family = row["metric_family"] as? String ?? "metric"
    status = row["status"] as? String ?? "ready"
    provider = row["provider"] as? String ?? row["implementation"] as? String ?? "goose"
    self.source = source
  }

  init(id: String, displayName: String, family: String, status: String, provider: String, source: HealthDataSource) {
    self.id = id
    self.displayName = displayName
    self.family = family
    self.status = status
    self.provider = provider
    self.source = source
  }
}

@MainActor
final class HealthDataStore: ObservableObject {
  @Published private(set) var algorithmDefinitions: [HealthAlgorithmDefinition]
  @Published private(set) var referenceDefinitions: [HealthAlgorithmDefinition]
  @Published var selectedAlgorithmByFamily: [String: String]
  @Published private(set) var catalogStatus = "Sample catalog loaded"
  @Published private(set) var catalogSource = HealthDataSource.sample("HealthDataStore fixtures")
  @Published private(set) var packetInputStatus = "No run"
  @Published private(set) var packetScoreStatus = "No run"
  @Published private(set) var externalSleepImportStatus = "No import"
  @Published private(set) var referenceRunStatusByFamily: [String: String] = [:]
  @Published private(set) var primarySleepDetail: PrimarySleepDetail?
  @Published var calibrationTargetFamily = "recovery"
  @Published private(set) var calibrationLabelsImported = false
  @Published private(set) var calibrationRunComplete = false
  @Published var recoveryRespiratoryRateText = "16.8"
  @Published var recoveryRespiratoryBaselineText = "16.5"
  @Published var recoverySkinTemperatureDeltaText = "+0.1"

  private let bridge = GooseRustBridge()
  private var attemptedCatalogLoad = false
  private var previewMissingData = false
  private var packetInputReports: [String: [String: Any]] = [:]
  private var packetScoreReports: [String: [String: Any]] = [:]
  private var referenceComparisonReports: [String: [String: Any]] = [:]
  private lazy var databasePath = HealthDataStore.defaultDatabasePath()

  init() {
    algorithmDefinitions = Self.sampleAlgorithms
    referenceDefinitions = Self.sampleReferences
    selectedAlgorithmByFamily = Dictionary(
      uniqueKeysWithValues: Self.sampleAlgorithms.map { ($0.family, $0.id) }
    )
    primarySleepDetail = Self.samplePrimarySleepDetail
  }

  private static func defaultDatabasePath() -> String {
    let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let directory = baseDirectory.appendingPathComponent("GooseSwift", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("goose.sqlite").path
  }

  var usesSampleData: Bool {
    catalogSource.isSample || packetInputStatus.hasPrefix("Preview") || packetScoreStatus.hasPrefix("Preview")
  }

  var localDataSupportsExport: Bool {
    !packetInputReports.isEmpty || !packetScoreReports.isEmpty || !referenceComparisonReports.isEmpty
  }

  var localHealthExportText: String {
    [
      "Goose Health Export",
      "Catalog: \(catalogStatus)",
      "External sleep import: \(externalSleepImportStatus)",
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

  func refreshBridgeCatalogs() {
    do {
      let algorithmsValue = try bridge.requestValue(method: "metrics.built_in_definitions")
      let referencesValue = try bridge.requestValue(method: "metrics.reference_definitions")
      let preferencesValue = try bridge.requestValue(method: "metrics.default_preferences")

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
    } catch {
      catalogSource = .sample("Rust catalog unavailable")
      catalogStatus = "Sample catalog active: \(String(describing: error))"
    }
  }

  func selectAlgorithm(_ algorithmID: String, for family: String) {
    selectedAlgorithmByFamily[family] = algorithmID
  }

  func runPacketInputs() {
    let baseArgs = bridgeBaseArgs(requireTrustedEvidence: false)
    do {
      packetInputReports["readiness"] = try bridge.request(
        method: "metrics.input_readiness",
        args: [
          "database_path": databasePath,
          "start": "0000",
          "end": "9999",
          "min_owned_captures": 2,
          "require_owned_captures": false,
          "require_scores_ready": true,
        ]
      )
      packetInputReports["motion"] = try bridge.request(method: "metrics.motion_features", args: baseArgs)
      packetInputReports["heart_rate"] = try bridge.request(method: "metrics.heart_rate_features", args: baseArgs)
      packetInputReports["vital_event"] = try bridge.request(method: "metrics.vital_event_features", args: baseArgs)
      packetInputReports["hrv"] = try bridge.request(
        method: "metrics.hrv_features",
        args: baseArgs.merging([
          "min_rr_intervals_to_compute": 2,
          "baseline_min_days": 3,
          "require_baseline": false,
        ]) { _, new in new }
      )
      packetInputReports["window"] = try bridge.request(method: "metrics.window_features", args: baseArgs)
      packetInputReports["resting_hr"] = try bridge.request(
        method: "metrics.resting_hr_features",
        args: baseArgs.merging([
          "baseline_min_days": 3,
          "require_baseline": false,
        ]) { _, new in new }
      )
      packetInputStatus = "Bridge packet-derived inputs extracted"
    } catch {
      packetInputStatus = "Bridge input extraction blocked: \(Self.shortError(error))"
    }
  }

  func runPacketScores() {
    let baseArgs = bridgeBaseArgs(requireTrustedEvidence: false)
    do {
      packetScoreReports["sleep"] = try sleepScoreReport(baseArgs: baseArgs)
      refreshPrimarySleepFromScoreReport()
      packetScoreReports["strain"] = try bridge.request(
        method: "metrics.strain_score_from_features",
        args: baseArgs.merging([
          "resting_start": "0000",
          "resting_end": "9999",
          "resting_baseline_min_days": 3,
        ]) { _, new in new }
      )
      packetScoreReports["recovery"] = try bridge.request(
        method: "metrics.recovery_score_from_features",
        args: baseArgs.merging(recoveryScoreBridgeArgs()) { _, new in new }
      )
      packetScoreReports["stress"] = try bridge.request(
        method: "metrics.stress_score_from_features",
        args: baseArgs.merging([
          "resting_start": "0000",
          "resting_end": "9999",
          "hrv_start": "0000",
          "hrv_end": "9999",
          "hrv_baseline_start": "0000",
          "hrv_baseline_end": "9999",
          "resting_baseline_min_days": 3,
          "hrv_min_rr_intervals_to_compute": 2,
          "hrv_baseline_min_days": 3,
        ]) { _, new in new }
      )
      packetScoreStatus = "Bridge packet-derived scores recomputed"
    } catch {
      packetScoreStatus = "Bridge score run blocked: \(Self.shortError(error))"
    }
  }

  func runSleepScore() {
    do {
      packetScoreReports["sleep"] = try sleepScoreReport(baseArgs: bridgeBaseArgs(requireTrustedEvidence: false))
      refreshPrimarySleepFromScoreReport()
      packetScoreStatus = "Bridge sleep score recomputed"
    } catch {
      packetScoreStatus = "Bridge sleep score blocked: \(Self.shortError(error))"
    }
  }

  func importHealthKitSleepHistory() async {
    externalSleepImportStatus = "Importing HealthKit sleep..."
    do {
      let batch = try await HealthKitSleepImporter.recentSleepHistory()
      guard !batch.isEmpty else {
        externalSleepImportStatus = "HealthKit sleep import found no sessions"
        return
      }
      let report = try bridge.request(
        method: "sleep.import_external_history",
        args: [
          "database_path": databasePath,
          "sessions": batch.sessions,
          "stages": batch.stages,
        ]
      )
      if let latestPrimarySleep = batch.latestPrimarySleep {
        primarySleepDetail = Self.primarySleepDetail(from: latestPrimarySleep)
      }
      let sessions = Self.intValue(report["session_count"]) ?? batch.sessions.count
      let insertedSessions = Self.intValue(report["inserted_session_count"]) ?? 0
      let insertedStages = Self.intValue(report["inserted_stage_count"]) ?? 0
      externalSleepImportStatus = "HealthKit imported \(sessions) sessions | \(insertedSessions) new | \(insertedStages) new stages"
    } catch {
      externalSleepImportStatus = "HealthKit sleep import blocked: \(Self.shortError(error))"
    }
  }

  func runReferenceComparisons() {
    for (family, args) in Self.referenceComparisonArgsByFamily {
      do {
        let report = try bridge.request(method: "metrics.reference_compare", args: args)
        referenceComparisonReports[family] = report
        referenceRunStatusByFamily[family] = Self.referenceComparisonStatus(from: report)
      } catch {
        referenceRunStatusByFamily[family] = "blocked | \(Self.shortError(error))"
      }
    }
  }

  func importCalibrationLabels() {
    calibrationLabelsImported = true
  }

  func calibrate() {
    calibrationRunComplete = true
  }

  var algorithmFamilies: [String] {
    let families = Set(algorithmDefinitions.map(\.family))
      .union(["recovery", "sleep", "strain", "stress", "hrv"])
    return families.sorted()
  }

  func algorithms(for family: String) -> [HealthAlgorithmDefinition] {
    algorithmDefinitions.filter { $0.family == family }
  }

  func landingSnapshots(liveHeartRateBPM: Int?, liveHeartRateSource: String, liveHeartRateUpdatedAt: Date?) -> [HealthMetricSnapshot] {
    var snapshots = Self.sampleLandingSnapshots
    if let index = snapshots.firstIndex(where: { $0.route == .sleep }) {
      snapshots[index] = sleepSnapshot(base: snapshots[index])
    }
    if let liveHeartRateBPM,
       let index = snapshots.firstIndex(where: { $0.id == "health-monitor" }) {
      snapshots[index] = HealthMetricSnapshot(
        id: "health-monitor",
        route: .healthMonitor,
        group: .today,
        title: "Health Monitor",
        value: "\(liveHeartRateBPM)",
        unit: "bpm",
        status: "Live HR",
        freshness: Self.relativeText(for: liveHeartRateUpdatedAt) ?? "Now",
        provenance: liveHeartRateSource,
        source: .live("BLE heart rate stream"),
        systemImage: "heart.text.square",
        tint: .red,
        trend: snapshots[index].trend
      )
    }
    return snapshots
  }

  func healthMonitorSnapshots() -> [HealthMetricSnapshot] {
    if previewMissingData {
      return Self.sampleHealthMonitorSnapshots.map { snapshot in
        HealthMetricSnapshot(
          id: snapshot.id,
          route: snapshot.route,
          group: snapshot.group,
          title: snapshot.title,
          value: "--",
          unit: snapshot.unit,
          status: "Unavailable",
          freshness: "No local data",
          provenance: "preview missing data",
          source: .unavailable("preview missing data"),
          systemImage: snapshot.systemImage,
          tint: snapshot.tint,
          trend: HealthTrendModel(id: snapshot.trend.id, title: snapshot.trend.title, rangeLabel: "No data", summary: "No trend data", analysis: "No local data has been captured for this trend yet.", resources: snapshot.trend.resources, points: [])
        )
      }
    }
    var snapshots = Self.sampleHealthMonitorSnapshots
    if let index = snapshots.firstIndex(where: { $0.id == "health-sleep" }) {
      snapshots[index] = sleepHealthMonitorSnapshot(base: snapshots[index])
    }
    return snapshots
  }

  func snapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    let snapshot = Self.sampleLandingSnapshots.first { $0.route == route }
      ?? Self.sampleLandingSnapshots[0]
    if route == .sleep && !previewMissingData {
      return sleepSnapshot(base: snapshot)
    }
    guard previewMissingData else {
      return snapshot
    }
    return HealthMetricSnapshot(
      id: snapshot.id,
      route: snapshot.route,
      group: snapshot.group,
      title: snapshot.title,
      value: "--",
      unit: snapshot.unit,
      status: "No data",
      freshness: "Missing",
      provenance: "preview missing data",
      source: .unavailable("preview missing data"),
      systemImage: snapshot.systemImage,
      tint: snapshot.tint,
      trend: HealthTrendModel(id: snapshot.trend.id, title: snapshot.trend.title, rangeLabel: "No data", summary: "No trend data", analysis: "No local data has been captured for this trend yet.", resources: snapshot.trend.resources, points: [])
    )
  }

  private func sleepSnapshot(base snapshot: HealthMetricSnapshot) -> HealthMetricSnapshot {
    if let output = Self.map(packetScoreReports["sleep"], "score_result", "output") {
      let scoreText = Self.numberText(output["score_0_to_100"], fractionDigits: 0) ?? snapshot.value
      return HealthMetricSnapshot(
        id: snapshot.id,
        route: snapshot.route,
        group: snapshot.group,
        title: snapshot.title,
        value: scoreText,
        unit: "%",
        status: Self.sleepQualityLabel(score: Self.doubleValue(output["score_0_to_100"])),
        freshness: "Latest",
        provenance: "metrics.sleep_score_from_features",
        source: .bridge("goose.sleep.v1"),
        systemImage: snapshot.systemImage,
        tint: snapshot.tint,
        trend: snapshot.trend
      )
    }
    if let primarySleepDetail, !primarySleepDetail.source.isSample {
      return HealthMetricSnapshot(
        id: snapshot.id,
        route: snapshot.route,
        group: snapshot.group,
        title: snapshot.title,
        value: primarySleepDetail.durationText,
        unit: "",
        status: primarySleepDetail.qualityText,
        freshness: primarySleepDetail.dateLabel,
        provenance: primarySleepDetail.source.detail,
        source: primarySleepDetail.source,
        systemImage: snapshot.systemImage,
        tint: snapshot.tint,
        trend: snapshot.trend
      )
    }
    return snapshot
  }

  private func sleepHealthMonitorSnapshot(base snapshot: HealthMetricSnapshot) -> HealthMetricSnapshot {
    if let primarySleepDetail, !primarySleepDetail.source.isSample {
      return HealthMetricSnapshot(
        id: snapshot.id,
        route: snapshot.route,
        group: snapshot.group,
        title: snapshot.title,
        value: primarySleepDetail.durationText,
        unit: "",
        status: primarySleepDetail.qualityText,
        freshness: primarySleepDetail.dateLabel,
        provenance: primarySleepDetail.source.detail,
        source: primarySleepDetail.source,
        systemImage: snapshot.systemImage,
        tint: snapshot.tint,
        trend: snapshot.trend
      )
    }
    if let output = Self.map(packetScoreReports["sleep"], "score_result", "output"),
       let duration = Self.doubleValue(output["sleep_duration_minutes"]) {
      return HealthMetricSnapshot(
        id: snapshot.id,
        route: snapshot.route,
        group: snapshot.group,
        title: snapshot.title,
        value: Self.minutesText(duration),
        unit: "",
        status: Self.sleepQualityLabel(score: Self.doubleValue(output["score_0_to_100"])),
        freshness: "Latest",
        provenance: "metrics.sleep_score_from_features",
        source: .bridge("goose.sleep.v1"),
        systemImage: snapshot.systemImage,
        tint: snapshot.tint,
        trend: snapshot.trend
      )
    }
    return snapshot
  }

  func trendRows(for route: HealthRoute) -> [HealthMetricSnapshot] {
    if previewMissingData {
      return []
    }
    switch route {
    case .sleep:
      return Self.sleepTrendRows
    case .recovery:
      return Self.recoveryTrendRows
    case .strain:
      return Self.strainTrendRows
    case .stress:
      return Self.stressTrendRows
    default:
      return []
    }
  }

  func metricInputReadinessSummary() -> String {
    guard let report = packetInputReports["readiness"] else {
      return packetInputStatus == "No run" ? "No run | bridge extract available" : packetInputStatus
    }
    let status = Self.passStatus(report)
    let ready = Self.intValue(report["ready_family_count"]) ?? 0
    let total = Self.intValue(report["family_count"]) ?? Self.array(report["families"]).count
    return "\(status) | \(ready)/\(total) score families ready"
  }

  func metricInputReadinessNextActionSummary() -> String {
    if let action = Self.firstActionText(in: packetInputReports["readiness"]) {
      return action
    }
    return packetInputStatus == "No run" ? "Run Extract to populate packet-derived inputs" : ""
  }

  func latestHeartRateSummary(bpm: Int?, source: String, updatedAt: Date?) -> String {
    guard let bpm else {
      return "No HR extraction"
    }
    let freshness = Self.relativeText(for: updatedAt) ?? "Now"
    return "\(bpm) bpm | trusted | \(freshness)"
  }

  func latestHeartRateProvenanceSummary(source: String) -> String {
    source == "waiting" ? "" : "source_signal=\(source) | trusted_metric_input=true"
  }

  func motionFeatureSummary() -> String {
    guard let report = packetInputReports["motion"] else {
      return packetInputStatus == "No run" ? "No run" : packetInputStatus
    }
    let trusted = Self.intValue(report["trusted_feature_count"]) ?? 0
    let total = Self.intValue(report["feature_count"]) ?? Self.array(report["features"]).count
    return "\(Self.passStatus(report)) | \(trusted)/\(total) trusted motion inputs"
  }

  func motionFeatureProvenanceSummary() -> String {
    guard let feature = Self.firstMap(in: packetInputReports["motion"], key: "features") else {
      return ""
    }
    let kind = feature["body_summary_kind"] as? String ?? "motion"
    return "body_summary_kind=\(kind) | trusted_metric_input=\(Self.boolText(feature["trusted_metric_input"]))"
  }

  func hrvFeatureSummary() -> String {
    guard let report = packetInputReports["hrv"] else {
      return packetInputStatus == "No run" ? "No run" : packetInputStatus
    }
    let rr = Self.intValue(report["trusted_rr_interval_count"])
      ?? Self.intValue(report["rr_interval_count"])
      ?? 0
    let output = Self.map(report, "score_result", "output")
    let rmssd = Self.numberText(output?["rmssd_ms"], fractionDigits: 1) ?? "no RMSSD"
    let baseline = Self.map(report, "baseline")
    let baselineText = Self.numberText(baseline?["hrv_baseline_rmssd_ms"], fractionDigits: 1) ?? "no baseline"
    return "\(Self.passStatus(report)) | \(rr) RR | \(rmssd) ms RMSSD | \(baselineText) ms base"
  }

  func hrvFeatureProvenanceSummary() -> String {
    guard let report = packetInputReports["hrv"] else {
      return ""
    }
    let algorithm = Self.map(report, "score_result")?["algorithm_id"] as? String ?? "goose.hrv.v0"
    return "algorithm=\(algorithm) | daily=\(Self.array(report["daily"]).count) | issues=\(Self.array(report["issues"]).count)"
  }

  func restingHeartRateFeatureSummary() -> String {
    guard let report = packetInputReports["resting_hr"] else {
      return packetInputStatus == "No run" ? "No run" : packetInputStatus
    }
    let resting = Self.map(report, "resting")
    let baseline = Self.map(report, "baseline")
    let restingText = Self.numberText(resting?["resting_hr_bpm"], fractionDigits: 0) ?? "no resting HR"
    let baselineText = Self.numberText(baseline?["resting_hr_baseline_bpm"], fractionDigits: 0) ?? "no baseline"
    return "\(Self.passStatus(report)) | \(restingText) bpm rest | \(baselineText) bpm base"
  }

  func restingHeartRateFeatureProvenanceSummary() -> String {
    guard let report = packetInputReports["resting_hr"] else {
      return ""
    }
    return "daily=\(Self.array(report["daily"]).count) | trusted_hr=\(Self.intValue(report["trusted_heart_rate_feature_count"]) ?? 0)"
  }

  func windowFeatureSummary() -> String {
    guard let report = packetInputReports["window"] else {
      return packetInputStatus == "No run" ? "No run" : packetInputStatus
    }
    let window = Self.map(report, "window")
    let duration = Self.numberText(window?["duration_minutes"], fractionDigits: 1) ?? "no duration"
    let average = Self.numberText(window?["average_hr_bpm"], fractionDigits: 0) ?? "no HR"
    return "\(Self.passStatus(report)) | \(duration) min | \(average) bpm avg"
  }

  func windowFeatureProvenanceSummary() -> String {
    guard let report = packetInputReports["window"] else {
      return ""
    }
    return "hr_features=\(Self.intValue(report["heart_rate_feature_count"]) ?? 0) | motion_features=\(Self.intValue(report["motion_feature_count"]) ?? 0)"
  }

  func vitalEventFeatureSummary() -> String {
    guard let report = packetInputReports["vital_event"] else {
      return packetInputStatus == "No run" ? "No run" : packetInputStatus
    }
    let trusted = Self.intValue(report["trusted_feature_count"]) ?? 0
    let total = Self.intValue(report["feature_count"]) ?? Self.array(report["features"]).count
    let resolved = Self.intValue(report["resolved_metric_input_count"]) ?? 0
    return "\(Self.passStatus(report)) | \(trusted)/\(total) trusted events | \(resolved) resolved"
  }

  func vitalEventFeatureProvenanceSummary() -> String {
    guard let feature = Self.firstMap(in: packetInputReports["vital_event"], key: "features") else {
      return ""
    }
    let eventName = feature["event_name"] as? String ?? "vital_event"
    return "\(eventName) | semantics_verified=\(Self.boolText(feature["value_semantics_verified"]))"
  }

  func packetDerivedFeatureNextActionSummary() -> String {
    if let action = Self.firstActionText(in: packetInputReports["readiness"])
      ?? Self.firstActionText(in: packetInputReports["vital_event"]) {
      return action
    }
    return packetInputStatus == "No run" ? "Run Extract to populate packet-derived inputs" : "Capture trusted vitals packets for respiratory, SpO2, and temperature"
  }

  func sleepFeatureScoreSummary() -> String {
    guard let report = packetScoreReports["sleep"] else {
      return packetScoreStatus == "No run" ? "No run" : packetScoreStatus
    }
    let output = Self.map(report, "score_result", "output")
    let score = Self.numberText(output?["score_0_to_100"], fractionDigits: 1) ?? "no score"
    let window = Self.map(report, "sleep_window")
    let asleep = Self.numberText(window?["sleep_duration_minutes"], fractionDigits: 0) ?? "no duration"
    let state = Self.map(output, "status_report")?["report_state"] as? String
    let prefix = state.map { "\($0.capitalized) | " } ?? ""
    return "\(prefix)\(Self.passStatus(report)) | \(score) sleep | \(asleep) min"
  }

  func sleepV1ModelStatusSummary() -> String {
    guard let report = packetScoreReports["sleep"],
          let status = Self.map(report, "score_result", "output", "status_report") else {
      return packetScoreStatus == "No run" ? "" : "V1 status unavailable"
    }
    let state = status["report_state"] as? String ?? "provisional"
    let nights = Self.intValue(status["imported_platform_sleep_nights"]) ?? 0
    let trusted = Self.intValue(status["trusted_goose_sleep_nights"]) ?? 0
    return "\(state.capitalized) | \(nights) imported nights | \(trusted) trusted goose nights"
  }

  func sleepV1ConfidenceSummary() -> String {
    guard let report = packetScoreReports["sleep"] else {
      return packetScoreStatus == "No run" ? "" : "confidence unavailable"
    }
    let output = Self.map(report, "score_result", "output")
    let confidence = Self.percentText(output?["confidence_0_to_1"]) ?? "no confidence"
    let window = Self.percentText(output?["sleep_window_confidence_0_to_1"]) ?? "no window"
    let coverage = Self.percentText(output?["data_coverage_fraction"]) ?? "no coverage"
    return "\(confidence) confidence | \(window) window | \(coverage) coverage"
  }

  func sleepV1DataNotesSummary() -> String {
    guard let report = packetScoreReports["sleep"] else {
      return ""
    }
    let issues = Self.array(report["issues"]).count
    let actions = Self.array(report["next_actions"]).count
    return "\(Self.passStatus(report)) | issues \(issues) | actions \(actions)"
  }

  func sleepV1ScheduleSummary() -> String {
    guard let output = Self.map(packetScoreReports["sleep"], "score_result", "output") else {
      return ""
    }
    let bed = Self.numberText(output["bedtime_deviation_minutes"], fractionDigits: 0) ?? "0"
    let wake = Self.numberText(output["wake_time_deviation_minutes"], fractionDigits: 0) ?? "0"
    let mid = Self.numberText(output["midpoint_deviation_minutes"], fractionDigits: 0) ?? "0"
    return "bed \(bed)m | wake \(wake)m | mid \(mid)m"
  }

  func sleepV1DebtSummary() -> String {
    guard let output = Self.map(packetScoreReports["sleep"], "score_result", "output") else {
      return ""
    }
    let tonight = Self.numberText(output["sleep_debt_minutes"], fractionDigits: 0) ?? "no"
    let rolling = Self.numberText(output["rolling_sleep_debt_minutes"], fractionDigits: 0) ?? "no"
    return "\(tonight)m tonight | \(rolling)m rolling"
  }

  func sleepV1HeartRateSummary() -> String {
    guard let output = Self.map(packetScoreReports["sleep"], "score_result", "output") else {
      return ""
    }
    let dip = Self.numberText(output["heart_rate_dip_percent"], fractionDigits: 1) ?? "no"
    let average = Self.numberText(output["sleep_hr_average_bpm"], fractionDigits: 0) ?? "no"
    let min = Self.numberText(output["sleep_hr_min_bpm"], fractionDigits: 0) ?? "no"
    return "\(dip)% dip | \(average) bpm avg | \(min) bpm min"
  }

  func sleepV1StagesSummary() -> String {
    guard let detail = primarySleepDetail else {
      return ""
    }
    return detail.stages.map { "\($0.stage) \(Int($0.durationMinutes.rounded()))m" }.joined(separator: " | ")
  }

  func sleepV1ArchitectureCalibrationSummary() -> String {
    guard let output = Self.map(packetScoreReports["sleep"], "score_result", "output") else {
      return ""
    }
    let component = Self.map(output, "component_provenance", "sleep_architecture")
    let confidence = Self.percentText(component?["confidence_0_to_1"]) ?? "architecture confidence pending"
    return "\(confidence) architecture confidence | source=packet-derived"
  }

  func sleepV1WhyChangedSummary() -> String {
    guard let comparison = Self.map(packetScoreReports["sleep"], "score_result", "output", "previous_night_comparison") else {
      return ""
    }
    let duration = Self.numberText(comparison["sleep_duration_delta_minutes"], fractionDigits: 0) ?? "0"
    let debt = Self.numberText(comparison["sleep_debt_delta_minutes"], fractionDigits: 0) ?? "0"
    let hr = Self.numberText(comparison["sleep_hr_average_delta_bpm"], fractionDigits: 0) ?? "0"
    return "duration \(duration)m vs prev | debt \(debt)m vs prev | HR avg \(hr) bpm"
  }

  func sleepV1ComponentBreakdownRows() -> [HealthSummaryRow] {
    guard packetScoreStatus != "No run" else {
      return []
    }
    let components = Self.array(Self.map(packetScoreReports["sleep"], "score_result", "output")?["components"])
    if !components.isEmpty {
      return components.enumerated().map { index, component in
        let label = component["name"] as? String ?? component["component_id"] as? String ?? "Component \(index + 1)"
        let score = Self.numberText(component["score_0_to_100"], fractionDigits: 0) ?? "no score"
        let weight = Self.percentText(component["weight_0_to_1"]) ?? "no weight"
        return HealthSummaryRow(label.capitalized, value: "\(score) score | \(weight) weight", source: .bridge("sleep v1 components"), systemImage: "chart.bar")
      }
    }
    return [
      HealthSummaryRow("Duration component", value: "86 score | 35% weight | 30.1 pts", source: .sample("sleepV1ComponentBreakdownRows()"), systemImage: "clock"),
      HealthSummaryRow("Consistency component", value: "78 score | 20% weight | 15.6 pts", source: .sample("sleepV1ComponentBreakdownRows()"), systemImage: "calendar"),
      HealthSummaryRow("Architecture component", value: "81 score | 25% weight | 20.3 pts", source: .sample("sleepV1ComponentBreakdownRows()"), systemImage: "chart.bar")
    ]
  }

  func recoveryFeatureScoreSummary() -> String {
    guard let report = packetScoreReports["recovery"] else {
      return packetScoreStatus == "No run" ? "No run" : packetScoreStatus
    }
    let score = Self.numberText(Self.map(report, "score_result", "output")?["score_0_to_100"], fractionDigits: 1) ?? "no score"
    return "\(Self.passStatus(report)) | \(score) recovery"
  }

  func recoveryProvidedVitalsSummary() -> String {
    if let vitals = Self.map(packetScoreReports["recovery"], "provided_vitals") {
      let source = vitals["source"] as? String ?? "provided"
      let rr = Self.numberText(vitals["respiratory_rate_rpm"], fractionDigits: 1) ?? recoveryRespiratoryRateText
      let baseline = Self.numberText(vitals["respiratory_rate_baseline_rpm"], fractionDigits: 1) ?? recoveryRespiratoryBaselineText
      let temp = Self.numberText(vitals["skin_temp_delta_c"], fractionDigits: 1) ?? recoverySkinTemperatureDeltaText
      return "\(source) | \(rr) rpm | \(baseline) rpm baseline | \(temp) C"
    }
    return "manual | \(recoveryRespiratoryRateText) rpm | \(recoveryRespiratoryBaselineText) rpm baseline | \(recoverySkinTemperatureDeltaText) C"
  }

  func strainFeatureScoreSummary() -> String {
    guard let report = packetScoreReports["strain"] else {
      return packetScoreStatus == "No run" ? "No run" : packetScoreStatus
    }
    let score = Self.numberText(Self.map(report, "score_result", "output")?["score_0_to_21"], fractionDigits: 2) ?? "no score"
    return "\(Self.passStatus(report)) | \(score) strain"
  }

  func stressFeatureScoreSummary() -> String {
    guard let report = packetScoreReports["stress"] else {
      return packetScoreStatus == "No run" ? "No run" : packetScoreStatus
    }
    let score = Self.numberText(Self.map(report, "score_result", "output")?["score_0_to_100"], fractionDigits: 1) ?? "no score"
    return "\(Self.passStatus(report)) | \(score) stress"
  }

  func packetScoreProvenanceSummary(_ family: String) -> String {
    guard let report = packetScoreReports[family] else {
      return packetScoreStatus == "No run" ? "" : "family=\(family) | source=packet-derived bridge run"
    }
    let result = Self.map(report, "score_result")
    let algorithm = result?["algorithm_id"] as? String ?? "packet-derived-\(family)"
    return "family=\(family) | algorithm=\(algorithm) | issues=\(Self.array(report["issues"]).count)"
  }

  func packetDerivedScoreNextActionSummary() -> String {
    if let action = ["sleep", "recovery", "strain", "stress"].compactMap({ Self.firstActionText(in: packetScoreReports[$0]) }).first {
      return action
    }
    return packetScoreStatus == "No run" ? "Run scores to populate packet-derived outputs" : "Replace blocked score inputs with trusted captured packet feature reports"
  }

  func referenceComparisonSummary(_ family: String) -> String {
    referenceRunStatusByFamily[family] ?? "No comparison"
  }

  func calibrationLabelSummary() -> String {
    calibrationLabelsImported ? "1 label | manual" : "No labels"
  }

  func calibrationSummary() -> String {
    calibrationRunComplete ? "ready | 4 train / 2 holdout | improved" : "No run"
  }

  func calibratedScoreSummary() -> String {
    calibrationRunComplete ? "71.5 raw -> 74.2 / 100" : "No run"
  }

  func calibrationIssues() -> [String] {
    if !calibrationLabelsImported {
      return ["Import labels before calibration"]
    }
    if !calibrationRunComplete {
      return ["Run calibration to generate holdout evidence"]
    }
    return []
  }

  func calibrationNextActionSummary() -> String {
    if !calibrationLabelsImported {
      return "Import labels"
    }
    if !calibrationRunComplete {
      return "Calibrate"
    }
    return "Review calibrated \(calibrationTargetFamily) score"
  }

  func packetInputSource(_ detail: String) -> HealthDataSource {
    packetInputReports.isEmpty ? .sample(detail) : .bridge(detail)
  }

  func packetScoreSource(_ detail: String) -> HealthDataSource {
    packetScoreReports.isEmpty ? .sample(detail) : .bridge(detail)
  }

  func referenceComparisonSource(_ family: String) -> HealthDataSource {
    referenceComparisonReports[family] == nil ? .sample("referenceComparisonSummary(\(family))") : .bridge("metrics.reference_compare")
  }

  func primarySleep() -> PrimarySleepDetail? {
    primarySleepDetail
  }

  func sleepTimelineEmptyActionSummary() -> String {
    "Add Sleep opens the manual sleep entry placeholder until write support lands"
  }

  func cardioLoadWeeklyPoints() -> [CardioLoadDay] {
    guard !previewMissingData else {
      return []
    }
    return Self.sampleCardioLoadDays
  }

  func cardioStatusRows() -> [HealthSummaryRow] {
    let points = cardioLoadWeeklyPoints()
    guard !points.isEmpty else {
      return [
        HealthSummaryRow("Calibrating", value: "No weekly HR + activity data yet", source: .unavailable("cardio inputs pending"), systemImage: "heart.circle")
      ]
    }
    let grouped = Dictionary(grouping: points, by: \.status)
    return ["Calibrating", "Detraining", "Maintaining", "Peaking", "Productive", "Fatigued", "Overtraining"].map { status in
      let days = grouped[status]?.count ?? 0
      let percent = Double(days) / Double(points.count)
      return HealthSummaryRow(
        status,
        value: days == 0 ? "0d | supported status state" : "\(days)d | \(Self.percentText(percent) ?? "0%") of visible week",
        source: .sample("Cardio Load status states"),
        systemImage: "heart.circle"
      )
    }
  }

  func energyStressChartPoints() -> [EnergyStressPoint] {
    guard !previewMissingData else {
      return []
    }
    return Self.sampleEnergyStressPoints
  }

  func energyStressSelectedPoint() -> EnergyStressPoint? {
    energyStressChartPoints().first { $0.id == "2130" } ?? energyStressChartPoints().last
  }

  func healthMonitorExportRows() -> [HealthSummaryRow] {
    guard localDataSupportsExport else {
      return []
    }
    return [
      HealthSummaryRow("Local health export", value: "Packet reports and reference comparisons available", source: .bridge("local cached bridge reports"), systemImage: "square.and.arrow.up")
    ]
  }

  func applyPreviewState(_ state: HealthPreviewState) {
    attemptedCatalogLoad = true
    switch state {
    case .populated:
      previewMissingData = false
      primarySleepDetail = Self.samplePrimarySleepDetail
      packetInputStatus = "Preview packet-derived inputs extracted"
      packetScoreStatus = "Preview packet-derived scores recomputed"
      externalSleepImportStatus = "Preview HealthKit sleep imported"
      packetInputReports = Self.previewPacketInputReports
      packetScoreReports = Self.previewPacketScoreReports
      refreshPrimarySleepFromScoreReport()
      referenceComparisonReports = Self.previewReferenceComparisonReports
      referenceRunStatusByFamily = Dictionary(
        uniqueKeysWithValues: referenceComparisonReports.map { ($0.key, Self.referenceComparisonStatus(from: $0.value)) }
      )
      calibrationLabelsImported = true
      calibrationRunComplete = true
    case .missing:
      previewMissingData = true
      primarySleepDetail = nil
      packetInputStatus = "No run"
      packetScoreStatus = "No run"
      externalSleepImportStatus = "No import"
      packetInputReports = [:]
      packetScoreReports = [:]
      referenceComparisonReports = [:]
      referenceRunStatusByFamily = [:]
      algorithmDefinitions = []
      referenceDefinitions = []
      selectedAlgorithmByFamily = [:]
      catalogStatus = "Preview missing catalog"
      catalogSource = .unavailable("preview missing catalog")
      calibrationLabelsImported = false
      calibrationRunComplete = false
    }
  }

  private func refreshPrimarySleepFromScoreReport() {
    guard let detail = Self.primarySleepDetail(fromSleepReport: packetScoreReports["sleep"]) else {
      return
    }
    primarySleepDetail = detail
  }

  private static func primarySleepDetail(from imported: ImportedPrimarySleep) -> PrimarySleepDetail {
    PrimarySleepDetail(
      id: imported.id,
      dateLabel: dateLabel(imported.startDate),
      startLabel: timeLabel(imported.startDate),
      endLabel: timeLabel(imported.endDate),
      durationText: minutesText(imported.asleepMinutes),
      timeInBedText: minutesText(imported.timeInBedMinutes),
      scoreText: "--",
      qualityText: "Imported sleep",
      source: .bridge("sleep.import_external_history"),
      stages: imported.stages.map { stage in
        HealthSleepStageSegment(
          id: "\(imported.id)-\(stage.stage)-\(Int(stage.startDate.timeIntervalSince1970))",
          stage: stage.stage,
          startLabel: timeLabel(stage.startDate),
          endLabel: timeLabel(stage.endDate),
          durationMinutes: stage.durationMinutes,
          confidence: stage.confidence,
          source: .bridge("HealthKit sleep stage")
        )
      }
    )
  }

  private static func primarySleepDetail(fromSleepReport report: [String: Any]?) -> PrimarySleepDetail? {
    guard let report,
          let output = map(report, "score_result", "output") else {
      return nil
    }
    let window = map(report, "sleep_window")
    let input = map(report, "sleep_v1_input") ?? map(report, "sleep_input")
    let start = bridgeDate(input?["start_time"] ?? window?["start_time"])
    let end = bridgeDate(input?["end_time"] ?? window?["end_time"])
    let duration = doubleValue(output["sleep_duration_minutes"])
      ?? doubleValue(window?["sleep_duration_minutes"])
      ?? doubleValue(input?["sleep_duration_minutes"])
      ?? 0
    let timeInBed = doubleValue(output["time_in_bed_minutes"])
      ?? doubleValue(window?["time_in_bed_minutes"])
      ?? doubleValue(input?["time_in_bed_minutes"])
      ?? duration
    let score = numberText(output["score_0_to_100"], fractionDigits: 0) ?? "--"
    let stages = sleepStageSegments(from: output)
    let idSuffix = start.map { "\(Int($0.timeIntervalSince1970))" } ?? "latest"

    return PrimarySleepDetail(
      id: "primary-sleep-\(idSuffix)",
      dateLabel: start.map(dateLabel) ?? "Latest",
      startLabel: start.map(timeLabel) ?? "--",
      endLabel: end.map(timeLabel) ?? "--",
      durationText: minutesText(duration),
      timeInBedText: minutesText(timeInBed),
      scoreText: score,
      qualityText: sleepQualityLabel(score: doubleValue(output["score_0_to_100"])),
      source: .bridge("metrics.sleep_score_from_features"),
      stages: stages
    )
  }

  private static func sleepStageSegments(from output: [String: Any]) -> [HealthSleepStageSegment] {
    let stageRows = array(output["stage_segments"])
    if !stageRows.isEmpty {
      return stageRows.enumerated().compactMap { index, row in
        let stage = row["stage_kind"] as? String ?? row["stage"] as? String ?? "core"
        let duration = doubleValue(row["duration_minutes"]) ?? 0
        guard duration > 0 else {
          return nil
        }
        let start = bridgeDate(row["start_time"])
        let end = bridgeDate(row["end_time"])
        return HealthSleepStageSegment(
          id: "bridge-stage-\(index)-\(stage)",
          stage: stage,
          startLabel: start.map(timeLabel) ?? "--",
          endLabel: end.map(timeLabel) ?? "--",
          durationMinutes: duration,
          confidence: doubleValue(row["confidence_0_to_1"]),
          source: .bridge("sleep_v1 output stage_segments")
        )
      }
    }

    guard let minutesByStage = output["stage_minutes"] as? [String: Any] else {
      return []
    }
    return ["awake", "rem", "core", "deep"].compactMap { stage in
      guard let minutes = doubleValue(minutesByStage[stage]),
            minutes > 0 else {
        return nil
      }
      return HealthSleepStageSegment(
        id: "bridge-stage-total-\(stage)",
        stage: stage,
        startLabel: "--",
        endLabel: "--",
        durationMinutes: minutes,
        confidence: doubleValue(output["stage_segment_confidence_0_to_1"]),
        source: .bridge("sleep_v1 output stage_minutes")
      )
    }
  }

  private static func sleepQualityLabel(score: Double?) -> String {
    guard let score else {
      return "No score"
    }
    if score >= 85 {
      return "Optimal"
    }
    if score >= 70 {
      return "Good"
    }
    if score >= 50 {
      return "Needs attention"
    }
    return "Low"
  }

  private func bridgeBaseArgs(requireTrustedEvidence: Bool) -> [String: Any] {
    [
      "database_path": databasePath,
      "start": "0000",
      "end": "9999",
      "min_owned_captures": 2,
      "require_trusted_evidence": requireTrustedEvidence,
    ]
  }

  private func sleepScoreReport(baseArgs: [String: Any]) throws -> [String: Any] {
    try bridge.request(
      method: "metrics.sleep_score_from_features",
      args: baseArgs.merging([
        "sleep_need_minutes": 480.0,
        "low_motion_threshold_0_to_1": 0.05,
        "disturbance_motion_threshold_0_to_1": 0.20,
        "target_midpoint_minutes_since_midnight": 180.0,
        "history_import_in_progress": false,
        "algorithm_id": "goose.sleep.v1",
      ]) { _, new in new }
    )
  }

  private func recoveryScoreBridgeArgs() -> [String: Any] {
    [
      "hrv_start": "0000",
      "hrv_end": "9999",
      "hrv_baseline_start": "0000",
      "hrv_baseline_end": "9999",
      "resting_start": "0000",
      "resting_end": "9999",
      "sleep_start": "0000",
      "sleep_end": "9999",
      "prior_strain_start": "0000",
      "prior_strain_end": "9999",
      "resting_baseline_min_days": 3,
      "hrv_min_rr_intervals_to_compute": 2,
      "hrv_baseline_min_days": 3,
      "sleep_need_minutes": 480.0,
      "low_motion_threshold_0_to_1": 0.05,
      "disturbance_motion_threshold_0_to_1": 0.20,
      "target_midpoint_minutes_since_midnight": 180.0,
      "prior_strain_resting_baseline_min_days": 3,
      "respiratory_rate_rpm": Double(recoveryRespiratoryRateText) ?? 16.8,
      "respiratory_rate_baseline_rpm": Double(recoveryRespiratoryBaselineText) ?? 16.5,
      "skin_temp_delta_c": Double(recoverySkinTemperatureDeltaText) ?? 0.1,
      "provided_vitals_source": "manual_metrics_form",
      "provided_vitals_provenance_json": "{\"owner\":\"user\",\"entry_method\":\"manual_metrics_form\",\"source\":\"goose_swift\"}",
    ]
  }

  private static func shortError(_ error: Error) -> String {
    let text = String(describing: error)
    return text.count > 96 ? "\(text.prefix(96))..." : text
  }

  private static func passStatus(_ report: [String: Any]?) -> String {
    boolValue(report?["pass"]) == true ? "pass" : "blocked"
  }

  private static func referenceComparisonStatus(from report: [String: Any]) -> String {
    let status = passStatus(report)
    let deltas = array(report["deltas"]).count
    let goose = report["goose_algorithm_id"] as? String ?? "goose"
    let reference = report["reference_algorithm_id"] as? String ?? "reference"
    return "benchmark-only \(status) | \(deltas) deltas | \(goose) vs \(reference)"
  }

  private static func map(_ value: Any?, _ keys: String...) -> [String: Any]? {
    var current: Any? = value
    for key in keys {
      current = (current as? [String: Any])?[key]
    }
    return current as? [String: Any]
  }

  private static func array(_ value: Any?) -> [[String: Any]] {
    value as? [[String: Any]] ?? []
  }

  private static func firstMap(in report: [String: Any]?, key: String) -> [String: Any]? {
    array(report?[key]).first
  }

  private static func firstActionText(in report: [String: Any]?) -> String? {
    let action = firstMap(in: report, key: "next_actions")
    return action?["summary"] as? String
      ?? action?["action"] as? String
      ?? (report?["issues"] as? [String])?.first
  }

  private static func boolValue(_ value: Any?) -> Bool? {
    if let bool = value as? Bool {
      return bool
    }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    return nil
  }

  private static func boolText(_ value: Any?) -> String {
    boolValue(value).map { $0 ? "true" : "false" } ?? "unknown"
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int {
      return int
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    return nil
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double {
      return double
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    return nil
  }

  private static func numberText(_ value: Any?, fractionDigits: Int) -> String? {
    guard let double = doubleValue(value) else {
      return nil
    }
    return String(format: "%.\(fractionDigits)f", double)
  }

  static func percentText(_ value: Any?) -> String? {
    guard let double = doubleValue(value) else {
      return nil
    }
    return "\(Int((double * 100).rounded()))%"
  }

  nonisolated static func minutesText(_ minutes: Double) -> String {
    let rounded = Int(minutes.rounded())
    let hours = rounded / 60
    let mins = rounded % 60
    return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
  }

  private static func bridgeDate(_ value: Any?) -> Date? {
    if let date = value as? Date {
      return date
    }
    if let number = value as? NSNumber {
      return Date(timeIntervalSince1970: number.doubleValue / 1000.0)
    }
    guard let text = value as? String else {
      return nil
    }
    if text.hasPrefix("unix_ms:"),
       let milliseconds = Double(text.dropFirst("unix_ms:".count)) {
      return Date(timeIntervalSince1970: milliseconds / 1000.0)
    }
    if let milliseconds = Double(text), milliseconds > 100_000_000_000 {
      return Date(timeIntervalSince1970: milliseconds / 1000.0)
    }
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: text) {
      return date
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
  }

  private static func timeLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
  }

  private static func dateLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd/MM/yyyy"
    return formatter.string(from: date)
  }

  private static func algorithmRows(from value: Any) -> [[String: Any]] {
    value as? [[String: Any]] ?? []
  }

  private static func preferenceRows(from value: Any) -> [String: String] {
    guard let rows = value as? [[String: Any]] else {
      return [:]
    }
    return Dictionary(
      uniqueKeysWithValues: rows.compactMap { row in
        guard let family = row["metric_family"] as? String,
              let algorithmID = row["algorithm_id"] as? String else {
          return nil
        }
        return (family, algorithmID)
      }
    )
  }

  private static func trend(_ id: String, title: String, values: [Double], range: String, summary: String) -> HealthTrendModel {
    HealthTrendModel(
      id: id,
      title: title,
      rangeLabel: range,
      summary: summary,
      analysis: values.isEmpty ? "No local data has been captured for this trend yet." : "Sample trend shows a stable baseline with one recent movement worth reviewing.",
      resources: ["The Basics", "How \(title) is calculated"],
      points: values.enumerated().map { index, value in
        HealthTrendPoint(label: "D\(index + 1)", value: value)
      }
    )
  }

  private static func snapshot(
    id: String,
    route: HealthRoute,
    group: HealthMetricGroup,
    title: String,
    value: String,
    unit: String,
    status: String,
    freshness: String,
    provenance: String,
    source: HealthDataSource,
    systemImage: String,
    tint: Color,
    trendValues: [Double],
    range: String
  ) -> HealthMetricSnapshot {
    HealthMetricSnapshot(
      id: id,
      route: route,
      group: group,
      title: title,
      value: value,
      unit: unit,
      status: status,
      freshness: freshness,
      provenance: provenance,
      source: source,
      systemImage: systemImage,
      tint: tint,
      trend: trend(id, title: title, values: trendValues, range: range, summary: "\(status) | \(range)")
    )
  }

  static func relativeText(for date: Date?) -> String? {
    guard let date else {
      return nil
    }
    if abs(date.timeIntervalSinceNow) < 10 {
      return "Now"
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date()).capitalized
  }
}

private extension HealthDataStore {
  static let samplePrimarySleepDetail = PrimarySleepDetail(
    id: "primary-sleep-2026-05-31",
    dateLabel: "31/05/2026",
    startLabel: "23:12",
    endLabel: "06:48",
    durationText: "7h 05m",
    timeInBedText: "7h 36m",
    scoreText: "82",
    qualityText: "Good",
    source: .sample("sleep score output + imported stage records"),
    stages: [
      HealthSleepStageSegment(id: "awake", stage: "awake", startLabel: "23:12", endLabel: "23:43", durationMinutes: 31, confidence: 0.74, source: .sample("sleep stage record")),
      HealthSleepStageSegment(id: "rem", stage: "REM", startLabel: "23:43", endLabel: "01:09", durationMinutes: 86, confidence: 0.82, source: .sample("sleep stage record")),
      HealthSleepStageSegment(id: "core", stage: "core", startLabel: "01:09", endLabel: "05:20", durationMinutes: 251, confidence: 0.88, source: .sample("sleep stage record")),
      HealthSleepStageSegment(id: "deep", stage: "deep", startLabel: "05:20", endLabel: "06:48", durationMinutes: 88, confidence: 0.79, source: .sample("sleep stage record")),
    ]
  )

  static let sampleCardioLoadDays = [
    CardioLoadDay(id: "mon", dateLabel: "Mon", load: 31, status: "Detraining", durationText: "18 min", percent: 0.31, source: .sample("weekly cardio load fixture")),
    CardioLoadDay(id: "tue", dateLabel: "Tue", load: 36, status: "Maintaining", durationText: "22 min", percent: 0.36, source: .sample("weekly cardio load fixture")),
    CardioLoadDay(id: "wed", dateLabel: "Wed", load: 42, status: "Productive", durationText: "42 min", percent: 0.42, source: .sample("weekly cardio load fixture")),
    CardioLoadDay(id: "thu", dateLabel: "Thu", load: 40, status: "Maintaining", durationText: "31 min", percent: 0.40, source: .sample("weekly cardio load fixture")),
    CardioLoadDay(id: "fri", dateLabel: "Fri", load: 44, status: "Peaking", durationText: "48 min", percent: 0.44, source: .sample("weekly cardio load fixture")),
    CardioLoadDay(id: "sat", dateLabel: "Sat", load: 39, status: "Maintaining", durationText: "28 min", percent: 0.39, source: .sample("weekly cardio load fixture")),
    CardioLoadDay(id: "sun", dateLabel: "Sun", load: 42, status: "Productive", durationText: "35 min", percent: 0.42, source: .sample("weekly cardio load fixture")),
  ]

  static let sampleEnergyStressPoints = [
    EnergyStressPoint(id: "0600", timeLabel: "06:00", energy: 51, stress: 22, usage: 8, isSleepWindow: true, isChargeEvent: true),
    EnergyStressPoint(id: "0900", timeLabel: "09:00", energy: 58, stress: 34, usage: 18, isSleepWindow: false, isChargeEvent: false),
    EnergyStressPoint(id: "1200", timeLabel: "12:00", energy: 63, stress: 48, usage: 28, isSleepWindow: false, isChargeEvent: false),
    EnergyStressPoint(id: "1500", timeLabel: "15:00", energy: 59, stress: 54, usage: 42, isSleepWindow: false, isChargeEvent: false),
    EnergyStressPoint(id: "1830", timeLabel: "18:30", energy: 52, stress: 61, usage: 55, isSleepWindow: false, isChargeEvent: false),
    EnergyStressPoint(id: "2130", timeLabel: "21:30", energy: 45, stress: 65, usage: 64, isSleepWindow: false, isChargeEvent: false),
    EnergyStressPoint(id: "2330", timeLabel: "23:30", energy: 62, stress: 24, usage: 12, isSleepWindow: true, isChargeEvent: true),
  ]

  static let previewPacketInputReports: [String: [String: Any]] = [
    "readiness": ["pass": true, "ready_family_count": 4, "family_count": 6, "families": [] as [[String: Any]]],
    "motion": ["pass": true, "trusted_feature_count": 12, "feature_count": 12, "features": [["body_summary_kind": "raw_motion_k10", "trusted_metric_input": true]]],
    "heart_rate": ["pass": true, "trusted_feature_count": 8, "feature_count": 8],
    "vital_event": ["pass": false, "trusted_feature_count": 0, "feature_count": 3, "resolved_metric_input_count": 0, "features": [["event_name": "TEMPERATURE_LEVEL", "value_semantics_verified": false]]],
    "hrv": ["pass": true, "trusted_rr_interval_count": 164, "daily": [["day": "2026-05-31"]], "baseline": ["hrv_baseline_rmssd_ms": 71.0], "score_result": ["algorithm_id": "goose.hrv.v0", "output": ["rmssd_ms": 74.2]], "issues": [] as [String]],
    "window": ["pass": true, "heart_rate_feature_count": 8, "motion_feature_count": 12, "window": ["duration_minutes": 20.0, "average_hr_bpm": 75.0]],
    "resting_hr": ["pass": true, "trusted_heart_rate_feature_count": 6, "daily": [["day": "2026-05-31"]], "resting": ["resting_hr_bpm": 49.0], "baseline": ["resting_hr_baseline_bpm": 51.0]],
  ]

  static let previewPacketScoreReports: [String: [String: Any]] = [
    "sleep": ["pass": true, "sleep_window": ["sleep_duration_minutes": 425.0], "score_result": ["algorithm_id": "goose.sleep.v1", "output": ["score_0_to_100": 82.2, "confidence_0_to_1": 0.82, "sleep_window_confidence_0_to_1": 0.91, "data_coverage_fraction": 0.88, "bedtime_deviation_minutes": -12.0, "wake_time_deviation_minutes": 8.0, "midpoint_deviation_minutes": -2.0, "sleep_debt_minutes": 34.0, "rolling_sleep_debt_minutes": 112.0, "heart_rate_dip_percent": 8.4, "sleep_hr_average_bpm": 52.0, "sleep_hr_min_bpm": 45.0, "status_report": ["report_state": "provisional", "imported_platform_sleep_nights": 4, "trusted_goose_sleep_nights": 1]]], "issues": [] as [String], "next_actions": [] as [[String: Any]]],
    "recovery": ["pass": true, "score_result": ["algorithm_id": "goose.recovery.v0", "output": ["score_0_to_100": 71.5]], "provided_vitals": ["source": "manual_metrics_form", "respiratory_rate_rpm": 16.8, "respiratory_rate_baseline_rpm": 16.5, "skin_temp_delta_c": 0.1], "issues": [] as [String]],
    "strain": ["pass": true, "score_result": ["algorithm_id": "goose.strain.v0", "output": ["score_0_to_21": 8.75]], "issues": [] as [String]],
    "stress": ["pass": true, "score_result": ["algorithm_id": "goose.stress.v0", "output": ["score_0_to_100": 38.4]], "issues": [] as [String]],
  ]

  static let previewReferenceComparisonReports: [String: [String: Any]] = [
    "hrv": ["pass": true, "deltas": [["field": "rmssd"]], "goose_algorithm_id": "goose.hrv.v0", "reference_algorithm_id": "reference.hrv.time_domain.v1"],
    "sleep": ["pass": true, "deltas": [["field": "sleep_minutes"]], "goose_algorithm_id": "goose.sleep.v0", "reference_algorithm_id": "reference.sleep.actigraphy_summary.v1"],
    "strain": ["pass": true, "deltas": [["field": "score"]], "goose_algorithm_id": "goose.strain.v0", "reference_algorithm_id": "reference.strain.hr_load.v1"],
    "stress": ["pass": true, "deltas": [["field": "score"]], "goose_algorithm_id": "goose.stress.v0", "reference_algorithm_id": "reference.stress.hrv_hr_proxy.v1"],
  ]

  static let referenceComparisonArgsByFamily: [String: [String: Any]] = [
    "hrv": [
      "family": "hrv",
      "input": [
        "start_time": "2026-05-27T00:00:00Z",
        "end_time": "2026-05-27T00:01:00Z",
        "rr_intervals_ms": [800.0, 810.0, 790.0, 800.0],
        "input_ids": ["goose-swift.reference.hrv.sample"],
      ],
    ],
    "sleep": [
      "family": "sleep",
      "input": [
        "start_time": "2026-05-27T22:30:00Z",
        "end_time": "2026-05-28T06:30:00Z",
        "sleep_duration_minutes": 420.0,
        "sleep_need_minutes": 480.0,
        "time_in_bed_minutes": 480.0,
        "midpoint_deviation_minutes": 30.0,
        "disturbance_count": 4,
        "input_ids": ["goose-swift.reference.sleep.sample"],
      ],
    ],
    "strain": [
      "family": "strain",
      "input": [
        "start_time": "2026-05-28T12:00:00Z",
        "end_time": "2026-05-28T12:30:00Z",
        "duration_minutes": 30.0,
        "resting_hr_bpm": 60.0,
        "average_hr_bpm": 80.0,
        "max_hr_bpm": 100.0,
        "hr_zone_minutes": [10.0, 10.0, 5.0, 3.0, 2.0],
        "input_ids": ["goose-swift.reference.strain.sample"],
      ],
    ],
    "stress": [
      "family": "stress",
      "input": [
        "start_time": "2026-05-28T12:00:00Z",
        "end_time": "2026-05-28T12:05:00Z",
        "heart_rate_bpm": 90.0,
        "resting_hr_bpm": 60.0,
        "hrv_rmssd_ms": 25.0,
        "hrv_baseline_rmssd_ms": 50.0,
        "motion_intensity_0_to_1": 0.0,
        "input_ids": ["goose-swift.reference.stress.sample"],
      ],
    ],
  ]

  static let sampleAlgorithms = [
    HealthAlgorithmDefinition(id: "goose.hrv.rmssd.v0", displayName: "Goose HRV RMSSD", family: "hrv", status: "ready", provider: "goose", source: .sample("algorithmDefinitions")),
    HealthAlgorithmDefinition(id: "goose.sleep.v1", displayName: "Goose Sleep V1", family: "sleep", status: "learning", provider: "goose", source: .sample("algorithmDefinitions")),
    HealthAlgorithmDefinition(id: "goose.recovery.v0", displayName: "Goose Recovery V0", family: "recovery", status: "ready", provider: "goose", source: .sample("algorithmDefinitions")),
    HealthAlgorithmDefinition(id: "goose.strain.v0", displayName: "Goose Strain V0", family: "strain", status: "ready", provider: "goose", source: .sample("algorithmDefinitions")),
    HealthAlgorithmDefinition(id: "goose.stress.v0", displayName: "Goose Stress V0", family: "stress", status: "ready", provider: "goose", source: .sample("algorithmDefinitions")),
  ]

  static let sampleReferences = [
    HealthAlgorithmDefinition(id: "reference.hrv.time_domain.v1", displayName: "Reference HRV Time Domain", family: "hrv", status: "benchmark-only", provider: "reference", source: .sample("referenceAlgorithmDefinitions")),
    HealthAlgorithmDefinition(id: "reference.sleep.actigraphy_summary.v1", displayName: "Reference Sleep Actigraphy", family: "sleep", status: "benchmark-only", provider: "reference", source: .sample("referenceAlgorithmDefinitions")),
    HealthAlgorithmDefinition(id: "reference.strain.hr_load.v1", displayName: "Reference Strain HR Load", family: "strain", status: "benchmark-only", provider: "reference", source: .sample("referenceAlgorithmDefinitions")),
    HealthAlgorithmDefinition(id: "reference.stress.hrv_hr_proxy.v1", displayName: "Reference Stress HR/HRV Proxy", family: "stress", status: "benchmark-only", provider: "reference", source: .sample("referenceAlgorithmDefinitions")),
  ]

  static let sampleLandingSnapshots = [
    snapshot(id: "health-monitor", route: .healthMonitor, group: .today, title: "Health Monitor", value: "6", unit: "vitals", status: "Sample ready", freshness: "Today", provenance: "Health Monitor fixture grid", source: .sample("Health Monitor card"), systemImage: "heart.text.square", tint: .red, trendValues: [16.7, 16.8, 16.9, 16.8, 17.0], range: "Vitals grid"),
    snapshot(id: "sleep", route: .sleep, group: .today, title: "Sleep", value: "82", unit: "%", status: "Good", freshness: "Today", provenance: "sleepFeatureScoreSummary()", source: .sample("packet score fixture"), systemImage: "bed.double", tint: .indigo, trendValues: [75, 79, 81, 77, 82], range: "70 - 90%"),
    snapshot(id: "recovery", route: .recovery, group: .today, title: "Recovery", value: "72", unit: "%", status: "Ready", freshness: "Today", provenance: "recoveryFeatureScoreSummary()", source: .sample("packet score fixture"), systemImage: "battery.100percent", tint: .green, trendValues: [65, 69, 68, 74, 72], range: "60 - 100%"),
    snapshot(id: "strain", route: .strain, group: .training, title: "Strain", value: "8.8", unit: "/21", status: "Low", freshness: "Today", provenance: "strainFeatureScoreSummary()", source: .sample("packet score fixture"), systemImage: "figure.run", tint: .orange, trendValues: [5.1, 7.4, 11.0, 4.8, 8.8], range: "0 - 21"),
    snapshot(id: "stress", route: .stress, group: .vitals, title: "Stress", value: "38", unit: "%", status: "Medium", freshness: "Latest", provenance: "stressFeatureScoreSummary()", source: .sample("packet score fixture"), systemImage: "waveform.path.ecg", tint: .yellow, trendValues: [28, 34, 45, 39, 38], range: "24 - 49%"),
    snapshot(id: "cardio-load", route: .cardioLoad, group: .training, title: "Cardio Load", value: "42", unit: "load", status: "Calibrating", freshness: "7d", provenance: "activity sessions + HR stream required", source: .sample("cardio load contract"), systemImage: "heart.circle", tint: .pink, trendValues: [32, 37, 44, 35, 42], range: "Detraining to Productive"),
    snapshot(id: "energy-bank", route: .energyBank, group: .today, title: "Energy Bank", value: "62", unit: "%", status: "Balanced", freshness: "Today", provenance: "stress + sleep + activity contracts", source: .sample("energy bank contract"), systemImage: "bolt.circle", tint: .teal, trendValues: [51, 58, 63, 59, 62], range: "0 - 100%"),
    snapshot(id: "packet-inputs", route: .packetInputs, group: .algorithms, title: "Packet Inputs", value: "Ready", unit: "", status: "Extractable", freshness: "Now", provenance: "metricInputReadinessSummary()", source: .sample("packet-derived fixtures"), systemImage: "square.stack.3d.up", tint: .blue, trendValues: [], range: "Run to populate"),
    snapshot(id: "algorithms", route: .algorithms, group: .algorithms, title: "Algorithms", value: "5", unit: "families", status: "Loaded", freshness: "Now", provenance: "algorithmDefinitions", source: .sample("algorithm registry"), systemImage: "function", tint: .purple, trendValues: [], range: "Local registry"),
    snapshot(id: "calibration", route: .calibration, group: .algorithms, title: "Calibration", value: "Pending", unit: "", status: "Needs labels", freshness: "Now", provenance: "calibrationSummary()", source: .sample("calibration fixture"), systemImage: "slider.horizontal.3", tint: .mint, trendValues: [], range: "stored labels + local runs"),
  ]

  static let sampleHealthMonitorSnapshots = [
    snapshot(id: "respiratory-rate", route: .healthMonitor, group: .vitals, title: "Respiratory Rate", value: "17.0", unit: "rpm", status: "Normal range", freshness: "Primary sleep", provenance: "vitalEventFeatureSummary()", source: .sample("pending packet proof"), systemImage: "lungs", tint: .green, trendValues: [16.5, 16.7, 16.9, 16.8, 17.0], range: "16.4 - 17.2 rpm"),
    snapshot(id: "resting-hr", route: .healthMonitor, group: .vitals, title: "Resting HR", value: "49", unit: "bpm", status: "Normal range", freshness: "Primary sleep", provenance: "restingHeartRateFeatureSummary()", source: .sample("resting HR feature"), systemImage: "heart", tint: .red, trendValues: [51, 50, 52, 48, 49], range: "44 - 56 bpm"),
    snapshot(id: "resting-hrv", route: .healthMonitor, group: .vitals, title: "Resting HRV", value: "74", unit: "ms", status: "Normal range", freshness: "Primary sleep", provenance: "hrvFeatureSummary()", source: .sample("HRV feature"), systemImage: "waveform.path.ecg", tint: .blue, trendValues: [69, 72, 70, 76, 74], range: "60 - 95 ms"),
    snapshot(id: "oxygen-saturation", route: .healthMonitor, group: .vitals, title: "Oxygen Saturation", value: "--", unit: "%", status: "Unavailable", freshness: "Packet proof pending", provenance: "vitalEventFeatureProvenanceSummary()", source: .unavailable("SpO2 packet proof pending"), systemImage: "drop", tint: .cyan, trendValues: [], range: "94.7 - 96.3%"),
    snapshot(id: "wrist-temperature", route: .healthMonitor, group: .vitals, title: "Wrist Temperature", value: "--", unit: "C", status: "Unavailable", freshness: "Packet proof pending", provenance: "vitalEventFeatureProvenanceSummary()", source: .unavailable("temperature packet proof pending"), systemImage: "thermometer.medium", tint: .orange, trendValues: [], range: "35.4 - 35.9 C"),
    snapshot(id: "health-sleep", route: .sleep, group: .vitals, title: "Sleep", value: "7h 05m", unit: "", status: "Good", freshness: "Today", provenance: "sleepFeatureScoreSummary()", source: .sample("sleep score output"), systemImage: "bed.double", tint: .indigo, trendValues: [390, 410, 423, 398, 425], range: "6h 45m - 8h 30m"),
  ]

  static let sleepTrendRows = [
    snapshot(id: "sleep-score-trend", route: .sleep, group: .today, title: "Sleep Score", value: "82", unit: "%", status: "Good", freshness: "30d", provenance: "sleep score output", source: .sample("sleep trend fixture"), systemImage: "bed.double", tint: .indigo, trendValues: [75, 79, 81, 77, 82], range: "70 - 90%"),
    snapshot(id: "time-asleep-trend", route: .sleep, group: .today, title: "Time Asleep", value: "7h 05m", unit: "", status: "Normal range", freshness: "30d", provenance: "sleep window", source: .sample("sleep trend fixture"), systemImage: "clock", tint: .indigo, trendValues: [390, 410, 423, 398, 425], range: "6h 45m - 8h 30m"),
    snapshot(id: "rem-trend", route: .sleep, group: .today, title: "REM sleep", value: "1h 26m", unit: "", status: "Normal range", freshness: "30d", provenance: "sleep stages", source: .sample("sleep trend fixture"), systemImage: "moon.zzz", tint: .indigo, trendValues: [70, 79, 82, 75, 86], range: "60 - 110m"),
    snapshot(id: "deep-trend", route: .sleep, group: .today, title: "Deep Sleep", value: "1h 28m", unit: "", status: "Normal range", freshness: "30d", provenance: "sleep stages", source: .sample("sleep trend fixture"), systemImage: "moon.stars", tint: .indigo, trendValues: [80, 76, 91, 84, 88], range: "45 - 105m"),
    snapshot(id: "hr-dip-trend", route: .sleep, group: .today, title: "Heart Rate Dip", value: "8.4", unit: "%", status: "Normal range", freshness: "30d", provenance: "sleep HR", source: .sample("sleep trend fixture"), systemImage: "heart", tint: .indigo, trendValues: [5, 7, 8, 6, 8.4], range: "5 - 15%"),
    snapshot(id: "sleep-bank-trend", route: .sleep, group: .today, title: "Sleep Bank", value: "-1h 52m", unit: "", status: "Debt", freshness: "30d", provenance: "sleep debt", source: .sample("sleep trend fixture"), systemImage: "banknote", tint: .indigo, trendValues: [-160, -140, -121, -130, -112], range: "-4h - +2h"),
    snapshot(id: "sleep-time-trend", route: .sleep, group: .today, title: "Sleep Time", value: "23:12", unit: "", status: "Normal range", freshness: "30d", provenance: "schedule", source: .sample("sleep trend fixture"), systemImage: "bed.double", tint: .indigo, trendValues: [23.2, 23.5, 23.1, 22.9, 23.2], range: "22:30 - 23:45"),
    snapshot(id: "wake-time-trend", route: .sleep, group: .today, title: "Wake Time", value: "06:48", unit: "", status: "Normal range", freshness: "30d", provenance: "schedule", source: .sample("sleep trend fixture"), systemImage: "sun.max", tint: .indigo, trendValues: [6.8, 7.1, 6.9, 6.7, 6.8], range: "06:30 - 07:30"),
    snapshot(id: "time-to-fall-asleep-trend", route: .sleep, group: .today, title: "Time To Fall Asleep", value: "--", unit: "", status: "No data", freshness: "Needs labels", provenance: "sleep timeline", source: .unavailable("latency labels pending"), systemImage: "timer", tint: .indigo, trendValues: [], range: "No data"),
  ]

  static let recoveryTrendRows = [
    snapshot(id: "recovery-score-trend", route: .recovery, group: .today, title: "Recovery Score", value: "72", unit: "%", status: "Ready", freshness: "30d", provenance: "recovery score output", source: .sample("recovery trend fixture"), systemImage: "battery.100percent", tint: .green, trendValues: [65, 69, 68, 74, 72], range: "60 - 100%"),
    snapshot(id: "recovery-hrv-trend", route: .recovery, group: .vitals, title: "Resting HRV", value: "74", unit: "ms", status: "Normal range", freshness: "30d", provenance: "HRV/resting HR features", source: .sample("recovery trend fixture"), systemImage: "waveform.path.ecg", tint: .green, trendValues: [69, 72, 70, 76, 74], range: "60 - 95 ms"),
    snapshot(id: "recovery-rhr-trend", route: .recovery, group: .vitals, title: "Resting HR", value: "49", unit: "bpm", status: "Normal range", freshness: "30d", provenance: "resting HR features", source: .sample("recovery trend fixture"), systemImage: "heart", tint: .green, trendValues: [51, 50, 52, 48, 49], range: "44 - 56 bpm"),
    snapshot(id: "recovery-rr-trend", route: .recovery, group: .vitals, title: "Respiratory Rate", value: "--", unit: "rpm", status: "Unavailable", freshness: "Packet proof pending", provenance: "provided vitals", source: .unavailable("respiratory packet proof pending"), systemImage: "lungs", tint: .green, trendValues: [], range: "No data"),
    snapshot(id: "recovery-spo2-trend", route: .recovery, group: .vitals, title: "Oxygen Saturation", value: "--", unit: "%", status: "Unavailable", freshness: "Packet proof pending", provenance: "provided vitals", source: .unavailable("SpO2 packet proof pending"), systemImage: "drop", tint: .green, trendValues: [], range: "No data"),
    snapshot(id: "recovery-temp-trend", route: .recovery, group: .vitals, title: "Wrist Temperature", value: "--", unit: "C", status: "Unavailable", freshness: "Packet proof pending", provenance: "provided vitals", source: .unavailable("temperature packet proof pending"), systemImage: "thermometer.medium", tint: .green, trendValues: [], range: "No data"),
  ]

  static let strainTrendRows = [
    snapshot(id: "strain-score-trend", route: .strain, group: .training, title: "Strain Score", value: "8.8", unit: "/21", status: "Low", freshness: "30d", provenance: "strain score output", source: .sample("strain trend fixture"), systemImage: "figure.run", tint: .orange, trendValues: [5.1, 7.4, 11.0, 4.8, 8.8], range: "0 - 21"),
    snapshot(id: "exercise-duration-trend", route: .strain, group: .training, title: "Exercise Duration", value: "42", unit: "min", status: "Normal range", freshness: "30d", provenance: "activity sessions", source: .sample("strain trend fixture"), systemImage: "timer", tint: .orange, trendValues: [0, 32, 48, 12, 42], range: "0 - 90m"),
    snapshot(id: "daytime-hr-trend", route: .strain, group: .training, title: "Daytime HR", value: "78", unit: "bpm", status: "Normal range", freshness: "30d", provenance: "HR stream", source: .sample("strain trend fixture"), systemImage: "heart", tint: .orange, trendValues: [72, 76, 83, 70, 78], range: "60 - 110 bpm"),
    snapshot(id: "total-energy-trend", route: .strain, group: .training, title: "Total Energy", value: "2,340", unit: "kcal", status: "Normal range", freshness: "30d", provenance: "energy contract", source: .sample("strain trend fixture"), systemImage: "flame", tint: .orange, trendValues: [2100, 2250, 2520, 2000, 2340], range: "1800 - 2800 kcal"),
    snapshot(id: "step-count-trend", route: .strain, group: .training, title: "Step Count", value: "8,920", unit: "", status: "Normal range", freshness: "30d", provenance: "step count contract", source: .sample("strain trend fixture"), systemImage: "shoeprints.fill", tint: .orange, trendValues: [6200, 7900, 10400, 5100, 8920], range: "5k - 12k"),
  ]

  static let stressTrendRows = [
    snapshot(id: "stress-score-trend", route: .stress, group: .vitals, title: "Stress Score", value: "38", unit: "%", status: "Medium", freshness: "30d", provenance: "stress score output", source: .sample("stress trend fixture"), systemImage: "waveform.path.ecg", tint: .yellow, trendValues: [28, 34, 45, 39, 38], range: "24 - 49%"),
    snapshot(id: "non-activity-stress-trend", route: .stress, group: .vitals, title: "Non-Activity Stress", value: "42", unit: "%", status: "Normal range", freshness: "30d", provenance: "activity masking", source: .sample("stress trend fixture"), systemImage: "brain.head.profile", tint: .yellow, trendValues: [31, 38, 52, 47, 42], range: "36 - 59%"),
    snapshot(id: "sleep-stress-trend", route: .stress, group: .vitals, title: "Sleep Stress", value: "24", unit: "%", status: "Low", freshness: "30d", provenance: "sleep windows", source: .sample("stress trend fixture"), systemImage: "moon.zzz", tint: .yellow, trendValues: [28, 26, 22, 25, 24], range: "0 - 35%"),
  ]
}

struct HealthView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var store: HealthDataStore

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HealthStatusBanner(store: store)

        HealthCardGroup(
          title: "Today",
          snapshots: snapshots(in: .today)
        )

        HealthCardGroup(
          title: "Vitals",
          snapshots: snapshots(in: .vitals)
        )

        HealthCardGroup(
          title: "Training",
          snapshots: snapshots(in: .training)
        )

        HealthCardGroup(
          title: "Algorithms",
          snapshots: snapshots(in: .algorithms)
        )
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Health")
    .navigationDestination(for: HealthRoute.self) { route in
      HealthRouteContentView(route: route, store: store)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          store.refreshBridgeCatalogs()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Refresh Health Catalogs")
      }
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Health")
      store.loadBridgeCatalogsIfNeeded()
    }
  }

  private func snapshots(in group: HealthMetricGroup) -> [HealthMetricSnapshot] {
    store
      .landingSnapshots(
        liveHeartRateBPM: model.ble.liveHeartRateBPM,
        liveHeartRateSource: model.ble.liveHeartRateSource,
        liveHeartRateUpdatedAt: model.ble.liveHeartRateUpdatedAt
      )
      .filter { $0.group == group }
  }
}

struct HealthRouteDetailView: View {
  let route: HealthRoute
  @StateObject private var store: HealthDataStore

  init(route: HealthRoute, previewState: HealthPreviewState? = nil) {
    self.route = route
    let store = HealthDataStore()
    if let previewState {
      store.applyPreviewState(previewState)
    }
    _store = StateObject(wrappedValue: store)
  }

  var body: some View {
    HealthRouteContentView(route: route, store: store)
      .task {
        store.loadBridgeCatalogsIfNeeded()
      }
  }
}

private struct HealthRouteContentView: View {
  let route: HealthRoute
  @ObservedObject var store: HealthDataStore

  var body: some View {
    switch route {
    case .healthMonitor:
      HealthMonitorView(store: store)
    case .sleep, .recovery, .strain, .stress:
      HealthMetricFamilyView(route: route, store: store)
    case .cardioLoad:
      CardioLoadView(store: store)
    case .energyBank:
      EnergyBankView(store: store)
    case .packetInputs:
      PacketHealthView(store: store)
    case .algorithms:
      AlgorithmsHealthView(store: store)
    case .referenceComparisons:
      ReferenceComparisonsView(store: store)
    case .calibration:
      CalibrationHealthView(store: store)
    }
  }
}

private struct HealthStatusBanner: View {
  @ObservedObject var store: HealthDataStore

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: store.usesSampleData ? "testtube.2" : "checkmark.seal")
          .foregroundStyle(store.usesSampleData ? .orange : .green)
        Text(store.catalogStatus)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
        Spacer()
      }
      Text("Every row below declares bridge, live, sample, or unavailable provenance.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(14)
    .healthCardSurface()
  }
}

private struct HealthCardGroup: View {
  let title: String
  let snapshots: [HealthMetricSnapshot]

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HealthSectionTitle(title)
      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(snapshots) { snapshot in
          NavigationLink(value: snapshot.route) {
            HealthMetricCard(snapshot: snapshot)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

private struct HealthMetricCard: View {
  let snapshot: HealthMetricSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: snapshot.systemImage)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(snapshot.tint)
        Spacer()
        HealthSourceBadge(source: snapshot.source)
      }

      Text(snapshot.displayValue)
        .font(.title2.bold())
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      VStack(alignment: .leading, spacing: 3) {
        Text(snapshot.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text("\(snapshot.status) | \(snapshot.freshness)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Text(snapshot.provenance)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 144, alignment: .topLeading)
    .padding(14)
    .healthCardSurface()
  }
}

private struct HealthMonitorView: View {
  @ObservedObject var store: HealthDataStore
  @State private var selectedTrend: HealthMetricSnapshot?

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HealthHero(snapshot: store.snapshot(for: .healthMonitor), subtitle: "Vitals, timeline, and primary sleep inputs")

        LazyVGrid(columns: columns, spacing: 10) {
          ForEach(store.healthMonitorSnapshots()) { snapshot in
            Button {
              selectedTrend = snapshot
            } label: {
              HealthMetricCard(snapshot: snapshot)
            }
            .buttonStyle(.plain)
          }
        }

        NavigationLink(value: HealthRoute.cardioLoad) {
          HealthWideRouteCard(
            title: "Cardio Load",
            value: "42 load",
            status: "Calibrating",
            systemImage: "heart.circle",
            tint: .pink,
            source: .sample("cardio load route")
          )
        }
        .buttonStyle(.plain)

        HealthSectionTitle("Timeline")
        VStack(spacing: 8) {
          HealthInfoRow(row: HealthSummaryRow("Today timeline", value: "Primary sleep and latest packet windows", source: .sample("timeline rows"), systemImage: "timeline.selection"))
          HealthInfoRow(row: HealthSummaryRow("Primary sleep", value: "23:12 - 06:48 | 7h 05m | 82 score", source: .sample("sleep score output"), systemImage: "bed.double"))
        }

        if store.localDataSupportsExport {
          HealthSectionTitle("Export")
          VStack(alignment: .leading, spacing: 10) {
            ForEach(store.healthMonitorExportRows()) { row in
              HealthInfoRow(row: row)
            }
            ShareLink(item: store.localHealthExportText) {
              Label("Share Local Health Snapshot", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
            }
          }
          .padding(14)
          .healthCardSurface()
        }
      }
      .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Health Monitor")
    .sheet(item: $selectedTrend) { snapshot in
      HealthTrendSheet(snapshot: snapshot)
    }
  }
}

private struct PacketHealthView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var store: HealthDataStore

  var body: some View {
    List {
      Section {
        Button {
          store.runPacketInputs()
        } label: {
          Label("Extract Packet-Derived Inputs", systemImage: "square.stack.3d.up")
        }
      }

      Section("Packet-Derived Inputs") {
        HealthInfoRow(row: HealthSummaryRow("Readiness", value: store.metricInputReadinessSummary(), source: store.packetInputSource("metrics.input_readiness"), systemImage: "checklist"))
        HealthInfoRow(row: HealthSummaryRow("Latest HR", value: store.latestHeartRateSummary(bpm: model.ble.liveHeartRateBPM, source: model.ble.liveHeartRateSource, updatedAt: model.ble.liveHeartRateUpdatedAt), source: model.ble.liveHeartRateBPM == nil ? .sample("latestHeartRateSummary() fallback") : .live("BLE latest HR"), systemImage: "heart"))
        if !store.latestHeartRateProvenanceSummary(source: model.ble.liveHeartRateSource).isEmpty {
          HealthInfoRow(row: HealthSummaryRow("HR provenance", value: store.latestHeartRateProvenanceSummary(source: model.ble.liveHeartRateSource), source: .live("latestHeartRateProvenanceSummary()"), systemImage: "doc.text.magnifyingglass"))
        }
        HealthInfoRow(row: HealthSummaryRow("Motion", value: store.motionFeatureSummary(), source: store.packetInputSource("metrics.motion_features"), systemImage: "figure.walk.motion"))
        if !store.motionFeatureProvenanceSummary().isEmpty {
          HealthInfoRow(row: HealthSummaryRow("Motion provenance", value: store.motionFeatureProvenanceSummary(), source: store.packetInputSource("metrics.motion_features"), systemImage: "doc.text.magnifyingglass"))
        }
        HealthInfoRow(row: HealthSummaryRow("HRV", value: store.hrvFeatureSummary(), source: store.packetInputSource("metrics.hrv_features"), systemImage: "waveform.path.ecg"))
        if !store.hrvFeatureProvenanceSummary().isEmpty {
          HealthInfoRow(row: HealthSummaryRow("HRV provenance", value: store.hrvFeatureProvenanceSummary(), source: store.packetInputSource("metrics.hrv_features"), systemImage: "doc.text.magnifyingglass"))
        }
        HealthInfoRow(row: HealthSummaryRow("Resting HR", value: store.restingHeartRateFeatureSummary(), source: store.packetInputSource("metrics.resting_hr_features"), systemImage: "heart"))
        if !store.restingHeartRateFeatureProvenanceSummary().isEmpty {
          HealthInfoRow(row: HealthSummaryRow("Resting HR provenance", value: store.restingHeartRateFeatureProvenanceSummary(), source: store.packetInputSource("metrics.resting_hr_features"), systemImage: "doc.text.magnifyingglass"))
        }
        HealthInfoRow(row: HealthSummaryRow("Window", value: store.windowFeatureSummary(), source: store.packetInputSource("metrics.window_features"), systemImage: "rectangle.dashed"))
        if !store.windowFeatureProvenanceSummary().isEmpty {
          HealthInfoRow(row: HealthSummaryRow("Window provenance", value: store.windowFeatureProvenanceSummary(), source: store.packetInputSource("metrics.window_features"), systemImage: "doc.text.magnifyingglass"))
        }
        HealthInfoRow(row: HealthSummaryRow("Vitals", value: store.vitalEventFeatureSummary(), source: store.packetInputSource("metrics.vital_event_features"), systemImage: "thermometer.medium"))
        if !store.vitalEventFeatureProvenanceSummary().isEmpty {
          HealthInfoRow(row: HealthSummaryRow("Vitals provenance", value: store.vitalEventFeatureProvenanceSummary(), source: store.packetInputSource("metrics.vital_event_features"), systemImage: "doc.text.magnifyingglass"))
        }
        HealthInfoRow(row: HealthSummaryRow("Next action", value: store.packetDerivedFeatureNextActionSummary(), source: store.packetInputSource("packetDerivedFeatureNextActionSummary()"), systemImage: "arrow.triangle.2.circlepath"))
      }

      Section {
        Button {
          store.runPacketScores()
        } label: {
          Label("Run Packet-Derived Scores", systemImage: "chart.xyaxis.line")
        }
      }

      Section("Packet-Derived Scores") {
        HealthInfoRow(row: HealthSummaryRow("Sleep", value: store.sleepFeatureScoreSummary(), source: store.packetScoreSource("metrics.sleep_score_from_features"), systemImage: "bed.double"))
        HealthOptionalRow(label: "Sleep model", value: store.sleepV1ModelStatusSummary(), source: store.packetScoreSource("sleepV1ModelStatusSummary()"), systemImage: "brain.head.profile")
        HealthOptionalRow(label: "Sleep confidence", value: store.sleepV1ConfidenceSummary(), source: store.packetScoreSource("sleepV1ConfidenceSummary()"), systemImage: "checkmark.seal")
        HealthOptionalRow(label: "Sleep data", value: store.sleepV1DataNotesSummary(), source: store.packetScoreSource("sleepV1DataNotesSummary()"), systemImage: "info.circle")
        HealthOptionalRow(label: "Sleep schedule", value: store.sleepV1ScheduleSummary(), source: store.packetScoreSource("sleepV1ScheduleSummary()"), systemImage: "calendar")
        HealthOptionalRow(label: "Sleep debt", value: store.sleepV1DebtSummary(), source: store.packetScoreSource("sleepV1DebtSummary()"), systemImage: "minus.circle")
        HealthOptionalRow(label: "Sleep HR", value: store.sleepV1HeartRateSummary(), source: store.packetScoreSource("sleepV1HeartRateSummary()"), systemImage: "heart")
        HealthOptionalRow(label: "Sleep stages", value: store.sleepV1StagesSummary(), source: store.packetScoreSource("sleepV1StagesSummary()"), systemImage: "chart.bar")
        HealthOptionalRow(label: "Sleep architecture", value: store.sleepV1ArchitectureCalibrationSummary(), source: store.packetScoreSource("sleepV1ArchitectureCalibrationSummary()"), systemImage: "point.3.connected.trianglepath.dotted")
        HealthOptionalRow(label: "Sleep change", value: store.sleepV1WhyChangedSummary(), source: store.packetScoreSource("sleepV1WhyChangedSummary()"), systemImage: "arrow.left.arrow.right")
        ForEach(store.sleepV1ComponentBreakdownRows()) { row in
          HealthInfoRow(row: row)
        }
        HealthOptionalRow(label: "Sleep provenance", value: store.packetScoreProvenanceSummary("sleep"), source: store.packetScoreSource("packetScoreProvenanceSummary(sleep)"), systemImage: "doc.text.magnifyingglass")
        HealthInfoRow(row: HealthSummaryRow("Recovery", value: store.recoveryFeatureScoreSummary(), source: store.packetScoreSource("metrics.recovery_score_from_features"), systemImage: "battery.100percent"))
        HealthInfoRow(row: HealthSummaryRow("Recovery vitals", value: store.recoveryProvidedVitalsSummary(), source: store.packetScoreSource("recoveryProvidedVitalsSummary()"), systemImage: "lungs"))
        RecoveryVitalsEditor(store: store)
        HealthOptionalRow(label: "Recovery provenance", value: store.packetScoreProvenanceSummary("recovery"), source: store.packetScoreSource("packetScoreProvenanceSummary(recovery)"), systemImage: "doc.text.magnifyingglass")
        HealthInfoRow(row: HealthSummaryRow("Strain", value: store.strainFeatureScoreSummary(), source: store.packetScoreSource("metrics.strain_score_from_features"), systemImage: "figure.run"))
        HealthOptionalRow(label: "Strain provenance", value: store.packetScoreProvenanceSummary("strain"), source: store.packetScoreSource("packetScoreProvenanceSummary(strain)"), systemImage: "doc.text.magnifyingglass")
        HealthInfoRow(row: HealthSummaryRow("Stress", value: store.stressFeatureScoreSummary(), source: store.packetScoreSource("metrics.stress_score_from_features"), systemImage: "waveform.path.ecg"))
        HealthOptionalRow(label: "Stress provenance", value: store.packetScoreProvenanceSummary("stress"), source: store.packetScoreSource("packetScoreProvenanceSummary(stress)"), systemImage: "doc.text.magnifyingglass")
        HealthInfoRow(row: HealthSummaryRow("Next action", value: store.packetDerivedScoreNextActionSummary(), source: store.packetScoreSource("packetDerivedScoreNextActionSummary()"), systemImage: "arrow.triangle.2.circlepath"))
      }
    }
    .navigationTitle("Packet Inputs")
  }
}

private struct RecoveryVitalsEditor: View {
  @ObservedObject var store: HealthDataStore

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Editable Recovery Vitals")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        TextField("Resp rate", text: $store.recoveryRespiratoryRateText)
          .textFieldStyle(.roundedBorder)
          .keyboardType(.decimalPad)
        TextField("Baseline", text: $store.recoveryRespiratoryBaselineText)
          .textFieldStyle(.roundedBorder)
          .keyboardType(.decimalPad)
        TextField("Temp delta", text: $store.recoverySkinTemperatureDeltaText)
          .textFieldStyle(.roundedBorder)
          .keyboardType(.numbersAndPunctuation)
      }
    }
    .padding(.vertical, 6)
  }
}

private struct HealthMetricFamilyView: View {
  let route: HealthRoute
  @ObservedObject var store: HealthDataStore
  @State private var selectedTrend: HealthMetricSnapshot?
  @State private var selectedPrimarySleep: PrimarySleepDetail?
  @State private var showAddSleepPlaceholder = false

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HealthHero(snapshot: store.snapshot(for: route), subtitle: subtitle)
        ForEach(heroRows) { row in
          HealthInfoRow(row: row)
            .padding(.horizontal, 0)
        }

        if route == .sleep {
          SleepDataBridgeSection(store: store)
        }

        if route == .stress {
          StressDailyChart()
          StressBreakdownRows()
        }

        if route == .strain {
          HeartRateZonesSection()
        }

        if route == .sleep {
          SleepTimelineSection(
            session: store.primarySleep(),
            onAddSleep: { showAddSleepPlaceholder = true },
            onSelectPrimarySleep: { selectedPrimarySleep = $0 }
          )
        } else {
          HealthSectionTitle("Timeline")
          ForEach(timelineRows) { row in
            HealthInfoRow(row: row)
          }
        }

        HealthSectionTitle("Insights")
        ForEach(insightRows) { row in
          HealthInfoRow(row: row)
        }

        HealthSectionTitle("Trends")
        ForEach(store.trendRows(for: route)) { snapshot in
          Button {
            selectedTrend = snapshot
          } label: {
            HealthTrendRow(snapshot: snapshot)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(route.title)
    .sheet(item: $selectedTrend) { snapshot in
      HealthTrendSheet(snapshot: snapshot)
    }
    .sheet(item: $selectedPrimarySleep) { sleep in
      PrimarySleepDetailSheet(sleep: sleep)
    }
    .alert("Add Sleep", isPresented: $showAddSleepPlaceholder) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(store.sleepTimelineEmptyActionSummary())
    }
  }

  private var subtitle: String {
    switch route {
    case .sleep: "Score, stages, sleep needed, alarm, and trend surfaces"
    case .recovery: "Recovery score, HRV, resting HR, vitals, and unavailable states"
    case .strain: "0-21 strain semantics with percent-ready trend rows"
    case .stress: "Stress score, HRV/HR inputs, daily chart, and breakdown"
    default: ""
    }
  }

  private var heroRows: [HealthSummaryRow] {
    switch route {
    case .sleep:
      return [
        HealthSummaryRow("Quality", value: primarySleepQualitySummary, source: store.packetScoreSource("sleep score output"), systemImage: "bed.double"),
        HealthSummaryRow("Time in bed", value: store.primarySleep()?.timeInBedText ?? "No data", source: store.packetScoreSource("sleep window"), systemImage: "clock"),
        HealthSummaryRow("Time asleep", value: store.primarySleep()?.durationText ?? "No data", source: store.packetScoreSource("sleep window"), systemImage: "moon.zzz"),
        HealthSummaryRow("Sleep Needed", value: "7h 39m | wind down 22:20 | target 23:00", source: .sample("Sleep Coach"), systemImage: "alarm"),
        HealthSummaryRow("Alarm", value: "07:00 | window enabled", source: .sample("alarm settings state"), systemImage: "bell"),
      ]
    case .recovery:
      return [
        HealthSummaryRow("Recovery Score", value: store.recoveryFeatureScoreSummary(), source: store.packetScoreSource("recovery score output"), systemImage: "battery.100percent"),
        HealthSummaryRow("Resting HRV", value: store.hrvFeatureSummary(), source: store.packetInputSource("HRV features"), systemImage: "waveform.path.ecg"),
        HealthSummaryRow("Resting HR", value: store.restingHeartRateFeatureSummary(), source: store.packetInputSource("resting HR features"), systemImage: "heart"),
        HealthSummaryRow("Provided vitals", value: store.recoveryProvidedVitalsSummary(), source: store.packetScoreSource("manual provided vitals"), systemImage: "lungs"),
      ]
    case .strain:
      return [
        HealthSummaryRow("Strain Score", value: store.strainFeatureScoreSummary(), source: store.packetScoreSource("strain score output"), systemImage: "figure.run"),
        HealthSummaryRow("Target strain", value: "6.0 - 10.5 / 21", source: .sample("training target"), systemImage: "target"),
        HealthSummaryRow("Duration", value: "42 min", source: .sample("activity sessions"), systemImage: "timer"),
        HealthSummaryRow("Total Energy", value: "2,340 kcal", source: .sample("energy contract"), systemImage: "flame"),
      ]
    case .stress:
      return [
        HealthSummaryRow("Stress score", value: store.stressFeatureScoreSummary(), source: store.packetScoreSource("stress score output"), systemImage: "waveform.path.ecg"),
        HealthSummaryRow("Last HRV", value: store.hrvFeatureSummary(), source: store.packetInputSource("HRV feature"), systemImage: "waveform.path.ecg"),
        HealthSummaryRow("Last HR", value: "78 bpm", source: .sample("HR stream"), systemImage: "heart"),
      ]
    default:
      return []
    }
  }

  private var primarySleepQualitySummary: String {
    guard let sleep = store.primarySleep() else {
      return "-- | No data"
    }
    return "\(sleep.scoreDisplayText) | \(sleep.qualityText)"
  }

  private var timelineRows: [HealthSummaryRow] {
    switch route {
    case .sleep, .recovery:
      return [
        HealthSummaryRow("Primary sleep", value: "23:12 - 06:48 | 7h 05m | 82 score", source: .sample("Primary Sleep detail"), systemImage: "bed.double"),
        HealthSummaryRow("Timeline", value: "Sleep, awake, and packet windows", source: .sample("timeline rows"), systemImage: "timeline.selection"),
      ]
    case .strain:
      return [
        HealthSummaryRow("Activities", value: "No activities | add or record an activity", source: .sample("activity sessions empty state"), systemImage: "plus.circle"),
      ]
    case .stress:
      return [
        HealthSummaryRow("Daily timeline", value: "Sleep mask + HRV/HR stress segments", source: .sample("stress time series"), systemImage: "timeline.selection"),
      ]
    default:
      return []
    }
  }

  private var insightRows: [HealthSummaryRow] {
    switch route {
    case .sleep:
      return [
        HealthSummaryRow("Score impacts", value: "Duration positive, consistency locked until more nights", source: .sample("sleep insights"), systemImage: "sparkles"),
        HealthSummaryRow("Low confidence state", value: "Shown when packet coverage falls below threshold", source: .sample("sleep insights"), systemImage: "lock"),
      ]
    case .recovery:
      return [
        HealthSummaryRow("Tags", value: "Hydration positive | stress tag locked", source: .sample("recovery insights/tags"), systemImage: "tag"),
        HealthSummaryRow("Vitals unavailable", value: "Respiratory rate, SpO2, and temperature require packet proof", source: .unavailable("vital packet proof pending"), systemImage: "exclamationmark.triangle"),
      ]
    case .strain:
      return [
        HealthSummaryRow("Coaching", value: "Stay near target strain; 0-21 raw score preserved", source: .sample("strain coaching"), systemImage: "sparkles"),
      ]
    case .stress:
      return [
        HealthSummaryRow("Breakdown", value: "High 18% | Medium 27% | Low 55%", source: .sample("stress breakdown"), systemImage: "chart.bar"),
      ]
    default:
      return []
    }
  }
}

private struct CardioLoadView: View {
  @ObservedObject var store: HealthDataStore
  @State private var selectedRange = "30D"

  var body: some View {
    List {
      Section {
        HealthHero(snapshot: store.snapshot(for: .cardioLoad), subtitle: "Weekly load, status breakdown, and calibration contract")
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
      }
      Section("Cardio Status Breakdown") {
        ForEach(store.cardioStatusRows()) { row in
          VStack(alignment: .leading, spacing: 6) {
            HealthInfoRow(row: row)
            BreakdownRow(label: row.label, value: row.value.components(separatedBy: "|").first?.trimmingCharacters(in: .whitespaces) ?? "", tint: cardioStatusColor(row.label), width: cardioStatusWidth(row.value))
          }
        }
      }
      Section("Weekly Chart") {
        Picker("Range", selection: $selectedRange) {
          ForEach(["30D", "3M", "6M", "1Y"], id: \.self) { range in
            Text(range).tag(range)
          }
        }
        .pickerStyle(.segmented)
        CardioWeeklyLoadChart(days: store.cardioLoadWeeklyPoints())
          .frame(height: 170)
        HealthInfoRow(row: HealthSummaryRow("Resources", value: "The Basics: Cardio Load | Cardio Status", source: .sample("Cardio Load resources"), systemImage: "book"))
        HealthInfoRow(row: HealthSummaryRow("Required inputs", value: "HR stream + activity sessions + calibration window", source: .sample("required inputs contract"), systemImage: "checklist"))
      }
      Section("Timeline") {
        if store.cardioLoadWeeklyPoints().isEmpty {
          ContentUnavailableView("No Cardio Timeline", systemImage: "heart.circle", description: Text("Cardio Load needs seven days of HR and activity data."))
        } else {
          ForEach(store.cardioLoadWeeklyPoints()) { day in
            HealthInfoRow(row: HealthSummaryRow(day.dateLabel, value: "\(Int(day.load)) load | \(day.status) | \(day.durationText)", source: day.source, systemImage: "calendar"))
          }
        }
      }
    }
    .navigationTitle("Cardio Load")
  }

  private func cardioStatusWidth(_ value: String) -> CGFloat {
    if value.hasPrefix("0d") {
      return 0
    }
    if value.hasPrefix("1d") {
      return 1.0 / 7.0
    }
    if value.hasPrefix("2d") {
      return 2.0 / 7.0
    }
    return 0.5
  }

  private func cardioStatusColor(_ status: String) -> Color {
    switch status {
    case "Productive", "Peaking": .green
    case "Maintaining": .blue
    case "Fatigued", "Overtraining": .red
    case "Detraining": .orange
    default: .pink
    }
  }
}

private struct EnergyBankView: View {
  @ObservedObject var store: HealthDataStore

  var body: some View {
    List {
      Section {
        HealthHero(snapshot: store.snapshot(for: .energyBank), subtitle: "Energy charge, drain, stress, and sleep contribution")
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
      }
      Section("Energy And Stress") {
        EnergyAndStressChart(points: store.energyStressChartPoints(), selectedPoint: store.energyStressSelectedPoint())
          .frame(height: 190)
        if let selected = store.energyStressSelectedPoint() {
          HealthInfoRow(row: HealthSummaryRow("Selected window", value: "\(selected.timeLabel) | Energy \(Int(selected.energy)) | Stress \(Int(selected.stress))", source: .sample("energy stress selected point"), systemImage: "scope"))
        }
        HealthInfoRow(row: HealthSummaryRow("Total Charged", value: "+69%", source: .sample("charge windows"), systemImage: "plus.circle"))
        HealthInfoRow(row: HealthSummaryRow("Total Drained", value: "-61%", source: .sample("drain windows"), systemImage: "minus.circle"))
      }
      Section("Energy Usage") {
        HealthInfoRow(row: HealthSummaryRow("Primary sleep contribution", value: "+24% charged", source: .sample("Primary sleep contribution"), systemImage: "bed.double"))
        HealthInfoRow(row: HealthSummaryRow("Stress usage window", value: "21:30 - 21:36 | stress 65 | usage 64", source: .sample("energy stress chart values"), systemImage: "waveform.path.ecg"))
        HealthInfoRow(row: HealthSummaryRow("Required inputs", value: "stress time series + sleep contribution + activity drains", source: .sample("Energy Bank data contract"), systemImage: "checklist"))
      }
    }
    .navigationTitle("Energy Bank")
  }
}

private struct AlgorithmsHealthView: View {
  @ObservedObject var store: HealthDataStore

  var body: some View {
    List {
      Section("Primary Selection") {
        ForEach(store.algorithmFamilies, id: \.self) { family in
          let algorithms = store.algorithms(for: family)
          if algorithms.isEmpty {
            HealthInfoRow(row: HealthSummaryRow(family.uppercased(), value: "No algorithms registered", source: store.catalogSource, systemImage: "function"))
          } else {
            Picker(family.uppercased(), selection: Binding(
              get: { store.selectedAlgorithmByFamily[family] ?? algorithms[0].id },
              set: { store.selectAlgorithm($0, for: family) }
            )) {
              ForEach(algorithms) { algorithm in
                Text(algorithm.displayName).tag(algorithm.id)
              }
            }
          }
        }
      }

      Section("Algorithm Definitions") {
        ForEach(store.algorithmDefinitions) { definition in
          HealthInfoRow(row: HealthSummaryRow(definition.displayName, value: "\(definition.family) | \(definition.status) | \(definition.provider)", source: definition.source, systemImage: "function"))
        }
      }

      Section("Reference Definitions") {
        ForEach(store.referenceDefinitions) { definition in
          HealthInfoRow(row: HealthSummaryRow(definition.displayName, value: "\(definition.family) | \(definition.status)", source: definition.source, systemImage: "scalemass"))
        }
      }
    }
    .navigationTitle("Algorithms")
  }
}

private struct ReferenceComparisonsView: View {
  @ObservedObject var store: HealthDataStore

  var body: some View {
    List {
      Section {
        Button {
          store.runReferenceComparisons()
        } label: {
          Label("Run Reference Comparisons", systemImage: "compare.arrows")
        }
      }
      Section("Policy") {
        HealthInfoRow(row: HealthSummaryRow("Pass/fail policy", value: "Goose scores are primary; references are benchmark-only unless a report says pass", source: .sample("reference comparison policy"), systemImage: "checkmark.seal"))
      }
      Section("Comparisons") {
        ForEach(["hrv", "sleep", "strain", "stress"], id: \.self) { family in
          HealthInfoRow(row: HealthSummaryRow(family.uppercased(), value: store.referenceComparisonSummary(family), source: store.referenceComparisonSource(family), systemImage: "scalemass"))
        }
      }
    }
    .navigationTitle("References")
  }
}

private struct CalibrationHealthView: View {
  @ObservedObject var store: HealthDataStore

  var body: some View {
    List {
      Section("Target") {
        Picker("Family", selection: $store.calibrationTargetFamily) {
          ForEach(["recovery", "sleep", "strain", "stress", "hrv"], id: \.self) { family in
            Text(family.uppercased()).tag(family)
          }
        }
        .pickerStyle(.segmented)
      }

      Section("Actions") {
        Button {
          store.importCalibrationLabels()
        } label: {
          Label("Import Labels", systemImage: "square.and.arrow.down")
        }
        Button {
          store.calibrate()
        } label: {
          Label("Calibrate", systemImage: "slider.horizontal.3")
        }
      }

      Section("Calibration") {
        HealthInfoRow(row: HealthSummaryRow("Dataset", value: "stored labels + local runs", source: .sample("dataset policy"), systemImage: "folder"))
        HealthInfoRow(row: HealthSummaryRow("User labels", value: store.calibrationLabelSummary(), source: .sample("calibrationLabelSummary()"), systemImage: "tag"))
        HealthInfoRow(row: HealthSummaryRow("Holdout", value: store.calibrationSummary(), source: .sample("calibrationSummary()"), systemImage: "chart.xyaxis.line"))
        HealthInfoRow(row: HealthSummaryRow("Calibrated score", value: store.calibratedScoreSummary(), source: .sample("calibratedScoreSummary()"), systemImage: "checkmark.seal"))
        HealthInfoRow(row: HealthSummaryRow("Label policy", value: "official_labels_are_labels", source: .sample("label policy"), systemImage: "text.badge.checkmark"))
        HealthInfoRow(row: HealthSummaryRow("Next action", value: store.calibrationNextActionSummary(), source: .sample("calibration next action"), systemImage: "arrow.triangle.2.circlepath"))
        ForEach(store.calibrationIssues(), id: \.self) { issue in
          HealthInfoRow(row: HealthSummaryRow("Issue", value: issue, source: .sample("calibration issues"), systemImage: "exclamationmark.triangle"))
        }
      }
    }
    .navigationTitle("Calibration")
  }
}

private struct HealthHero: View {
  let snapshot: HealthMetricSnapshot
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: snapshot.systemImage)
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(snapshot.tint)
          .frame(width: 48, height: 48)
          .background(snapshot.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        VStack(alignment: .leading, spacing: 4) {
          Text(snapshot.title)
            .font(.title2.bold())
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
        HealthSourceBadge(source: snapshot.source)
      }

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(snapshot.displayValue)
          .font(.system(size: 36, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text(snapshot.status)
          .font(.headline)
          .foregroundStyle(snapshot.tint)
      }
      Text("\(snapshot.freshness) | \(snapshot.provenance)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(16)
    .healthCardSurface()
  }
}

private struct HealthWideRouteCard: View {
  let title: String
  let value: String
  let status: String
  let systemImage: String
  let tint: Color
  let source: HealthDataSource

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 38, height: 38)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        Text("\(value) | \(status)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      HealthSourceBadge(source: source)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(.tertiary)
    }
    .padding(14)
    .healthCardSurface()
  }
}

private struct HealthInfoRow: View {
  let row: HealthSummaryRow

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: row.systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(row.source.kind == .unavailable ? .orange : .secondary)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(row.label)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
        Text(row.value)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if !row.status.isEmpty {
          Text(row.status)
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        Text(row.source.label)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
  }
}

private struct HealthOptionalRow: View {
  let label: String
  let value: String
  let source: HealthDataSource
  let systemImage: String

  var body: some View {
    if !value.isEmpty {
      HealthInfoRow(row: HealthSummaryRow(label, value: value, source: source, systemImage: systemImage))
    }
  }
}

private struct HealthTrendRow: View {
  let snapshot: HealthMetricSnapshot

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: snapshot.systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(snapshot.tint)
        .frame(width: 32, height: 32)
        .background(snapshot.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(snapshot.title)
          .font(.headline)
        Text("\(snapshot.displayValue) | \(snapshot.status)")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(snapshot.source.label)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      Spacer()
      HealthSparkline(points: snapshot.trend.points.map(\.value), tint: snapshot.tint)
        .frame(width: 76, height: 34)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(.tertiary)
    }
    .padding(14)
    .healthCardSurface()
  }
}

private struct HealthTrendSheet: View {
  let snapshot: HealthMetricSnapshot
  @Environment(\.dismiss) private var dismiss
  @State private var selectedRange = "30D"

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text(snapshot.displayValue)
                .font(.system(size: 34, weight: .bold))
              Spacer()
              Text(snapshot.status)
                .font(.headline)
                .foregroundStyle(snapshot.tint)
            }
            Text(snapshot.trend.rangeLabel)
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Text(snapshot.source.label)
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }

        Section("Trend") {
          Picker("Range", selection: $selectedRange) {
            ForEach(["7D", "30D", "6M"], id: \.self) { range in
              Text(range).tag(range)
            }
          }
          .pickerStyle(.segmented)

          if snapshot.trend.hasData {
            HealthSparkline(points: snapshot.trend.points.map(\.value), tint: snapshot.tint)
              .frame(height: 160)
            Text(snapshot.trend.summary)
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            ContentUnavailableView("No Trend Data", systemImage: "chart.line.uptrend.xyaxis", description: Text(snapshot.trend.analysis))
          }
        }

        Section("Analysis") {
          Text(snapshot.trend.analysis)
        }

        Section("Resources") {
          ForEach(snapshot.trend.resources, id: \.self) { resource in
            Label(resource, systemImage: "book")
          }
        }
      }
      .navigationTitle(snapshot.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") {
            dismiss()
          }
        }
      }
    }
  }
}

private struct SleepDataBridgeSection: View {
  @ObservedObject var store: HealthDataStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HealthSectionTitle("Sleep Data")
      VStack(spacing: 8) {
        HealthInfoRow(row: HealthSummaryRow("HealthKit history", value: store.externalSleepImportStatus, source: .bridge("sleep.import_external_history"), systemImage: "heart.text.square"))
        HealthInfoRow(row: HealthSummaryRow("Goose sleep score", value: store.sleepFeatureScoreSummary(), source: store.packetScoreSource("metrics.sleep_score_from_features"), systemImage: "bed.double"))
      }
      HStack(spacing: 10) {
        Button {
          Task {
            await store.importHealthKitSleepHistory()
          }
        } label: {
          Label("Import HealthKit", systemImage: "square.and.arrow.down")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
          store.runSleepScore()
        } label: {
          Label("Run Sleep Score", systemImage: "chart.xyaxis.line")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }
}

private struct SleepTimelineSection: View {
  let session: PrimarySleepDetail?
  let onAddSleep: () -> Void
  let onSelectPrimarySleep: (PrimarySleepDetail) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        HealthSectionTitle("Sleep Timeline")
        Spacer()
        Button {
          onAddSleep()
        } label: {
          Label("Add Sleep", systemImage: "plus.circle")
        }
        .font(.subheadline.weight(.semibold))
      }

      if let session {
        Button {
          onSelectPrimarySleep(session)
        } label: {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text("Primary Sleep")
                  .font(.headline)
                Text("\(session.dateLabel) | \(session.startLabel) - \(session.endLabel)")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 3) {
                Text(session.scoreDisplayText)
                  .font(.title3.bold())
                Text(session.durationText)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            SleepStageTimeline(stages: session.stages)
            Text(session.source.label)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
          .padding(14)
          .healthCardSurface()
        }
        .buttonStyle(.plain)
      } else {
        ContentUnavailableView("No Sleep Timeline", systemImage: "bed.double", description: Text("Add Sleep creates the first local sleep row once manual entry is available."))
          .frame(maxWidth: .infinity)
          .padding(14)
          .healthCardSurface()
      }
    }
  }
}

private struct SleepStageTimeline: View {
  let stages: [HealthSleepStageSegment]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GeometryReader { proxy in
        HStack(spacing: 2) {
          ForEach(stages) { stage in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(stageColor(stage.stage))
              .frame(width: segmentWidth(stage, totalWidth: proxy.size.width))
              .overlay {
                Text(stage.durationText)
                  .font(.caption2.weight(.bold))
                  .foregroundStyle(.white)
                  .lineLimit(1)
                  .minimumScaleFactor(0.6)
              }
          }
        }
      }
      .frame(height: 30)

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
        ForEach(stages) { stage in
          HStack(spacing: 8) {
            Circle()
              .fill(stageColor(stage.stage))
              .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
              Text(stage.displayStage)
                .font(.caption.weight(.semibold))
              Text("\(stage.durationText) | \(stage.startLabel)-\(stage.endLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }

  private func segmentWidth(_ stage: HealthSleepStageSegment, totalWidth: CGFloat) -> CGFloat {
    let totalMinutes = max(stages.map(\.durationMinutes).reduce(0, +), 1)
    return max(32, totalWidth * CGFloat(stage.durationMinutes / totalMinutes))
  }

  private func stageColor(_ stage: String) -> Color {
    switch stage.lowercased() {
    case "awake": return .orange
    case "rem": return .purple
    case "deep": return .blue
    default: return .indigo
    }
  }
}

private struct PrimarySleepDetailSheet: View {
  let sleep: PrimarySleepDetail
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Text("Primary Sleep")
              .font(.title2.bold())
            Text("\(sleep.dateLabel) | \(sleep.startLabel) - \(sleep.endLabel)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            HStack(spacing: 12) {
              HealthSummaryPill(title: "Score", value: sleep.scoreDisplayText)
              HealthSummaryPill(title: "Asleep", value: sleep.durationText)
              HealthSummaryPill(title: "In Bed", value: sleep.timeInBedText)
            }
          }
        }
        Section("Stages") {
          SleepStageTimeline(stages: sleep.stages)
            .frame(minHeight: 118)
          ForEach(sleep.stages) { stage in
            HealthInfoRow(row: HealthSummaryRow(stage.displayStage, value: "\(stage.startLabel) - \(stage.endLabel) | \(stage.durationText)", status: stage.confidence.map { "confidence \(HealthDataStore.percentText($0) ?? "--")" } ?? "", source: stage.source, systemImage: "moon.zzz"))
          }
        }
        Section("Source") {
          HealthInfoRow(row: HealthSummaryRow("Data source", value: sleep.source.label, source: sleep.source, systemImage: "doc.text.magnifyingglass"))
        }
      }
      .navigationTitle("Primary Sleep")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") {
            dismiss()
          }
        }
      }
    }
  }
}

private struct HealthSummaryPill: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.weight(.bold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct HealthSourceBadge: View {
  let source: HealthDataSource

  var body: some View {
    Text(source.kind.rawValue)
      .font(.caption2.weight(.bold))
      .foregroundStyle(color)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(color.opacity(0.12), in: Capsule())
  }

  private var color: Color {
    switch source.kind {
    case .bridge: .green
    case .live: .blue
    case .sample: .orange
    case .unavailable: .secondary
    }
  }
}

private struct LegacyCardioWeeklyLoadChart: View {
  let days: [CardioLoadDay]

  var body: some View {
    if days.isEmpty {
      ContentUnavailableView("No Weekly Load", systemImage: "heart.circle", description: Text("Cardio Load needs HR and activity data."))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      HStack(alignment: .bottom, spacing: 10) {
        ForEach(days) { day in
          VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(color(for: day.status))
              .frame(height: max(12, 120 * day.percent))
              .overlay(alignment: .top) {
                Text("\(Int(day.load))")
                  .font(.caption2.weight(.bold))
                  .foregroundStyle(.white)
                  .padding(.top, 4)
              }
            Text(day.dateLabel)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding(.top, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
  }

  private func color(for status: String) -> Color {
    switch status {
    case "Productive", "Peaking":
      return .green
    case "Maintaining":
      return .blue
    case "Detraining":
      return .orange
    case "Fatigued", "Overtraining":
      return .red
    default:
      return .pink
    }
  }
}

private struct LegacyEnergyAndStressChart: View {
  let points: [EnergyStressPoint]
  let selectedPoint: EnergyStressPoint?

  var body: some View {
    if points.isEmpty {
      ContentUnavailableView("No Energy Data", systemImage: "bolt.circle", description: Text("Energy Bank needs stress, sleep, and activity inputs."))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 10) {
        GeometryReader { proxy in
          ZStack {
            chartPath(values: points.map(\.energy), size: proxy.size)
              .stroke(.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            chartPath(values: points.map(\.stress), size: proxy.size)
              .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            if let selectedPoint, let index = points.firstIndex(where: { $0.id == selectedPoint.id }) {
              let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
              Rectangle()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 2)
                .position(x: x, y: proxy.size.height / 2)
            }
          }
        }

        HStack(spacing: 16) {
          Label("Energy", systemImage: "bolt.fill")
            .foregroundStyle(.teal)
          Label("Stress", systemImage: "waveform.path.ecg")
            .foregroundStyle(.orange)
        }
        .font(.caption.weight(.semibold))
      }
      .padding(.vertical, 8)
    }
  }

  private func chartPath(values: [Double], size: CGSize) -> Path {
    Path { path in
      guard !values.isEmpty else {
        return
      }
      for (index, value) in values.enumerated() {
        let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
        let normalized = min(max(value / 100, 0), 1)
        let y = size.height - size.height * CGFloat(normalized)
        if index == 0 {
          path.move(to: CGPoint(x: x, y: y))
        } else {
          path.addLine(to: CGPoint(x: x, y: y))
        }
      }
    }
  }
}

private struct CompactEnergyAndStressChart: View {
  let points: [EnergyStressPoint]
  let selectedPoint: EnergyStressPoint?

  var body: some View {
    if points.isEmpty {
      ContentUnavailableView("No Energy Data", systemImage: "battery.0percent", description: Text("Energy Bank needs stress, sleep, and activity data."))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 12) {
        GeometryReader { proxy in
          ZStack(alignment: .bottomLeading) {
            chartLine(points.map(\.energy), in: proxy.size)
              .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            chartLine(points.map(\.stress), in: proxy.size)
              .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            ForEach(points) { point in
              Circle()
                .fill(point.id == selectedPoint?.id ? Color.primary : Color.secondary.opacity(0.45))
                .frame(width: point.id == selectedPoint?.id ? 9 : 6, height: point.id == selectedPoint?.id ? 9 : 6)
                .position(position(for: point.energy, index: index(of: point), size: proxy.size))
            }
          }
        }
        .frame(height: 126)

        HStack(spacing: 12) {
          ChartLegend(color: .green, label: "Energy")
          ChartLegend(color: .orange, label: "Stress")
          Spacer()
          if let selectedPoint {
            Text(selectedPoint.timeLabel)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(.top, 8)
    }
  }

  private func chartLine(_ values: [Double], in size: CGSize) -> Path {
    Path { path in
      for (index, value) in values.enumerated() {
        let point = position(for: value, index: index, size: size)
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private func position(for value: Double, index: Int, size: CGSize) -> CGPoint {
    let x = size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
    let y = size.height - size.height * CGFloat(min(max(value / 100, 0), 1))
    return CGPoint(x: x, y: y)
  }

  private func index(of point: EnergyStressPoint) -> Int {
    points.firstIndex(where: { $0.id == point.id }) ?? 0
  }
}

private struct ChartLegend: View {
  let color: Color
  let label: String

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
  }
}

private struct HealthSparkline: View {
  let points: [Double]
  let tint: Color

  var body: some View {
    GeometryReader { proxy in
      if points.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(.tertiarySystemFill))
          .overlay {
            Text("No data")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
          }
      } else {
        Path { path in
          let minimum = points.min() ?? 0
          let maximum = points.max() ?? 1
          let span = max(maximum - minimum, 1)
          for (index, point) in points.enumerated() {
            let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
            let normalized = (point - minimum) / span
            let y = proxy.size.height - proxy.size.height * CGFloat(normalized)
            if index == 0 {
              path.move(to: CGPoint(x: x, y: y))
            } else {
              path.addLine(to: CGPoint(x: x, y: y))
            }
          }
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
      }
    }
  }
}

private struct CardioWeeklyLoadChart: View {
  let days: [CardioLoadDay]

  var body: some View {
    GeometryReader { proxy in
      if days.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(.tertiarySystemFill))
          .overlay {
            Text("No weekly load data")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
      } else {
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
          rangeBand(in: proxy.size)
          chartPath(in: proxy.size)
            .stroke(.pink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
            let point = chartPoint(index: index, load: day.load, size: proxy.size)
            Circle()
              .fill(index == days.count - 1 ? Color.pink : Color.white)
              .stroke(.pink, lineWidth: 2)
              .frame(width: index == days.count - 1 ? 12 : 8, height: index == days.count - 1 ? 12 : 8)
              .position(point)
            Text(day.dateLabel)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .position(x: point.x, y: proxy.size.height - 12)
          }
          VStack(alignment: .trailing, spacing: 0) {
            Text("60")
            Spacer()
            Text("30")
            Spacer()
            Text("0")
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(width: proxy.size.width - 8, height: proxy.size.height - 24, alignment: .trailing)
          .padding(.top, 8)
          if let last = days.last {
            Text("\(Int(last.load)) load | \(last.status)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.pink)
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .background(.thinMaterial, in: Capsule())
              .position(x: min(proxy.size.width - 72, chartPoint(index: days.count - 1, load: last.load, size: proxy.size).x), y: 18)
          }
        }
      }
    }
  }

  private func rangeBand(in size: CGSize) -> some View {
    let top = yPosition(load: 45, height: size.height)
    let bottom = yPosition(load: 30, height: size.height)
    return Rectangle()
      .fill(Color.green.opacity(0.12))
      .frame(width: size.width, height: max(bottom - top, 1))
      .position(x: size.width / 2, y: (top + bottom) / 2)
  }

  private func chartPath(in size: CGSize) -> Path {
    Path { path in
      for (index, day) in days.enumerated() {
        let point = chartPoint(index: index, load: day.load, size: size)
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private func chartPoint(index: Int, load: Double, size: CGSize) -> CGPoint {
    let left: CGFloat = 16
    let right: CGFloat = 34
    let usableWidth = max(size.width - left - right, 1)
    let x = left + usableWidth * CGFloat(index) / CGFloat(max(days.count - 1, 1))
    return CGPoint(x: x, y: yPosition(load: load, height: size.height))
  }

  private func yPosition(load: Double, height: CGFloat) -> CGFloat {
    let top: CGFloat = 18
    let bottom: CGFloat = 34
    let usableHeight = max(height - top - bottom, 1)
    let normalized = min(max(load / 60.0, 0), 1)
    return top + usableHeight * CGFloat(1 - normalized)
  }
}

private struct EnergyAndStressChart: View {
  let points: [EnergyStressPoint]
  let selectedPoint: EnergyStressPoint?

  var body: some View {
    GeometryReader { proxy in
      if points.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(.tertiarySystemFill))
          .overlay {
            Text("No energy or stress data")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
      } else {
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
          ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
            if point.isSleepWindow {
              Rectangle()
                .fill(Color.indigo.opacity(0.10))
                .frame(width: max(proxy.size.width / CGFloat(points.count), 28), height: proxy.size.height - 28)
                .position(x: xPosition(index: index, width: proxy.size.width), y: (proxy.size.height - 28) / 2)
            }
            Capsule()
              .fill(point.stress > 55 ? Color.red.opacity(0.55) : Color.orange.opacity(0.40))
              .frame(width: 6, height: max(8, CGFloat(point.usage)))
              .position(x: xPosition(index: index, width: proxy.size.width), y: proxy.size.height - 24 - CGFloat(point.usage) / 2)
            if point.isChargeEvent {
              Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .position(x: xPosition(index: index, width: proxy.size.width), y: proxy.size.height - 20)
            }
          }
          energyPath(in: proxy.size)
            .stroke(.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          stressPath(in: proxy.size)
            .stroke(.yellow, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
          if let selectedPoint,
             let selectedIndex = points.firstIndex(where: { $0.id == selectedPoint.id }) {
            let x = xPosition(index: selectedIndex, width: proxy.size.width)
            Rectangle()
              .fill(Color.primary.opacity(0.18))
              .frame(width: 1, height: proxy.size.height - 28)
              .position(x: x, y: (proxy.size.height - 28) / 2)
            Text("Energy \(Int(selectedPoint.energy)) | Stress \(Int(selectedPoint.stress))")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.primary)
              .padding(.horizontal, 7)
              .padding(.vertical, 4)
              .background(.thinMaterial, in: Capsule())
              .position(x: min(max(x, 74), proxy.size.width - 74), y: 18)
          }
          HStack {
            ForEach(points) { point in
              Text(point.timeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.bottom, 2)
          VStack(alignment: .trailing) {
            Text("100%")
            Spacer()
            Text("50%")
            Spacer()
            Text("0%")
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(width: proxy.size.width - 8, height: proxy.size.height - 28, alignment: .trailing)
          .padding(.top, 8)
        }
      }
    }
  }

  private func energyPath(in size: CGSize) -> Path {
    Path { path in
      for (index, point) in points.enumerated() {
        let cgPoint = CGPoint(x: xPosition(index: index, width: size.width), y: yPosition(value: point.energy, height: size.height))
        if index == 0 {
          path.move(to: cgPoint)
        } else {
          path.addLine(to: cgPoint)
        }
      }
    }
  }

  private func stressPath(in size: CGSize) -> Path {
    Path { path in
      for (index, point) in points.enumerated() {
        let cgPoint = CGPoint(x: xPosition(index: index, width: size.width), y: yPosition(value: point.stress, height: size.height))
        if index == 0 {
          path.move(to: cgPoint)
        } else {
          path.addLine(to: cgPoint)
        }
      }
    }
  }

  private func xPosition(index: Int, width: CGFloat) -> CGFloat {
    let left: CGFloat = 16
    let right: CGFloat = 38
    let usableWidth = max(width - left - right, 1)
    return left + usableWidth * CGFloat(index) / CGFloat(max(points.count - 1, 1))
  }

  private func yPosition(value: Double, height: CGFloat) -> CGFloat {
    let top: CGFloat = 20
    let bottom: CGFloat = 34
    let usableHeight = max(height - top - bottom, 1)
    return top + usableHeight * CGFloat(1 - min(max(value / 100, 0), 1))
  }
}

private struct StressDailyChart: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HealthSectionTitle("Today's Stress")
      HealthSparkline(points: [18, 22, 20, 38, 56, 42, 31, 44, 38], tint: .yellow)
        .frame(height: 96)
      Text("Sleep mask and activity masking are represented by sample time-series segments.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(14)
    .healthCardSurface()
  }
}

private struct StressBreakdownRows: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HealthSectionTitle("Stress Breakdown")
      BreakdownRow(label: "High", value: "18%", tint: .red, width: 0.18)
      BreakdownRow(label: "Medium", value: "27%", tint: .orange, width: 0.27)
      BreakdownRow(label: "Low", value: "55%", tint: .green, width: 0.55)
    }
    .padding(14)
    .healthCardSurface()
  }
}

private struct HeartRateZonesSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HealthSectionTitle("Heart Rate Zones")
      BreakdownRow(label: "Zone 5", value: "4 min", tint: .red, width: 0.10)
      BreakdownRow(label: "Zone 4", value: "12 min", tint: .orange, width: 0.32)
      BreakdownRow(label: "Zone 3", value: "18 min", tint: .yellow, width: 0.48)
      BreakdownRow(label: "Zone 2", value: "8 min", tint: .green, width: 0.22)
    }
    .padding(14)
    .healthCardSurface()
  }
}

private struct BreakdownRow: View {
  let label: String
  let value: String
  let tint: Color
  let width: CGFloat

  var body: some View {
    HStack(spacing: 12) {
      Text(label)
        .font(.subheadline.weight(.semibold))
        .frame(width: 74, alignment: .leading)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color(.tertiarySystemFill))
          Capsule()
            .fill(tint)
            .frame(width: proxy.size.width * min(max(width, 0), 1))
        }
      }
      .frame(height: 8)
      Text(value)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 54, alignment: .trailing)
    }
  }
}

private struct HealthSectionTitle: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.title3.bold())
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private extension View {
  func healthCardSurface() -> some View {
    background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06))
      }
  }
}

private struct HealthPreviewRouteHost: View {
  let route: HealthRoute
  let state: HealthPreviewState

  var body: some View {
    NavigationStack {
      HealthRouteDetailView(route: route, previewState: state)
    }
    .environmentObject(GooseAppModel(startBLE: false))
  }
}

#Preview("Health Landing") {
  NavigationStack {
    HealthView(store: HealthDataStore())
  }
  .environmentObject(GooseAppModel(startBLE: false))
}

#Preview("Health Monitor - Populated") {
  HealthPreviewRouteHost(route: .healthMonitor, state: .populated)
}

#Preview("Health Monitor - Missing Vitals") {
  HealthPreviewRouteHost(route: .healthMonitor, state: .missing)
}

#Preview("Sleep - Populated") {
  HealthPreviewRouteHost(route: .sleep, state: .populated)
}

#Preview("Sleep - Missing Sleep Data") {
  HealthPreviewRouteHost(route: .sleep, state: .missing)
}

#Preview("Recovery - Populated") {
  HealthPreviewRouteHost(route: .recovery, state: .populated)
}

#Preview("Recovery - Missing Vitals") {
  HealthPreviewRouteHost(route: .recovery, state: .missing)
}

#Preview("Strain - Populated") {
  HealthPreviewRouteHost(route: .strain, state: .populated)
}

#Preview("Strain - Missing Activities") {
  HealthPreviewRouteHost(route: .strain, state: .missing)
}

#Preview("Stress - Populated") {
  HealthPreviewRouteHost(route: .stress, state: .populated)
}

#Preview("Stress - Missing Time Series") {
  HealthPreviewRouteHost(route: .stress, state: .missing)
}

#Preview("Cardio Load - Populated") {
  HealthPreviewRouteHost(route: .cardioLoad, state: .populated)
}

#Preview("Cardio Load - Missing Inputs") {
  HealthPreviewRouteHost(route: .cardioLoad, state: .missing)
}

#Preview("Energy Bank - Populated") {
  HealthPreviewRouteHost(route: .energyBank, state: .populated)
}

#Preview("Energy Bank - Missing Inputs") {
  HealthPreviewRouteHost(route: .energyBank, state: .missing)
}

#Preview("Packet Inputs - Populated") {
  HealthPreviewRouteHost(route: .packetInputs, state: .populated)
}

#Preview("Packet Inputs - Missing") {
  HealthPreviewRouteHost(route: .packetInputs, state: .missing)
}

#Preview("Algorithms - Populated") {
  HealthPreviewRouteHost(route: .algorithms, state: .populated)
}

#Preview("Algorithms - Missing Catalog") {
  HealthPreviewRouteHost(route: .algorithms, state: .missing)
}

#Preview("Reference Comparisons - Populated") {
  HealthPreviewRouteHost(route: .referenceComparisons, state: .populated)
}

#Preview("Reference Comparisons - Missing") {
  HealthPreviewRouteHost(route: .referenceComparisons, state: .missing)
}

#Preview("Calibration - Populated") {
  HealthPreviewRouteHost(route: .calibration, state: .populated)
}

#Preview("Calibration - Missing") {
  HealthPreviewRouteHost(route: .calibration, state: .missing)
}
