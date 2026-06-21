import Darwin
import Foundation
import SwiftUI
import UIKit

extension HealthDataStore {
  func stressAlgorithmSummary(
    for date: Date = Date(),
    calendar: Calendar = .current,
    allowLiveFallbacks: Bool = true
  ) -> StressAlgorithmSummary {
    guard !previewMissingData else {
      return emptyStressSummary(
        status: "No data",
        freshness: "Missing",
        source: .unavailable("preview missing stress data")
      )
    }

    let samples = heartRateSeriesStore.samples(forDayContaining: date, calendar: calendar)
    guard samples.count >= 6 else {
      return emptyStressSummary(
        status: "No HR data",
        freshness: heartRateTimelineStatus,
        source: .unavailable("stress requires at least six heart-rate samples today")
      )
    }

    let dayStart = calendar.startOfDay(for: date)

    // Return a memoized result when the day's heart-rate sample set is materially
    // unchanged. The summary is a whole-day rollup, so the signature is quantized:
    // live HR streaming adds a sample roughly every second, but rebuilding the
    // daily aggregate on every render/sample is wasteful and was the dominant
    // streaming-time cost in profiling. Bucketing the sample count (every 16) and
    // the latest sample time (every 30s) rebuilds at most ~every 16-30s while
    // connected — imperceptible staleness for a daily score — and caches fully
    // when no new samples are arriving.
    let sampleBucket = samples.count / 16
    let timeBucket = Int((samples.last?.capturedAt.timeIntervalSince1970 ?? 0) / 30)
    let cacheSignature = "\(dayStart.timeIntervalSince1970)|\(sampleBucket)|\(timeBucket)|\(allowLiveFallbacks)"
    if let cached = stressSummaryCache[cacheSignature] {
      return cached
    }

    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
    let restingHeartRate = stressRestingHeartRateEstimate(
      samples: samples,
      date: date,
      calendar: calendar,
      allowLiveFallbacks: allowLiveFallbacks
    )
    let bucketSeconds: TimeInterval = 10 * 60
    let grouped = Dictionary(grouping: samples) { sample in
      Int(max(sample.capturedAt.timeIntervalSince(dayStart), 0) / bucketSeconds)
    }

    let windows = grouped
      .sorted { $0.key < $1.key }
      .compactMap { bucket, bucketSamples -> StressWindowPoint? in
        guard !bucketSamples.isEmpty else {
          return nil
        }
        let values = bucketSamples.map(\.bpm)
        let averageHeartRate = Double(values.reduce(0, +)) / Double(values.count)
        let minHeartRate = Double(values.min() ?? Int(averageHeartRate.rounded()))
        let maxHeartRate = Double(values.max() ?? Int(averageHeartRate.rounded()))
        let heartRatePressure = Self.clamp(
          (averageHeartRate - restingHeartRate) / max(32.0, restingHeartRate * 0.62),
          min: 0,
          max: 1
        )
        let volatilityPressure = Self.clamp(
          ((maxHeartRate - minHeartRate) / max(averageHeartRate, 1)) / 0.24,
          min: 0,
          max: 1
        )
        let start = dayStart.addingTimeInterval(TimeInterval(bucket) * bucketSeconds)
        let end = min(start.addingTimeInterval(bucketSeconds), dayEnd)
        let sleepWindow = Self.isLikelySleepWindow(start, calendar: calendar)
        var stress = (heartRatePressure * 0.88 + volatilityPressure * 0.12) * 100.0
        if sleepWindow {
          stress *= 0.62
        }
        if averageHeartRate <= restingHeartRate + 4 {
          stress *= 0.65
        }
        stress = Self.clamp(stress, min: 0, max: 100)

        return StressWindowPoint(
          id: "\(Int64((start.timeIntervalSince1970 * 1000).rounded()))",
          start: start,
          end: end,
          timeLabel: Self.timeLabel(start),
          stress: stress,
          averageHeartRate: averageHeartRate,
          sampleCount: bucketSamples.count,
          isSleepWindow: sleepWindow
        )
      }

    guard !windows.isEmpty else {
      return emptyStressSummary(
        status: "No HR data",
        freshness: heartRateTimelineStatus,
        source: .unavailable("stress buckets could not be computed")
      )
    }

    let weightedSampleCount = max(windows.reduce(0) { $0 + $1.sampleCount }, 1)
    let score = windows.reduce(0.0) { $0 + $1.stress * Double($1.sampleCount) } / Double(weightedSampleCount)
    let averageHeartRate = windows.reduce(0.0) { $0 + $1.averageHeartRate * Double($1.sampleCount) } / Double(weightedSampleCount)
    let totalMinutes = max(windows.reduce(0.0) { $0 + $1.durationMinutes }, 1)
    let highMinutes = windows.filter { $0.stress >= 66 }.reduce(0.0) { $0 + $1.durationMinutes }
    let mediumMinutes = windows.filter { $0.stress >= 33 && $0.stress < 66 }.reduce(0.0) { $0 + $1.durationMinutes }
    let lowMinutes = max(totalMinutes - highMinutes - mediumMinutes, 0)
    let sampleConfidence = Self.clamp(Double(samples.count) / 120.0, min: 0, max: 1)
    let windowConfidence = Self.clamp(Double(windows.count) / 18.0, min: 0, max: 1)
    let stressConfidence = Self.clamp(0.32 + sampleConfidence * 0.42 + windowConfidence * 0.18, min: 0.32, max: 0.88)
    let inputSummary = [
      "hr_samples=\(samples.count)",
      "windows=\(windows.count)",
      "resting_hr=\(Self.numberText(restingHeartRate, fractionDigits: 0) ?? "--") bpm",
      "model=hr_elevation+hr_volatility",
    ].joined(separator: " | ")
    let confidenceText = Self.numberText(stressConfidence, fractionDigits: 2) ?? "0"

    let summary = StressAlgorithmSummary(
      score: score,
      status: Self.stressStatusLabel(score: score),
      averageHeartRate: averageHeartRate,
      averageHRV: nil,
      windows: windows,
      high: StressZoneSummary(label: "High", percent: highMinutes / totalMinutes, durationMinutes: highMinutes),
      medium: StressZoneSummary(label: "Med", percent: mediumMinutes / totalMinutes, durationMinutes: mediumMinutes),
      low: StressZoneSummary(label: "Low", percent: lowMinutes / totalMinutes, durationMinutes: lowMinutes),
      sampleCount: samples.count,
      source: .localEstimate("goose.stress.hr_proxy.v1 | confidence=\(confidenceText) | \(inputSummary)"),
      freshness: Self.relativeText(for: samples.last?.capturedAt) ?? "Today",
      confidence: stressConfidence,
      inputSummary: inputSummary
    )

    // Bound the cache: only a few distinct day/sample signatures are ever live
    // (today plus any selected detail date), so clear if it grows unexpectedly.
    if stressSummaryCache.count > 12 {
      stressSummaryCache.removeAll(keepingCapacity: true)
    }
    stressSummaryCache[cacheSignature] = summary
    return summary
  }

