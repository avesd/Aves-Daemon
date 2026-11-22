// Generated from @avesd/logo by generate-brand.ts.
import SwiftUI

enum BrandGeometry {
    struct Mark {
        let contour: Path
        let eye: Path

        var solid: Path {
            var path = contour
            path.addPath(eye)
            return path
        }
    }

    static let size: CGFloat = 192
    static let square = Mark(contour: Path { path in
        path.move(to: CGPoint(x: 26, y: 76))
        path.addCurve(to: CGPoint(x: 81, y: 42), control1: CGPoint(x: 41, y: 54), control2: CGPoint(x: 57, y: 43))
        path.addLine(to: CGPoint(x: 116, y: 42))
        path.addCurve(to: CGPoint(x: 147, y: 73), control1: CGPoint(x: 137, y: 42), control2: CGPoint(x: 147, y: 53))
        path.addLine(to: CGPoint(x: 146, y: 103))
        path.addCurve(to: CGPoint(x: 179, y: 118), control1: CGPoint(x: 146, y: 117), control2: CGPoint(x: 157, y: 123))
        path.addCurve(to: CGPoint(x: 132, y: 161), control1: CGPoint(x: 165, y: 137), control2: CGPoint(x: 148, y: 153))
        path.addCurve(to: CGPoint(x: 86, y: 167), control1: CGPoint(x: 120, y: 167), control2: CGPoint(x: 103, y: 168))
        path.addLine(to: CGPoint(x: 68, y: 166))
        path.addCurve(to: CGPoint(x: 36, y: 129), control1: CGPoint(x: 46, y: 165), control2: CGPoint(x: 35, y: 150))
        path.addLine(to: CGPoint(x: 38, y: 104))
        path.addCurve(to: CGPoint(x: 18, y: 83), control1: CGPoint(x: 40, y: 91), control2: CGPoint(x: 33, y: 82))
        path.closeSubpath()
    }, eye: Path { path in
        path.move(to: CGPoint(x: 54, y: 88))
        path.addCurve(to: CGPoint(x: 61, y: 95), control1: CGPoint(x: 54, y: 91.86599324881556), control2: CGPoint(x: 57.134006751184444, y: 95))
        path.addCurve(to: CGPoint(x: 68, y: 88), control1: CGPoint(x: 64.86599324881556, y: 95), control2: CGPoint(x: 68, y: 91.86599324881556))
        path.addCurve(to: CGPoint(x: 61, y: 81), control1: CGPoint(x: 68, y: 84.13400675118444), control2: CGPoint(x: 64.86599324881556, y: 81))
        path.addCurve(to: CGPoint(x: 54, y: 88), control1: CGPoint(x: 57.134006751184444, y: 81), control2: CGPoint(x: 54, y: 84.13400675118444))
        path.closeSubpath()
    })

    static let standard = Mark(contour: Path { path in
        path.move(to: CGPoint(x: 26, y: 76))
        path.addCurve(to: CGPoint(x: 104, y: 42), control1: CGPoint(x: 47, y: 54), control2: CGPoint(x: 76, y: 42))
        path.addCurve(to: CGPoint(x: 136, y: 70), control1: CGPoint(x: 124, y: 42), control2: CGPoint(x: 135, y: 52))
        path.addCurve(to: CGPoint(x: 147, y: 115), control1: CGPoint(x: 137, y: 89), control2: CGPoint(x: 137, y: 104))
        path.addCurve(to: CGPoint(x: 182, y: 118), control1: CGPoint(x: 155, y: 123), control2: CGPoint(x: 168, y: 122))
        path.addCurve(to: CGPoint(x: 105, y: 167), control1: CGPoint(x: 162, y: 136), control2: CGPoint(x: 135, y: 153))
        path.addCurve(to: CGPoint(x: 53, y: 162), control1: CGPoint(x: 86, y: 175), control2: CGPoint(x: 67, y: 173))
        path.addCurve(to: CGPoint(x: 39, y: 114), control1: CGPoint(x: 40, y: 150), control2: CGPoint(x: 36, y: 133))
        path.addCurve(to: CGPoint(x: 27, y: 81), control1: CGPoint(x: 42, y: 94), control2: CGPoint(x: 38, y: 82))
        path.addLine(to: CGPoint(x: 18, y: 82))
        path.closeSubpath()
    }, eye: Path { path in
        path.move(to: CGPoint(x: 52, y: 92))
        path.addCurve(to: CGPoint(x: 59, y: 99), control1: CGPoint(x: 52, y: 95.86599324881556), control2: CGPoint(x: 55.134006751184444, y: 99))
        path.addCurve(to: CGPoint(x: 66, y: 92), control1: CGPoint(x: 62.865993248815556, y: 99), control2: CGPoint(x: 66, y: 95.86599324881556))
        path.addCurve(to: CGPoint(x: 59, y: 85), control1: CGPoint(x: 66, y: 88.13400675118444), control2: CGPoint(x: 62.865993248815556, y: 85))
        path.addCurve(to: CGPoint(x: 52, y: 92), control1: CGPoint(x: 55.134006751184444, y: 85), control2: CGPoint(x: 52, y: 88.13400675118444))
        path.closeSubpath()
    })
}
