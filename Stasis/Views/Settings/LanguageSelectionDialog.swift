import AppKit
import Defaults
import SwiftUI

enum AppRestartHelper {
    static func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", url.path]
        try? task.run()

        exit(0)
    }
}

struct LanguageSelectionDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage: AppLanguage
    private let initialLanguage: AppLanguage

    init() {
        let current = Defaults[.appLanguage]
        _selectedLanguage = State(initialValue: current)
        initialLanguage = current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select Display Language")
                        .font(.headline)
                    Text("Stasis will restart to apply the new language setting.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(height: 230)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save and Restart") {
                    saveAndRestart()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedLanguage == initialLanguage)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func saveAndRestart() {
        Defaults[.appLanguage] = selectedLanguage
        if let code = selectedLanguage.code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()

        AppRestartHelper.restartApp()
    }
}