  func energyBankAlgorithmSummary(
    for date: Date = Date(),
    calendar: Calendar = .current,
    allowLiveFallbacks: Bool = true
  ) -> EnergyBankAlgorithmSummary {
    let stress = stressAlgorithmSummary(for: date, calendar: calendar, allowLiveFallbacks: allowLiveFallbacks)
    guard stress.hasData else {
      return emptyEnergyBankSummary(
        status: "No stress data",
        freshness: stress.freshness,
        source: stress.source
      )
    }

    let recoverySeed = recoveryScoreValue()
    var energy = Self.clamp(recoverySeed ?? 55, min: 5, max: 100)
    var points: [EnergyStressPoint] = []
    var totalCharged = 0.0
    var totalDrained = 0.0
    var sleepCharge = 0.0

    for window in stress.windows.sorted(by: { $0.start < $1.start }) {
      let hours = max(window.durationMinutes / 60.0, 1.0 / 6.0)
      let delta: Double
      if window.isSleepWindow {
        let lowStressBonus = max(0, 35 - window.stress) * 0.045
        delta = (3.3 + lowStressBonus) * hours
      } else {
        let stressDrain = (0.75 + window.stress / 20.0) * hours
        let quietCharge = window.stress < 22 ? 0.55 * hours : 0
        delta = quietCharge - stressDrain
      }

      energy = Self.clamp(energy + delta, min: 0, max: 100)
      if delta >= 0 {
        totalCharged += delta
        if window.isSleepWindow {
          sleepCharge += delta
        }
      } else {
        totalDrained += abs(delta)
      }

      points.append(
        EnergyStressPoint(
          id: window.id,
          timeLabel: window.timeLabel,
          energy: energy,
          stress: window.stress,
          usage: Self.clamp(abs(delta) * 12.0, min: 4, max: 100),
          isSleepWindow: window.isSleepWindow,
          isChargeEvent: delta > 0
        )
      )
    }

    let stressConfidence = stress.confidence ?? 0.35
    let energyConfidence = Self.clamp(stressConfidence * 0.86 + (recoverySeed == nil ? 0 : 0.10), min: 0.30, max: 0.90)
    let seedText = recoverySeed.flatMap { Self.numberText($0, fractionDigits: 0) }.map { "recovery_score=\($0)" } ?? "recovery_score=default_55"
    let inputSummary = [
      "stress_windows=\(stress.windows.count)",
      "stress_confidence=\(Self.numberText(stressConfidence, fractionDigits: 2) ?? "0")",
      seedText,
      "model=stress_charge_drain",
    ].joined(separator: " | ")
    let confidenceText = Self.numberText(energyConfidence, fractionDigits: 2) ?? "0"

    return EnergyBankAlgorithmSummary(
      percent: energy,
      status: Self.energyBankStatusLabel(percent: energy),
      points: points,
      totalCharged: totalCharged,
      totalDrained: totalDrained,
      primarySleepCharge: sleepCharge,
      source: .localEstimate("goose.energy_bank.v1 | confidence=\(confidenceText) | \(inputSummary)"),
      freshness: stress.freshness,
      confidence: energyConfidence,
      inputSummary: inputSummary
    )
  }

