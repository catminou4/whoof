import SwiftUI

struct DeviceView: View {
  @EnvironmentObject private var model: GooseAppModel

  var body: some View {
    DeviceContentView(ble: model.ble)
      .environmentObject(model)
  }
}

private enum DevicePanel {
  case status
  case advanced
}

private struct DeviceContentView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var ble: GooseBLEClient
  @State private var selectedPanel: DevicePanel = .status

  var body: some View {
    ZStack {
      deviceBackground.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          DeviceConnectionHeader(
            connected: deviceConnected,
            statusText: connectionHeadline,
            deviceName: ble.activeDeviceName,
            lastSync: lastSyncSummary
          )
          .padding(.bottom, 30)

          DeviceStatusTabs(selectedPanel: $selectedPanel)
            .padding(.bottom, 46)

          if selectedPanel == .status {
            DeviceImageAndBattery(batteryPercent: ble.batteryLevelPercent)
          } else {
            DeviceAdvancedPanel(model: model, ble: ble)
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 36)
        .padding(.bottom, 28)
      }
    }
    .navigationTitle("Device")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          ble.refreshBatteryLevel()
        } label: {
          Image(systemName: "battery.75percent")
        }
        .foregroundStyle(.white)
        .accessibilityLabel("Refresh Battery")
      }
    }
    .onAppear {
      ble.refreshBatteryLevel()
    }
  }

  private var deviceConnected: Bool {
    let state = ble.connectionState.lowercased()
    return state == "ready" || state == "connected" || state == "discovering"
  }

  private var connectionHeadline: String {
    let state = ble.connectionState.lowercased()
    if deviceConnected {
      return "CONNECTED TO"
    }
    if state == "connecting" {
      return "CONNECTING"
    }
    if ble.isScanning {
      return "SCANNING"
    }
    return "NOT CONNECTED"
  }

  private var lastSyncSummary: String {
    relativeSummary(for: ble.lastSyncAt) ?? "Not synced"
  }
}

private struct DeviceStatusTabs: View {
  @Binding var selectedPanel: DevicePanel

  var body: some View {
    HStack(spacing: 46) {
      DeviceTabButton(
        label: "STATUS",
        selected: selectedPanel == .status
      ) {
        withAnimation(.easeOut(duration: 0.16)) {
          selectedPanel = .status
        }
      }
      DeviceTabButton(
        label: "ADVANCED",
        selected: selectedPanel == .advanced
      ) {
        withAnimation(.easeOut(duration: 0.16)) {
          selectedPanel = .advanced
        }
      }
    }
  }
}

private struct DeviceTabButton: View {
  let label: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        Text(label)
          .font(deviceLabelFont)
          .foregroundStyle(selected ? .white : mutedText)
        Rectangle()
          .fill(.white)
          .frame(width: selected ? underlineWidth : 0, height: 3)
      }
      .frame(width: label == "ADVANCED" ? 96 : 72, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var underlineWidth: CGFloat {
    label == "ADVANCED" ? 76 : 52
  }
}

private struct DeviceImageAndBattery: View {
  let batteryPercent: Int?

  var body: some View {
    GeometryReader { proxy in
      let imageWidth = min(max(proxy.size.width * 0.95, 290), 390)
      let percentFontSize = min(max(proxy.size.width * 0.155, 50), 62)
      ZStack(alignment: .topLeading) {
        Image("whoop_gen5_front")
          .resizable()
          .scaledToFit()
          .frame(width: imageWidth, height: 305)
          .offset(x: -imageWidth * 0.28, y: 36)
          .accessibilityLabel("WHOOP strap")

        HStack(alignment: .bottom, spacing: 18) {
          HStack(alignment: .bottom, spacing: 0) {
            Text(batteryText)
              .font(.system(size: percentFontSize, weight: .black, design: .default))
              .foregroundStyle(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text("%")
              .font(.system(size: percentFontSize * 0.42, weight: .black, design: .default))
              .foregroundStyle(.white)
              .padding(.bottom, percentFontSize * 0.08)
          }
          BatteryRail(percent: batteryPercent)
        }
        .frame(maxWidth: proxy.size.width, alignment: .trailing)
        .padding(.top, 190)
      }
      .frame(width: proxy.size.width, height: 350, alignment: .topLeading)
    }
    .frame(height: 350)
  }

  private var batteryText: String {
    guard let batteryPercent else {
      return "--"
    }
    return "\(batteryPercent)"
  }
}

private struct DeviceConnectionHeader: View {
  let connected: Bool
  let statusText: String
  let deviceName: String
  let lastSync: String

