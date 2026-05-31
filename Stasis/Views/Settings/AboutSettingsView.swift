import Defaults
import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Default(.automaticallyCheckForUpdates) var automaticallyCheckForUpdates
    @Default(.updateCheckInterval) var updateCheckInterval
    @Default(.updateAutomationMode) var updateAutomationMode
    @State private var showResetSuccessAlert = false

    private let updaterService: UpdaterService

    init(updaterService: UpdaterService) {
        self.updaterService = updaterService
    }

    var body: some View {
        Form {
            Section("About Stasis") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stasis")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Battery and charging control for MacBook.")
                        .foregroundStyle(.secondary)

                    if let versionText {
                        Text(versionText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Developer") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dinanath Dash")
                        .fontWeight(.medium)
                    Text(
                        "Originally forked from an open-source base, then developed further with new features."
                    )
                    .foregroundStyle(.secondary)
                    Text(
                        "Built with a focus on practical battery health and charging workflows."
                    )
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("Community") {
                HStack(spacing: 16) {
                    Button {
                        openURL(
                            URL(
                                string:
                                    "https://github.com/DinanathDash/Stasis/issues/new?template=bug_report.yml"
                            )!
                        )
                    } label: {
                        Label("Report a bug", systemImage: "ant")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openURL(
                            URL(
                                string:
                                    "https://github.com/DinanathDash/Stasis/issues/new?template=feature_request.yml"
                            )!
                        )
                    } label: {
                        Label("Request a feature", systemImage: "lightbulb")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openURL(
                            URL(
                                string: "https://github.com/DinanathDash/Stasis"
                            )!
                        )
                    } label: {
                        Label {
                            Text("View on GitHub")
                        } icon: {
                            Image("GitHubMark")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Toggle(
                    "Automatically check for updates",
                    isOn: $automaticallyCheckForUpdates
                )

                Picker("Check frequency", selection: $updateCheckInterval) {
                    Text("At start").tag(
                        UpdaterService.UpdateCheckInterval.atStart
                    )
                    Divider()
                    Text("Once per day").tag(
                        UpdaterService.UpdateCheckInterval.daily
                    )
                    Text("Once per week").tag(
                        UpdaterService.UpdateCheckInterval.weekly
                    )
                    Text("Once per month").tag(
                        UpdaterService.UpdateCheckInterval.monthly
                    )
                }
                .disabled(!automaticallyCheckForUpdates)
                .onChange(of: updateCheckInterval) { _, _ in
                    updaterService.startIfAvailable()
                }

                Picker(
                    "When updates are found",
                    selection: $updateAutomationMode
                ) {
                    Text("Notify only").tag(
                        UpdaterService.UpdateAutomationMode.notify
                    )
                    Text("Auto-download to Downloads folder").tag(
                        UpdaterService.UpdateAutomationMode.autoDownload
                    )
                }
                .disabled(!automaticallyCheckForUpdates)

                Button("Check for updates now") {
                    updaterService.checkForUpdates()
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates")
                    Text(
                        "Stasis can check and download updates to your Downloads folder."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text("Reset all preferences")
                    Spacer()
                    Button("Reset") {
                        resetAllPreferences()
                        showResetSuccessAlert = true  // Trigger the alert
                    }
                    .foregroundColor(.red)
                }
            } header: {
                Text("Reset Preferences")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
        .alert("Preferences Reset", isPresented: $showResetSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "All preferences have been successfully restored to their defaults."
            )
        }
        .onChange(of: automaticallyCheckForUpdates) { _, _ in
            updaterService.startIfAvailable()
        }
    }

    private var versionText: String? {
        guard
            let shortVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        else {
            return nil
        }

        return "Version \(shortVersion)"
    }

    // MARK: - Preferences reset helper
    private func resetAllPreferences() {
        // Uninstall the helper daemon
        do {
            try ChargingHelperManager.shared.uninstall()
        } catch {
            print("Failed to uninstall charging helper: \(error)")
        }

        // Disable launch at login
        LaunchAtLoginService.shared.setLaunchAtLogin(false)

        // Remove all persisted defaults for this app bundle
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dinanathdash.stasis"
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
    }
}

#Preview {
    AboutSettingsView(updaterService: UpdaterService.shared)
}
