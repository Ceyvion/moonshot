import Foundation
import CoreGraphics

/// Analyzes binary masks to find connected components (blobs)
final class ConnectedComponentsAnalyzer {

    /// Find blobs in binary mask using two-pass connected component labeling
    func findBlobs(in mask: BinaryMask, minArea: Int, maxArea: Int) -> [BlobInfo] {
        let width = mask.width
        let height = mask.height

        // First pass: assign preliminary labels
        var labels = [Int](repeating: 0, count: width * height)
        var equivalences = UnionFind()
        var nextLabel = 1

        for y in 0..<height {
            for x in 0..<width {
                guard mask.value(at: x, y: y) else { continue }

                let idx = y * width + x

                // Check neighbors (4-connectivity)
                let leftLabel = x > 0 && mask.value(at: x - 1, y: y) ? labels[idx - 1] : 0
                let topLabel = y > 0 && mask.value(at: x, y: y - 1) ? labels[idx - width] : 0

                if leftLabel == 0 && topLabel == 0 {
                    // New label
                    labels[idx] = nextLabel
                    equivalences.makeSet(nextLabel)
                    nextLabel += 1
                } else if leftLabel != 0 && topLabel == 0 {
                    labels[idx] = leftLabel
                } else if leftLabel == 0 && topLabel != 0 {
                    labels[idx] = topLabel
                } else {
                    // Both neighbors labeled - use minimum and union
                    labels[idx] = min(leftLabel, topLabel)
                    equivalences.union(leftLabel, topLabel)
                }
            }
        }

        // Second pass: resolve equivalences
        for i in 0..<labels.count {
            if labels[i] > 0 {
                labels[i] = equivalences.find(labels[i])
            }
        }

        // Collect blob statistics
        var blobStats: [Int: BlobStats] = [:]

        for y in 0..<height {
            for x in 0..<width {
                let label = labels[y * width + x]
                guard label > 0 else { continue }

                if blobStats[label] == nil {
                    blobStats[label] = BlobStats()
                }

                blobStats[label]!.addPixel(x: x, y: y)

                // Check if this is an edge pixel
                let isEdge = !mask.value(at: x - 1, y: y) ||
                            !mask.value(at: x + 1, y: y) ||
                            !mask.value(at: x, y: y - 1) ||
                            !mask.value(at: x, y: y + 1)

                if isEdge {
                    blobStats[label]!.addEdgePixel(x: x, y: y)
                }
            }
        }

        // Convert to BlobInfo array
        var blobs: [BlobInfo] = []

        for (_, stats) in blobStats {
            let area = stats.area
            guard area >= minArea && area <= maxArea else { continue }

            let centroid = stats.centroid
            let boundingBox = stats.boundingBox
            let perimeter = stats.perimeter

            // Circularity = 4 * pi * area / perimeter^2
            let circularity = perimeter > 0 ? (4.0 * Float.pi * Float(area)) / (Float(perimeter) * Float(perimeter)) : 0

            blobs.append(BlobInfo(
                boundingBox: boundingBox,
                area: area,
                centroid: centroid,
                circularity: min(1.0, circularity),  // Cap at 1.0
                edgePoints: stats.edgePoints
            ))
        }

        // Sort by area (largest first)
        blobs.sort { $0.area > $1.area }

        return blobs
    }
}

// MARK: - Helper Types

private class BlobStats {
    var minX = Int.max
    var maxX = Int.min
    var minY = Int.max
    var maxY = Int.min
    var sumX = 0
    var sumY = 0
    var area = 0
    var edgePoints: [CGPoint] = []

    var centroid: CGPoint {
        guard area > 0 else { return .zero }
        return CGPoint(x: CGFloat(sumX) / CGFloat(area), y: CGFloat(sumY) / CGFloat(area))
    }

    var boundingBox: CGRect {
        guard minX <= maxX && minY <= maxY else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    var perimeter: Int {
        return edgePoints.count
    }

    func addPixel(x: Int, y: Int) {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
        sumX += x
        sumY += y
        area += 1
    }

    func addEdgePixel(x: Int, y: Int) {
        edgePoints.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
    }
}

/// Union-Find data structure for connected component labeling
private class UnionFind {
    private var parent: [Int: Int] = [:]
    private var rank: [Int: Int] = [:]

    func makeSet(_ x: Int) {
        parent[x] = x
        rank[x] = 0
    }

    func find(_ x: Int) -> Int {
        guard let p = parent[x] else { return x }
        if p != x {
            parent[x] = find(p)  // Path compression
        }
        return parent[x]!
    }

    func union(_ x: Int, _ y: Int) {
        let rootX = find(x)
        let rootY = find(y)

        guard rootX != rootY else { return }

        // Union by rank
        let rankX = rank[rootX] ?? 0
        let rankY = rank[rootY] ?? 0

        if rankX < rankY {
            parent[rootX] = rootY
        } else if rankX > rankY {
            parent[rootY] = rootX
        } else {
            parent[rootY] = rootX
            rank[rootX] = rankX + 1
        }
    }
}
