import SwiftUI

struct BatteryMainInfo: View {
    let label: String
    let value: String
    let percentage: Int
    let chargeLimit: Int?
    let barColor: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                Spacer(minLength: 20)
                Text(value)
                    .foregroundStyle(.primary)
                    .font(.body)
                    .monospacedDigit()
            }
            ChargeBar(percentage: percentage, chargeLimit: chargeLimit, color: barColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct ChargeBar: View {
    let percentage: Int
    let chargeLimit: Int?
    let color: Color

    private enum Layout {
        static let barHeight: CGFloat = 4
        static let markerWidth: CGFloat = 2
        static let markerHeight: CGFloat = 10
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: Layout.barHeight)
                Capsule()
                    .fill(color)
                    .frame(width: width * fraction(percentage), height: Layout.barHeight)
                    .animation(.snappy, value: percentage)
                if let chargeLimit, chargeLimit < 100 {
                    Capsule()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: Layout.markerWidth, height: Layout.markerHeight)
                        .offset(x: width * fraction(chargeLimit) - Layout.markerWidth / 2)
                }
            }
            .frame(height: Layout.markerHeight)
        }
        .frame(height: Layout.markerHeight)
    }

    private func fraction(_ value: Int) -> CGFloat {
        CGFloat(min(max(value, 0), 100)) / 100
    }
}

struct BatteryAdditionalInfo: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
            Spacer(minLength: 20)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .monospacedDigit()
        }
        .foregroundColor(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

#Preview("Menu Items") {
    VStack(spacing: 0) {
        BatteryMainInfo(label: "Battery", value: 85.formattedPercentage, percentage: 85, chargeLimit: 90, barColor: .green)
        Divider()
        BatteryAdditionalInfo(label: "Battery Percentage", value: 85.formattedPercentage)
        BatteryAdditionalInfo(label: "Time Remaining", value: "02:45")
        BatteryAdditionalInfo(label: "Battery Mode", value: "Discharging")
    }
    .frame(width: 300)
    .background(Color(NSColor.controlBackgroundColor))
}
