import CoreBluetooth
import HealthKit
import SwiftUI
import UIKit
import UserNotifications

struct OnboardingView: View {
  @EnvironmentObject private var model: GooseAppModel
  let onComplete: () -> Void

  @State private var step = OnboardingStep.profile
  @State private var dateOfBirth = OnboardingDate.defaultDateOfBirth()
  @State private var validationMessage: String?
  @State private var healthKitStatus = "Not requested"
  @State private var healthKitRequesting = false
  @State private var notificationStatus = "Not requested"
  @State private var notificationRequesting = false
  @State private var bluetoothPermissionResolved = OnboardingPermissionState.bluetoothResolved()
  @State private var notificationPermissionResolved = false
  @FocusState private var focusedField: OnboardingInputField?

  @AppStorage(OnboardingStorage.firstName) private var firstName = ""
  @AppStorage(OnboardingStorage.dateOfBirth) private var dateOfBirthString = ""
  @AppStorage(OnboardingStorage.unitSystem) private var unitSystemRaw = OnboardingUnitSystem.imperial.rawValue
  @AppStorage(OnboardingStorage.heightInput) private var heightInput = ""
  @AppStorage(OnboardingStorage.heightFeetInput) private var heightFeetInput = ""
  @AppStorage(OnboardingStorage.heightInchesInput) private var heightInchesInput = ""
  @AppStorage(OnboardingStorage.weightInput) private var weightInput = ""
  @AppStorage(OnboardingStorage.gender) private var genderRaw = ""
  @AppStorage(OnboardingStorage.heightMm) private var heightMm = 0
  @AppStorage(OnboardingStorage.weightGrams) private var weightGrams = 0
  @AppStorage(OnboardingStorage.createdAtUnixMs) private var createdAtUnixMs = 0
  @AppStorage(OnboardingStorage.timezoneID) private var timezoneID = ""
  @AppStorage(OnboardingStorage.healthKitPermissionHandled) private var healthKitPermissionHandled = false
  @AppStorage(OnboardingStorage.notificationPermissionHandled) private var notificationPermissionHandled = false

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          OnboardingHeader(step: step)
          content
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 28)
      }
    }
    .background {
      ZStack {
        Color(.systemGroupedBackground)
          .ignoresSafeArea()
          .onTapGesture {
            focusedField = nil
          }
        OnboardingKeyboardDismissTapCatcher(isEnabled: focusedField != nil) {
          focusedField = nil
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .toolbar(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") {
          focusedField = nil
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if focusedField == nil {
        footer
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .onAppear(perform: hydrateOnAppear)
    .onChange(of: dateOfBirth) { _, newValue in
      dateOfBirthString = OnboardingDate.dateOnlyString(OnboardingDate.clamp(newValue))
    }
    .onChange(of: unitSystemRaw) { oldValue, newValue in
      convertDisplayedMeasurements(from: oldValue, to: newValue)
    }
    .onChange(of: model.ble.bluetoothState) { _, _ in
      bluetoothPermissionResolved = OnboardingPermissionState.bluetoothResolved()
      if step == .bluetooth, shouldSkip(.bluetooth) {
        moveForward()
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case .profile:
      OnboardingProfileStep(
        firstName: $firstName,
        dateOfBirth: $dateOfBirth,
        unitSystemRaw: $unitSystemRaw,
        heightInput: $heightInput,
        heightFeetInput: $heightFeetInput,
        heightInchesInput: $heightInchesInput,
        weightInput: $weightInput,
        genderRaw: $genderRaw,
        validationMessage: validationMessage,
        focusedField: $focusedField
      )
    case .healthKit:
      OnboardingPermissionStep(
        systemImage: "heart.fill",
        title: "HealthKit",
        bodyText: "Goose uses HealthKit to compare WHOOP reads with local health signals on this iPhone.",
        details: [
          "Heart rate, HRV, respiratory rate, and oxygen saturation",
          "Sleep, steps, active energy, and body temperature",
          "Read-only access from Apple Health",
        ],
        buttonTitle: "Enable HealthKit",
        isRequesting: healthKitRequesting,
        tint: .red,
        action: requestHealthKitAccess
      )
    case .bluetooth:
      OnboardingPermissionStep(
        systemImage: "bluetooth",
        title: "Bluetooth",
        bodyText: "Goose needs Bluetooth to find your owned WHOOP strap and keep the local connection live.",
        details: [
          "Scan for nearby WHOOP services",
          "Connect to the selected strap",
          "Read live battery, firmware, and strap notifications",
        ],
        buttonTitle: "Enable Bluetooth",
        isRequesting: false,
        tint: .blue,
        action: requestBluetoothAccess
      )
    case .notifications:
      OnboardingPermissionStep(
        systemImage: "bell.badge.fill",
        title: "Notifications",
        bodyText: "Goose can notify you when the strap connects, disconnects, or needs attention.",
        details: [
          "Connection and reconnect status",
          "Battery and sync reminders",
          "Local alerts only",
        ],
        buttonTitle: "Enable Notifications",
        isRequesting: notificationRequesting,
        tint: .orange,
        action: requestNotificationAccess
      )
    case .connect:
      OnboardingConnectStep(ble: model.ble)
    }
  }

  @ViewBuilder
  private var footer: some View {
    if step == .connect {
      OnboardingConnectActionBar(
        ble: model.ble,
        onBack: moveBack,
        onComplete: finishOnboarding
      )
    } else {
      OnboardingStandardActionBar(
        showBack: step != .profile,
        primaryTitle: "Continue",
        onBack: moveBack,
        onPrimary: continueFromCurrentStep
      )
    }
  }

  private func hydrateOnAppear() {
    hydrateDateOfBirth()
    hydrateMeasurementsIfNeeded()
    refreshPermissionState()
    if shouldSkip(step), let next = nextAvailableStep(after: step) {
      step = next
    }
  }

  private func hydrateDateOfBirth() {
    if let saved = OnboardingDate.parse(dateOfBirthString) {
      dateOfBirth = OnboardingDate.clamp(saved)
    } else {
      dateOfBirth = OnboardingDate.defaultDateOfBirth()
      dateOfBirthString = OnboardingDate.dateOnlyString(dateOfBirth)
    }
  }

  private func hydrateMeasurementsIfNeeded() {
    let unitSystem = OnboardingUnitSystem(rawValue: unitSystemRaw) ?? .imperial
    if unitSystem == .imperial,
       heightFeetInput.isEmpty,
       heightInchesInput.isEmpty {
      if let totalInches = measurementValue(heightInput), totalInches > 0 {
        applyHeightMillimeters(Int((totalInches * 25.4).rounded()), for: .imperial)
      } else if heightMm > 0 {
        applyHeightMillimeters(heightMm, for: .imperial)
      }
    }
    if unitSystem == .metric, heightInput.isEmpty, heightMm > 0 {
      applyHeightMillimeters(heightMm, for: .metric)
    }
    if weightInput.isEmpty, weightGrams > 0 {
      applyWeightGrams(weightGrams, for: unitSystem)
    }
  }

  private func continueFromCurrentStep() {
    if step == .profile {
      saveProfileAndContinue()
      return
    }
    moveForward()
  }

  private func saveProfileAndContinue() {
    validationMessage = nil
    let trimmedName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      validationMessage = "Enter your first name."
      return
    }
    guard trimmedName.count <= 40 else {
      validationMessage = "Use 40 characters or fewer."
      return
    }
    guard !genderRaw.isEmpty else {
      validationMessage = "Select a gender."
      return
    }
    let unitSystem = OnboardingUnitSystem(rawValue: unitSystemRaw) ?? .imperial
    guard let parsedHeightMm = heightMillimeters(for: unitSystem) else {
      validationMessage = "Enter height."
      return
    }
    guard let parsedWeightGrams = weightGrams(for: unitSystem) else {
      validationMessage = "Enter weight."
      return
    }

    let heightCentimeters = Double(parsedHeightMm) / 10
    guard (90...245).contains(heightCentimeters) else {
      validationMessage = "Check height."
      return
    }
    let weightKilograms = Double(parsedWeightGrams) / 1000
    guard (30...320).contains(weightKilograms) else {
      validationMessage = "Check weight."
      return
    }

    firstName = trimmedName
    dateOfBirthString = OnboardingDate.dateOnlyString(dateOfBirth)
    heightMm = parsedHeightMm
    weightGrams = parsedWeightGrams
    createdAtUnixMs = Int((Date().timeIntervalSince1970 * 1000).rounded())
    timezoneID = TimeZone.current.identifier
    model.recordUIAction(
      "onboarding.profile.saved",
      detail: "\(unitSystem.rawValue) height_mm=\(heightMm) weight_g=\(weightGrams)"
    )
    moveForward()
  }

  private func measurementValue(_ rawValue: String) -> Double? {
    let normalized = rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: ".")
    return Double(normalized)
  }

  private func convertDisplayedMeasurements(from oldRawValue: String, to newRawValue: String) {
    guard
      let oldUnitSystem = OnboardingUnitSystem(rawValue: oldRawValue),
      let newUnitSystem = OnboardingUnitSystem(rawValue: newRawValue),
      oldUnitSystem != newUnitSystem
    else {
      return
    }
    if let currentHeightMm = heightMillimeters(for: oldUnitSystem) {
      applyHeightMillimeters(currentHeightMm, for: newUnitSystem)
    }
    if let currentWeightGrams = weightGrams(for: oldUnitSystem) {
      applyWeightGrams(currentWeightGrams, for: newUnitSystem)
    }
  }

  private func heightMillimeters(for unitSystem: OnboardingUnitSystem) -> Int? {
    switch unitSystem {
    case .metric:
      guard let centimeters = measurementValue(heightInput), centimeters > 0 else {
        return nil
      }
      return Int((centimeters * 10).rounded())
    case .imperial:
      let feet = measurementValue(heightFeetInput) ?? 0
      let inches = measurementValue(heightInchesInput) ?? 0
      let totalInches = feet * 12 + inches
      guard totalInches > 0 else {
        return nil
      }
      return Int((totalInches * 25.4).rounded())
    }
  }

  private func weightGrams(for unitSystem: OnboardingUnitSystem) -> Int? {
    guard let weight = measurementValue(weightInput), weight > 0 else {
      return nil
    }
    switch unitSystem {
    case .metric:
      return Int((weight * 1000).rounded())
    case .imperial:
      return Int((weight * 453.59237).rounded())
    }
  }

  private func applyHeightMillimeters(_ millimeters: Int, for unitSystem: OnboardingUnitSystem) {
    switch unitSystem {
    case .metric:
      heightInput = Self.formatted(Double(millimeters) / 10, maxFractionDigits: 1)
    case .imperial:
      let totalInches = Double(millimeters) / 25.4
      let feet = Int(totalInches / 12)
      let inches = totalInches - Double(feet * 12)
      heightFeetInput = String(feet)
      heightInchesInput = Self.formatted(inches, maxFractionDigits: 1)
      heightInput = Self.formatted(totalInches, maxFractionDigits: 1)
    }
  }

  private func applyWeightGrams(_ grams: Int, for unitSystem: OnboardingUnitSystem) {
    switch unitSystem {
    case .metric:
      weightInput = Self.formatted(Double(grams) / 1000, maxFractionDigits: 1)
    case .imperial:
      weightInput = Self.formatted(Double(grams) / 453.59237, maxFractionDigits: 1)
    }
  }

  private static func formatted(_ value: Double, maxFractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maxFractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxFractionDigits)f", value)
  }

  private func requestHealthKitAccess() {
    guard !healthKitRequesting else {
      return
    }
    healthKitRequesting = true
    healthKitStatus = "Requesting..."
    model.recordUIAction("onboarding.healthkit.requested")

    Task {
      let status = await HealthKitPermissionRequester.requestReadAccess()
      await MainActor.run {
        healthKitStatus = status
        healthKitRequesting = false
        healthKitPermissionHandled = true
        model.recordUIAction("onboarding.healthkit.result", detail: status)
        moveForward()
      }
    }
  }

  private func requestBluetoothAccess() {
    model.ble.requestBluetooth()
    bluetoothPermissionResolved = OnboardingPermissionState.bluetoothResolved()
    model.recordUIAction("onboarding.bluetooth.requested")
    if shouldSkip(.bluetooth) {
      moveForward()
    }
  }

  private func requestNotificationAccess() {
    guard !notificationRequesting else {
      return
    }
    notificationRequesting = true
    notificationStatus = "Requesting..."
    model.recordUIAction("onboarding.notifications.requested")

    Task {
      let status: String
      do {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        status = granted ? "Allowed" : "Not allowed"
      } catch {
        status = "Failed: \(error.localizedDescription)"
      }
      await MainActor.run {
        notificationStatus = status
        notificationRequesting = false
        notificationPermissionHandled = true
        notificationPermissionResolved = true
        model.recordUIAction("onboarding.notifications.result", detail: status)
        moveForward()
      }
    }
  }

  private func moveForward() {
    refreshPermissionState()
    guard let next = nextAvailableStep(after: step) else {
      finishOnboarding()
      return
    }
    validationMessage = nil
    withAnimation(.snappy) {
      step = next
    }
  }

  private func moveBack() {
    refreshPermissionState()
    guard let previous = previousAvailableStep(before: step) else {
      return
    }
    validationMessage = nil
    withAnimation(.snappy) {
      step = previous
    }
  }

  private func finishOnboarding() {
    model.recordUIAction("onboarding.finish", detail: "step=\(step.rawValue)")
    onComplete()
  }

  private func refreshPermissionState() {
    bluetoothPermissionResolved = OnboardingPermissionState.bluetoothResolved()
    Task {
      let resolved = await OnboardingPermissionState.notificationResolved()
      await MainActor.run {
        notificationPermissionResolved = resolved
        if resolved {
          notificationPermissionHandled = true
        }
      }
    }
  }

  private func shouldSkip(_ candidate: OnboardingStep) -> Bool {
    switch candidate {
    case .profile, .connect:
      return false
    case .healthKit:
      return healthKitPermissionHandled || !HKHealthStore.isHealthDataAvailable()
    case .bluetooth:
      return bluetoothPermissionResolved || bluetoothStateIsResolved
    case .notifications:
      return notificationPermissionHandled || notificationPermissionResolved
    }
  }

  private var bluetoothStateIsResolved: Bool {
    switch model.ble.bluetoothState {
    case "powered on", "powered off", "unauthorized", "unsupported", "bluetooth unavailable":
      return true
    default:
      return false
    }
  }

  private func nextAvailableStep(after currentStep: OnboardingStep) -> OnboardingStep? {
    var candidate = currentStep.next
    while let step = candidate, shouldSkip(step) {
      candidate = step.next
    }
    return candidate
  }

  private func previousAvailableStep(before currentStep: OnboardingStep) -> OnboardingStep? {
    var candidate = currentStep.previous
    while let step = candidate, shouldSkip(step) {
      candidate = step.previous
    }
    return candidate
  }
}

private enum OnboardingStep: Int, CaseIterable {
  case profile
  case healthKit
  case bluetooth
  case notifications
  case connect

  var title: String {
    switch self {
    case .profile:
      return "Set up Goose"
    case .healthKit:
      return "Connect HealthKit"
    case .bluetooth:
      return "Enable Bluetooth"
    case .notifications:
      return "Enable Notifications"
    case .connect:
      return "Connect your WHOOP"
    }
  }

  var progress: Double {
    Double(rawValue + 1) / Double(Self.allCases.count)
  }

  var stepLabel: String {
    "Step \(rawValue + 1) of \(Self.allCases.count)"
  }

  var next: OnboardingStep? {
    Self(rawValue: rawValue + 1)
  }

  var previous: OnboardingStep? {
    Self(rawValue: rawValue - 1)
  }
}

private enum OnboardingInputField: Hashable {
  case firstName
  case heightCentimeters
  case heightFeet
  case heightInches
  case weight
}

private enum OnboardingUnitSystem: String, CaseIterable, Identifiable {
  case imperial
  case metric

  var id: String { rawValue }

  var title: String {
    switch self {
    case .imperial:
      return "Imperial"
    case .metric:
      return "Metric"
    }
  }
}

private enum OnboardingGender: String, CaseIterable, Identifiable {
  case female
  case male
  case nonBinary = "non_binary"
  case preferNotToSay = "prefer_not_to_say"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .female:
      return "Female"
    case .male:
      return "Male"
    case .nonBinary:
      return "Non-binary"
    case .preferNotToSay:
      return "Prefer not to say"
    }
  }
}

