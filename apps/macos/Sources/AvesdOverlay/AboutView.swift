import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    static let version: String = {
        let info = Bundle.main
        let release = info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = info.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let release, !release.isEmpty {
            if let build, !build.isEmpty { return "Version \(release) (\(build))" }
            return "Version \(release)"
        }
        if let build, !build.isEmpty { return "Build \(build)" }
        return "Development build"
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BrandGeometry.square.solid
                    .applying(.init(scaleX: 44 / BrandGeometry.size, y: 44 / BrandGeometry.size))
                    .fill(style: FillStyle(eoFill: true))
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aves Daemon").font(.custom("Futura-Medium", size: 22, relativeTo: .title2))
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: Self.version).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("A menu bar app that previews passing aircraft at the edge of your screen.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Rain summaries use [MET Norway](https://www.met.no/en) forecasts under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).")
                .font(.caption)
            HStack {
                Link("avesd.ai", destination: URL(string: "https://avesd.ai")!)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}
