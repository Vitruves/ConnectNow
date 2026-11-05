import SwiftUI

struct FooterBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            // Left: what is happening (spinning arrow + state), right: the action.
            HStack(spacing: 6) {
                SpinningArrow(isSpinning: model.isScanning)
                ScanAge(isScanning: model.isScanning, lastScan: model.lastScan)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button("Rescan") { model.rescan() }
                .buttonStyle(.borderless)
                .disabled(model.isScanning)
                .help("Scan the network again (⌘R)")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct SpinningArrow: View {
    let isSpinning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Redrawn only while a scan runs.
        TimelineView(.animation(paused: !isSpinning || reduceMotion)) { context in
            let angle = isSpinning && !reduceMotion
                ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0
            Image(systemName: "arrow.clockwise").rotationEffect(.degrees(angle))
        }
    }
}

private struct ScanAge: View {
    let isScanning: Bool
    let lastScan: Date?

    var body: some View {
        Group {
            if isScanning {
                Text("Scanning…")
            } else if let lastScan {
                TimelineView(.periodic(from: lastScan, by: 1)) { context in
                    Text(Self.age(since: lastScan, now: context.date))
                }
            }
        }
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }

    static func age(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<3: return "Scanned just now"
        case ..<60: return "Scanned \(seconds) s ago"
        default: return "Scanned \(seconds / 60) min ago"
        }
    }
}
