import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum ActivityEnvironment {
  case outdoor
  case indoor
  case pool
}

enum ActivityKind: String, CaseIterable, Identifiable {
  case run
  case walk
  case hike
  case roadRide
  case mountainBike
  case soccer
  case strength
  case hiit
  case yoga
  case row
  case indoorRide
  case poolSwim

  var id: String { rawValue }

  var title: String {
    switch self {
    case .run: "Run"
    case .walk: "Walk"
    case .hike: "Hike"
    case .roadRide: "Road Ride"
    case .mountainBike: "MTB"
    case .soccer: "Soccer"
    case .strength: "Strength"
    case .hiit: "HIIT"
    case .yoga: "Yoga"
    case .row: "Row"
    case .indoorRide: "Indoor Ride"
    case .poolSwim: "Pool Swim"
    }
  }

  var subtitle: String {
    switch environment {
    case .outdoor: "GPS + HR"
    case .indoor: "HR zones"
    case .pool: "HR + laps"
    }
  }

  var systemImage: String {
    switch self {
    case .run: "figure.run"
    case .walk: "figure.walk"
    case .hike: "figure.hiking"
    case .roadRide: "bicycle"
    case .mountainBike: "mountain.2"
    case .soccer: "soccerball"
    case .strength: "dumbbell"
    case .hiit: "flame"
    case .yoga: "figure.yoga"
    case .row: "figure.rower"
    case .indoorRide: "figure.indoor.cycle"
    case .poolSwim: "figure.pool.swim"
    }
  }

  var tint: Color {
    switch self {
    case .run: .orange
    case .walk: .green
    case .hike: .brown
    case .roadRide: .blue
    case .mountainBike: .mint
    case .soccer: .teal
    case .strength: .red
    case .hiit: .pink
    case .yoga: .purple
    case .row: .cyan
    case .indoorRide: .indigo
    case .poolSwim: .cyan
    }
  }

  var environment: ActivityEnvironment {
    switch self {
    case .run, .walk, .hike, .roadRide, .mountainBike, .soccer:
      .outdoor
    case .poolSwim:
      .pool
    case .strength, .hiit, .yoga, .row, .indoorRide:
      .indoor
    }
  }

  var usesGPS: Bool {
    environment == .outdoor
  }

  var trainingFocus: String {
    switch self {
    case .run: "Pace, route, and time in aerobic zones"
    case .walk: "Steady movement, HR drift, and route"
    case .hike: "Distance, elevation context, and low-zone time"
    case .roadRide: "Speed, route, and sustained zone work"
    case .mountainBike: "Route, surges, and high-intensity bursts"
    case .soccer: "Field coverage, repeated efforts, and HR recovery"
    case .strength: "Work blocks, recovery gaps, and strain"
    case .hiit: "Intervals, peaks, and recovery between rounds"
    case .yoga: "Duration, low-zone control, and calm time"
    case .row: "Sustained effort, HR stability, and cadence later"
    case .indoorRide: "Zone control and steady-state effort"
    case .poolSwim: "Session time, HR response, and lap support later"
    }
  }
}

struct HeartRateZone: Identifiable {
  let id: Int
  let title: String
  let range: String
  let color: Color

  static let maxHeartRate = 190

  static let zones = [
    HeartRateZone(id: 1, title: "Zone 1", range: "<60%", color: .blue),
    HeartRateZone(id: 2, title: "Zone 2", range: "60-70%", color: .green),
    HeartRateZone(id: 3, title: "Zone 3", range: "70-80%", color: .yellow),
    HeartRateZone(id: 4, title: "Zone 4", range: "80-90%", color: .orange),
    HeartRateZone(id: 5, title: "Zone 5", range: "90%+", color: .red),
  ]

  static func zoneID(for bpm: Int) -> Int {
    let percentage = Double(bpm) / Double(maxHeartRate)
    if percentage < 0.60 {
      return 1
    }
    if percentage < 0.70 {
      return 2
    }
    if percentage < 0.80 {
      return 3
    }
    if percentage < 0.90 {
      return 4
    }
    return 5
  }

  static func zone(for id: Int) -> HeartRateZone {
    zones.first { $0.id == id } ?? zones[0]
  }
}

enum PaceZone: String {
  case easy
  case steady
  case tempo
  case fast
  case unknown

  var title: String {
    switch self {
    case .easy: "Easy"
    case .steady: "Steady"
    case .tempo: "Tempo"
    case .fast: "Fast"
    case .unknown: "GPS"
    }
  }

  var color: Color {
    switch self {
    case .easy: .blue
    case .steady: .green
    case .tempo: .orange
    case .fast: .red
    case .unknown: .gray
    }
  }

  static func zone(secondsPerKilometer: TimeInterval, activity: ActivityKind) -> PaceZone {
    if activity == .roadRide || activity == .mountainBike {
      switch secondsPerKilometer {
      case ..<120: .fast
      case ..<180: .tempo
      case ..<240: .steady
      default: .easy
      }
    } else if activity == .walk || activity == .hike {
      switch secondsPerKilometer {
      case ..<540: .fast
      case ..<720: .tempo
      case ..<900: .steady
      default: .easy
      }
    } else {
      switch secondsPerKilometer {
      case ..<270: .fast
      case ..<330: .tempo
      case ..<420: .steady
      default: .easy
      }
    }
  }
}

struct ActivityRouteSegment: Identifiable {
  let id: Int
  let start: CLLocationCoordinate2D
  let end: CLLocationCoordinate2D
  let zone: PaceZone

  var coordinates: [CLLocationCoordinate2D] {
    [start, end]
  }
}

final class ActivitySessionModel: ObservableObject {
  @Published private(set) var selectedActivity: ActivityKind = .run
  @Published private(set) var isActive = false
  @Published private(set) var isPaused = false
  @Published private(set) var startedAt: Date?
  @Published private(set) var endedAt: Date?
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var averageHeartRate: Int?
  @Published private(set) var maxHeartRate: Int?
  @Published private(set) var zoneDurations: [Int: TimeInterval] = [:]

  private var lastTick: Date?
  private var heartRateWeightedTotal: Double = 0
  private var heartRateMeasuredSeconds: TimeInterval = 0
  private var timer: Timer?
  private var heartRateProvider: (() -> Int?)?

  deinit {
    timer?.invalidate()
  }

  var statusText: String {
    if isActive && isPaused {
      return "Paused"
    }
    if isActive {
      return "Recording"
    }
    if endedAt != nil {
      return "Ended"
    }
    return "Ready"
  }

  func select(_ activity: ActivityKind) {
    guard !isActive else {
      return
    }
    selectedActivity = activity
    resetMetrics(keepingSelection: true)
  }

  func start(now: Date = Date(), heartRateProvider: @escaping () -> Int?) {
    resetMetrics(keepingSelection: true)
    self.heartRateProvider = heartRateProvider
    isActive = true
    isPaused = false
    startedAt = now
    endedAt = nil
    lastTick = now
    scheduleTimer()
  }

  func resume(now: Date = Date(), heartRateProvider: @escaping () -> Int?) {
    guard isActive, isPaused else {
      return
    }
    self.heartRateProvider = heartRateProvider
    isPaused = false
    lastTick = now
    scheduleTimer()
  }

  func pause(now: Date = Date(), heartRate: Int?) {
    guard isActive, !isPaused else {
      return
    }
    tick(now: now, heartRate: heartRate)
    isPaused = true
    lastTick = nil
    timer?.invalidate()
    timer = nil
  }

  func end(now: Date = Date(), heartRate: Int?) {
    guard isActive else {
      return
    }
    tick(now: now, heartRate: heartRate)
    isActive = false
    isPaused = false
    endedAt = now
    lastTick = nil
    timer?.invalidate()
    timer = nil
    heartRateProvider = nil
  }

