import SwiftUI

struct AppShellView: View {
  @EnvironmentObject private var model: GooseAppModel
  @EnvironmentObject private var router: AppRouter
  @StateObject private var healthStore = HealthDataStore()

  var body: some View {
    TabView(selection: tabSelection) {
      ForEach(GooseAppTab.allCases) { tab in
        tabNavigationStack(for: tab)
        .tabItem {
          Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
      }
    }
  }

  private var tabSelection: Binding<GooseAppTab> {
    Binding {
      router.selectedTab
    } set: { newTab in
      guard newTab != router.selectedTab else {
        return
      }
      router.selectedTab = newTab
      model.recordUIAction("tab.selected", detail: newTab.title)
    }
  }

  @ViewBuilder
  private func tabNavigationStack(for tab: GooseAppTab) -> some View {
    if tab == .health {
      NavigationStack(path: $router.healthPath) {
        tabContent(for: tab)
      }
    } else {
      NavigationStack {
        tabContent(for: tab)
      }
    }
  }

  @ViewBuilder
  private func tabContent(for tab: GooseAppTab) -> some View {
    switch tab {
    case .home:
      HomeDashboardView(healthStore: healthStore)
    case .health:
      HealthView(store: healthStore)
    case .coach:
      CoachView()
    case .more:
      MorePlaceholderView()
    }
  }
}

enum GooseAppTab: String, CaseIterable, Identifiable {
  case home
  case health
  case coach
  case more

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .health: "Health"
    case .coach: "Coach"
    case .more: "More"
    }
  }

  var systemImage: String {
    switch self {
    case .home: "house"
    case .health: "heart.text.square"
    case .coach: "sparkles"
    case .more: "ellipsis.circle"
    }
  }

}

private struct HomeDashboardView: View {
  @EnvironmentObject private var model: GooseAppModel
  @EnvironmentObject private var router: AppRouter
  @ObservedObject var healthStore: HealthDataStore

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HomeDailyScoreCard(
          scores: scoreSnapshots,
          actionSummary: dailyActionSummary,
          openScore: openHealth,
          openCoach: openCoach
        )

        HomeStressEnergySection(
          stress: landingSnapshot(for: .stress),
          energy: landingSnapshot(for: .energyBank),
          openStress: { openHealth(.stress) }
        )

        HomeHealthMonitorSection(
          snapshots: healthStore.healthMonitorSnapshots(),
          openHealthMonitor: { openHealth(.healthMonitor) }
        )

        HomeTimelineSection(
          sleep: homeSnapshot(for: .sleep),
          activity: homeSnapshot(for: .strain),
          recovery: homeSnapshot(for: .recovery),
          openSleep: { openHealth(.sleep) },
          openActivity: { openHealth(.strain) },
          openRecovery: { openHealth(.recovery) }
        )

        HomeSectionHeader(title: "Next")
        VStack(spacing: 8) {
          ForEach(PlaceholderData.setupCards) { page in
            PlaceholderNavigationRow(page: page)
          }
        }

        HomeSectionHeader(title: "Explore")
        VStack(spacing: 8) {
          ForEach(PlaceholderData.homeSections) { section in
            NavigationLink {
              PlaceholderSectionDetailView(section: section)
            } label: {
              SectionSummaryRow(section: section)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Today")
    .safeAreaInset(edge: .bottom, alignment: .trailing) {
      HomeStartActivityFloatingButton(session: model.activitySession)
        .padding(.trailing, 18)
        .padding(.bottom, 10)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          DeviceView()
        } label: {
          Image(systemName: "sensor.tag.radiowaves.forward")
        }
        .accessibilityLabel("Device")
      }
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Home")
    }
    .task {
      healthStore.loadBridgeCatalogsIfNeeded()
    }
  }

  private var scoreSnapshots: [HealthMetricSnapshot] {
    [
      homeSnapshot(for: .sleep),
      homeSnapshot(for: .recovery),
      homeSnapshot(for: .strain),
    ]
  }

