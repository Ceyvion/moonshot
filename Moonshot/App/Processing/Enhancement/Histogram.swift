import Foundation

/// Histogram-based percentiles for normalized [0,1] data.
enum Histogram {
    static func percentile(
        values: [Float],
        mask: MaskBuffer? = nil,
        percentile: Float,
        bins: Int = 1024
    ) -> Float {
        guard !values.isEmpty, bins > 1 else { return 0 }
        let clampedP = min(1, max(0, percentile))

        var histogram = [Int](repeating: 0, count: bins)
        var total = 0

        if let mask, mask.data.count == values.count {
            for i in 0..<values.count {
                if mask.data[i] <= 0.5 { continue }
                let v = min(1, max(0, values[i]))
                let bin = min(bins - 1, max(0, Int(v * Float(bins - 1))))
                histogram[bin] += 1
                total += 1
            }
        } else {
            for v in values {
                let clamped = min(1, max(0, v))
                let bin = min(bins - 1, max(0, Int(clamped * Float(bins - 1))))
                histogram[bin] += 1
                total += 1
            }
        }

        guard total > 0 else { return 0 }
        let targetIndex = Int(Float(total - 1) * clampedP)

        var cumulative = 0
        for i in 0..<bins {
            cumulative += histogram[i]
            if cumulative - 1 >= targetIndex {
                return Float(i) / Float(bins - 1)
            }
        }

        return 1
    }

    static func median(values: [Float], mask: MaskBuffer? = nil, bins: Int = 1024) -> Float {
        return percentile(values: values, mask: mask, percentile: 0.5, bins: bins)
    }
}
