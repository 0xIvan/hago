import AppKit
import HagoCore
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: WorkProfileStore
    @State private var hasChrome = false
    @State private var showsWorkSites = false
    @State private var error: String?

    private static let stepTitles = ["Allow access", "Your role", "Your work", "Ready"]

    private var step: Int {
        min(profileStore.profile.step, Self.stepTitles.count - 1)
    }

    private var isLastStep: Bool {
        step == Self.stepTitles.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            stepper.padding(.top, 20)
            ScrollView {
                Group {
                    switch step {
                    case 0: accessStep
                    case 1: roleStep
                    case 2: workStep
                    default: readyStep
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
                .padding(.vertical, 24)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 10)
            }
            Divider()
            buttonBar
        }
        .frame(width: 560, height: 560)
        .onAppear {
            hasChrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil
            showsWorkSites = !profileStore.profile.workDomains.isEmpty
            appState.refreshLoginItemStatus()
        }
    }

    private var stepper: some View {
        HStack(spacing: 8) {
            ForEach(Self.stepTitles.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(index <= step ? Color.accentColor : Color.primary.opacity(0.08))
                        if index < step {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(index == step ? Color.white : Color.secondary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(Self.stepTitles[index])
                        .font(.caption.weight(index == step ? .semibold : .regular))
                        .foregroundStyle(index == step ? .primary : .secondary)
                }
                if index < Self.stepTitles.count - 1 {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 28, height: 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of \(Self.stepTitles.count): \(Self.stepTitles[step])")
    }

    private var buttonBar: some View {
        HStack {
            if !isLastStep {
                Button("Set Up Later") { profileStore.needsSetup = false }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if step > 0 {
                Button("Back") {
                    error = nil
                    profileStore.profile.step = step - 1
                }
                .keyboardShortcut(.cancelAction)
            }
            Button(isLastStep ? "Open Hago" : "Continue") { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func advance() {
        do {
            if step == 1 || step == 2 { try appState.applyWorkProfile(&profileStore.profile) }
            if isLastStep {
                profileStore.finish()
                appState.selectedSection = .overview
            } else {
                profileStore.profile.step = step + 1
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func heading(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420)
        .padding(.bottom, 18)
    }

    private var accessStep: some View {
        VStack(spacing: 0) {
            heading(
                "lock.shield",
                "Let Hago see what you’re working on",
                "Everything stays on this Mac. Hago records which app, window and site is in front. It never records what you type or what’s on screen."
            )
            OnboardingCard {
                permissionRow(
                    symbol: "macwindow",
                    title: "Window titles",
                    detail: "Tell documents and projects apart",
                    isGranted: appState.accessibilityTrusted
                ) {
                    Button(appState.accessibilityRequest == .notRequested ? "Allow…" : "Open Settings…") {
                        appState.requestAccessibilityPermission()
                    }
                }
                if !appState.accessibilityTrusted, appState.accessibilityRequest == .stillOffAfterSettings {
                    HStack(spacing: 8) {
                        Text("Already turned on? Reopen Hago to apply it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reopen Hago") { appState.relaunch() }
                            .controlSize(.small)
                            .disabled(appState.isRelaunching)
                    }
                    .padding(.leading, 42)
                    .padding(.bottom, 10)
                }
                if hasChrome {
                    Divider().padding(.leading, 42)
                    permissionRow(
                        symbol: "globe",
                        title: "Chrome tabs",
                        detail: "Tell work sites from personal ones",
                        isGranted: appState.chromeAutomationGranted
                    ) {
                        if appState.chromePermissionRequestPending {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Allow…") { appState.requestChromeAccess() }
                        }
                    }
                }
                Divider().padding(.leading, 42)
                loginRow
            }
            Text("Hago works without these, but more activity will need your review.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
        .task {
            // System Settings changes the grant outside Hago; poll while this step is visible.
            while !Task.isCancelled, !appState.accessibilityTrusted {
                appState.refreshAccessibilityTrust()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var loginRow: some View {
        HStack(spacing: 12) {
            OnboardingRowIcon(symbol: "power")
            VStack(alignment: .leading, spacing: 2) {
                Text("Open at login")
                if appState.loginItemStatus == .requiresApproval {
                    Button("Allow in System Settings…") { appState.openLoginItemSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                } else if let loginError = appState.loginItemError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                } else {
                    Text("So no day goes untracked").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Open at login", isOn: Binding(
                get: { appState.loginItemStatus == .enabled || appState.loginItemStatus == .requiresApproval },
                set: { appState.setOpenAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 10)
    }

    private func permissionRow<Action: View>(
        symbol: String,
        title: String,
        detail: String,
        isGranted: Bool,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 12) {
            OnboardingRowIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                action()
            }
        }
        .padding(.vertical, 10)
    }

    private var roleStep: some View {
        VStack(spacing: 0) {
            heading(
                "person.crop.rectangle",
                "What do you do?",
                "Hago turns on starter rules for your field and files common personal sites, so most of your day sorts itself. Untick anything that doesn’t fit."
            )
            OnboardingCard {
                StarterPackPicker().padding(.vertical, 12)
            }
            Text("Your profession also guides AI suggestions if you turn them on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
    }

    private var workStep: some View {
        VStack(spacing: 0) {
            heading(
                "briefcase",
                "What else counts as work?",
                "Add apps and sites you only use for work. Anything Hago isn’t sure about goes to Needs review, and you can teach it from there."
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("Apps you only use for work")
                    .font(.subheadline.weight(.semibold))
                WorkAppSelectionView(selectedIDs: $profileStore.profile.workApps)
            }
            if showsWorkSites {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Work-only websites")
                        .font(.subheadline.weight(.semibold))
                    TextField("company.slack.com, one per line", text: $profileStore.profile.workDomains, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, 16)
            } else {
                Button {
                    showsWorkSites = true
                } label: {
                    Label("Add work-only websites", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 0) {
            heading(
                "checkmark.circle",
                "Hago is tracking",
                "It lives in your menu bar: work time today, then everything tracked today. Open Hago for the details."
            )
            HStack(spacing: 4) {
                if let glyph = StatusBarController.activityTraceImage() {
                    Image(nsImage: glyph)
                }
                Text(appState.menuBarTitle)
                    .font(Font(NSFont.menuBarFont(ofSize: 0)))
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(appState.menuBarAccessibilityLabel)
            .padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 14) {
                tip(
                    "tray",
                    "Sort what Hago isn’t sure about",
                    "Needs review collects unclear activity. One click files it; Remember turns it into a rule."
                )
                tip(
                    "arrow.uturn.backward",
                    "Fix mistakes any time",
                    "Sleep, lock and pause stop tracking. If you left your Mac unlocked, remove that time in Activity."
                )
                VStack(alignment: .leading, spacing: 4) {
                    tip("sparkles", "AI suggestions are optional", "Connect a provider to suggest how to file Needs review.")
                    Button("AI Settings…") {
                        profileStore.finish()
                        appState.openHagoWindow(section: .aiReview)
                    }
                    .buttonStyle(.link)
                    .padding(.leading, 32)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SetupReminderCard: View {
    var resume: () -> Void

    var body: some View {
        Button(action: resume) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Finish setting up Hago").font(.callout.weight(.semibold))
                    Text("Tell Hago what counts as work").font(.caption).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(11)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct OnboardingRowIcon: View {
    var symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}