  func stressSnapshot(base snapshot: HealthMetricSnapshot, allowLiveFallbacks: Bool = true) -> HealthMetricSnapshot {
    let summary = stressAlgorithmSummary(allowLiveFallbacks: allowLiveFallbacks)
    guard let score = summary.score,
          let scoreText = Self.numberText(score, fractionDigits: 0) else {
      return replacingHealthMonitorSnapshot(
        snapshot,
        value: "--",
        unit: "%",
        status: summary.status,
        freshness: summary.freshness,
        provenance: summary.source.detail,
        source: summary.source,
        trend: Self.emptyTrend(from: snapshot.trend, packetCount: packetEvidenceFrameCount())
      )
    }

    return replacingHealthMonitorSnapshot(
      snapshot,
      value: scoreText,
      unit: "%",
      status: summary.status,
      freshness: summary.freshness,
      provenance: summary.source.detail,
      source: summary.source,
      trend: trendMergingPersistedSeries(
        Self.stressTrendModel(base: snapshot.trend, summary: summary),
        metricName: "stress_score")
    )
  }

  func energyBankSnapshot(base snapshot: HealthMetricSnapshot, allowLiveFallbacks: Bool = true) -> HealthMetricSnapshot {
    let summary = energyBankAlgorithmSummary(allowLiveFallbacks: allowLiveFallbacks)
    guard let percent = summary.percent,
          let percentText = Self.numberText(percent, fractionDigits: 0) else {
      return replacingHealthMonitorSnapshot(
        snapshot,
        value: "--",
        unit: "%",
        status: summary.status,
        freshness: summary.freshness,
        provenance: summary.source.detail,
        source: summary.source,
        trend: Self.emptyTrend(from: snapshot.trend, packetCount: packetEvidenceFrameCount())
      )
    }

    return replacingHealthMonitorSnapshot(
      snapshot,
      value: percentText,
      unit: "%",
      status: summary.status,
      freshness: summary.freshness,
      provenance: summary.source.detail,
      source: summary.source,
      trend: trendMergingPersistedSeries(
        Self.energyBankTrendModel(base: snapshot.trend, summary: summary),
        metricName: "energy_bank_percent")
    )
  }