  func tick(now: Date, heartRate: Int?) {
    guard isActive, !isPaused else {
      return
    }
    let previousTick = lastTick ?? now
    let delta = max(0, now.timeIntervalSince(previousTick))
    elapsed += delta
    lastTick = now

    guard delta > 0, let heartRate else {
      return
    }
    let zoneID = HeartRateZone.zoneID(for: heartRate)
    zoneDurations[zoneID, default: 0] += delta
    heartRateWeightedTotal += Double(heartRate) * delta
    heartRateMeasuredSeconds += delta
    averageHeartRate = Int((heartRateWeightedTotal / max(heartRateMeasuredSeconds, 1)).rounded())
    maxHeartRate = max(maxHeartRate ?? heartRate, heartRate)
  }

  private func scheduleTimer() {
    timer?.invalidate()
    let newTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      guard let self else {
        return
      }
      self.tick(now: Date(), heartRate: self.heartRateProvider?())
    }
    newTimer.tolerance = 0.002
    RunLoop.main.add(newTimer, forMode: .common)
    timer = newTimer
  }

  private func resetMetrics(keepingSelection: Bool) {
    timer?.invalidate()
    timer = nil
    if !keepingSelection {
      selectedActivity = .run
    }
    elapsed = 0
    averageHeartRate = nil
    maxHeartRate = nil
    zoneDurations = [:]
    heartRateWeightedTotal = 0
    heartRateMeasuredSeconds = 0
    lastTick = nil
    startedAt = nil
    endedAt = nil
    isActive = false
    isPaused = false
    heartRateProvider = nil
  }
}

final class ActivityLocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
  @Published private(set) var locations: [CLLocation] = []
  @Published private(set) var distanceMeters: CLLocationDistance = 0
  @Published private(set) var currentPaceSecondsPerKilometer: TimeInterval?
  @Published private(set) var elevationMeters: CLLocationDistance = 0
  @Published private(set) var elevationGainMeters: CLLocationDistance = 0
  @Published private(set) var gpsStatus = "GPS idle"

  private let manager = CLLocationManager()
  private var lastAcceptedLocation: CLLocation?
  private var recentLocations: [CLLocation] = []
  private var wantsUpdates = false

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 5
    manager.activityType = .fitness
    authorizationStatus = manager.authorizationStatus
  }

  func start(reset: Bool) {
    wantsUpdates = true
    if reset {
      resetRoute()
    }
    gpsStatus = "Starting GPS"

    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.startUpdatingLocation()
      gpsStatus = "Looking for GPS"
    case .denied, .restricted:
      gpsStatus = "Location permission needed"
    @unknown default:
      gpsStatus = "Location unavailable"
    }
    authorizationStatus = manager.authorizationStatus
  }

  func stop() {
    wantsUpdates = false
    manager.stopUpdatingLocation()
    gpsStatus = locations.isEmpty ? "GPS idle" : "GPS paused"
  }

  func resetRoute() {
    locations = []
    recentLocations = []
    lastAcceptedLocation = nil
    distanceMeters = 0
    currentPaceSecondsPerKilometer = nil
    elevationMeters = 0
    elevationGainMeters = 0
  }

  func routeSegments(for activity: ActivityKind) -> [ActivityRouteSegment] {
    guard locations.count > 1 else {
      return []
    }

    var segments: [ActivityRouteSegment] = []
    for index in 1..<locations.count {
      let start = locations[index - 1]
      let end = locations[index]
      let distance = end.distance(from: start)
      let seconds = max(end.timestamp.timeIntervalSince(start.timestamp), 0)
      let secondsPerKilometer = distance > 1 && seconds > 0 ? seconds / (distance / 1000) : nil
      let zone = secondsPerKilometer.map { PaceZone.zone(secondsPerKilometer: $0, activity: activity) } ?? .unknown
      segments.append(ActivityRouteSegment(id: index, start: start.coordinate, end: end.coordinate, zone: zone))
    }
    return segments
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationStatus = manager.authorizationStatus
    guard wantsUpdates else {
      return
    }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.startUpdatingLocation()
      gpsStatus = "Looking for GPS"
    case .denied, .restricted:
      manager.stopUpdatingLocation()
      gpsStatus = "Location permission needed"
    case .notDetermined:
      gpsStatus = "Waiting for permission"
    @unknown default:
      gpsStatus = "Location unavailable"
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations newLocations: [CLLocation]) {
    for location in newLocations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 80 {
      append(location)
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    gpsStatus = "GPS error: \(error.localizedDescription)"
  }

  private func append(_ location: CLLocation) {
    if let lastAcceptedLocation {
      let segmentDistance = location.distance(from: lastAcceptedLocation)
      if segmentDistance >= 1 {
        distanceMeters += segmentDistance
      }
      if lastAcceptedLocation.verticalAccuracy >= 0,
         location.verticalAccuracy >= 0,
         lastAcceptedLocation.verticalAccuracy <= 50,
         location.verticalAccuracy <= 50 {
        elevationGainMeters += max(0, location.altitude - lastAcceptedLocation.altitude)
      }
    }

    lastAcceptedLocation = location
    locations.append(location)
    recentLocations.append(location)
    if recentLocations.count > 8 {
      recentLocations.removeFirst(recentLocations.count - 8)
    }
    currentPaceSecondsPerKilometer = recentPace()
    if location.verticalAccuracy >= 0 && location.verticalAccuracy <= 80 {
      elevationMeters = location.altitude
    }
    gpsStatus = "GPS locked +/- \(Int(location.horizontalAccuracy))m"
  }

  private func recentPace() -> TimeInterval? {
    guard let first = recentLocations.first, let last = recentLocations.last, recentLocations.count > 1 else {
      return nil
    }
    let seconds = last.timestamp.timeIntervalSince(first.timestamp)
    guard seconds > 0 else {
      return nil
    }
    var distance: CLLocationDistance = 0
    for index in 1..<recentLocations.count {
      distance += recentLocations[index].distance(from: recentLocations[index - 1])
    }
    guard distance > 5 else {
      return nil
    }
    return seconds / (distance / 1000)
  }
}

struct LiveActivityView: View {
  @EnvironmentObject private var model: GooseAppModel

  var body: some View {
    LiveActivityContentView(
      ble: model.ble,
      session: model.activitySession,
      locationTracker: model.activityLocationTracker
    )
    .environmentObject(model)
  }
}

private enum FitnessWorkoutPage: Int, CaseIterable, Identifiable {
  case overview
  case heartRate
  case segment
  case split
  case elevation

  var id: Int { rawValue }
}

