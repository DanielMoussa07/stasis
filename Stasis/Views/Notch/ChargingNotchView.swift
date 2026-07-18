import SwiftUI
import Observation

@MainActor
@Observable
class NotchHUDState {
    var isVisible: Bool = false
    var statusText: String = ""
    var batteryLevel: Int = 0
    var chargingMode: ChargingMode = .discharging
    var isLowPowerModeEnabled: Bool = false

    // Dynamic metrics for an asymmetric pill that wraps perfectly tightly around content
    // but uses a visual offset to keep the physical hardware notch dead center
    
    var leftContentWidth: CGFloat {
        if !isVisible { return 0 }
        // 16pt outer padding + text width + 16pt inner padding
        let textWidth = CGFloat(statusText.count) * 7.5
        return 16 + textWidth + 16
    }
    
    var rightContentWidth: CGFloat {
        if !isVisible { return 0 }
        // 16pt inner padding + battery icon + 16pt outer padding
        return 16 + 60 + 16 // battery is around 60 wide
    }

    var dynamicWidth: CGFloat {
        if !isVisible { return 180 }
        return leftContentWidth + 180 + rightContentWidth
    }
    
    var correctionOffset: CGFloat {
        if !isVisible { return 0 }
        // Math to keep the 180 gap perfectly centered on screen despite an asymmetrical shape
        return (rightContentWidth - leftContentWidth) / 2
    }
}

struct ChargingNotchView: View {
    var state: NotchHUDState

    var body: some View {
        HStack(spacing: 0) {
            // LEFT SIDE: Text
            Text(state.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white) // Always dark theme
                .fixedSize(horizontal: true, vertical: false) // Prevent truncation during animation
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                .frame(width: state.isVisible ? state.leftContentWidth : 0)
                .clipped()

            // CENTER: The physical notch width
            Spacer()
                .frame(width: 180) 

            // RIGHT SIDE: Battery
            BatteryIndicatorView(
                batteryLevel: state.batteryLevel,
                chargingMode: state.chargingMode,
                isLowPowerModeEnabled: state.isLowPowerModeEnabled,
                batteryPercentageVisibility: .nextToIcon,
                showState: true
            )
            .colorScheme(.dark) // Always dark theme
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .frame(width: state.isVisible ? state.rightContentWidth : 0)
            .clipped()
        }
        // Use dynamically calculated asymmetric width that perfectly wraps content
        .frame(width: state.dynamicWidth)
        .frame(maxHeight: .infinity)
        // Background and clip shape MUST be applied BEFORE offset so they perfectly wrap the asymmetric content
        .background(NotchShape().fill(.black))
        .clipShape(NotchShape())
        // Offset the entire capsule so the 180 gap remains perfectly dead center on the physical hardware notch
        .offset(x: state.correctionOffset)
        // Improved bouncy spring animation (response: 0.4, dampingFraction: 0.6)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: state.isVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