  private var dailyActionSummary: String {
    let inputAction = healthStore.metricInputReadinessNextActionSummary()
    if !inputAction.isEmpty {
      return inputAction
    }
    return healthStore.packetDerivedScoreNextActionSummary()
  }

  private var landingSnapshots: [HealthMetricSnapshot] {
    healthStore.landingSnapshots(
      liveHeartRateBPM: model.ble.liveHeartRateBPM,
      liveHeartRateSource: model.ble.liveHeartRateSource,
      liveHeartRateUpdatedAt: model.ble.liveHeartRateUpdatedAt
    )
  }

  private func landingSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    landingSnapshots.first { $0.route == route } ?? healthStore.snapshot(for: route)
  }

  private func homeSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    let snapshot = landingSnapshot(for: route)
    guard route == .strain, snapshot.unit != "%" else {
      return snapshot
    }
    let rawValue = firstNumber(in: snapshot.displayValue) ?? firstNumber(in: snapshot.value) ?? 0
    let percent = min(max(Int((rawValue / 21 * 100).rounded()), 0), 100)
    return HealthMetricSnapshot(
      id: snapshot.id,
      route: snapshot.route,
      group: snapshot.group,
      title: snapshot.title,
      value: "\(percent)",
      unit: "%",
      status: snapshot.status,
      freshness: snapshot.freshness,
      provenance: snapshot.provenance,
      source: snapshot.source,
      systemImage: snapshot.systemImage,
      tint: snapshot.tint,
      trend: snapshot.trend
    )
  }

  private func openHealth(_ route: HealthRoute) {
    router.openHealth(route)
    model.recordUIAction("health.deep_link.opened", detail: route.title)
  }

  private func openCoach() {
    router.selectedTab = .coach
    model.recordUIAction("coach.opened", detail: "Home daily score card")
  }
}

private struct HomeStartActivityFloatingButton: View {
  @ObservedObject var session: ActivitySessionModel

  var body: some View {
    NavigationLink {
      LiveActivityView()
    } label: {
      Image(systemName: session.isActive ? session.selectedActivity.systemImage : "plus")
        .font(.system(size: 21, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 54, height: 54)
        .background(session.selectedActivity.tint, in: Circle())
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 7)
        .overlay {
          Circle()
            .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(session.isActive ? "Open Activity" : "Start Activity")
  }
}

private struct HomeDailyScoreCard: View {
  let scores: [HealthMetricSnapshot]
  let actionSummary: String
  let openScore: (HealthRoute) -> Void
  let openCoach: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        ForEach(scores) { score in
          Button {
            openScore(score.route)
          } label: {
            HomeScoreDial(snapshot: score)
          }
          .buttonStyle(.plain)
        }
      }
      .frame(maxWidth: .infinity)

      Button {
        openCoach()
      } label: {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "sparkles")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.purple)
            .frame(width: 32, height: 32)
            .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text("Coach")
                .font(.headline)
                .foregroundStyle(.primary)
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            }
            Text(actionSummary)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }
        .padding(14)
        .cardSurface()
      }
      .buttonStyle(.plain)
    }
  }
}

private struct HomeScoreDial: View {
  let snapshot: HealthMetricSnapshot

