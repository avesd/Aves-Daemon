import SwiftUI

enum MenuBarBrand {
    static let image: NSImage = {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            let scale = rect.width / BrandGeometry.size
            let center = BrandGeometry.square.contour.boundingRect
            context.translateBy(x: rect.midX - center.midX * scale, y: rect.midY - center.midY * scale)
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(BrandGeometry.square.solid.cgPath)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        return image
    }()
}

private struct BrandNod: AnimatableModifier {
    nonisolated var phase: Double
    nonisolated var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        let t = phase - floor(phase)
        let degrees: Double
        switch t {
        case ..<0.38: degrees = -10 * t / 0.38
        case ..<0.72: degrees = -10 + 12 * (t - 0.38) / 0.34
        default: degrees = 2 * (1 - t) / 0.28
        }
        return content.rotationEffect(.degrees(degrees), anchor: UnitPoint(x: 0.5, y: 108 / 192.0))
    }
}

private struct FooterBird: Shape {
    var progress: CGFloat
    let includeEye: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    // Both authored contours begin at the beak and wind in the same direction.
    private static func sample(_ path: Path) -> [CGPoint] {
        (0..<256).map { index in
            if index == 0 { return path.cgPath.currentPoint }
            return path.trimmedPath(from: 0, to: CGFloat(index) / 256).cgPath.currentPoint
        }
    }

    private static let points = Array(zip(sample(BrandGeometry.square.contour), sample(BrandGeometry.standard.contour)))

    func path(in rect: CGRect) -> Path {
        let from = BrandGeometry.square, to = BrandGeometry.standard
        var path: Path
        if progress <= 0 {
            path = includeEye ? from.solid : from.contour
        } else if progress >= 1 {
            path = includeEye ? to.solid : to.contour
        } else {
            path = Path()
            for (index, pair) in Self.points.enumerated() {
                let (a, b) = pair
                let point = CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            if includeEye {
                let a = from.eye.boundingRect, b = to.eye.boundingRect
                path.addPath(from.eye, transform: .init(translationX: (b.midX - a.midX) * progress,
                                                         y: (b.midY - a.midY) * progress))
            }
        }
        let scale = min(rect.width, rect.height) / BrandGeometry.size
        return path.applying(.init(translationX: rect.midX - BrandGeometry.size * scale / 2,
                                   y: rect.midY - BrandGeometry.size * scale / 2).scaledBy(x: scale, y: scale))
    }
}

struct BrandFooter: View {
    let showAbout: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var shift: CGFloat = 4.25
    @FocusState private var focused: Bool
    @State private var hovered = false
    @State private var entered = false
    @State private var nodPhase = 0.0
    @State private var lastNod: ContinuousClock.Instant?

    private var active: Bool { hovered || focused }
    private var morph: Animation? { reduceMotion ? nil : .timingCurve(0.2, 0.75, 0.25, 1, duration: 0.24) }

    var body: some View {
        Button(action: showAbout) {
            HStack(alignment: .bottom) {
                HStack(spacing: 5) {
                    bird.frame(width: 23, height: 23)
                    wordmark
                }
                Spacer(minLength: 8)
                Text(verbatim: AboutView.version)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .opacity(active ? 1 : 0)
            }
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 3)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .accessibilityLabel("About Aves Daemon")
        .accessibilityValue(Text(verbatim: AboutView.version))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        .onHover { hovered = $0 }
        .onChange(of: active) { if $0 { nod() } }
        .task { entered = true }
    }

    private var wordmark: some View {
        HStack(spacing: 0) {
            Text(verbatim: "Aves ")
            ZStack(alignment: .leading) {
                Text(verbatim: "D").opacity(active ? 0 : 1)
                Text(verbatim: "d").opacity(active ? 1 : 0)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.14).delay(0.03), value: active)
            .offset(x: active ? -shift : 0)
            .animation(morph, value: active)
            Text(verbatim: "aemon")
                .opacity(active ? 0.75 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: active)
        }
        .font(BrandTypography.wordmark)
        .fixedSize()
    }

    private var bird: some View {
        let progress: CGFloat = active ? 1 : 0
        let solid = FooterBird(progress: progress, includeEye: true)
            .fill(style: FillStyle(eoFill: true))
            .animation(morph, value: active)
        return Group {
            if reduceMotion {
                solid
            } else {
                ZStack {
                    solid.opacity(entered ? 1 : 0)
                        .animation(.easeInOut(duration: 0.456).delay(0.744), value: entered)
                    FooterBird(progress: progress, includeEye: false)
                        .trim(from: 0, to: entered ? 1 : 0)
                        .stroke(style: StrokeStyle(lineWidth: 2.0 / 3, lineCap: .round, lineJoin: .round))
                        .animation(morph, value: active)
                        .animation(.easeInOut(duration: 0.864), value: entered)
                        .opacity(entered ? 0 : 1)
                        .animation(.easeInOut(duration: 0.336).delay(0.864), value: entered)
                }
                .modifier(BrandNod(phase: nodPhase))
            }
        }
    }

    private func nod() {
        guard !reduceMotion else { return }
        let now = ContinuousClock.now
        if let lastNod, lastNod.duration(to: now) < .milliseconds(700) { return }
        lastNod = now
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.7)) { nodPhase += 1 }
    }
}
