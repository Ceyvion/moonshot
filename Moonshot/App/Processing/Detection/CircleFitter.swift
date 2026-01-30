import Foundation
import CoreGraphics
import Accelerate

/// Fits circles to edge points using Taubin's algebraic method
final class CircleFitter {

    /// Minimum number of points required for fitting
    private let minPoints = 5

    /// Fit a circle to the given edge points using Taubin's method.
    /// Returns nil if fitting fails or there are too few points.
    func fit(edgePoints: [CGPoint]) -> FittedCircle? {
        guard edgePoints.count >= minPoints else { return nil }

        // Taubin's algebraic circle fit
        // Minimizes the algebraic distance with a constraint that normalizes the fit

        let n = edgePoints.count

        // Compute mean for centering
        var meanX: CGFloat = 0
        var meanY: CGFloat = 0
        for point in edgePoints {
            meanX += point.x
            meanY += point.y
        }
        meanX /= CGFloat(n)
        meanY /= CGFloat(n)

        // Center the points
        var u = [CGFloat](repeating: 0, count: n)
        var v = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            u[i] = edgePoints[i].x - meanX
            v[i] = edgePoints[i].y - meanY
        }

        // Compute moments
        var Suu: CGFloat = 0, Suv: CGFloat = 0, Svv: CGFloat = 0
        var Suuu: CGFloat = 0, Svvv: CGFloat = 0, Suvv: CGFloat = 0, Svuu: CGFloat = 0

        for i in 0..<n {
            let ui = u[i]
            let vi = v[i]
            let ui2 = ui * ui
            let vi2 = vi * vi

            Suu += ui2
            Suv += ui * vi
            Svv += vi2
            Suuu += ui2 * ui
            Svvv += vi2 * vi
            Suvv += ui * vi2
            Svuu += vi * ui2
        }

        // Solve the system
        // This is the Taubin method which solves a constrained optimization problem

        let A = CGFloat(n) * Suu - Suu
        let B = CGFloat(n) * Suv
        let C = (Suuu + Suvv) / 2.0
        let D = CGFloat(n) * Suv
        let E = CGFloat(n) * Svv - Svv
        let F = (Svvv + Svuu) / 2.0

        let denominator = A * E - B * D

        guard abs(denominator) > 1e-10 else {
            // Degenerate case - try simpler method
            return fitSimple(edgePoints: edgePoints)
        }

        let uc = (C * E - B * F) / denominator
        let vc = (A * F - C * D) / denominator

        // Convert back to original coordinates
        let centerX = uc + meanX
        let centerY = vc + meanY

        // Compute radius
        var sumR: CGFloat = 0
        for point in edgePoints {
            let dx = point.x - centerX
            let dy = point.y - centerY
            sumR += sqrt(dx * dx + dy * dy)
        }
        let radius = sumR / CGFloat(n)

        // Compute residual error (RMS)
        var sumSqError: CGFloat = 0
        for point in edgePoints {
            let dx = point.x - centerX
            let dy = point.y - centerY
            let r = sqrt(dx * dx + dy * dy)
            let error = r - radius
            sumSqError += error * error
        }
        let residualError = sqrt(sumSqError / CGFloat(n))

        // Validate result
        guard radius > 0 && !radius.isNaN && !centerX.isNaN && !centerY.isNaN else {
            return fitSimple(edgePoints: edgePoints)
        }

        return FittedCircle(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius,
            residualError: residualError
        )
    }

    /// Simple least-squares circle fit (fallback)
    private func fitSimple(edgePoints: [CGPoint]) -> FittedCircle? {
        guard edgePoints.count >= minPoints else { return nil }

        let n = edgePoints.count

        // Compute centroid as initial center estimate
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for point in edgePoints {
            sumX += point.x
            sumY += point.y
        }
        let centerX = sumX / CGFloat(n)
        let centerY = sumY / CGFloat(n)

        // Compute average radius
        var sumR: CGFloat = 0
        for point in edgePoints {
            let dx = point.x - centerX
            let dy = point.y - centerY
            sumR += sqrt(dx * dx + dy * dy)
        }
        let radius = sumR / CGFloat(n)

        // Compute residual
        var sumSqError: CGFloat = 0
        for point in edgePoints {
            let dx = point.x - centerX
            let dy = point.y - centerY
            let r = sqrt(dx * dx + dy * dy)
            sumSqError += (r - radius) * (r - radius)
        }
        let residualError = sqrt(sumSqError / CGFloat(n))

        guard radius > 0 else { return nil }

        return FittedCircle(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius,
            residualError: residualError
        )
    }

    /// RANSAC-based fitting for robust outlier rejection
    func fitRANSAC(edgePoints: [CGPoint], iterations: Int = 100, inlierThreshold: CGFloat = 2.0) -> FittedCircle? {
        guard edgePoints.count >= minPoints else { return nil }

        var bestCircle: FittedCircle?
        var bestInlierCount = 0

        for _ in 0..<iterations {
            // Randomly sample 3 points
            var sample = [CGPoint]()
            var indices = Set<Int>()

            while sample.count < 3 {
                let idx = Int.random(in: 0..<edgePoints.count)
                if !indices.contains(idx) {
                    indices.insert(idx)
                    sample.append(edgePoints[idx])
                }
            }

            // Fit circle to sample
            guard let circle = fitThreePoints(sample[0], sample[1], sample[2]) else {
                continue
            }

            // Count inliers
            var inlierCount = 0
            for point in edgePoints {
                let dx = point.x - circle.center.x
                let dy = point.y - circle.center.y
                let dist = abs(sqrt(dx * dx + dy * dy) - circle.radius)
                if dist < inlierThreshold {
                    inlierCount += 1
                }
            }

            if inlierCount > bestInlierCount {
                bestInlierCount = inlierCount
                bestCircle = circle
            }
        }

        // Refit using all inliers
        if let circle = bestCircle {
            var inliers = [CGPoint]()
            for point in edgePoints {
                let dx = point.x - circle.center.x
                let dy = point.y - circle.center.y
                let dist = abs(sqrt(dx * dx + dy * dy) - circle.radius)
                if dist < inlierThreshold {
                    inliers.append(point)
                }
            }

            if inliers.count >= minPoints {
                return fit(edgePoints: inliers)
            }
        }

        return bestCircle
    }

    /// Fit circle through exactly 3 points
    private func fitThreePoints(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> FittedCircle? {
        let ax = p1.x, ay = p1.y
        let bx = p2.x, by = p2.y
        let cx = p3.x, cy = p3.y

        let d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
        guard abs(d) > 1e-10 else { return nil }

        let ax2 = ax * ax, ay2 = ay * ay
        let bx2 = bx * bx, by2 = by * by
        let cx2 = cx * cx, cy2 = cy * cy

        let ux = ((ax2 + ay2) * (by - cy) + (bx2 + by2) * (cy - ay) + (cx2 + cy2) * (ay - by)) / d
        let uy = ((ax2 + ay2) * (cx - bx) + (bx2 + by2) * (ax - cx) + (cx2 + cy2) * (bx - ax)) / d

        let center = CGPoint(x: ux, y: uy)
        let radius = sqrt((ax - ux) * (ax - ux) + (ay - uy) * (ay - uy))

        guard radius > 0 && !radius.isNaN else { return nil }

        return FittedCircle(center: center, radius: radius, residualError: 0)
    }
}