private struct LiveActivityContentView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var model: GooseAppModel
  @AppStorage("goose.swift.activity.lockHintSeen") private var lockHintSeen = false
  @ObservedObject var ble: GooseBLEClient
  @ObservedObject var session: ActivitySessionModel
  @ObservedObject var locationTracker: ActivityLocationTracker

  @State private var selectedPage: FitnessWorkoutPage = .overview
  @State private var dockExpanded = false
  @State private var controlsLocked = false
  @State private var showingActivityPicker = false
  @State private var showingLockHint = false
  @State private var countdownValue: Int?
  @State private var countdownTimer: Timer?
  @State private var segmentReturnTask: Task<Void, Never>?
  @State private var segmentNumber = 1

  var body: some View {
    ZStack {
      FitnessColor.background
        .ignoresSafeArea()

      if let countdownValue {
        FitnessCountdownView(value: countdownValue, activity: session.selectedActivity)
      } else if showingSummary {
        FitnessSummaryView(activity: session.selectedActivity, session: session, ble: ble, locationTracker: locationTracker) {
          dismiss()
        }
      } else if !session.isActive {
        FitnessActivityPickerStartView(selectedActivity: session.selectedActivity) { activity in
          startFromPicker(activity)
        }
      } else {
        FitnessLiveWorkoutView(
          selectedPage: $selectedPage,
          activity: session.selectedActivity,
          session: session,
          ble: ble,
          locationTracker: locationTracker,
          segmentNumber: segmentNumber,
          dockExpanded: $dockExpanded,
          controlsLocked: $controlsLocked,
          onPrimaryAction: primaryAction,
          onEndWorkout: endActivity,
          onStopViewing: { dismiss() },
          onLockControls: lockControls,
          onUnlockControls: unlockControls,
          onActivityTap: {
            if !session.isActive {
              showingActivityPicker = true
              model.recordUIAction("activity.picker.opened", detail: session.selectedActivity.title)
            }
          },
          onSegmentTap: markSegment,
          onHeartPageTap: {
            selectedPage = .heartRate
            model.recordUIAction("activity.page.shortcut", detail: "Heart Rate")
          }
        )
      }
    }
    .preferredColorScheme(.dark)
    .toolbar(showingSummary ? .visible : .hidden, for: .navigationBar)
    .toolbar(.hidden, for: .tabBar)
    .sheet(isPresented: $showingActivityPicker) {
      FitnessActivityPickerSheet(selectedActivity: session.selectedActivity, onSelect: select)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
    .alert("Controls Locked", isPresented: $showingLockHint) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Hold the pause/resume button for 5 seconds to unlock it.")
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Live Activity")
    }
    .onDisappear {
      countdownTimer?.invalidate()
      countdownTimer = nil
      segmentReturnTask?.cancel()
      segmentReturnTask = nil
    }
    .onChange(of: locationTracker.authorizationStatus) { _, status in
      model.recordUIAction("activity.location.authorization", detail: authorizationText(status))
    }
  }

  private var showingSummary: Bool {
    session.endedAt != nil && !session.isActive
  }

  private func select(_ activity: ActivityKind) {
    session.select(activity)
    selectedPage = .overview
    model.recordUIAction("activity.selected", detail: activity.title)
  }

  private func startFromPicker(_ activity: ActivityKind) {
    select(activity)
    beginCountdown()
  }

  private func primaryAction() {
    guard countdownValue == nil else {
      return
    }

    if session.isActive && session.isPaused {
      session.resume {
        ble.liveHeartRateBPM
      }
      if session.selectedActivity.usesGPS {
        locationTracker.start(reset: false)
      }
      model.recordUIAction("activity.resume", detail: session.selectedActivity.title)
      return
    }

    if session.isActive {
      session.pause(heartRate: ble.liveHeartRateBPM)
      if session.selectedActivity.usesGPS {
        locationTracker.stop()
      }
      model.recordUIAction("activity.pause", detail: session.selectedActivity.title)
      return
    }

    beginCountdown()
  }

  private func beginCountdown() {
    countdownTimer?.invalidate()
    countdownValue = 3
    dockExpanded = false
    controlsLocked = false
    selectedPage = .overview
    model.recordUIAction("activity.countdown.start", detail: session.selectedActivity.title)

    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
      guard let countdownValue else {
        timer.invalidate()
        return
      }

      if countdownValue > 1 {
        self.countdownValue = countdownValue - 1
      } else {
        timer.invalidate()
        self.countdownTimer = nil
        self.countdownValue = nil
        self.startWorkoutNow()
      }
    }
    countdownTimer?.tolerance = 0.05
  }

  private func startWorkoutNow() {
    segmentNumber = 1
    session.start {
      ble.liveHeartRateBPM
    }
    if session.selectedActivity.usesGPS {
      locationTracker.start(reset: true)
    } else {
      locationTracker.stop()
      locationTracker.resetRoute()
    }
    model.recordUIAction("activity.start", detail: session.selectedActivity.title)
  }

  private func endActivity() {
    countdownTimer?.invalidate()
    countdownTimer = nil
    segmentReturnTask?.cancel()
    segmentReturnTask = nil
    countdownValue = nil
    controlsLocked = false
    session.end(heartRate: ble.liveHeartRateBPM)
    locationTracker.stop()
    dockExpanded = false
    model.recordUIAction("activity.end", detail: "\(session.selectedActivity.title) \(formatDuration(session.elapsed))")
  }

  private func markSegment() {
    guard session.isActive else {
      return
    }
    let returnPage = selectedPage == .segment ? .overview : selectedPage
    segmentNumber += 1
    selectedPage = .segment
    withAnimation(.interactiveSpring(response: 0.44, dampingFraction: 0.9, blendDuration: 0.12)) {
      dockExpanded = false
    }
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    model.recordUIAction("activity.segment.marked", detail: "\(segmentNumber)")
    scheduleSegmentReturn(to: returnPage)
  }

  private func scheduleSegmentReturn(to page: FitnessWorkoutPage) {
    segmentReturnTask?.cancel()
    segmentReturnTask = Task {
      try? await Task.sleep(nanoseconds: 10_000_000_000)
      guard !Task.isCancelled else {
        return
      }
      await MainActor.run {
        guard selectedPage == .segment, session.isActive else {
          return
        }
        withAnimation(.easeInOut(duration: 0.28)) {
          selectedPage = page
        }
      }
    }
  }

  private func lockControls() {
    controlsLocked = true
    withAnimation(.interactiveSpring(response: 0.44, dampingFraction: 0.9, blendDuration: 0.12)) {
      dockExpanded = false
    }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    if !lockHintSeen {
      lockHintSeen = true
      showingLockHint = true
    }
    model.recordUIAction("activity.controls.locked", detail: session.selectedActivity.title)
  }

  private func unlockControls() {
    controlsLocked = false
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    model.recordUIAction("activity.controls.unlocked", detail: session.selectedActivity.title)
  }
}

private struct FitnessLiveWorkoutView: View {
  @Binding var selectedPage: FitnessWorkoutPage
  let activity: ActivityKind
  @ObservedObject var session: ActivitySessionModel
  @ObservedObject var ble: GooseBLEClient
  @ObservedObject var locationTracker: ActivityLocationTracker
  let segmentNumber: Int
  @Binding var dockExpanded: Bool
  @Binding var controlsLocked: Bool
  let onPrimaryAction: () -> Void
  let onEndWorkout: () -> Void
  let onStopViewing: () -> Void
  let onLockControls: () -> Void
  let onUnlockControls: () -> Void
  let onActivityTap: () -> Void
  let onSegmentTap: () -> Void
  let onHeartPageTap: () -> Void
  @GestureState private var dockDragTranslation: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let compactDockHeight = min(max(proxy.size.height * 0.30, 268), 306)
      let dockIsRaised = dockExpanded
      let expandedBottomOverflow = proxy.safeAreaInsets.bottom + 42
      let expandedDockHeight = proxy.size.height - 56 + expandedBottomOverflow
      let dockHeight = dockIsRaised ? expandedDockHeight : compactDockHeight
      let compactDockWidth = max(proxy.size.width - 24, 0)
      let dockWidth = dockIsRaised ? proxy.size.width : compactDockWidth
      let dockBaseOffsetY = dockIsRaised ? expandedBottomOverflow : -10
      let dockDragOffsetY = controlsLocked ? 0 : constrainedDockDragOffset(isExpanded: dockIsRaised)

