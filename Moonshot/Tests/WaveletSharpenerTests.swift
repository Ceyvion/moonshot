import XCTest
@testable import Moonshot

final class WaveletSharpenerTests: XCTestCase {
    func testMaxLumaStopsSharpeningInHighlights() {
        let width = 8
        let height = 8
        var luma = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                luma[y * width + x] = x < width / 2 ? 0.4 : 0.7
            }
        }

        let original = luma
        let confidence = MaskBuffer.filled(width: width, height: height, value: 1.0)
        let limb = MaskBuffer.empty(width: width, height: height)

        let params = PresetConfiguration.WaveletParameters(
            fineGain: 0.3,
            midGain: 0.2,
            coarseGain: 0.1,
            cExponent: 1.0,
            limbMultiplier: 1.0,
            minSNR: 0.0,
            maxLuma: 0.6,
            maxLumaFade: 0.05
        )

        WaveletSharpener().apply(
            luma: &luma,
            width: width,
            height: height,
            params: params,
            confidence: confidence,
            snrMap: nil,
            limbRing: limb
        )

        let highlightIndex = 4 * width + 6
        XCTAssertEqual(luma[highlightIndex], original[highlightIndex], accuracy: 1e-6)

        let edgeIndex = 4 * width + 3
        XCTAssertNotEqual(luma[edgeIndex], original[edgeIndex])
    }
}