private enum OnboardingStorage {
  static let firstName = "goose.swift.profile.firstName"
  static let dateOfBirth = "goose.swift.profile.dateOfBirth"
  static let unitSystem = "goose.swift.profile.unitSystem"
  static let heightInput = "goose.swift.profile.heightInput"
  static let heightFeetInput = "goose.swift.profile.heightFeetInput"
  static let heightInchesInput = "goose.swift.profile.heightInchesInput"
  static let weightInput = "goose.swift.profile.weightInput"
  static let gender = "goose.swift.profile.gender"
  static let heightMm = "goose.swift.profile.heightMm"
  static let weightGrams = "goose.swift.profile.weightGrams"
  static let createdAtUnixMs = "goose.swift.profile.createdAtUnixMs"
  static let timezoneID = "goose.swift.profile.timezoneID"
  static let healthKitPermissionHandled = "goose.swift.permissions.healthKitHandled"
  static let notificationPermissionHandled = "goose.swift.permissions.notificationHandled"
}

private enum OnboardingPermissionState {
  static func bluetoothResolved() -> Bool {
    switch CBManager.authorization {
    case .notDetermined:
      return false
    case .allowedAlways, .denied, .restricted:
      return true
    @unknown default:
      return false
    }
  }

  static func notificationResolved() async -> Bool {
    await withCheckedContinuation { continuation in
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        continuation.resume(returning: settings.authorizationStatus != .notDetermined)
      }
    }
  }
}

