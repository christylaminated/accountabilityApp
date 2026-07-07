import SwiftUI

/// Lightweight particle confetti rendered with `TimelineView` + `Canvas`.
/// ~50 particles, each falling from the top with a slow horizontal drift
/// and rotation. No third-party library, no heavy assets — the whole
/// thing is one struct.
///
/// Particles seed once on appear and are advanced by elapsed time (so
/// pause/resume from SwiftUI's animation system doesn't desync). When a
/// particle falls off the bottom it disappears; the field empties over
/// ~5 seconds and stays empty until the view re-appears. That matches
/// the celebration screen's one-shot "yay, you locked in" moment.
struct ConfettiView: View {
    /// Default palette — soft enough to read on the canvas, varied so
    /// the field doesn't look uniform.
    static let defaultColors: [Color] = [
        Color(red: 0.96, green: 0.49, blue: 0.36),  // coral
        Color(red: 0.99, green: 0.79, blue: 0.27),  // gold
        Color(red: 0.42, green: 0.68, blue: 0.96),  // sky
        Color(red: 0.62, green: 0.86, blue: 0.55),  // sage
        Color(red: 0.79, green: 0.56, blue: 0.92),  // violet
    ]

    var particleCount: Int = 50
    var colors: [Color] = defaultColors
    var duration: TimeInterval = 5

    @State private var particles: [Particle] = []
    @State private var startedAt: Date?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                Canvas { context, size in
                    for p in particles {
                        let t = elapsed
                        let x = p.x0 + p.driftPerSec * t * size.width
                        let y = p.y0 + p.fallPerSec * t * size.height
                        let angle = p.spinPerSec * t * 2 * .pi
                        guard y < size.height + 20 else { continue }
                        let rect = CGRect(
                            x: x * size.width - p.size / 2,
                            y: y - p.size / 2,
                            width: p.size,
                            height: p.size * 0.6
                        )
                        var transform = CGAffineTransform.identity
                        transform = transform
                            .translatedBy(x: rect.midX, y: rect.midY)
                            .rotated(by: angle)
                            .translatedBy(x: -rect.midX, y: -rect.midY)
                        context.drawLayer { layerCtx in
                            layerCtx.concatenate(transform)
                            layerCtx.fill(
                                Path(roundedRect: rect, cornerRadius: 2),
                                with: .color(p.color)
                            )
                        }
                    }
                }
            }
            .onAppear {
                guard particles.isEmpty else { return }
                particles = Self.seed(count: particleCount, colors: colors)
                startedAt = Date()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }

    private static func seed(count: Int, colors: [Color]) -> [Particle] {
        (0..<count).map { _ in
            Particle(
                x0: CGFloat.random(in: 0...1),
                y0: CGFloat.random(in: -40...(-5)),
                driftPerSec: CGFloat.random(in: -0.12...0.12),
                fallPerSec: CGFloat.random(in: 90...160),
                spinPerSec: CGFloat.random(in: -0.6...0.6),
                size: CGFloat.random(in: 6...10),
                color: colors.randomElement() ?? .accentColor
            )
        }
    }

    private struct Particle {
        let x0: CGFloat
        let y0: CGFloat
        let driftPerSec: CGFloat
        let fallPerSec: CGFloat
        let spinPerSec: CGFloat
        let size: CGFloat
        let color: Color
    }
}
