import AppKit
import CoreGraphics

/// 💥 A picture broken into irregular pieces, for what falls apart on screen:
/// the 😱 of #8 while it grows, the red button of #7 when it is hit.
///
/// A jittered grid cut along random diagonals, so the pieces read as shards
/// rather than tiles. Each one is its own small bitmap, already cut out, because
/// a mask per piece would have the compositor redo the cut every frame.
struct Shard {
    let image: CGImage
    /// Where it sits in the picture, in unit coordinates, y down.
    let rect: CGRect
    /// From the middle of the picture out through this piece, unit length, y down.
    let direction: CGVector
    /// Picks how far and how fast this one goes: 0.6…1.4.
    let speed: CGFloat
    /// Total turn in radians, either way round.
    let spin: CGFloat
}

enum Shatter {
    /// The triangles covering the unit square, y down. Inner grid points are
    /// moved by up to `jitter` of a cell; the border stays put, so nothing is
    /// lost from the picture and nothing overlaps.
    static func signedArea(_ t: [CGPoint]) -> CGFloat {
        ((t[1].x - t[0].x) * (t[2].y - t[0].y) - (t[2].x - t[0].x) * (t[1].y - t[0].y)) / 2
    }

    static func triangles(columns: Int, rows: Int, jitter: CGFloat = 0.35) -> [[CGPoint]] {
        func point(_ c: Int, _ r: Int) -> CGPoint {
            CGPoint(x: CGFloat(c) / CGFloat(columns), y: CGFloat(r) / CGFloat(rows))
        }
        var grid = (0...rows).map { r in (0...columns).map { c in point(c, r) } }
        for r in 1..<max(1, rows) {
            for c in 1..<max(1, columns) {
                grid[r][c].x += .random(in: -jitter...jitter) / CGFloat(columns)
                grid[r][c].y += .random(in: -jitter...jitter) / CGFloat(rows)
            }
        }
        var out: [[CGPoint]] = []
        for r in 0..<rows {
            for c in 0..<columns {
                let (a, b, d, e) = (grid[r][c], grid[r][c + 1], grid[r + 1][c], grid[r + 1][c + 1])
                // Jitter can make a cell non-convex; then one of its diagonals
                // runs outside it and folds a triangle over its neighbour
                // (overlapping shards, area > 1 — the flaky ShatterTests of
                // 2026-11-12). Only a diagonal that keeps both triangles the
                // same way round as the unjittered grid is allowed.
                let one = [[a, b, d], [b, e, d]], other = [[a, b, e], [a, e, d]]
                let ok = { (pair: [[CGPoint]]) in pair.allSatisfy { signedArea($0) > 0 } }
                switch (ok(one), ok(other)) {
                case (true, false): out += one
                case (false, true): out += other
                default: out += Bool.random() ? one : other
                }
            }
        }
        return out
    }

    static func shards(of image: CGImage, columns: Int, rows: Int) -> [Shard] {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        return triangles(columns: columns, rows: rows).compactMap { tri in
            let xs = tri.map(\.x), ys = tri.map(\.y)
            let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            let pw = Int((rect.width * w).rounded(.up)), ph = Int((rect.height * h).rounded(.up))
            guard pw > 0, ph > 0,
                  let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            // The bitmap is y-up, the unit coordinates y-down.
            let path = CGMutablePath()
            path.addLines(between: tri.map {
                CGPoint(x: ($0.x - rect.minX) * w, y: CGFloat(ph) - ($0.y - rect.minY) * h)
            })
            path.closeSubpath()
            ctx.addPath(path)
            ctx.clip()
            ctx.draw(image, in: CGRect(x: -rect.minX * w, y: CGFloat(ph) + rect.minY * h - h, width: w, height: h))
            guard let piece = ctx.makeImage() else { return nil }
            let c = CGPoint(x: xs.reduce(0, +) / 3 - 0.5, y: ys.reduce(0, +) / 3 - 0.5)
            let length = max(0.001, hypot(c.x, c.y))
            return Shard(image: piece, rect: rect,
                         direction: CGVector(dx: c.x / length, dy: c.y / length),
                         speed: .random(in: 0.6...1.4),
                         spin: .random(in: 1...4) * (Bool.random() ? 1 : -1))
        }
    }
}
