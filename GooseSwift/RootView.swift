import SwiftUI

struct RootView: View {
  @EnvironmentObject private var model: GooseAppModel
  @AppStorage("goose.swift.onboardingComplete") private var onboardingComplete = false

  var body: some View {
    ZStack(alignment: .top) {
      Group {
        if onboardingComplete {
          AppShellView()
        } else {
          OnboardingView {
            onboardingComplete = true
            model.completeOnboarding()
          }
        }
      }
      SyncToastHost(ble: model.ble)
    }
    .onAppear(perform: syncModelOnboardingState)
    .onChange(of: onboardingComplete) { _, _ in
      syncModelOnboardingState()
    }
  }

  private func syncModelOnboardingState() {
    guard model.onboardingComplete != onboardingComplete else {
      return
    }
    model.onboardingComplete = onboardingComplete
  }
}

private struct SyncToastHost: View {
  @ObservedObject var ble: GooseBLEClient

  var body: some View {
    VStack {
      if let toast = ble.syncToast {
        Button {
          if toast.phase == .failed, let failure = ble.lastSyncFailure {
            ble.syncFailureSheet = failure
          }
        } label: {
          SyncStatusToastView(toast: toast)
        }
        .buttonStyle(.plain)
        .disabled(toast.phase != .failed)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .transition(.asymmetric(
          insertion: .move(edge: .top).combined(with: .opacity),
          removal: .move(edge: .top).combined(with: .opacity)
        ))
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .allowsHitTesting(ble.syncToast?.phase == .failed)
    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: ble.syncToast?.id)
    .sheet(item: $ble.syncFailureSheet) { failure in
      SyncFailureSheet(failure: failure)
    }
  }
}

private struct SyncStatusToastView: View {
  let toast: GooseSyncToast

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .black))
        .symbolEffect(.rotate, options: .repeating, value: toast.phase == .syncing)
        .frame(width: 18, height: 18)
        .foregroundStyle(tint)

      Text(toast.title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.primary)
        .lineLimit(1)

      if toast.phase == .failed {
        Image(systemName: "chevron.up")
          .font(.system(size: 12, weight: .black))
          .foregroundStyle(tint)
      }
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 8)
    .fixedSize(horizontal: true, vertical: false)
    .background {
      Capsule(style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay {
          Capsule(style: .continuous)
            .fill(tint.opacity(0.11))
        }
    }
    .overlay {
      Capsule(style: .continuous)
        .strokeBorder(tint.opacity(0.72), lineWidth: 1.4)
    }
    .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 7)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var systemImage: String {
    switch toast.phase {
    case .syncing: "arrow.triangle.2.circlepath"
    case .synced: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    }
  }

  private var tint: Color {
    switch toast.phase {
    case .syncing: Color(red: 0.18, green: 0.48, blue: 0.95)
    case .synced: Color(red: 0.20, green: 0.68, blue: 0.27)
    case .failed: Color(red: 0.95, green: 0.23, blue: 0.18)
    }
  }

  private var accessibilityText: String {
    guard !toast.detail.isEmpty else {
      return toast.title
    }
    return "\(toast.title), \(toast.detail)"
  }
}

private struct SyncFailureSheet: View {
  let failure: GooseSyncFailure
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text(failure.title)
              .font(.title2.bold())
            Text(failure.occurredAt, style: .date)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
          }

          Text(failure.message)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(20)
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Sync Error")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}
