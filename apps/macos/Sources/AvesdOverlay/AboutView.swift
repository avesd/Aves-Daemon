import AvesdEnvironment
import SwiftUI

struct AboutView: View {
    let environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BrandGeometry.square.solid
                    .applying(.init(scaleX: 44 / BrandGeometry.size, y: 44 / BrandGeometry.size))
                    .fill(style: FillStyle(eoFill: true))
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: environment.channel.appName).font(.custom("Futura-Medium", size: 22, relativeTo: .title2))
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: environment.version).font(.caption).foregroundStyle(.secondary)
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
