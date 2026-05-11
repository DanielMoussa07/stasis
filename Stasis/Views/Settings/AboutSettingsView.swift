import Defaults
import SwiftUI

struct AboutSettingsView: View {
    @Default(.automaticallyCheckForUpdates) var automaticallyCheckForUpdates
    @Default(.updateAutomationMode) var updateAutomationMode

    @State private var updateStatusMessage: String?

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
                    Text("Originally forked from an open-source base, then developed further with new features.")
                        .foregroundStyle(.secondary)
                    Text("Built with a focus on practical battery health and charging workflows.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section {
                Toggle("Automatically check for updates", isOn: $automaticallyCheckForUpdates)

                Picker("When updates are found", selection: $updateAutomationMode) {
                    Text("Notify only").tag(UpdaterService.UpdateAutomationMode.notify)
                    Text("Auto-download, ask to install").tag(UpdaterService.UpdateAutomationMode.autoDownload)
                    Text("Auto-download and auto-install").tag(UpdaterService.UpdateAutomationMode.autoInstall)
                }
                .disabled(!automaticallyCheckForUpdates)

                Button("Check for updates now") {
                    updaterService.checkForUpdates()
                    if updaterService.updaterAvailable {
                        updateStatusMessage = "Update check started for this build."
                    } else {
                        updateStatusMessage = "Updater framework is not linked in this build yet."
                    }
                }

                if let updateStatusMessage {
                    Text(updateStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates")
                    Text("Stasis can check, download, and install updates based on your preference.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("macOS security prompts and Gatekeeper rules still apply. Stasis will not bypass system security.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0)
        .onChange(of: automaticallyCheckForUpdates) { _, _ in
            updaterService.applyPreferencesToSystemDefaults()
        }
        .onChange(of: updateAutomationMode) { _, _ in
            updaterService.applyPreferencesToSystemDefaults()
        }
    }

    private var versionText: String? {
        guard
            let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return nil
        }

        return "Version \(shortVersion) (\(build))"
    }
}

#Preview {
    AboutSettingsView(updaterService: UpdaterService.shared)
}
