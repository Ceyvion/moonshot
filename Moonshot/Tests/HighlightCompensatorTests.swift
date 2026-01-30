import XCTest
@testable import Moonshot

final class HighlightCompensatorTests: XCTestCase {
    func testClippedRegionSoftened() {
        let width = 8
        let height = 8
        var luma = [Float](repeating: 0.95, count: width * height)
        let mask = MaskBuffer.filled(width: width, height: height, value: 1.0)

        HighlightCompensator().apply(
            luma: &luma,
            width: width,
            height: height,
            moonMask: mask,
            clipStart: 0.9,
            strength: 0.6
        )

        let maxValue = luma.max() ?? 0
        XCTAssertLessThan(maxValue, 0.95)
    }
}
