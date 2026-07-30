import Foundation

enum PercentageFormatter {
    /// Formats an integer representing a percentage (e.g. 50 for 50%) into a locale-aware percentage string (e.g. "50%").
    /// Uses Foundation's .percent format style to avoid hardcoding '%' and prevent Xcode String Catalog localization warnings.
    nonisolated static func string(from percentage: Int) -> String {
        (Double(percentage) / 100.0).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Formats a double representing a 0.0–1.0 ratio (e.g. 0.50) into a locale-aware percentage string (e.g. "50%").
    /// Uses Foundation's .percent format style to avoid hardcoding '%' and prevent Xcode String Catalog localization warnings.
    nonisolated static func string(from ratio: Double) -> String {
        ratio.formatted(.percent.precision(.fractionLength(0)))
    }
}

extension Int {
    /// Helper to cleanly interpolate percentages in localized string literals without triggering Xcode percentage formatting warnings.
    nonisolated var formattedPercentage: String {
        PercentageFormatter.string(from: self)
    }
}

extension Double {
    /// Helper to cleanly interpolate ratio percentages in localized string literals without triggering Xcode percentage formatting warnings.
    nonisolated var formattedPercentage: String {
        PercentageFormatter.string(from: self)
    }
}