      ZStack(alignment: .bottom) {
        FitnessPageCarousel(
          selectedPage: $selectedPage,
          activity: activity,
          session: session,
          ble: ble,
          locationTracker: locationTracker,
          segmentNumber: segmentNumber
        )
        .padding(.bottom, compactDockHeight + 26)
        .allowsHitTesting(!controlsLocked)

        if dockIsRaised {
          Color.black.opacity(0.56)
            .ignoresSafeArea()
            .onTapGesture {
              collapseDock()
            }
        } else {
          FitnessPageDots(selectedPage: selectedPage)
            .padding(.bottom, compactDockHeight + 12)
        }

        FitnessControlDock(
          activity: activity,
          elapsed: session.elapsed,
          isActive: session.isActive,
          isPaused: session.isPaused,
          segmentNumber: segmentNumber,
          expanded: $dockExpanded,
          controlsLocked: controlsLocked,
          onPrimaryAction: onPrimaryAction,
          onEndWorkout: onEndWorkout,
          onStopViewing: onStopViewing,
          onLockControls: onLockControls,
          onUnlockControls: onUnlockControls,
          onActivityTap: onActivityTap,
          onSegmentTap: onSegmentTap,
          onHeartPageTap: onHeartPageTap
        )
        .frame(width: dockWidth, height: dockHeight)
        .offset(y: dockBaseOffsetY + dockDragOffsetY)
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(dockAnimation, value: dockExpanded)
        .simultaneousGesture(
          DragGesture(minimumDistance: 12)
            .updating($dockDragTranslation) { value, state, _ in
              guard !controlsLocked else {
                return
              }
              state = value.translation.height
            }
            .onEnded { value in
              guard !controlsLocked else {
                return
              }

              let vertical = value.predictedEndTranslation.height
              if !dockExpanded && (vertical < -34 || value.translation.height < -64) {
                expandDock()
              } else if dockExpanded && (vertical > 34 || value.translation.height > 64) {
                collapseDock()
              }
            }
        )
      }
    }
  }

  private var dockAnimation: Animation {
    .interactiveSpring(response: 0.44, dampingFraction: 0.9, blendDuration: 0.12)
  }

  private func constrainedDockDragOffset(isExpanded: Bool) -> CGFloat {
    if isExpanded {
      return max(0, min(dockDragTranslation, 120))
    }
    return min(0, max(dockDragTranslation, -96))
  }

  private func expandDock() {
    withAnimation(dockAnimation) {
      dockExpanded = true
    }
  }

  private func collapseDock() {
    withAnimation(dockAnimation) {
      dockExpanded = false
    }
  }
}

private struct FitnessPageCarousel: View {
  @Binding var selectedPage: FitnessWorkoutPage
  let activity: ActivityKind
  @ObservedObject var session: ActivitySessionModel
  @ObservedObject var ble: GooseBLEClient
  @ObservedObject var locationTracker: ActivityLocationTracker
  let segmentNumber: Int

  var body: some View {
    TabView(selection: $selectedPage) {
      ForEach(FitnessWorkoutPage.allCases) { page in
        pageContent(page)
          .tag(page)
      }
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
  }

  @ViewBuilder
  private func pageContent(_ page: FitnessWorkoutPage) -> some View {
    switch page {
    case .overview:
      FitnessOverviewPage(
        currentHeartRate: ble.liveHeartRateBPM,
        distanceMeters: locationTracker.distanceMeters,
        currentPace: locationTracker.currentPaceSecondsPerKilometer,
        averagePace: averagePace
      )
    case .heartRate:
      FitnessHeartRatePage(
        currentHeartRate: ble.liveHeartRateBPM,
        averageHeartRate: session.averageHeartRate,
        zoneDurations: session.zoneDurations,
        elapsed: session.elapsed
      )
    case .segment:
      FitnessSegmentPage(
        title: "SEGMENT",
        number: segmentNumber,
        elapsed: session.elapsed,
        distanceMeters: locationTracker.distanceMeters,
        currentHeartRate: ble.liveHeartRateBPM,
        currentPace: locationTracker.currentPaceSecondsPerKilometer
      )
    case .split:
      FitnessSplitPage(
        number: segmentNumber,
        elapsed: session.elapsed,
        distanceMeters: locationTracker.distanceMeters,
        currentHeartRate: ble.liveHeartRateBPM,
        currentPace: locationTracker.currentPaceSecondsPerKilometer
      )
    case .elevation:
      FitnessElevationPage(
        elevationMeters: locationTracker.elevationMeters,
        elevationGainMeters: locationTracker.elevationGainMeters,
        currentPace: locationTracker.currentPaceSecondsPerKilometer
      )
    }
  }

  private var averagePace: TimeInterval? {
    guard locationTracker.distanceMeters > 5, session.elapsed > 0 else {
      return nil
    }
    return session.elapsed / (locationTracker.distanceMeters / 1000)
  }
}

private struct FitnessOverviewPage: View {
  let currentHeartRate: Int?
  let distanceMeters: CLLocationDistance
  let currentPace: TimeInterval?
  let averagePace: TimeInterval?

  var body: some View {
    FitnessMetricPageLayout {
      VStack(alignment: .leading, spacing: 0) {
        FitnessHeartRateValue(currentHeartRate, size: 76)
          .padding(.top, 62)

        Spacer()

        FitnessPaceBlock(value: formatFitnessPace(currentPace), label: "ROLLING\nKM", color: .white)
          .padding(.bottom, 76)

        FitnessPaceBlock(value: formatFitnessPace(averagePace), label: "AVERAGE\nPACE", color: .white)
          .padding(.bottom, 88)

        let distance = fitnessDistanceParts(distanceMeters)
        FitnessNumberUnit(value: distance.value, unit: distance.unit, color: .white, size: 72, unitSize: 40)
          .padding(.bottom, 18)
      }
    }
  }
}

private struct FitnessHeartRatePage: View {
  let currentHeartRate: Int?
  let averageHeartRate: Int?
  let zoneDurations: [Int: TimeInterval]
  let elapsed: TimeInterval

  var body: some View {
    FitnessMetricPageLayout {
      VStack(spacing: 0) {
        FitnessHeartRateValue(currentHeartRate, size: 82, centered: true)
          .padding(.top, 76)

        Spacer()

        FitnessZoneRibbon(currentHeartRate: currentHeartRate)
          .padding(.bottom, 64)

        HStack(alignment: .top, spacing: 34) {
          VStack(alignment: .leading, spacing: 4) {
            Text(formatDuration(zoneDurations[HeartRateZone.zoneID(for: currentHeartRate ?? 0), default: 0]))
              .font(.system(size: 52, weight: .regular, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            FitnessMetricLabel("TIME IN ZONE")
          }

          VStack(alignment: .leading, spacing: 4) {
            FitnessNumberUnit(
              value: averageHeartRate.map(String.init) ?? "--",
              unit: "BPM",
              color: .white,
              size: 52,
              unitSize: 28
            )
            FitnessMetricLabel("AVERAGE HR")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 24)
      }
    }
  }
}

private struct FitnessSegmentPage: View {
  let title: String
  let number: Int
  let elapsed: TimeInterval
  let distanceMeters: CLLocationDistance
  let currentHeartRate: Int?
  let currentPace: TimeInterval?

  var body: some View {
    FitnessMetricPageLayout {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center, spacing: 18) {
          Text(formatDuration(elapsed))
            .font(.system(size: 72, weight: .regular, design: .rounded))
            .foregroundStyle(FitnessColor.segmentPink)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
          FitnessSegmentBadge(number: number, size: 72)
        }
        .padding(.top, 74)

        Spacer()

        FitnessPaceBlock(value: formatFitnessPace(currentPace), label: "\(title)\nPACE", color: .white)
          .padding(.bottom, 86)

        HStack(alignment: .lastTextBaseline, spacing: 12) {
          let distance = fitnessDistanceParts(distanceMeters)
          FitnessNumberUnit(value: distance.value, unit: distance.unit, color: .white, size: 72, unitSize: 40)
          FitnessMetricLabel(title)
            .padding(.bottom, 10)
        }
        .padding(.bottom, 70)

        FitnessHeartRateValue(currentHeartRate, size: 70)
          .padding(.bottom, 18)
      }
    }
  }
}

private struct FitnessSplitPage: View {
  let number: Int
  let elapsed: TimeInterval
  let distanceMeters: CLLocationDistance
  let currentHeartRate: Int?
  let currentPace: TimeInterval?