  func emptyStressSummary(
    status: String,
    freshness: String,
    source: HealthDataSource
  ) -> StressAlgorithmSummary {
    StressAlgorithmSummary(
      score: nil,
      status: status,
      averageHeartRate: nil,
      averageHRV: nil,
      windows: [],
      high: StressZoneSummary(label: "High", percent: 0, durationMinutes: 0),
      medium: StressZoneSummary(label: "Med", percent: 0, durationMinutes: 0),
      low: StressZoneSummary(label: "Low", percent: 0, durationMinutes: 0),
      sampleCount: 0,
      source: source,
      freshness: freshness,
      confidence: nil,
      inputSummary: source.detail
    )
  }

  func emptyEnergyBankSummary(
    status: String,
    freshness: String,
    source: HealthDataSource
  ) -> EnergyBankAlgorithmSummary {
    EnergyBankAlgorithmSummary(
      percent: nil,
      status: status,
      points: [],
      totalCharged: 0,
      totalDrained: 0,
      primarySleepCharge: 0,
      source: source,
      freshness: freshness,
      confidence: nil,
      inputSummary: source.detail
    )
  }

  func stressRestingHeartRateEstimate(
    samples: [HeartRateSamplePoint],
    date: Date,
    calendar: Calendar,
    allowLiveFallbacks: Bool = true
  ) -> Double {
    if let storeEstimate = heartRateSeriesStore.restingEstimate(forDayContaining: date, calendar: calendar)?.bpm {
      return storeEstimate
    }
    if allowLiveFallbacks, let liveEstimate = Self.liveHRDerivedRestingHeartRateSample()?.bpm {
      return liveEstimate
    }
    let values = samples.map(\.bpm).sorted()
    let lowCount = max(1, values.count / 4)
    return Double(values.prefix(lowCount).reduce(0, +)) / Double(lowCount)
  }

  func zeroStrainSnapshot(
    base snapshot: HealthMetricSnapshot,
    freshness: String,
    provenance: String,
    sourceDetail: String
  ) -> HealthMetricSnapshot {
    replacingHealthMonitorSnapshot(
      snapshot,
      value: "--",
      unit: "",
      status: "No strain data",
      freshness: freshness,
      provenance: provenance,
      source: .unavailable(sourceDetail),
      trend: Self.emptyTrend(from: snapshot.trend, packetCount: packetEvidenceFrameCount())
    )
  }

  // MARK: - Daily persistence (Energy Bank + Stress)

