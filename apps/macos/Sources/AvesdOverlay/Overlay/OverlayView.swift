import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: OverlaySession

    var body: some View {
        ZStack(alignment: .topLeading) {
            card.offset(x: OverlayLayout.origin.x, y: OverlayLayout.origin.y)
            artwork.allowsHitTesting(false).accessibilityHidden(true)
        }
        .frame(width: OverlayLayout.panelSize.width, height: OverlayLayout.panelSize.height, alignment: .topLeading)
        .foregroundStyle(.white)
        .opacity(state.frame.panel.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.content?.accessibility ?? "")
    }

    @ViewBuilder private var artwork: some View {
        if !state.frame.scenery.isEmpty {
            let canvas = ArtworkCanvas(commands: state.frame.scenery, icon: false)
            if state.content?.icon == "artwork" {
                canvas.shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
            } else {
                canvas
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: OverlayLayout.headerHeight)
                .mask(alignment: .leading) {
                    if state.content?.icon == "airline" {
                        let edge = max(0, state.frame.panel.reveal_edge - OverlayLayout.origin.x - OverlayLayout.inset)
                        HStack(spacing: 0) {
                            Rectangle().frame(width: max(0, edge - 10))
                            LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: min(10, edge))
                        }
                    } else {
                        Rectangle()
                    }
                }
            details.opacity(state.frame.panel.surface_opacity)
        }
        .padding(.horizontal, OverlayLayout.inset)
        .frame(width: OverlayLayout.width)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .circular)
                .fill(LinearGradient(colors: [Color(red: 0.17, green: 0.27, blue: 0.34),
                                              Color(red: 0.10, green: 0.17, blue: 0.24)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .circular)
                        .strokeBorder(.white.opacity(0.24), lineWidth: 0.75)
                }
                .modifier(Unfold(fraction: state.frame.panel.open_fraction))
                .opacity(state.frame.panel.surface_opacity)
        }
        .mask(alignment: .top) { Rectangle().modifier(Unfold(fraction: state.frame.panel.open_fraction)) }
        .overlay {
            if state.frame.panel.expansion > 0 && state.frame.panel.expansion < 1 {
                ContrailOutline()
                    .trim(from: 0, to: state.frame.panel.traced_fraction)
                    .stroke(Color(red: 0.90, green: 0.98, blue: 1).opacity(state.frame.panel.trace_opacity),
                            style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    .accessibilityHidden(true)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.cardHeight = $0 }
    }

    private var summary: some View {
        OverlaySummaryRow {
            if let content = state.content {
                switch content.icon {
                case "airline":
                    if let logo = state.logo {
                        Image(nsImage: logo).renderingMode(.template).resizable().scaledToFit()
                    } else {
                        Text(content.airlineCode ?? "").font(BrandTypography.code(13))
                    }
                case "rain":
                    Image(systemName: "drop").font(.system(size: 15, weight: .regular))
                        .opacity(state.frame.fieldOpacity(0))
                default:
                    ArtworkCanvas(commands: state.frame.icon, icon: true)
                        .opacity(state.frame.fieldOpacity(0))
                }
            }
        } information: {
            if let content = state.content {
                fields(secondary: content.secondary, trailing: content.trailing, visibility: state.frame.fieldOpacity) {
                    if let destination = content.routeDestination {
                        HStack(spacing: 6) {
                            Text(content.headline)
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium)).opacity(0.8)
                            Text(destination)
                        }
                    } else {
                        Text(content.headline)
                    }
                }
            }
        }
        .shadow(color: .black.opacity(0.72 * (1 - state.frame.panel.open_fraction)), radius: 1.8, y: 0.5)
    }

    @ViewBuilder private func fields(secondary: String, trailing: String, visibility: (Int) -> Double = { _ in 1 },
                                     @ViewBuilder headline: () -> some View) -> some View {
        headline().font(BrandTypography.code(16)).opacity(visibility(1))
        if !secondary.isEmpty {
            Text("·").opacity(0.65 * visibility(2))
            Text(secondary).opacity(visibility(2))
        }
        if !trailing.isEmpty {
            Text("·").opacity(0.65 * visibility(3))
            Text(trailing).opacity(visibility(3))
        }
    }

    @ViewBuilder private var details: some View {
        if let content = state.content {
            detailSection(title: content.title, caption: content.caption) {
                ForEach(content.rows.indices, id: \.self) { i in
                    let row = content.rows[i]
                    detailRow(row.label, row.value)
                }
            }
        }
    }

    private func detailSection(title: String, caption: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 16, design: .serif)).lineLimit(2)
                Spacer(minLength: 0)
                Text(caption).font(BrandTypography.code(12))
                    .foregroundStyle(.white.opacity(0.78)).fixedSize()
            }
            Grid(alignment: .leading, horizontalSpacing: 13, verticalSpacing: 4, content: rows)
        }
        .padding(.bottom, 12)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.68))
            Text(value).font(.system(size: 13)).lineLimit(2)
        }
    }
}

struct OverlaySummaryRow<Icon: View, Information: View>: View {
    @ViewBuilder let icon: Icon
    @ViewBuilder let information: Information

    var body: some View {
        HStack(spacing: 9) {
            icon.frame(width: OverlayLayout.markSize, height: OverlayLayout.markSize)
                .fixedSize()
            HStack(spacing: 9) { information }
        }
        .font(BrandTypography.code(12))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// Start above the aircraft type and trace clockwise around the final card bounds.
private struct ContrailOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: 0.625, dy: 0.625)
        let start = CGPoint(x: bounds.maxX - 39, y: bounds.minY)
        let topRight = CGPoint(x: bounds.maxX, y: bounds.minY)
        let bottomRight = CGPoint(x: bounds.maxX, y: bounds.maxY)
        let bottomLeft = CGPoint(x: bounds.minX, y: bounds.maxY)
        let topLeft = CGPoint(x: bounds.minX, y: bounds.minY)
        var path = Path()
        path.move(to: start)
        path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: 13)
        path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: 13)
        path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: 13)
        path.addArc(tangent1End: topLeft, tangent2End: start, radius: 13)
        path.closeSubpath()
        return path
    }
}

// Only the boundary moves. The summary and details always lay out at their final positions.
private struct Unfold: ViewModifier {
    let fraction: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content.frame(width: geometry.size.width,
                          height: OverlayLayout.headerHeight + (geometry.size.height - OverlayLayout.headerHeight) * fraction)
        }
    }
}