private enum OnboardingDate {
  static func parse(_ value: String) -> Date? {
    let formatter = dateFormatter
    guard let date = formatter.date(from: value) else {
      return nil
    }
    return Calendar.current.startOfDay(for: date)
  }

  static func dateOnlyString(_ date: Date) -> String {
    dateFormatter.string(from: date)
  }

  static func defaultDateOfBirth() -> Date {
    clamp(Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date())
  }

  static func minimumDateOfBirth() -> Date {
    Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? Date.distantPast
  }

  static func maximumDateOfBirth() -> Date {
    Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date()
  }

  static func clamp(_ date: Date) -> Date {
    let normalized = Calendar.current.startOfDay(for: date)
    let minimum = Calendar.current.startOfDay(for: minimumDateOfBirth())
    let maximum = Calendar.current.startOfDay(for: maximumDateOfBirth())
    if normalized < minimum {
      return minimum
    }
    if normalized > maximum {
      return maximum
    }
    return normalized
  }

  private static var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }
}

private enum HealthKitPermissionRequester {
  static func requestReadAccess() async -> String {
    guard HKHealthStore.isHealthDataAvailable() else {
      return "Unavailable on this device"
    }

    let store = HKHealthStore()
    var readTypes = Set<HKObjectType>()
    let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
      .heartRate,
      .restingHeartRate,
      .heartRateVariabilitySDNN,
      .respiratoryRate,
      .oxygenSaturation,
      .stepCount,
      .activeEnergyBurned,
      .bodyTemperature,
    ]
    for identifier in quantityIdentifiers {
      if let type = HKObjectType.quantityType(forIdentifier: identifier) {
        readTypes.insert(type)
      }
    }
    if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
      readTypes.insert(sleepType)
    }

    do {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        store.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes) { success, error in
          if let error {
            continuation.resume(throwing: error)
          } else if success {
            continuation.resume()
          } else {
            continuation.resume(throwing: HealthKitPermissionError.notAllowed)
          }
        }
      }
      return "Requested in Health"
    } catch {
      return "Failed: \(error.localizedDescription)"
    }
  }
}