  /// Persist today's computed Energy Bank and Stress values into the named-daily
  /// metric store so trends survive app restarts (they were previously computed
  /// in-memory only). Idempotent: re-writing the same day replaces the value.
  func persistDailyEnergyAndStressMetrics(
    for date: Date = Date(),
    calendar: Calendar = .current
  ) {
    let window = HealthDataStore.currentDailyMetricWindow()

    let energy = energyBankAlgorithmSummary(for: date, calendar: calendar)
    if let percent = energy.percent {
      writeDailyNamedMetric(
        name: "energy_bank_percent", value: percent, unit: "percent",
        source: "goose.energy_bank.v1", confidence: energy.confidence, dateKey: window.dateKey)
      writeDailyNamedMetric(
        name: "energy_bank_charged", value: energy.totalCharged, unit: "kcal",
        source: "goose.energy_bank.v1", confidence: energy.confidence, dateKey: window.dateKey)
      writeDailyNamedMetric(
        name: "energy_bank_drained", value: energy.totalDrained, unit: "kcal",
        source: "goose.energy_bank.v1", confidence: energy.confidence, dateKey: window.dateKey)
    }

    let stress = stressAlgorithmSummary(for: date, calendar: calendar)
    if let score = stress.score {
      writeDailyNamedMetric(
        name: "stress_score", value: score, unit: "score",
        source: "goose.stress.v1", confidence: stress.confidence, dateKey: window.dateKey)
    }
  }

  private func writeDailyNamedMetric(
    name: String, value: Double, unit: String, source: String,
    confidence: Double?, dateKey: String
  ) {
    guard value.isFinite else { return }
    var args: [String: Any] = [
      "database_path": databasePath,
      "date_key": dateKey,
      "metric_name": name,
      "value": value,
      "unit": unit,
      "source_kind": source,
    ]
    if let confidence {
      args["confidence"] = confidence
    }
    _ = try? bridge.request(method: "metrics.write_daily_named_metric", args: args)
  }

  /// Read a persisted named-daily metric series (inclusive date-key range) for
  /// building Energy Bank / Stress trends.
  func dailyNamedMetricSeries(
    name: String, from startDateKey: String, to endDateKey: String
  ) -> [(dateKey: String, value: Double)] {
    guard
      let report = try? bridge.request(
        method: "metrics.read_daily_named_metrics",
        args: [
          "database_path": databasePath,
          "metric_name": name,
          "start_date_key": startDateKey,
          "end_date_key": endDateKey,
        ])
    else {
      return []
    }
    let metrics = report["metrics"] as? [[String: Any]] ?? []
    return metrics.compactMap { metric in
      guard let dateKey = metric["date_key"] as? String else { return nil }
      let value =
        (metric["value"] as? Double) ?? (metric["value"] as? NSNumber)?.doubleValue
      guard let value else { return nil }
      return (dateKey, value)
    }
  }

  /// Trend points from the persisted named-daily series for the last `days`.
  /// Returns nil when nothing is stored yet so callers keep their fallback trend.
  func persistedTrendPoints(
    metricName: String, days: Int = 14, calendar: Calendar = .current
  ) -> [HealthTrendPoint]? {
    let today = Date()
    guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
      return nil
    }
    let start = HealthDataStore.metricDateKey(for: startDate, calendar: calendar)
    let end = HealthDataStore.metricDateKey(for: today, calendar: calendar)
    let series = dailyNamedMetricSeries(name: metricName, from: start, to: end)
    guard !series.isEmpty else { return nil }
    return series.map { entry in
      HealthTrendPoint(label: Self.shortDayLabel(entry.dateKey), value: entry.value)
    }
  }

  /// Replace a fallback trend's points with the persisted multi-day series once at
  /// least two days exist; otherwise keep the fallback (preserves prior behavior
  /// and its labels/analysis).
  func trendMergingPersistedSeries(
    _ base: HealthTrendModel, metricName: String
  ) -> HealthTrendModel {
    guard let points = persistedTrendPoints(metricName: metricName), points.count >= 2 else {
      return base
    }
    return HealthTrendModel(
      id: base.id,
      title: base.title,
      rangeLabel: base.rangeLabel,
      summary: base.summary,
      analysis: base.analysis,
      resources: base.resources,
      points: points
    )
  }

  private static func shortDayLabel(_ dateKey: String) -> String {
    let parts = dateKey.split(separator: "-")
    guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
      return dateKey
    }
    return "\(month)/\(day)"
  }

}
