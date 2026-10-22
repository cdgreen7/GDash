import SwiftUI

/// Slowly drifting dark mesh gradient used behind every screen.
struct HubBackground: View {
    var accent: Color = HubSection.assistant.tint

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let dx = Float(sin(t * 0.22)) * 0.14
            let dy = Float(cos(t * 0.17)) * 0.14
            let points: [SIMD2<Float>] = [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + dx, 0.5 + dy], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ]
            MeshGradient(width: 3, height: 3, points: points, colors: [
                accent.opacity(0.42), Theme.background, Theme.background,
                Theme.background, accent.opacity(0.14), Theme.background,
                Theme.background, Theme.background, accent.opacity(0.24),
            ])
        }
        .background(Theme.background)
        .ignoresSafeArea()
    }
}

/// Liquid-glass card container.
struct GlassCard<Content: View>: View {
    var tint: Color?
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.16)) } ?? .regular,
                         in: .rect(cornerRadius: Theme.corner))
    }
}

/// Scales cards slightly while pressed.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GradientProgressBar: View {
    var value: Double
    var colors: [Color]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
    }
}

struct ProgressRing: View {
    var value: Double
    var colors: [Color]
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)
    }
}

struct IconBadge: View {
    var systemName: String
    var colors: [Color]
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.black.opacity(0.85))
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: size * 0.32))
    }
}

/// Small uppercase label used above card content.
struct Eyebrow: View {
    var text: String
    var color: Color = Theme.secondary

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

struct SectionTitle: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.display(22, weight: .bold))
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.top, 8)
    }
}

struct EmptyHint: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.tertiary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

/// Horizontal wrap of selectable swatches.
struct ColorSwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Theme.palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(.white, lineWidth: selection == hex ? 3 : 0).padding(-4))
                        .onTapGesture { selection = hex }
                }
            }
            .padding(6)
        }
    }
}

struct IconPicker: View {
    var icons: [String]
    @Binding var selection: String
    var color: Color

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
            ForEach(icons, id: \.self) { icon in
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(selection == icon ? .black : .white)
                    .background(selection == icon ? color : Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
                    .onTapGesture { selection = icon }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shown over the hub while the app is in the app switcher.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            HubBackground()
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.secondary)
        }
    }
}
