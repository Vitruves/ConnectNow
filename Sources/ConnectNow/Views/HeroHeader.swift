import SwiftUI
import ConnectNowCore

/// Header: the icon's sky, which brightens from night to day as the connection comes up.
struct HeroHeader: View {
    let status: NetworkStatus
    let isScanning: Bool
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: Brand.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 11) {
                    StatusBadge(status: status, isScanning: isScanning)
                    Text(status.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.86))
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .shadow(color: .night.opacity(0.35), radius: 6)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 20)
        .padding(.top, 4)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { DawnSky(status: status).ignoresSafeArea() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.title). \(subtitle)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Layered gradients: the icon's dawn, a night veil and a rising sun, crossfaded per status.
struct DawnSky: View {
    let status: NetworkStatus

    private var night: Double {
        switch status {
        case .noNetwork: 0.92
        case .offline: 0.78
        case .scanning: 0.55
        case .captive: 0.12
        case .online: 0
        }
    }

    private var sun: Double {
        switch status {
        case .online: 1
        case .captive: 0.45
        default: 0
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .night, location: 0),
                                   .init(color: .violet, location: 0.45),
                                   .init(color: .rose, location: 0.72),
                                   .init(color: .coral, location: 0.88),
                                   .init(color: .gold, location: 1)],
                           startPoint: .bottomLeading, endPoint: .topTrailing)
            LinearGradient(colors: [.night, .night, .violet.opacity(0.85)],
                           startPoint: .bottomLeading, endPoint: .topTrailing)
                .opacity(night)
            RadialGradient(colors: [.gold.opacity(0.75), .coral.opacity(0.25), .clear],
                           center: UnitPoint(x: 0.95, y: 0.05), startRadius: 0, endRadius: 300)
                .blendMode(.screen)
                .opacity(sun)
            // Soft sheen at the top, hairline at the bottom.
            LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.25)).frame(height: 0.5)
        }
        .animation(.easeInOut(duration: 1.4), value: status)
    }
}

struct StatusBadge: View {
    let status: NetworkStatus
    let isScanning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isScanning && !reduceMotion {
                PulseHalo().transition(.opacity)
            }
            Circle().fill(status.badgeFill)
            Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
            Image(systemName: status.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(status.badgeGlyph)
                .symbolEffect(.variableColor.iterative, isActive: status == .scanning && !reduceMotion)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 24, height: 24)
        .animation(.smooth, value: status)
        .accessibilityHidden(true)
    }
}

/// Expanding ring shown while a scan runs.
private struct PulseHalo: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(.white, lineWidth: 1.5)
            .scaleEffect(expanded ? 1.6 : 1)
            .opacity(expanded ? 0 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { expanded = true }
            }
    }
}