  var body: some View {
    HStack(alignment: .bottom, spacing: 16) {
      VStack(alignment: .leading, spacing: 7) {
        Text(statusText)
          .font(deviceLabelFont)
          .foregroundStyle(connected ? connectedGreen : disconnectedRed)
          .lineLimit(1)
        Text(deviceName.uppercased())
          .font(.system(size: 26, weight: .black, design: .default))
          .foregroundStyle(.white)
          .lineLimit(2)
          .minimumScaleFactor(0.78)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .trailing, spacing: 7) {
        Text("LAST SYNC")
          .font(deviceLabelFont)
          .foregroundStyle(secondaryText)
        HStack(spacing: 8) {
          Text(lastSync)
            .font(deviceBodyFont.weight(.black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
          Image(systemName: "icloud")
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(secondaryText)
        }
      }
    }
  }
}

private struct BatteryRail: View {
  let percent: Int?

  var body: some View {
    ZStack(alignment: .bottom) {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(red: 0.23, green: 0.25, blue: 0.27))
        .frame(width: 10, height: 138)
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(batteryYellow)
        .frame(width: 10, height: 138 * CGFloat(value))
    }
    .frame(width: 12, height: 138)
  }

  private var value: Double {
    Double(min(max(percent ?? 0, 0), 100)) / 100
  }
}

private struct DeviceAdvancedPanel: View {
  @ObservedObject var model: GooseAppModel
  @ObservedObject var ble: GooseBLEClient

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      DeviceDetailStack {
        DeviceFactRow(systemName: "gearshape", label: "Firmware", value: firmwareSummary)
        DeviceFactRow(systemName: "battery.25percent", label: "Battery", value: batterySummary)
        DeviceFactRow(systemName: "arrow.2.circlepath", label: "Last sync", value: relativeSummary(for: ble.lastSyncAt) ?? "Not synced")
      }

      DeviceFactRow(systemName: "iphone", label: "Model", value: modelSummary)

      DeviceDetailStack {
        DeviceFactRow(systemName: "heart", label: "Live HR", value: heartRateSummary)
        DeviceFactRow(systemName: "dot.radiowaves.left.and.right", label: "Connection", value: ble.connectionState.capitalized)
        DeviceFactRow(systemName: "arrow.triangle.2.circlepath", label: "Historical sync", value: ble.historicalSyncStatus.capitalized)
        DeviceFactRow(systemName: "cpu", label: "Rust", value: model.rustStatus)
        DeviceFactRow(systemName: "waveform.path.ecg", label: "Last frame", value: model.lastParsedFrameSummary)
      }

      DeviceActionGrid(ble: ble)
      DiscoveredDeviceList(ble: ble)
      EventLogPreview(messages: Array(ble.messages.prefix(5)))
    }
  }

  private var firmwareSummary: String {
    ble.firmwareVersion ?? ble.softwareRevision ?? "Unknown"
  }

  private var batterySummary: String {
    guard let battery = ble.batteryLevelPercent else {
      return "Unknown"
    }
    if let updatedAt = ble.batteryUpdatedAt,
       Date().timeIntervalSince(updatedAt) > 3600,
       let relative = relativeSummary(for: updatedAt) {
      return "\(battery)% [\(relative)]"
    }
    return "\(battery)%"
  }

  private var modelSummary: String {
    if let modelNumber = ble.modelNumber {
      return modelNumber
    }
    if let hardwareRevision = ble.hardwareRevision {
      return "Hardware \(hardwareRevision)"
    }
    return ble.activeDeviceName
  }

  private var heartRateSummary: String {
    guard let bpm = ble.liveHeartRateBPM else {
      return ble.liveHeartRateSource.capitalized
    }
    if let updatedAt = ble.liveHeartRateUpdatedAt,
       let relative = relativeSummary(for: updatedAt) {
      return "\(bpm) bpm \(relative)"
    }
    return "\(bpm) bpm"
  }
}

private struct DeviceDetailStack<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
  }
}

private struct DeviceFactRow: View {
  let systemName: String
  let label: String
  let value: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemName)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(secondaryText)
        .frame(width: 24)
      Text(label)
        .font(advancedBodyFont)
        .foregroundStyle(secondaryText)
        .lineLimit(1)
      Spacer(minLength: 16)
      Text(value)
        .font(advancedBodyFont)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .multilineTextAlignment(.trailing)
    }
    .padding(.vertical, 16)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(dividerColor)
        .frame(height: 1)
    }
  }
}