  var body: some View {
    FitnessMetricPageLayout {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
          Text(formatDuration(elapsed))
            .font(.system(size: 72, weight: .regular, design: .rounded))
            .foregroundStyle(FitnessColor.segmentPink)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
          VStack(alignment: .leading, spacing: 0) {
            FitnessMetricLabel("SPLIT")
            Text("\(number)")
              .font(.system(size: 22, weight: .bold, design: .rounded))
              .foregroundStyle(FitnessColor.secondaryText)
          }
        }
        .padding(.top, 74)

        Spacer()

        FitnessPaceBlock(value: formatFitnessPace(currentPace), label: "SPLIT\nPACE", color: .white)
          .padding(.bottom, 86)

        HStack(alignment: .lastTextBaseline, spacing: 12) {
          let distance = fitnessDistanceParts(distanceMeters)
          FitnessNumberUnit(value: distance.value, unit: distance.unit, color: .white, size: 72, unitSize: 40)
          FitnessMetricLabel("SPLIT")
            .padding(.bottom, 10)
        }
        .padding(.bottom, 70)

        FitnessHeartRateValue(currentHeartRate, size: 70)
          .padding(.bottom, 18)
      }
    }
  }
}

private struct FitnessElevationPage: View {
  let elevationMeters: CLLocationDistance
  let elevationGainMeters: CLLocationDistance
  let currentPace: TimeInterval?

