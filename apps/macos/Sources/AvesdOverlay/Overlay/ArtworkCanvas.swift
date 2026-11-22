import CAvesdCore
import SwiftUI

struct ArtworkCanvas: View {
    let commands: [AvesdCommand]
    let icon: Bool

    var body: some View {
        Canvas { context, size in
            let center = icon ? CGPoint(x: size.width / 2, y: size.height / 2) : OverlayLayout.markCenter
            context.translateBy(x: center.x, y: center.y)
            var index = 0
            paint(into: context, index: &index)
        }
    }

    private func ink(_ tag: UInt32) -> Color {
        switch Int(tag) {
        case AVESD_INK_IVORY: Color(red: 0.90, green: 0.94, blue: 0.90)
        case AVESD_INK_SILVER: Color(red: 0.72, green: 0.80, blue: 0.79)
        case AVESD_INK_BRASS: Color(red: 0.95, green: 0.82, blue: 0.61)
        case AVESD_INK_SLATE: Color(red: 0.20, green: 0.28, blue: 0.32)
        case AVESD_INK_BRICK: Color(red: 0.53, green: 0.37, blue: 0.31)
        case AVESD_INK_BLACK: .black
        case AVESD_INK_CLEAR: .clear
        default: .white
        }
    }

    private func paint(into base: GraphicsContext, index: inout Int) {
        var ctx = base
        var stack: [GraphicsContext] = []
        var path = Path()
        var start = CGPoint.zero, end = CGPoint.zero
        var colors: [Color] = []
        while index < commands.count {
            let cmd = commands[index]
            index += 1
            let point = CGPoint(x: cmd.x, y: cmd.y)
            let rect = CGRect(x: cmd.x, y: cmd.y, width: cmd.a, height: cmd.b)
            switch Int(cmd.op) {
            case AVESD_OP_BEGIN: path = Path()
            case AVESD_OP_MOVE: path.move(to: point)
            case AVESD_OP_LINE_TO: path.addLine(to: point)
            case AVESD_OP_QUAD: path.addQuadCurve(to: point, control: CGPoint(x: cmd.a, y: cmd.b))
            case AVESD_OP_CLOSE: path.closeSubpath()
            case AVESD_OP_RECT: path = Path(rect)
            case AVESD_OP_ROUND_RECT: path = Path(roundedRect: rect, cornerRadius: Double(cmd.tag) / 1000)
            case AVESD_OP_ELLIPSE: path = Path(ellipseIn: rect)
            case AVESD_OP_ARC:
                path = Path()
                path.addRelativeArc(center: .zero, radius: 1, startAngle: .degrees(cmd.x), delta: .degrees(cmd.y))
            case AVESD_OP_TRANSFORM_ARC:
                path = path.applying(CGAffineTransform(translationX: cmd.x, y: cmd.y).scaledBy(x: cmd.a, y: cmd.b))
            case AVESD_OP_FILL: ctx.fill(path, with: .color(ink(cmd.tag).opacity(cmd.x)))
            case AVESD_OP_STROKE:
                ctx.stroke(path, with: .color(ink(cmd.tag).opacity(cmd.x)),
                           style: StrokeStyle(lineWidth: cmd.y, lineCap: cmd.a == 1 ? .round : .butt))
            case AVESD_OP_CLIP: ctx.clip(to: path)
            case AVESD_OP_SAVE: stack.append(ctx)
            case AVESD_OP_RESTORE: if let saved = stack.popLast() { ctx = saved }
            case AVESD_OP_TRANSLATE: ctx.translateBy(x: cmd.x, y: cmd.y)
            case AVESD_OP_ROTATE: ctx.rotate(by: .radians(cmd.x))
            case AVESD_OP_SCALE: ctx.scaleBy(x: cmd.x, y: cmd.y)
            case AVESD_OP_OPACITY: ctx.opacity *= cmd.x
            case AVESD_OP_BEGIN_LAYER: ctx.drawLayer { paint(into: $0, index: &index) }
            case AVESD_OP_END_LAYER: return
            case AVESD_OP_GRADIENT: start = point; end = CGPoint(x: cmd.a, y: cmd.b); colors.removeAll(keepingCapacity: true)
            case AVESD_OP_STOP: colors.append(ink(cmd.tag).opacity(cmd.x))
            case AVESD_OP_FILL_GRADIENT:
                ctx.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: start, endPoint: end))
            case AVESD_OP_STROKE_GRADIENT:
                ctx.stroke(path, with: .linearGradient(Gradient(colors: colors), startPoint: start, endPoint: end), lineWidth: cmd.x)
            case AVESD_OP_GLYPH:
                if let scalar = UnicodeScalar(cmd.tag) {
                    var glyph = ctx.resolve(Text(verbatim: String(scalar)).font(.system(size: cmd.x, weight: .medium)))
                    glyph.shading = .color(ink(UInt32(cmd.y)))
                    ctx.draw(glyph, at: .zero, anchor: .center)
                }
            case AVESD_OP_SYMBOL:
                if cmd.tag == 0 {
                    ctx.draw(ctx.resolve(Image(systemName: "drop.fill")), in: rect)
                } else {
                    var plane = ctx.resolve(Image(systemName: "airplane"))
                    plane.shading = .color(.white)
                    let h = cmd.a * plane.size.height / max(1, plane.size.width)
                    ctx.draw(plane, in: CGRect(x: cmd.x - cmd.a / 2, y: cmd.y - h / 2, width: cmd.a, height: h))
                }
            case AVESD_OP_SHADOW: ctx.addFilter(.shadow(color: .black.opacity(cmd.x), radius: cmd.y, y: cmd.a))
            default: break
            }
        }
    }
}