private struct DeviceActionGrid: View {
  @ObservedObject var ble: GooseBLEClient

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 10) {
      DeviceActionButton(title: "Bluetooth", systemName: "antenna.radiowaves.left.and.right") {
        ble.requestBluetooth()
      }
      DeviceActionButton(title: ble.isScanning ? "Stop Scan" : "Scan", systemName: "dot.radiowaves.left.and.right") {
        ble.isScanning ? ble.stopScan() : ble.startScan()
      }
      .disabled(!ble.canScan)

      DeviceActionButton(title: "Connect", systemName: "link") {
        ble.connectSelected()
      }
      .disabled(!ble.canConnect)

      DeviceActionButton(title: "Reconnect", systemName: "arrow.clockwise") {
        ble.reconnectRemembered()
      }
      .disabled(!ble.canReconnectRemembered)

      DeviceActionButton(title: ble.isHistoricalSyncing ? "Syncing" : "Sync", systemName: "arrow.triangle.2.circlepath") {
        ble.syncHistoricalPackets()
      }
      .disabled(!ble.canSyncHistorical)

      DeviceActionButton(title: "Hello", systemName: "paperplane") {
        ble.sendClientHello()
      }
      .disabled(!ble.canSendHello)

      DeviceActionButton(title: "Forget", systemName: "trash", role: .destructive) {
        ble.forgetRememberedDevice()
      }
      .disabled(!ble.hasRememberedDevice)
    }
  }
}

private struct DeviceActionButton: View {
  let title: String
  let systemName: String
  var role: ButtonRole?
  let action: () -> Void

  var body: some View {
    Button(role: role, action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemName)
          .font(.system(size: 15, weight: .bold))
        Text(title)
          .font(.system(size: 15, weight: .black, design: .default))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }
      .frame(maxWidth: .infinity, minHeight: 46)
      .padding(.horizontal, 10)
      .foregroundStyle(role == .destructive ? disconnectedRed : .white)
      .background(controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .opacity(isDisabled ? 0.45 : 1)
  }

  @Environment(\.isEnabled) private var isEnabled

  private var isDisabled: Bool {
    !isEnabled
  }
}

private struct DiscoveredDeviceList: View {
  @ObservedObject var ble: GooseBLEClient

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("DISCOVERED")
        .font(deviceLabelFont)
        .foregroundStyle(secondaryText)
      if ble.discoveredDevices.isEmpty {
        Text("No devices yet")
          .font(deviceBodyFont)
          .foregroundStyle(mutedText)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(spacing: 0) {
          ForEach(ble.discoveredDevices) { device in
            Button {
              ble.select(device)
            } label: {
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(device.name)
                    .font(deviceBodyFont.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                  Text(device.id.uuidString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(mutedText)
                    .lineLimit(1)
                }
                Spacer()
                Text("\(device.rssi)")
                  .font(deviceBodyFont.weight(.black))
                  .foregroundStyle(secondaryText)
              }
              .padding(.vertical, 13)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) {
              Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
            }
          }
        }
      }
    }
  }
}

private struct EventLogPreview: View {
  let messages: [GooseMessage]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("EVENTS")
        .font(deviceLabelFont)
        .foregroundStyle(secondaryText)
      if messages.isEmpty {
        Text("No events yet")
          .font(deviceBodyFont)
          .foregroundStyle(mutedText)
      } else {
        VStack(spacing: 0) {
          ForEach(messages) { message in
            VStack(alignment: .leading, spacing: 5) {
              HStack(spacing: 8) {
                Text(message.timestamp, style: .time)
                Text(message.level.rawValue.uppercased())
                Text(message.source)
              }
              .font(.system(size: 12, weight: .bold, design: .default))
              .foregroundStyle(mutedText)

              Text(message.title)
                .font(.system(size: 15, weight: .black, design: .default))
                .foregroundStyle(.white)
                .lineLimit(1)

              if !message.body.isEmpty {
                Text(message.body)
                  .font(.system(size: 12, weight: .semibold, design: .monospaced))
                  .foregroundStyle(secondaryText)
                  .lineLimit(2)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
              Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
            }
          }
        }
      }
    }
  }
}

private func relativeSummary(for date: Date?) -> String? {
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

private let deviceBackground = Color(red: 0.06, green: 0.09, blue: 0.11)
private let controlBackground = Color(red: 0.12, green: 0.16, blue: 0.18)
private let dividerColor = Color(red: 0.19, green: 0.22, blue: 0.25)
private let secondaryText = Color(red: 0.63, green: 0.65, blue: 0.67)
private let mutedText = Color(red: 0.56, green: 0.58, blue: 0.60)
private let connectedGreen = Color(red: 0.42, green: 0.84, blue: 0.30)
private let disconnectedRed = Color(red: 1.0, green: 0.27, blue: 0.23)
private let batteryYellow = Color(red: 1.0, green: 0.89, blue: 0.36)
private let deviceLabelFont = Font.system(size: 15, weight: .black, design: .default)
private let deviceBodyFont = Font.system(size: 17, weight: .bold, design: .default)
private let advancedBodyFont = Font.system(size: 17, weight: .regular, design: .default)