private enum HealthKitPermissionError: LocalizedError {
  case notAllowed

  var errorDescription: String? {
    "Health access was not allowed."
  }
}

private struct OnboardingHeader: View {
  let step: OnboardingStep

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(step.stepLabel)
        Spacer()
        Text("\(Int((step.progress * 100).rounded()))%")
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)

      Text(step.title)
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .foregroundStyle(.primary)
      ProgressView(value: step.progress)
        .tint(.blue)
    }
  }
}

private struct OnboardingProfileStep: View {
  @Binding var firstName: String
  @Binding var dateOfBirth: Date
  @Binding var unitSystemRaw: String
  @Binding var heightInput: String
  @Binding var heightFeetInput: String
  @Binding var heightInchesInput: String
  @Binding var weightInput: String
  @Binding var genderRaw: String
  let validationMessage: String?
  let focusedField: FocusState<OnboardingInputField?>.Binding

  private var unitSystem: OnboardingUnitSystem {
    OnboardingUnitSystem(rawValue: unitSystemRaw) ?? .imperial
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("These basics help Goose calculate your local metrics.")
        .font(.body)
        .foregroundStyle(.secondary)

      OnboardingGroupedSection {
        OnboardingTextFieldRow(
          label: "First name",
          text: $firstName,
          prompt: "First name",
          keyboardType: .default,
          textContentType: .givenName,
          field: .firstName,
          focusedField: focusedField
        )
        OnboardingDivider()
        DatePicker(
          "Date of birth",
          selection: $dateOfBirth,
          in: OnboardingDate.minimumDateOfBirth()...OnboardingDate.maximumDateOfBirth(),
          displayedComponents: .date
        )
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
      }

      VStack(alignment: .leading, spacing: 10) {
        OnboardingSectionLabel("Units")
        Picker("Units", selection: $unitSystemRaw) {
          ForEach(OnboardingUnitSystem.allCases) { unit in
            Text(unit.title).tag(unit.rawValue)
          }
        }
        .pickerStyle(.segmented)
      }

      VStack(alignment: .leading, spacing: 10) {
        OnboardingSectionLabel("Measurements")
        OnboardingGroupedSection {
          if unitSystem == .metric {
            OnboardingTextFieldRow(
              label: "Height",
              text: $heightInput,
              prompt: "cm",
              keyboardType: .decimalPad,
              suffix: "cm",
              field: .heightCentimeters,
              focusedField: focusedField
            )
          } else {
            OnboardingImperialHeightRow(
              feet: $heightFeetInput,
              inches: $heightInchesInput,
              focusedField: focusedField
            )
          }
          OnboardingDivider()
          OnboardingTextFieldRow(
            label: "Weight",
            text: $weightInput,
            prompt: unitSystem == .metric ? "kg" : "lb",
            keyboardType: .decimalPad,
            suffix: unitSystem == .metric ? "kg" : "lb",
            field: .weight,
            focusedField: focusedField
          )
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        OnboardingSectionLabel("Gender")
        OnboardingGroupedSection {
          Picker("Gender", selection: $genderRaw) {
            Text("Select").tag("")
            ForEach(OnboardingGender.allCases) { gender in
              Text(gender.title).tag(gender.rawValue)
            }
          }
          .pickerStyle(.menu)
          .font(.body)
          .padding(.horizontal, 16)
          .frame(minHeight: 50)
        }
      }

      if let validationMessage {
        Text(validationMessage)
          .font(.footnote)
          .foregroundStyle(.red)
          .padding(.horizontal, 4)
      }
    }
  }
}