  var body: some View {
    VStack(spacing: 9) {
      ZStack {
        Circle()
          .stroke(Color.primary.opacity(0.1), lineWidth: 9)
        Circle()
          .trim(from: 0, to: progress)
          .stroke(snapshot.tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
          .rotationEffect(.degrees(-90))

        Text(snapshot.displayValue)
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
          .padding(8)
      }
      .frame(width: 88, height: 88)

      HStack(spacing: 4) {
        Image(systemName: snapshot.systemImage)
          .font(.caption.weight(.bold))
          .foregroundStyle(snapshot.tint)
        Text(snapshot.title)
          .font(.caption.weight(.bold))
          .foregroundStyle(.primary)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private var progress: Double {
    let value = firstNumber(in: snapshot.displayValue) ?? 0
    return min(max(value / 100, 0), 1)
  }
}

private struct HomeStressEnergySection: View {
  let stress: HealthMetricSnapshot
  let energy: HealthMetricSnapshot
  let openStress: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Stress & Energy")

      Button {
        openStress()
      } label: {
        HStack(spacing: 14) {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
              Circle()
                .fill(.green)
                .frame(width: 10, height: 10)
              Text("Today's stress")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
              Spacer()
            }

            Text(stress.freshness)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)

            HStack(spacing: 12) {
              HomeStressStat(value: "88", label: "Highest", color: .red)
              HomeStressStat(value: "1", label: "Lowest", color: .cyan)
              HomeStressStat(value: stress.value, label: "Average", color: .green)
            }
          }

          ZStack {
            Circle()
              .stroke(Color.primary.opacity(0.1), lineWidth: 8)
            Circle()
              .trim(from: 0, to: stressProgress)
              .stroke(.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
              .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
              Text(stress.value)
                .font(.title3.bold())
              Text(stress.status)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .frame(width: 76, height: 76)

          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .cardSurface()
      }
      .buttonStyle(.plain)

      HomeEnergyBar(percent: Int(firstNumber(in: energy.displayValue) ?? 0), caption: energy.status)
    }
  }

  private var stressProgress: Double {
    min(max((firstNumber(in: stress.displayValue) ?? 0) / 100, 0), 1)
  }
}

private struct HomeStressStat: View {
  let value: String
  let label: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.headline.bold())
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct HomeEnergyBar: View {
  let percent: Int
  let caption: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "bolt.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.green)
        .frame(width: 30, height: 30)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      HStack(spacing: 3) {
        ForEach(0..<18, id: \.self) { index in
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(index < filledSegments ? Color.green : Color.primary.opacity(0.12))
            .frame(height: 18)
        }
      }

      VStack(alignment: .trailing, spacing: 2) {
        Text("\(percent)%")
          .font(.headline.bold())
          .lineLimit(1)
        Text(caption)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(14)
    .cardSurface()
  }

  private var filledSegments: Int {
    Int((Double(percent) / 100 * 18).rounded())
  }
}

private struct HomeHealthMonitorSection: View {
  let snapshots: [HealthMetricSnapshot]
  let openHealthMonitor: () -> Void

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Health Monitor")

      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(snapshots) { snapshot in
          Button {
            openHealthMonitor()
          } label: {
            HomeHealthMetricCard(snapshot: snapshot)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

private struct HomeHealthMetricCard: View {
  let snapshot: HealthMetricSnapshot

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: snapshot.systemImage)
            .foregroundStyle(.secondary)
          Text(snapshot.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }

        Spacer(minLength: 4)

        Text(snapshot.displayValue)
          .font(.title3.bold())
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.65)

        Label(snapshot.status, systemImage: statusImage)
          .font(.caption.weight(.bold))
          .foregroundStyle(snapshot.tint)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }

      Spacer(minLength: 0)

      Capsule()
        .fill(snapshot.tint.opacity(0.18))
        .frame(width: 8)
        .overlay(alignment: .bottom) {
          Capsule()
            .fill(snapshot.tint)
            .frame(height: 52)
        }
    }
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
    .padding(12)
    .cardSurface()
  }

  private var statusImage: String {
    snapshot.status.localizedCaseInsensitiveContains("unavailable") ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
  }
}

private struct HomeTimelineSection: View {
  let sleep: HealthMetricSnapshot
  let activity: HealthMetricSnapshot
  let recovery: HealthMetricSnapshot
  let openSleep: () -> Void
  let openActivity: () -> Void
  let openRecovery: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Timeline")

      VStack(spacing: 8) {
        HomeTimelineRow(
          time: "06:34",
          title: "Sleep summary",
          subtitle: summary(for: sleep),
          systemImage: "moon.fill",
          tint: sleep.tint,
          action: openSleep
        )
        HomeTimelineRow(
          time: "12:30",
          title: "Activity load",
          subtitle: summary(for: activity),
          systemImage: "arrow.triangle.2.circlepath",
          tint: activity.tint,
          action: openActivity
        )
        HomeTimelineRow(
          time: "17:00",
          title: "Recovery update",
          subtitle: summary(for: recovery),
          systemImage: "battery.25",
          tint: recovery.tint,
          action: openRecovery
        )
      }
    }
  }

  private func summary(for snapshot: HealthMetricSnapshot) -> String {
    "\(snapshot.displayValue) - \(snapshot.status)"
  }
}

