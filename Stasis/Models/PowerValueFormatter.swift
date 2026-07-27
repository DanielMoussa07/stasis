import Foundation

enum PowerValueFormatter {
    static func string(
        from watts: Double,
        showTwoDecimalPlaces: Bool
    ) -> String {
        let fractionLength = showTwoDecimalPlaces ? 2 : 0
        return abs(watts).formatted(
            .number.precision(.fractionLength(fractionLength))
        )
    }
}