private struct OnboardingPermissionStep: View {
  let systemImage: String
  let title: String
  let bodyText: String
  let details: [String]
  let buttonTitle: String
  let isRequesting: Bool
  let tint: Color
  let action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(bodyText)
        .font(.body)
        .foregroundStyle(.secondary)

      OnboardingGroupedSection {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 12) {
            Image(systemName: systemImage)
              .font(.headline)
              .foregroundStyle(tint)
              .frame(width: 36, height: 36)
              .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
              .font(.headline)
          }

          VStack(alignment: .leading, spacing: 10) {
            ForEach(details, id: \.self) { detail in
              Label(detail, systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
          }

          Button(action: action) {
            HStack {
              if isRequesting {
                ProgressView()
              }
              Text(buttonTitle)
                .frame(maxWidth: .infinity)
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(isRequesting)
        }
        .padding(16)
      }
    }
  }
}

private struct OnboardingConnectStep: View {
  @ObservedObject var ble: GooseBLEClient

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
        .aspectRatio(1.7, contentMode: .fit)
        .overlay {
          Image("onboarding_pairing_help")
            .resizable()
            .scaledToFit()
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 8) {
        Text(connectHeading)
          .font(.title2.weight(.bold))
        Text(connectBody)
          .font(.body)
          .foregroundStyle(.secondary)
      }