private struct HomeTimelineRow: View {
  let time: String
  let title: String
  let subtitle: String
  let systemImage: String
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button {
      action()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 36, height: 36)
          .background(tint.opacity(0.12), in: Circle())

        Text(time)
          .font(.caption.weight(.bold))
          .foregroundStyle(.secondary)
          .frame(width: 48, alignment: .leading)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(.tertiary)
      }
      .padding(14)
      .cardSurface()
    }
    .buttonStyle(.plain)
  }
}

private struct HomeSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.title3.bold())
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 4)
  }
}

private struct PlaceholderSectionListView: View {
  @EnvironmentObject private var model: GooseAppModel
  let title: String
  let sections: [PlaceholderSection]

  var body: some View {
    List {
      ForEach(sections) { section in
        Section(section.title) {
          ForEach(section.pages) { page in
            NavigationLink {
              PlaceholderPageDetailView(page: page)
            } label: {
              PlaceholderListRow(page: page)
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(title)
    .onAppear {
      model.recordUIAction("page.opened", detail: title)
    }
  }
}

private struct MorePlaceholderView: View {
  @EnvironmentObject private var model: GooseAppModel
  @AppStorage("goose.swift.onboardingComplete") private var onboardingComplete = false

  var body: some View {
    List {
      Section("Device") {
        NavigationLink {
          DeviceView()
        } label: {
          Label("Device", systemImage: "sensor.tag.radiowaves.forward")
        }

        NavigationLink {
          ConnectionView()
        } label: {
          Label("Connection Lab", systemImage: "antenna.radiowaves.left.and.right")
        }
      }

#if DEBUG
      Section("Debug") {
        Button {
          model.ble.previewHelloWorldToast()
        } label: {
          Label("Hello World Toast", systemImage: "bell.badge")
        }

        Button {
          model.recordUIAction("ui.debug.redo_onboarding")
          model.onboardingComplete = false
          onboardingComplete = false
        } label: {
          Label("Re-do Onboarding", systemImage: "arrow.counterclockwise.circle")
        }
      }
#endif

      ForEach(PlaceholderData.moreSections) { section in
        Section(section.title) {
          ForEach(section.pages) { page in
            NavigationLink {
              PlaceholderPageDetailView(page: page)
            } label: {
              PlaceholderListRow(page: page)
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("More")
    .onAppear {
      model.recordUIAction("page.opened", detail: "More")
    }
  }
}

private struct CoachPlaceholderView: View {
  @EnvironmentObject private var model: GooseAppModel

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 14) {
          Label("WHOOP Coach", systemImage: "sparkles")
            .font(.title3.bold())
          Text("Ask about recovery, strain, sleep, and the live device stream.")
            .foregroundStyle(.secondary)
          HStack {
            Image(systemName: "text.bubble")
              .foregroundStyle(.secondary)
            Text("What should I focus on today?")
              .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "arrow.up.circle.fill")
              .foregroundStyle(.blue)
          }
          .padding(12)
          .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 8)
      }

      ForEach(PlaceholderData.coachSections) { section in
        Section(section.title) {
          ForEach(section.pages) { page in
            NavigationLink {
              PlaceholderPageDetailView(page: page)
            } label: {
              PlaceholderListRow(page: page)
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Coach")
    .onAppear {
      model.recordUIAction("page.opened", detail: "Coach")
    }
  }
}

private struct PlaceholderNavigationRow: View {
  let page: PlaceholderPage

  var body: some View {
    NavigationLink {
      PlaceholderPageDetailView(page: page)
    } label: {
      PlaceholderCardRow(page: page)
    }
    .buttonStyle(.plain)
  }
}

private struct PlaceholderCardRow: View {
  let page: PlaceholderPage

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: page.systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(page.tint)
        .frame(width: 34, height: 34)
        .background(page.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(page.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(page.summary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(.tertiary)
    }
    .padding(14)
    .cardSurface()
  }
}

private struct PlaceholderListRow: View {
  let page: PlaceholderPage

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 3) {
        Text(page.title)
          .lineLimit(1)
        Text(page.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    } icon: {
      Image(systemName: page.systemImage)
        .foregroundStyle(page.tint)
    }
  }
}

private struct SectionSummaryRow: View {
  let section: PlaceholderSection

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: section.systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(section.tint)
        .frame(width: 34, height: 34)
        .background(section.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(section.title)
          .font(.headline)
          .foregroundStyle(.primary)
        Text("\(section.pages.count) mapped routes")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(.tertiary)
    }
    .padding(14)
    .cardSurface()
  }
}

private struct PlaceholderSectionDetailView: View {
  @EnvironmentObject private var model: GooseAppModel
  let section: PlaceholderSection

  var body: some View {
    List {
      Section {
        Label(section.title, systemImage: section.systemImage)
          .font(.headline)
      }
      Section("Routes") {
        ForEach(section.pages) { page in
          NavigationLink {
            PlaceholderPageDetailView(page: page)
          } label: {
            PlaceholderListRow(page: page)
          }
        }
      }
    }
    .navigationTitle(section.title)
    .onAppear {
      model.recordUIAction("section.opened", detail: section.title)
    }
  }
}

private struct PlaceholderPageDetailView: View {
  @EnvironmentObject private var model: GooseAppModel
  let page: PlaceholderPage

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 12) {
          Image(systemName: page.systemImage)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(page.tint)
          Text(page.title)
            .font(.title2.bold())
          Text(page.summary)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
      }

      if let route = page.route {
        Section("APK Route") {
          Text(route)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
        }
      }

      Section("Surface") {
        ForEach(page.items, id: \.self) { item in
          Label(item, systemImage: "checkmark.circle")
        }
      }
    }
    .navigationTitle(page.title)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      model.recordUIAction("placeholder.opened", detail: page.title)
    }
  }
}

private struct PlaceholderSection: Identifiable {
  let id: String
  let title: String
  let systemImage: String
  let tint: Color
  let pages: [PlaceholderPage]

  init(title: String, systemImage: String, tint: Color, pages: [PlaceholderPage]) {
    self.id = title
    self.title = title
    self.systemImage = systemImage
    self.tint = tint
    self.pages = pages
  }
}

private struct PlaceholderPage: Identifiable {
  let id: String
  let title: String
  let route: String?
  let summary: String
  let systemImage: String
  let tint: Color
  let items: [String]

  init(
    title: String,
    route: String? = nil,
    summary: String,
    systemImage: String,
    tint: Color,
    items: [String] = []
  ) {
    self.id = route ?? title
    self.title = title
    self.route = route
    self.summary = summary
    self.systemImage = systemImage
    self.tint = tint
    self.items = items.isEmpty ? ["Mapped from APK UI tree", "Awaiting native data contract"] : items
  }
}

private enum PlaceholderData {
  static let dashboardCards = [
    PlaceholderPage(title: "Sleep", summary: "Sleep score, performance, and coaching", systemImage: "bed.double", tint: .indigo, items: ["Sleep details", "Sleep performance", "Wake schedule"]),
    PlaceholderPage(title: "Recovery", summary: "Readiness, HRV, RHR, and trends", systemImage: "heart.circle", tint: .green, items: ["Recovery score", "HRV", "Resting heart rate"]),
    PlaceholderPage(title: "Strain", summary: "Daily load, activity, and training plan", systemImage: "figure.run", tint: .orange, items: ["Day strain", "Activity list", "Weekly plan"]),
    PlaceholderPage(title: "Stress Monitor", route: "stressMonitorFragment", summary: "Stress graph and session drill-in", systemImage: "waveform.path.ecg", tint: .red, items: ["Stress monitor", "Stress session", "Timeline markers"]),
  ]

  static let setupCards = [
    PlaceholderPage(title: "Tailor Goals", route: "homeCustomizationFragment", summary: "Goal and dashboard customization", systemImage: "slider.horizontal.3", tint: .blue),
    PlaceholderPage(title: "Set Up Sleep", route: "sleepCoachOnboardingFragment", summary: "Sleep coach setup and wake schedule", systemImage: "alarm", tint: .purple),
    PlaceholderPage(title: "Customize Journal", route: "journalFragmentV2", summary: "Journal settings and behavior tracking", systemImage: "book.closed", tint: .brown),
    PlaceholderPage(title: "Integrate Labs", route: "advancedLabsFragment", summary: "Advanced Labs onboarding and results", systemImage: "testtube.2", tint: .teal),
  ]

  static let homeSections = [
    PlaceholderSection(
      title: "Sleep, Recovery, Strain",
      systemImage: "chart.xyaxis.line",
      tint: .green,
      pages: [
        PlaceholderPage(title: "Sleep Details", route: "core_details_sleep_details_fragment", summary: "Sleep stages, performance, and coaching", systemImage: "bed.double", tint: .indigo),
        PlaceholderPage(title: "Core Details", route: "core_details_fragment", summary: "Reusable detail shell for core metrics", systemImage: "chart.bar", tint: .blue),
        PlaceholderPage(title: "Trends", route: "trends_redesign", summary: "Long-range metric trend exploration", systemImage: "chart.line.uptrend.xyaxis", tint: .green),
        PlaceholderPage(title: "Deep Dive", route: "deepDiveFragment", summary: "Metric detail analysis surface", systemImage: "magnifyingglass", tint: .orange),
      ]
    ),
    PlaceholderSection(
      title: "Activity And Training",
      systemImage: "figure.strengthtraining.traditional",
      tint: .orange,
      pages: [
        PlaceholderPage(title: "Start Activity", route: "start_activity_fragment", summary: "Start live activity tracking", systemImage: "play.circle", tint: .green),
        PlaceholderPage(title: "Add Activity", route: "add_activity_fragment", summary: "Manual activity creation", systemImage: "plus.circle", tint: .blue),
        PlaceholderPage(title: "Strength Trainer", route: "strength_trainer_fragment", summary: "Lift tracking and workout plan", systemImage: "dumbbell", tint: .orange),
        PlaceholderPage(title: "Weekly Plan", route: "weeklyPlan", summary: "Training targets and summary", systemImage: "calendar", tint: .purple),
      ]
    ),
    PlaceholderSection(
      title: "Journal And Behaviors",
      systemImage: "book.pages",
      tint: .brown,
      pages: [
        PlaceholderPage(title: "Journal Survey", route: "journalSurveyAnswerFragment", summary: "Daily journal answers", systemImage: "checklist", tint: .brown),
        PlaceholderPage(title: "Behavior Impact", route: "behaviorImpactFragment", summary: "Behavior correlations", systemImage: "point.3.connected.trianglepath.dotted", tint: .teal),
        PlaceholderPage(title: "Log Symptoms", route: "logsymptomsFragment", summary: "Symptom entry flow", systemImage: "cross.case", tint: .red),
      ]
    ),
    PlaceholderSection(
      title: "Calendar And Cycles",
      systemImage: "calendar.badge.clock",
      tint: .pink,
      pages: [
        PlaceholderPage(title: "Log Calendar", route: "logCalendar", summary: "Calendar and cycle logging", systemImage: "calendar", tint: .pink),
        PlaceholderPage(title: "MCI Overview", route: "mciOverview", summary: "Cycle insights overview", systemImage: "moonphase.first.quarter", tint: .purple),
        PlaceholderPage(title: "Pregnancy Insights", route: "pregnancyInsights", summary: "Pregnancy and postpartum insights", systemImage: "heart.text.square", tint: .pink),
      ]
    ),
  ]

  static let healthSections = [
    PlaceholderSection(
      title: "Health Monitor",
      systemImage: "heart.text.square",
      tint: .red,
      pages: [
        PlaceholderPage(title: "Health Landing", route: "healthLandingFragment", summary: "Health tab overview", systemImage: "heart.text.square", tint: .red),
        PlaceholderPage(title: "Health Monitor", route: "composableHealthMonitorFragment", summary: "Vitals and current status", systemImage: "waveform.path.ecg", tint: .green),
        PlaceholderPage(title: "Health Report", route: "healthReportFragment", summary: "Health report summary", systemImage: "doc.text", tint: .blue),
        PlaceholderPage(title: "Healthspan", route: "healthspanFragment", summary: "Long-term health metrics", systemImage: "figure.walk.motion", tint: .orange),
        PlaceholderPage(title: "Heart Screener", route: "heartScreenerFragment", summary: "Heart screening flow", systemImage: "heart.circle", tint: .red),
      ]
    ),
    PlaceholderSection(
      title: "Advanced Labs",
      systemImage: "testtube.2",
      tint: .teal,
      pages: [
        PlaceholderPage(title: "Advanced Labs Home", route: "advancedLabsFragment", summary: "Labs home and enrollment", systemImage: "testtube.2", tint: .teal),
        PlaceholderPage(title: "Biomarker Summary", route: "biomarkerSummaryFragment", summary: "Biomarker overview", systemImage: "list.bullet.clipboard", tint: .blue),
        PlaceholderPage(title: "Test Results", route: "testResultsFragment", summary: "Lab result details", systemImage: "doc.text.magnifyingglass", tint: .green),
        PlaceholderPage(title: "Action Plan", route: "actionPlanFragment", summary: "Recommended follow-up plan", systemImage: "checklist.checked", tint: .orange),
        PlaceholderPage(title: "Clinical Insights", route: "clinicalInsightsFragment", summary: "Clinician-reviewed insights", systemImage: "stethoscope", tint: .red),
      ]
    ),
    PlaceholderSection(
      title: "Programs",
      systemImage: "person.crop.circle.badge.checkmark",
      tint: .purple,
      pages: [
        PlaceholderPage(title: "Shepherd", route: "shepherdOnboarding", summary: "Shepherd onboarding and settings", systemImage: "person.crop.circle.badge.questionmark", tint: .purple),
        PlaceholderPage(title: "Labrador", route: "labradorDetailsFragment", summary: "Labrador device and reading flow", systemImage: "sensor", tint: .orange),
        PlaceholderPage(title: "Sanguine", route: "sanguineFragment", summary: "Sanguine waitlist and biomarkers", systemImage: "drop", tint: .red),
      ]
    ),
  ]

  static let coachSections = [
    PlaceholderSection(
      title: "Coach Surfaces",
      systemImage: "sparkles",
      tint: .purple,
      pages: [
        PlaceholderPage(title: "AI Conversation", route: "whoopBotFragment", summary: "Coach chat conversation", systemImage: "bubble.left.and.bubble.right", tint: .purple),
        PlaceholderPage(title: "AI Insights", route: "aiInsightsFragment", summary: "Generated insight sheet", systemImage: "lightbulb", tint: .yellow),
        PlaceholderPage(title: "Coach Settings", route: "whoopCoachSettingsFragment", summary: "Coach preferences", systemImage: "gearshape", tint: .blue),
        PlaceholderPage(title: "Sleep Coach Wizard", route: "sleepCoachWizardFragment", summary: "Wake-time and sleep plan wizard", systemImage: "alarm", tint: .indigo),
        PlaceholderPage(title: "Sage", route: "sageFragment", summary: "Sage coach route", systemImage: "leaf", tint: .green),
      ]
    ),
  ]

  static let moreSections = [
    PlaceholderSection(
      title: "Account And Settings",
      systemImage: "person.crop.circle",
      tint: .blue,
      pages: [
        PlaceholderPage(title: "My Account", route: "myAccountFragment", summary: "Account details", systemImage: "person.crop.circle", tint: .blue),
        PlaceholderPage(title: "Language Preferences", route: "chooseLanguage", summary: "Language settings", systemImage: "globe", tint: .green),
        PlaceholderPage(title: "Privacy", route: "privacyConsentFragment", summary: "Privacy consent and controls", systemImage: "hand.raised", tint: .purple),
        PlaceholderPage(title: "AI Settings", route: "whoopCoachSettingsFragment", summary: "Coach and AI settings", systemImage: "sparkles", tint: .purple),
      ]
    ),
    PlaceholderSection(
      title: "Device And Activity",
      systemImage: "sensor.tag.radiowaves.forward",
      tint: .green,
      pages: [
        PlaceholderPage(title: "Device Settings", route: "newStrapSettings", summary: "Strap settings", systemImage: "sensor.tag.radiowaves.forward", tint: .green),
        PlaceholderPage(title: "Advanced Strap Settings", route: "newAdvancedStrapSettings", summary: "Advanced strap controls", systemImage: "gearshape.2", tint: .orange),
        PlaceholderPage(title: "Pairing", route: "pairingFragment", summary: "Pair a strap", systemImage: "link", tint: .blue),
        PlaceholderPage(title: "Activity Detection", route: "activityDetectionFragment", summary: "Detection preferences", systemImage: "figure.run", tint: .orange),
        PlaceholderPage(title: "HR Settings", route: "trainingHrSettingsFragment", summary: "Training HR zones", systemImage: "heart", tint: .red),
      ]
    ),
    PlaceholderSection(
      title: "Integrations And Export",
      systemImage: "square.and.arrow.up",
      tint: .teal,
      pages: [
        PlaceholderPage(title: "Integrations", route: "integrationsFragment", summary: "Connected services", systemImage: "point.3.connected.trianglepath.dotted", tint: .teal),
        PlaceholderPage(title: "Notifications", route: "settingsNotificationFragment", summary: "Notification preferences", systemImage: "bell", tint: .orange),
        PlaceholderPage(title: "Export WHOOP Data", route: "memberdataexport_mdeFragment", summary: "Member data export", systemImage: "square.and.arrow.up", tint: .blue),
      ]
    ),
    PlaceholderSection(
      title: "Support And Commerce",
      systemImage: "questionmark.circle",
      tint: .orange,
      pages: [
        PlaceholderPage(title: "Support", route: "help_center", summary: "Help center", systemImage: "questionmark.circle", tint: .orange),
        PlaceholderPage(title: "Tutorials", route: "tutorialsFragment", summary: "Tutorial library", systemImage: "play.rectangle", tint: .red),
        PlaceholderPage(title: "Membership Services", route: "MembershipManagementFragment", summary: "Membership and plan controls", systemImage: "creditcard", tint: .green),
        PlaceholderPage(title: "Gift A Membership", route: "giftHubFragment", summary: "Gift hub and gifting flow", systemImage: "gift", tint: .pink),
        PlaceholderPage(title: "About", route: "aboutFragment", summary: "App information and licenses", systemImage: "info.circle", tint: .blue),
      ]
    ),
    PlaceholderSection(
      title: "Debug",
      systemImage: "ladybug",
      tint: .red,
      pages: [
        PlaceholderPage(title: "Debug", route: "debugFragment", summary: "Internal debug surface", systemImage: "ladybug", tint: .red),
        PlaceholderPage(title: "Feature Flags", route: "featureSettings", summary: "Feature flag settings", systemImage: "flag", tint: .orange),
        PlaceholderPage(title: "Battery Debug", route: "batteryDebugFragment", summary: "Battery diagnostics", systemImage: "battery.100percent", tint: .green),
        PlaceholderPage(title: "Design Showcase", route: "designShowcaseMenuFragment", summary: "Design gallery routes", systemImage: "paintpalette", tint: .purple),
      ]
    ),
  ]
}

private extension View {
  func cardSurface() -> some View {
    background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06))
      }
  }
}

private func firstNumber(in text: String) -> Double? {
  var buffer = ""
  var hasStarted = false

  for character in text {
    if character.isNumber || character == "." || character == "-" {
      buffer.append(character)
      hasStarted = true
      continue
    }
    if hasStarted {
      break
    }
  }

  return Double(buffer)
}
