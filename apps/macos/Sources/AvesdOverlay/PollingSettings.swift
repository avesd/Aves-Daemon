import SwiftUI

struct PollingSettings: View {
    @ObservedObject var preferences: DaemonPreferences

    private func binding<Value>(_ key: WritableKeyPath<PollingPolicy, Value>) -> Binding<Value> {
        Binding(get: { preferences.polling[keyPath: key] }, set: { value in
            var policy = preferences.polling
            policy[keyPath: key] = value
            preferences.setPolling(policy)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            minutes("Base interval", value: binding(\.base))
            SettingsRow(label: "Extend interval after playback") {
                Toggle("Extend interval after playback", isOn: binding(\.increasesAfterPlayback))
                    .labelsHidden().toggleStyle(.switch)
            }
            if preferences.polling.increasesAfterPlayback {
                minutes("Increase by", value: binding(\.step))
                minutes("Maximum interval", value: binding(\.maximum),
                        range: preferences.polling.base...PollingPolicy.minutes.upperBound)
            }
            intervalPreview.padding(.top, 22)
        }
    }

    private var intervalPreview: some View {
        let policy = preferences.polling
        let second = policy.nextInterval(after: policy.base, played: true)
        let intervals = [policy.base, second, policy.nextInterval(after: second, played: true)]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Interval after consecutive plays").font(.headline)
            HStack(spacing: 12) {
                ForEach(intervals.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geometry in
                            Capsule().fill(.tint)
                                .frame(width: max(2, geometry.size.width * CGFloat(intervals[index]) / CGFloat(intervals[2])))
                        }
                        .frame(height: 4)
                        Text("\(intervals[index]) min").monospacedDigit()
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 130, alignment: .leading)
                }
            }
            if policy.increasesAfterPlayback {
                Text("A round without playback resets the interval to its base value.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func minutes(_ label: String, value: Binding<Int>,
                         range: ClosedRange<Int> = PollingPolicy.minutes) -> some View {
        SettingsRow(label: label) {
            HStack(spacing: 6) {
                TextField(label, value: value, format: .number)
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 56)
                Text("min").foregroundStyle(.secondary)
                Stepper(label, value: value, in: range).labelsHidden()
            }
        }
    }
}