      OnboardingStateRow(systemImage: connectIcon, label: connectStateLabel, detail: ble.connectionState)

      if !ble.discoveredDevices.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          OnboardingSectionLabel("Choose your strap")
          VStack(spacing: 8) {
            ForEach(ble.discoveredDevices.prefix(4)) { device in
              OnboardingDiscoveredStrapRow(
                device: device,
                selected: ble.selectedDeviceID == device.id
              ) {
                ble.select(device)
              }
            }
          }
        }
      }
    }
  }

  private var hasDiscoveredStraps: Bool {
    !ble.discoveredDevices.isEmpty
  }

  private var connected: Bool {
    ["connecting", "discovering", "connected", "ready"].contains(ble.connectionState)
  }

  private var canVerify: Bool {
    ble.connectionState == "ready"
      || ble.liveHeartRateBPM != nil
      || ble.batteryLevelPercent != nil
      || ble.firmwareVersion != nil
      || ble.modelNumber != nil
  }

  private var searching: Bool {
    ble.isScanning || ble.bluetoothState == "waiting for bluetooth"
  }

  private var connectHeading: String {
    if canVerify {
      return "WHOOP is connected"
    }
    if connected {
      return "Reading strap data"
    }
    if hasDiscoveredStraps {
      return "We found a WHOOP nearby"
    }
    if searching {
      return "Looking for your WHOOP"
    }
    return "Pair your WHOOP strap"
  }

  private var connectBody: String {
    if canVerify {
      return "Finish setup to start using Goose with this strap."
    }
    if connected {
      return "Keep the strap close while Goose confirms it can read data."
    }
    if hasDiscoveredStraps {
      return "Select the strap you want to use with Goose."
    }
    if searching {
      return "Keep Bluetooth on and keep the strap close to this phone."
    }
    return "Take the strap off your wrist, keep it nearby, then start pairing."
  }

  private var connectStateLabel: String {
    if canVerify {
      return "Connected and ready"
    }
    if connected {
      return "Connected"
    }
    if hasDiscoveredStraps {
      return "Strap found"
    }
    if searching {
      return "Searching"
    }
    return "Ready to pair"
  }

  private var connectIcon: String {
    if canVerify || connected {
      return "checkmark.circle.fill"
    }
    if searching {
      return "antenna.radiowaves.left.and.right"
    }
    return "bluetooth"
  }
}

