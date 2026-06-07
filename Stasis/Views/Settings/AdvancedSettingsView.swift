import Defaults
import SwiftUI

struct AdvancedSettingsView: View {
    @Default(.useHardwarePercentage) var useHardwarePercentage
    @Default(.useRawHardwareHealth) var useRawHardwareHealth
    @Default(.showAdvancedChargingControls) var showAdvancedChargingControls

    var body: some View {
        Form {
            Section {
                Toggle("Use hardware percentage", isOn: $useHardwarePercentage)
                Toggle(
                    "Use raw hardware health",
                    isOn: $useRawHardwareHealth
                )
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery Reading")
                    Text(
                        "Use the raw battery percentage instead of the macOS calibrated value."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Menu Controls") {
                Toggle("Show manual charging controls", isOn: $showAdvancedChargingControls)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollEdgeEffectStyleSoftIfAvailable()
    }
}

#Preview {
    AdvancedSettingsView()
}
