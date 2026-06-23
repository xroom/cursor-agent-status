import AppKit
import SwiftUI

/// 灰色半透明磨砂玻璃，在白色背景下更易辨认
struct GlassBackground: View {
    var cornerRadius: CGFloat

    init(cornerRadius: CGFloat? = nil) {
        self.cornerRadius = cornerRadius ?? 24
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(
                material: .hudWindow,
                blendingMode: .behindWindow,
                cornerRadius: cornerRadius
            )

            // 灰色透明底，提升在浅色背景上的对比度
            shape.fill(Color.black.opacity(0.32))

            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        Color.black.opacity(0.06),
                        Color.black.opacity(0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            shape.fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        Color.clear,
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 200
                )
            )
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.38),
                        Color.white.opacity(0.14),
                        Color.black.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        view.alphaValue = 0.88
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