private struct OnboardingStandardActionBar: View {
  let showBack: Bool
  let primaryTitle: String
  let onBack: () -> Void
  let onPrimary: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      if showBack {
        Button(action: onBack) {
          Label("Back", systemImage: "chevron.left")
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }
      Button(action: onPrimary) {
        Text(primaryTitle)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(16)
    .background(.regularMaterial)
  }
}

private struct OnboardingConnectActionBar: View {
  @ObservedObject var ble: GooseBLEClient
  let onBack: () -> Void
  let onComplete: () -> Void

  var body: some View {
    VStack(spacing: 10) {
      Button(action: primaryAction) {
        Text(primaryTitle)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(primaryDisabled)

      if hasDiscoveredStraps && !connected {
        Button("Search again", action: startPairing)
          .buttonStyle(.bordered)
          .controlSize(.large)
          .frame(maxWidth: .infinity)
      }

      Button(action: onBack) {
        Label("Back", systemImage: "chevron.left")
          .labelStyle(.titleAndIcon)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
    }
    .padding(16)
    .background(.regularMaterial)
  }

  private var hasDiscoveredStraps: Bool {
    !ble.discoveredDevices.isEmpty
  }

  private var connected: Bool {
    ["connecting", "discovering", "connected", "ready"].contains(ble.connectionState)
  }

  private var canVerify: Bool {
    ble.connectionState == "ready"
      || ble.liveHeartRateBPM != nil
      || ble.batteryLevelPercent != nil
      || ble.firmwareVersion != nil
      || ble.modelNumber != nil
  }

  private var searching: Bool {
    ble.isScanning
  }

  private var primaryTitle: String {
    if canVerify {
      return "Finish setup"
    }
    if connected {
      return "Waiting for strap data"
    }
    if hasDiscoveredStraps {
      return "Connect selected strap"
    }
    return searching ? "Searching..." : "Find my WHOOP"
  }

  private var primaryDisabled: Bool {
    if connected && !canVerify {
      return true
    }
    if searching && !hasDiscoveredStraps {
      return true
    }
    return false
  }

  private func primaryAction() {
    if canVerify {
      onComplete()
    } else if hasDiscoveredStraps {
      ble.connectSelected()
    } else {
      startPairing()
    }
  }

  private func startPairing() {
    ble.requestBluetooth()
    ble.startScan()
  }
}

private struct OnboardingGroupedSection<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color(.separator).opacity(0.35))
    }
  }
}

