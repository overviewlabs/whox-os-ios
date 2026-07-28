import Foundation

public enum AudioMeter {
    /// Maps linear RMS input to a stable 0...1 visual level with useful speech sensitivity.
    public static func level(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let clamped = min(max(Double(rms), 0), 1)
        let decibels = 20 * log10(clamped)
        return min(max((decibels + 60) / 60, 0), 1)
    }
}