  var body: some View {
    FitnessMetricPageLayout {
      VStack(spacing: 0) {
        FitnessNumberUnit(
          value: "\(Int(max(elevationGainMeters, 0).rounded()))",
          unit: "M",
          color: FitnessColor.exerciseGreen,
          size: 64,
          unitSize: 34
        )
        .padding(.top, 58)
        FitnessMetricLabel("ELEVATION GAINED")
          .foregroundStyle(FitnessColor.exerciseGreen)
          .padding(.top, 6)

        FitnessElevationChart()
          .frame(height: 232)
          .padding(.top, 26)

        Spacer()

        HStack(alignment: .bottom, spacing: 36) {
          VStack(alignment: .leading, spacing: 4) {
            FitnessNumberUnit(
              value: "\(Int(max(elevationMeters, 0).rounded()))",
              unit: "M",
              color: .white,
              size: 52,
              unitSize: 30
            )
            FitnessMetricLabel("ELEVATION")
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          VStack(alignment: .leading, spacing: 4) {
            Text(formatFitnessPace(currentPace))
              .font(.system(size: 38, weight: .regular, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.72)
            FitnessMetricLabel("CURRENT PACE")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 8)
      }
    }
  }
}

private struct FitnessRingsPage: View {
  let elapsed: TimeInterval

  var body: some View {
    FitnessMetricPageLayout {
      VStack(alignment: .leading, spacing: 0) {
        ActivityRingsView(
          moveProgress: 0.49,
          exerciseProgress: min(max(elapsed / 1800, 0.18), 1.0),
          standProgress: 0.75,
          lineWidth: 28
        )
        .frame(width: 292, height: 292)
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
        .padding(.bottom, 48)

        VStack(alignment: .leading, spacing: 40) {
          VStack(alignment: .leading, spacing: 0) {
            Text("\(activeCalories)/940")
              .font(.system(size: 58, weight: .regular, design: .rounded))
              .foregroundStyle(FitnessColor.movePink)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            FitnessMetricLabel("MOVE")
          }

          HStack(alignment: .top, spacing: 42) {
            VStack(alignment: .leading, spacing: 0) {
              Text("\(exerciseMinutes)/30")
                .font(.system(size: 52, weight: .regular, design: .rounded))
                .foregroundStyle(FitnessColor.exerciseGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
              FitnessMetricLabel("EXERCISE")
            }

            VStack(alignment: .leading, spacing: 0) {
              Text("\(standHours)/12")
                .font(.system(size: 52, weight: .regular, design: .rounded))
                .foregroundStyle(FitnessColor.standCyan)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
              FitnessMetricLabel("STAND")
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var exerciseMinutes: Int {
    max(Int(elapsed / 60), 0)
  }

  private var activeCalories: Int {
    max(Int(elapsed / 8), 0)
  }

  private var standHours: Int {
    min(12, max(1, Int(elapsed / 3600) + 9))
  }
}

private struct FitnessMetricPageLayout<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(.horizontal, 22)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct FitnessControlDock: View {
  let activity: ActivityKind
  let elapsed: TimeInterval
  let isActive: Bool
  let isPaused: Bool
  let segmentNumber: Int
  @Binding var expanded: Bool
  let controlsLocked: Bool
  let onPrimaryAction: () -> Void
  let onEndWorkout: () -> Void
  let onStopViewing: () -> Void
  let onLockControls: () -> Void
  let onUnlockControls: () -> Void
  let onActivityTap: () -> Void
  let onSegmentTap: () -> Void
  let onHeartPageTap: () -> Void

  var body: some View {
    ZStack(alignment: .top) {
      UnevenRoundedRectangle(
        topLeadingRadius: 58,
        bottomLeadingRadius: expanded ? 0 : 58,
        bottomTrailingRadius: expanded ? 0 : 58,
        topTrailingRadius: 58,
        style: .continuous
      )
        .fill(FitnessColor.panel)

      Capsule()
        .fill(FitnessColor.grabber)
        .frame(width: 42, height: 6)
        .padding(.top, 10)

      if expanded {
        expandedControls
      } else {
        compactControls
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(dockAnimation, value: expanded)
  }

  private var compactControls: some View {
    VStack(spacing: 24) {
      HStack(alignment: .center, spacing: 16) {
        Button(action: onActivityTap) {
          FitnessWorkoutIcon(activity: activity, size: 48, backgroundOpacity: 0.32)
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .disabled(controlsLocked)

        FitnessDockTimerText(elapsed: elapsed, size: 52, color: FitnessColor.workoutYellow, width: 218)
          .frame(maxWidth: .infinity)
          .onTapGesture {
            if !controlsLocked {
              expandDock()
            }
          }

        Color.clear
          .frame(width: 48, height: 48)
      }
      .padding(.horizontal, 24)
      .padding(.top, 38)

      HStack(alignment: .center) {
        Button(action: onSegmentTap) {
          FitnessSegmentBadge(number: segmentNumber, size: 72)
            .frame(width: 86, height: 86)
            .background(FitnessColor.controlButton, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isActive || controlsLocked)

        Spacer()

        Button {
          if !controlsLocked {
            onPrimaryAction()
          }
        } label: {
          ZStack(alignment: .topTrailing) {
            Image(systemName: primaryIcon)
              .font(.system(size: 54, weight: .medium))
              .foregroundStyle(.white)
              .frame(width: 122, height: 122)
              .background(FitnessColor.controlButton, in: Circle())
            if controlsLocked {
              Image(systemName: "lock.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(FitnessColor.lime, in: Circle())
                .offset(x: -2, y: 0)
            }
          }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
          LongPressGesture(minimumDuration: 5, maximumDistance: 42)
            .onEnded { _ in
              if controlsLocked {
                onUnlockControls()
              }
            }
        )

        Spacer()

        Button(action: onHeartPageTap) {
          ZStack(alignment: .bottomTrailing) {
            Image(systemName: "waveform.path.ecg")
              .font(.system(size: 36, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 86, height: 86)
              .background(FitnessColor.controlButton, in: Circle())
              .overlay(alignment: .topTrailing) {
                Image(systemName: "heart.fill")
                  .font(.system(size: 18, weight: .bold))
                  .foregroundStyle(.white)
                  .offset(x: -17, y: 19)
              }
            Text("2")
              .font(.system(size: 18, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
              .frame(width: 38, height: 38)
              .background(FitnessColor.badge, in: Circle())
              .offset(x: 8, y: 7)
          }
        }
        .buttonStyle(.plain)
        .disabled(controlsLocked)
      }
      .padding(.horizontal, 22)
    }
  }

  private var expandedControls: some View {
    VStack(spacing: 20) {
      HStack(alignment: .center, spacing: 16) {
        FitnessWorkoutIcon(activity: activity, size: 50, backgroundOpacity: 0.22)
        FitnessDockTimerText(elapsed: elapsed, size: 50, color: FitnessColor.workoutYellow.opacity(0.45), width: 212)
        Spacer()
      }
      .padding(.top, 38)
      .padding(.horizontal, 24)

      HStack(spacing: 34) {
        Button(action: onSegmentTap) {
          FitnessSegmentBadge(number: segmentNumber, size: 68)
            .frame(width: 82, height: 82)
            .background(FitnessColor.controlButton.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)

        Button {
          collapseDock()
          onPrimaryAction()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 50, weight: .medium))
            .foregroundStyle(FitnessColor.workoutYellow)
            .frame(width: 116, height: 116)
            .background(FitnessColor.workoutYellow.opacity(0.15), in: Circle())
        }

        ZStack(alignment: .bottomTrailing) {
          Image(systemName: "waveform.path.ecg")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 82, height: 82)
            .background(FitnessColor.controlButton.opacity(0.5), in: Circle())
          Text("2")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(FitnessColor.badge, in: Circle())
            .offset(x: 8, y: 7)
        }
      }

      VStack(spacing: 16) {
        FitnessExpandedControlButton(
          title: "End Workout",
          systemImage: "xmark",
          foreground: FitnessColor.endRed,
          background: FitnessColor.endRed.opacity(0.22),
          action: onEndWorkout
        )

        FitnessExpandedControlButton(
          title: "Stop Viewing",
          systemImage: "iphone.and.play",
          foreground: .white,
          background: FitnessColor.controlButton,
          action: onStopViewing
        )

        FitnessExpandedControlButton(
          title: "Lock Controls",
          systemImage: "lock.fill",
          foreground: .white,
          background: FitnessColor.controlButton,
          action: onLockControls
        )
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 26)
    }
  }

  private var primaryIcon: String {
    if isActive && isPaused {
      return "play.fill"
    }
    if isActive {
      return "pause.fill"
    }
    return "play.fill"
  }

  private var dockAnimation: Animation {
    .interactiveSpring(response: 0.44, dampingFraction: 0.9, blendDuration: 0.12)
  }

  private func expandDock() {
    withAnimation(dockAnimation) {
      expanded = true
    }
  }

  private func collapseDock() {
    withAnimation(dockAnimation) {
      expanded = false
    }
  }
}

private struct FitnessDockTimerText: View {
  let elapsed: TimeInterval
  let size: CGFloat
  let color: Color
  let width: CGFloat

  var body: some View {
    Text(formatFitnessDockDuration(elapsed))
      .font(.system(size: size, weight: .semibold, design: .rounded))
      .monospacedDigit()
      .contentTransition(.numericText(value: elapsed))
      .foregroundStyle(color)
      .lineLimit(1)
      .minimumScaleFactor(0.64)
      .frame(width: width, alignment: .center)
      .transaction { transaction in
        transaction.animation = nil
      }
  }
}

private struct FitnessExpandedControlButton: View {
  let title: String
  let systemImage: String
  let foreground: Color
  let background: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 28, weight: .semibold, design: .rounded))
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(background, in: Capsule())
    }
    .buttonStyle(.plain)
  }
}

private struct FitnessPageDots: View {
  let selectedPage: FitnessWorkoutPage

  var body: some View {
    HStack(spacing: 14) {
      ForEach(FitnessWorkoutPage.allCases) { page in
        Circle()
          .fill(page == selectedPage ? Color.white : FitnessColor.pageDot)
          .frame(width: 9, height: 9)
      }
    }
  }
}

private struct FitnessCountdownView: View {
  let value: Int
  let activity: ActivityKind
  @State private var ringProgress: CGFloat = 1

  var body: some View {
    GeometryReader { proxy in
      let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.48)

      ZStack {
        FitnessWorkoutIcon(activity: activity, size: 66, backgroundOpacity: 0.36)
          .position(x: center.x, y: center.y - 194)

        ZStack {
          Circle()
            .stroke(FitnessColor.exerciseGreen.opacity(0.28), lineWidth: 18)
          Circle()
            .trim(from: 0, to: ringProgress)
            .stroke(
              LinearGradient(colors: [FitnessColor.exerciseGreen, FitnessColor.lime], startPoint: .top, endPoint: .bottom),
              style: StrokeStyle(lineWidth: 18, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
          Text("\(value)")
            .font(.system(size: 82, weight: .regular, design: .rounded))
            .foregroundStyle(.white)
        }
        .frame(width: 258, height: 258)
        .position(center)

        Text(activity.fitnessTitle)
          .font(.system(size: 34, weight: .regular, design: .rounded))
          .foregroundStyle(.white)
          .position(x: center.x, y: center.y + 188)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        animateRing(from: CGFloat(value) / 3)
      }
      .onChange(of: value) { _, newValue in
        animateRing(from: CGFloat(newValue) / 3)
      }
    }
  }

  private func animateRing(from progress: CGFloat) {
    ringProgress = progress
    withAnimation(.linear(duration: 0.96)) {
      ringProgress = max(progress - (1.0 / 3.0), 0)
    }
  }
}

private struct FitnessActivityPickerStartView: View {
  let selectedActivity: ActivityKind
  let onStart: (ActivityKind) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .center) {
          Text("Workout")
            .font(.system(size: 42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Spacer()
          FitnessWorkoutIcon(activity: selectedActivity, size: 44, backgroundOpacity: 0.24)
        }
        .padding(.top, 28)
        .padding(.bottom, 4)

        VStack(spacing: 10) {
          ForEach(ActivityKind.allCases) { activity in
            FitnessActivityStartRow(
              activity: activity,
              isSelected: selectedActivity == activity
            ) {
              onStart(activity)
            }
          }
        }
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 32)
    }
    .scrollIndicators(.hidden)
  }
}

private struct FitnessActivityStartRow: View {
  let activity: ActivityKind
  let isSelected: Bool
  let onStart: () -> Void

  var body: some View {
    Button(action: onStart) {
      HStack(spacing: 14) {
        FitnessWorkoutIcon(activity: activity, size: 48, backgroundOpacity: isSelected ? 0.34 : 0.22)

        VStack(alignment: .leading, spacing: 3) {
          Text(activity.fitnessTitle)
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
          Text(activity.subtitle)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(FitnessColor.secondaryText)
        }

        Spacer(minLength: 12)

        Text("Start")
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundStyle(.black)
          .padding(.horizontal, 14)
          .frame(height: 32)
          .background(FitnessColor.lime, in: Capsule())
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 13)
      .background(
        FitnessColor.panel,
        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
      )
      .overlay {
        if isSelected {
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(FitnessColor.lime.opacity(0.42), lineWidth: 1)
        }
      }
    }
    .buttonStyle(.plain)
  }
}

private struct FitnessActivityPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  let selectedActivity: ActivityKind
  let onSelect: (ActivityKind) -> Void

  var body: some View {
    NavigationStack {
      List {
        ForEach(ActivityKind.allCases) { activity in
          Button {
            onSelect(activity)
            dismiss()
          } label: {
            HStack(spacing: 14) {
              FitnessWorkoutIcon(activity: activity, size: 44, backgroundOpacity: 0.22)
              VStack(alignment: .leading, spacing: 2) {
                Text(activity.fitnessTitle)
                  .foregroundStyle(.white)
                Text(activity.subtitle)
                  .font(.caption)
                  .foregroundStyle(FitnessColor.secondaryText)
              }
              Spacer()
              if selectedActivity == activity {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(FitnessColor.exerciseGreen)
              }
            }
          }
          .listRowBackground(FitnessColor.panel)
        }
      }
      .scrollContentBackground(.hidden)
      .background(FitnessColor.background)
      .navigationTitle("Workout")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

private struct FitnessSummaryView: View {
  let activity: ActivityKind
  @ObservedObject var session: ActivitySessionModel
  @ObservedObject var ble: GooseBLEClient
  @ObservedObject var locationTracker: ActivityLocationTracker
  let onDone: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        HStack(spacing: 24) {
          FitnessWorkoutIcon(activity: activity, size: 88, backgroundOpacity: 0.34)

          VStack(alignment: .leading, spacing: 6) {
            Text(activity.fitnessTitle)
              .font(.system(size: 24, weight: .regular, design: .rounded))
              .foregroundStyle(.white)
            Text(summaryTimeRange)
              .font(.system(size: 22, weight: .regular, design: .rounded))
              .foregroundStyle(FitnessColor.secondaryText)
            Label("Exeter", systemImage: "location.fill")
              .font(.system(size: 22, weight: .regular, design: .rounded))
              .foregroundStyle(FitnessColor.secondaryText)
          }
        }

        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 8) {
            Text("Workout Details")
              .font(.system(size: 30, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
            Image(systemName: "chevron.right")
              .font(.system(size: 24, weight: .bold))
              .foregroundStyle(FitnessColor.secondaryText)
          }

          FitnessWorkoutDetailsCard(
            workoutTime: formatDuration(session.elapsed),
            elapsedTime: formatDuration(session.elapsed + 12),
            activeCalories: "\(activeCalories)KCAL",
            totalCalories: "\(activeCalories + 2)KCAL",
            averagePace: averagePaceText,
            averageHeartRate: "\(session.averageHeartRate ?? ble.liveHeartRateBPM ?? 0)BPM"
          )
        }

        if activity.usesGPS {
          FitnessRouteSummaryCard(activity: activity, locationTracker: locationTracker)
            .padding(.top, 4)
        }
      }
      .padding(.horizontal, 18)
      .padding(.top, 22)
      .padding(.bottom, 48)
    }
    .background(FitnessColor.background)
    .navigationTitle(summaryDate)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(FitnessColor.background, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: onDone) {
          Image(systemName: "checkmark")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(FitnessColor.lime)
        }
      }
    }
  }

  private var activeCalories: Int {
    max(Int(session.elapsed / 8), 0)
  }

  private var averagePaceText: String {
    guard locationTracker.distanceMeters > 5, session.elapsed > 0 else {
      return "--'--\"/KM"
    }
    return "\(formatFitnessPace(session.elapsed / (locationTracker.distanceMeters / 1000)))/KM"
  }

  private var summaryDate: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "E d MMM"
    return formatter.string(from: session.startedAt ?? Date())
  }

  private var summaryTimeRange: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    let start = session.startedAt ?? Date()
    let end = session.endedAt ?? Date()
    return "\(formatter.string(from: start))-\(formatter.string(from: end))"
  }
}

private struct FitnessWorkoutDetailsCard: View {
  let workoutTime: String
  let elapsedTime: String
  let activeCalories: String
  let totalCalories: String
  let averagePace: String
  let averageHeartRate: String

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 24) {
        FitnessSummaryMetric(title: "Workout Time", value: workoutTime, color: FitnessColor.workoutYellow)
        FitnessSummaryMetric(title: "Elapsed Time", value: elapsedTime, color: FitnessColor.workoutYellow)
      }
      .padding(.bottom, 22)

      Divider().background(FitnessColor.separator)

      HStack(spacing: 24) {
        FitnessSummaryMetric(title: "Active Kilocalories", value: activeCalories, color: FitnessColor.movePink)
        FitnessSummaryMetric(title: "Total Kilocalories", value: totalCalories, color: FitnessColor.movePink)
      }
      .padding(.vertical, 22)

      Divider().background(FitnessColor.separator)

      HStack(spacing: 24) {
        FitnessSummaryMetric(title: "Avg Pace", value: averagePace, color: FitnessColor.standCyan)
        FitnessSummaryMetric(title: "Avg Heart Rate", value: averageHeartRate, color: FitnessColor.heartRed)
      }
      .padding(.top, 22)
    }
    .padding(18)
    .background(FitnessColor.panel, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
  }
}

private struct FitnessSummaryMetric: View {
  let title: String
  let value: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 20, weight: .regular, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(value)
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct FitnessRouteSummaryCard: View {
  let activity: ActivityKind
  @ObservedObject var locationTracker: ActivityLocationTracker
  @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Route")
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .foregroundStyle(.white)

      Map(position: $cameraPosition) {
        UserAnnotation()
        ForEach(locationTracker.routeSegments(for: activity)) { segment in
          MapPolyline(coordinates: segment.coordinates)
            .stroke(segment.zone.color, lineWidth: 5)
        }
      }
      .mapStyle(.standard(elevation: .realistic))
      .frame(height: 220)
      .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
  }
}

private struct FitnessPaceBlock: View {
  let value: String
  let label: String
  let color: Color

  var body: some View {
    HStack(alignment: .center, spacing: 30) {
      Text(value)
        .font(.system(size: 48, weight: .regular, design: .rounded))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      FitnessMetricLabel(label)
        .frame(width: 120, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct FitnessZoneRibbon: View {
  let currentHeartRate: Int?

  var body: some View {
    GeometryReader { proxy in
      let spacing: CGFloat = 4
      let selectedWidth = min(max(proxy.size.width * 0.40, 134), 162)
      let inactiveWidth = max((proxy.size.width - selectedWidth - spacing * 4) / 4, 42)
      let inactiveHeight: CGFloat = 70
      let selectedHeight = 92 + nextZoneProgress * 96

      ZStack(alignment: .bottomLeading) {
        HStack(alignment: .bottom, spacing: spacing) {
          ForEach(HeartRateZone.zones) { zone in
            let selected = zone.id == selectedZone
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(zoneColor(zone.id).opacity(selected ? 1 : 0.42))
              .frame(width: selected ? selectedWidth : inactiveWidth, height: selected ? selectedHeight : inactiveHeight)
              .overlay(alignment: .bottomLeading) {
                if selected {
                  HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                      .font(.system(size: 17, weight: .bold))
                    Text("ZONE \(zone.id)")
                      .font(.system(size: 20, weight: .heavy, design: .rounded))
                      .lineLimit(1)
                      .minimumScaleFactor(0.62)
                  }
                  .foregroundStyle(.black)
                  .padding(.horizontal, 12)
                  .padding(.bottom, 18)
                }
              }
          }
        }

        Triangle()
          .fill(.white)
          .frame(width: 22, height: 16)
          .offset(x: CGFloat(selectedZone - 1) * (inactiveWidth + spacing) + 16, y: 14)
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
    }
    .frame(height: 190)
    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedZone)
    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: nextZoneProgress)
  }

  private var selectedZone: Int {
    guard let currentHeartRate else {
      return 1
    }
    return HeartRateZone.zoneID(for: currentHeartRate)
  }

  private var nextZoneProgress: CGFloat {
    guard let currentHeartRate else {
      return 0.2
    }

    let bpm = CGFloat(currentHeartRate)
    let maxHeartRate = CGFloat(HeartRateZone.maxHeartRate)
    let lower: CGFloat
    let upper: CGFloat

    switch selectedZone {
    case 1:
      lower = 0
      upper = maxHeartRate * 0.60
    case 2:
      lower = maxHeartRate * 0.60
      upper = maxHeartRate * 0.70
    case 3:
      lower = maxHeartRate * 0.70
      upper = maxHeartRate * 0.80
    case 4:
      lower = maxHeartRate * 0.80
      upper = maxHeartRate * 0.90
    default:
      lower = maxHeartRate * 0.90
      upper = maxHeartRate
    }

    return min(max((bpm - lower) / max(upper - lower, 1), 0), 1)
  }

  private func zoneColor(_ id: Int) -> Color {
    switch id {
    case 1: FitnessColor.zoneBlue
    case 2: FitnessColor.zoneTeal
    case 3: FitnessColor.zoneGreen
    case 4: FitnessColor.zoneOrange
    default: FitnessColor.zoneRed
    }
  }
}

private struct Triangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

private struct FitnessElevationChart: View {
  var body: some View {
    ZStack {
      VStack {
        Text("10")
          .frame(maxWidth: .infinity, alignment: .trailing)
        Spacer()
        Text("0")
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .font(.system(size: 16, weight: .bold, design: .rounded))
      .foregroundStyle(FitnessColor.secondaryText)

      HStack {
        Text("30 MIN AGO")
        Spacer()
        Text("NOW")
      }
      .font(.system(size: 16, weight: .bold, design: .rounded))
      .foregroundStyle(FitnessColor.secondaryText)
      .frame(maxHeight: .infinity, alignment: .bottom)
    }
  }
}

private struct ActivityRingsView: View {
  let moveProgress: Double
  let exerciseProgress: Double
  let standProgress: Double
  let lineWidth: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height)
      ZStack {
        FitnessRing(progress: moveProgress, color: FitnessColor.movePink, lineWidth: lineWidth, inset: 0)
        FitnessRing(progress: exerciseProgress, color: FitnessColor.exerciseGreen, lineWidth: lineWidth, inset: lineWidth * 1.42)
        FitnessRing(progress: standProgress, color: FitnessColor.standCyan, lineWidth: lineWidth, inset: lineWidth * 2.84)
      }
      .frame(width: size, height: size)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct FitnessRing: View {
  let progress: Double
  let color: Color
  let lineWidth: CGFloat
  let inset: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .inset(by: inset)
        .stroke(color.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
      Circle()
        .inset(by: inset)
        .trim(from: 0, to: min(max(progress, 0), 1))
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
  }
}

private struct FitnessWorkoutIcon: View {
  let activity: ActivityKind
  let size: CGFloat
  let backgroundOpacity: Double

  var body: some View {
    Image(systemName: activity.systemImage)
      .font(.system(size: size * 0.48, weight: .semibold))
      .foregroundStyle(FitnessColor.exerciseGreen)
      .frame(width: size, height: size)
      .background(FitnessColor.exerciseGreen.opacity(backgroundOpacity), in: Circle())
  }
}

private struct FitnessSegmentBadge: View {
  let number: Int
  let size: CGFloat

  var body: some View {
    Text("\(number)")
      .font(.system(size: size * 0.48, weight: .regular, design: .rounded))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .overlay {
        Circle()
          .stroke(.white, lineWidth: max(3, size * 0.06))
      }
  }
}

private struct FitnessHeartRateValue: View {
  let value: Int?
  let size: CGFloat
  let centered: Bool

  init(_ value: Int?, size: CGFloat, centered: Bool = false) {
    self.value = value
    self.size = size
    self.centered = centered
  }

  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: 8) {
      Text(value.map(String.init) ?? "--")
        .font(.system(size: size, weight: .regular, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Image(systemName: "heart.fill")
        .font(.system(size: size * 0.34, weight: .bold))
        .foregroundStyle(FitnessColor.heartRed)
        .baselineOffset(size * 0.06)
    }
    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
  }
}

private struct FitnessNumberUnit: View {
  let value: String
  let unit: String
  let color: Color
  let size: CGFloat
  let unitSize: CGFloat

  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: 4) {
      Text(value)
        .font(.system(size: size, weight: .regular, design: .rounded))
      Text(unit)
        .font(.system(size: unitSize, weight: .semibold, design: .rounded))
        .baselineOffset(size * 0.03)
    }
    .foregroundStyle(color)
    .lineLimit(1)
    .minimumScaleFactor(0.64)
  }
}

private struct FitnessMetricLabel: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.system(size: 18, weight: .heavy, design: .rounded))
      .foregroundStyle(FitnessColor.secondaryText)
      .lineLimit(2)
      .multilineTextAlignment(.leading)
      .minimumScaleFactor(0.75)
  }
}

private enum FitnessColor {
  static let background = Color.black
  static let panel = Color(red: 0.10, green: 0.10, blue: 0.11)
  static let controlButton = Color(red: 0.16, green: 0.16, blue: 0.17)
  static let badge = Color(red: 0.18, green: 0.18, blue: 0.19)
  static let grabber = Color(red: 0.47, green: 0.47, blue: 0.50)
  static let pageDot = Color(red: 0.43, green: 0.43, blue: 0.45)
  static let secondaryText = Color(red: 0.58, green: 0.58, blue: 0.62)
  static let separator = Color.white.opacity(0.08)
  static let workoutYellow = Color(red: 1.0, green: 0.91, blue: 0.24)
  static let exerciseGreen = Color(red: 0.62, green: 1.0, blue: 0.12)
  static let lime = Color(red: 0.70, green: 1.0, blue: 0.18)
  static let movePink = Color(red: 1.0, green: 0.10, blue: 0.34)
  static let standCyan = Color(red: 0.39, green: 0.92, blue: 0.95)
  static let heartRed = Color(red: 1.0, green: 0.23, blue: 0.18)
  static let endRed = Color(red: 1.0, green: 0.25, blue: 0.27)
  static let segmentPink = Color(red: 1.0, green: 0.43, blue: 0.51)
  static let zoneBlue = Color(red: 0.34, green: 0.62, blue: 0.94)
  static let zoneTeal = Color(red: 0.18, green: 0.44, blue: 0.40)
  static let zoneGreen = Color(red: 0.33, green: 0.45, blue: 0.09)
  static let zoneOrange = Color(red: 0.39, green: 0.21, blue: 0.07)
  static let zoneRed = Color(red: 0.42, green: 0.04, blue: 0.18)
}

private extension ActivityKind {
  var fitnessTitle: String {
    switch self {
    case .run: "Outdoor Run"
    case .walk: "Outdoor Walk"
    case .hike: "Hiking"
    case .roadRide: "Outdoor Cycle"
    case .mountainBike: "Mountain Biking"
    case .soccer: "Soccer"
    case .strength: "Traditional Strength Training"
    case .hiit: "High Intensity Interval Training"
    case .yoga: "Yoga"
    case .row: "Rowing"
    case .indoorRide: "Indoor Cycle"
    case .poolSwim: "Pool Swim"
    }
  }
}

private func fitnessDistanceParts(_ meters: CLLocationDistance) -> (value: String, unit: String) {
  if meters >= 1000 {
    return (String(format: "%.2f", meters / 1000), "KM")
  }
  return ("\(Int(max(meters, 0).rounded()))", "M")
}

private func formatFitnessPace(_ secondsPerKilometer: TimeInterval?) -> String {
  guard let secondsPerKilometer, secondsPerKilometer.isFinite else {
    return "--'--\""
  }
  let totalSeconds = max(Int(secondsPerKilometer.rounded()), 0)
  return String(format: "%d'%02d\"", totalSeconds / 60, totalSeconds % 60)
}

private func formatFitnessDockDuration(_ elapsed: TimeInterval) -> String {
  let seconds = max(elapsed, 0)
  let minutes = Int(seconds) / 60
  let wholeSeconds = Int(seconds) % 60
  let hundredths = Int((seconds - floor(seconds)) * 100)
  return String(format: "%02d:%02d.%02d", minutes, wholeSeconds, hundredths)
}

private func formatDuration(_ elapsed: TimeInterval) -> String {
  let seconds = max(Int(elapsed.rounded()), 0)
  let hours = seconds / 3600
  let minutes = (seconds % 3600) / 60
  let remainingSeconds = seconds % 60
  if hours > 0 {
    return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
  }
  return String(format: "%02d:%02d", minutes, remainingSeconds)
}

private func authorizationText(_ status: CLAuthorizationStatus) -> String {
  switch status {
  case .notDetermined: "not determined"
  case .restricted: "restricted"
  case .denied: "denied"
  case .authorizedAlways: "authorized always"
  case .authorizedWhenInUse: "authorized when in use"
  @unknown default: "unknown"
  }
}
