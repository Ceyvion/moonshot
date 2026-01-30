import Foundation

/// Parameters used for processing, stored with results for reproducibility.
struct ProcessingParameters: Hashable, Codable {
    let preset: EnhancementPreset
    let strength: Float
    let timestamp: Date

    init(preset: EnhancementPreset, strength: Float) {
        self.preset = preset
        self.strength = strength
        self.timestamp = Date()
    }
}

/// Enhancement preset selection
enum EnhancementPreset: String, CaseIterable, Hashable, Codable {
    case natural
    case crisp

    var displayName: String {
        switch self {
        case .natural: return "Natural"
        case .crisp: return "Crisp"
        }
    }

    var description: String {
        switch self {
        case .natural:
            return "Subtle enhancement that preserves the original character"
        case .crisp:
            return "Stronger detail with careful artifact prevention"
        }
    }
}

/// Capture quality assessment
enum CaptureQuality: String, Codable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Compute from median confidence and other metrics
    static func from(medianConfidence: Float, clippedFraction: Float, sharpnessScore: Float) -> CaptureQuality {
        // Penalize clipped highlights heavily
        let clippingPenalty: Float = clippedFraction > 0.01 ? 0.3 : (clippedFraction > 0.003 ? 0.15 : 0)

        let score = (medianConfidence * 0.5 + sharpnessScore * 0.5) - clippingPenalty

        if score > 0.6 {
            return .high
        } else if score > 0.35 {
            return .medium
        } else {
            return .low
        }
    }
}