private struct OnboardingImperialHeightRow: View {
  @Binding var feet: String
  @Binding var inches: String
  let focusedField: FocusState<OnboardingInputField?>.Binding

  var body: some View {
    VStack(spacing: 0) {
      OnboardingTextFieldRow(
        label: "Height",
        text: $feet,
        prompt: "ft",
        keyboardType: .numberPad,
        suffix: "ft",
        field: .heightFeet,
        focusedField: focusedField
      )
      OnboardingDivider()
      OnboardingTextFieldRow(
        label: "Inches",
        text: $inches,
        prompt: "in",
        keyboardType: .decimalPad,
        suffix: "in",
        field: .heightInches,
        focusedField: focusedField
      )
    }
  }
}

private struct OnboardingTextFieldRow: View {
  let label: String
  @Binding var text: String
  let prompt: String
  let keyboardType: UIKeyboardType
  var textContentType: UITextContentType?
  var suffix: String? = nil
  let field: OnboardingInputField
  let focusedField: FocusState<OnboardingInputField?>.Binding

  var body: some View {
    HStack(spacing: 12) {
      Text(label)
        .foregroundStyle(.primary)
      TextField(suffix == nil ? prompt : "0", text: $text)
        .multilineTextAlignment(.trailing)
        .keyboardType(keyboardType)
        .textContentType(textContentType)
        .focused(focusedField, equals: field)
        .submitLabel(.done)
        .onSubmit {
          focusedField.wrappedValue = nil
        }
      if let suffix {
        Text(suffix)
          .foregroundStyle(.secondary)
      }
    }
    .font(.body)
    .padding(.horizontal, 16)
    .frame(minHeight: 50)
  }
}

private struct OnboardingDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 16)
  }
}

private struct OnboardingSectionLabel: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text.uppercased())
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
  }
}

private struct OnboardingStateRow: View {
  let systemImage: String
  let label: String
  let detail: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(.blue)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct OnboardingDiscoveredStrapRow: View {
  let device: GooseDiscoveredDevice
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selected ? .blue : .secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(device.name)
            .font(.headline)
            .foregroundStyle(.primary)
          Text("RSSI \(device.rssi)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

private struct OnboardingKeyboardDismissTapCatcher: UIViewRepresentable {
  let isEnabled: Bool
  let dismiss: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(isEnabled: isEnabled, dismiss: dismiss)
  }

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.isEnabled = isEnabled
    context.coordinator.dismiss = dismiss
    DispatchQueue.main.async {
      context.coordinator.attach(to: uiView.window)
    }
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    coordinator.detach()
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var isEnabled: Bool
    var dismiss: () -> Void
    private weak var window: UIWindow?
    private weak var recognizer: UITapGestureRecognizer?

    init(isEnabled: Bool, dismiss: @escaping () -> Void) {
      self.isEnabled = isEnabled
      self.dismiss = dismiss
    }

    func attach(to nextWindow: UIWindow?) {
      guard let nextWindow else {
        return
      }
      if window === nextWindow {
        return
      }
      detach()
      let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
      tapRecognizer.cancelsTouchesInView = false
      tapRecognizer.delegate = self
      nextWindow.addGestureRecognizer(tapRecognizer)
      window = nextWindow
      recognizer = tapRecognizer
    }

    func detach() {
      if let recognizer, let window {
        window.removeGestureRecognizer(recognizer)
      }
      recognizer = nil
      window = nil
    }

    @objc private func handleTap() {
      guard isEnabled else {
        return
      }
      dismiss()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      guard isEnabled, let view = touch.view else {
        return false
      }
      return !view.hasSuperview(of: UIControl.self)
    }
  }
}

private extension UIView {
  func hasSuperview<T: UIView>(of type: T.Type) -> Bool {
    var candidate: UIView? = self
    while let current = candidate {
      if current is T {
        return true
      }
      candidate = current.superview
    }
    return false
  }
}
