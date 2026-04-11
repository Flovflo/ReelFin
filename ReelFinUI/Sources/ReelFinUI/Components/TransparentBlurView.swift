import SwiftUI

#if os(iOS)
import UIKit

struct TransparentBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.layer.backgroundColor = UIColor.clear.cgColor

        DispatchQueue.main.async {
            stripTint(from: view, coordinator: context.coordinator)
        }

        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
        uiView.backgroundColor = .clear
        uiView.layer.backgroundColor = UIColor.clear.cgColor

        if !context.coordinator.didStripTint {
            DispatchQueue.main.async {
                stripTint(from: uiView, coordinator: context.coordinator)
            }
        }
    }

    private func stripTint(from view: UIVisualEffectView, coordinator: Coordinator) {
        guard !coordinator.didStripTint else { return }
        coordinator.didStripTint = true

        view.layer.filters = []

        for subview in view.subviews {
            subview.backgroundColor = .clear
            subview.layer.backgroundColor = UIColor.clear.cgColor
            stripLayer(subview.layer)
        }
    }

    private func stripLayer(_ layer: CALayer) {
        layer.backgroundColor = UIColor.clear.cgColor
        layer.filters = []
        layer.sublayers?.forEach(stripLayer)
    }

    final class Coordinator {
        var didStripTint = false
    }
}
#endif
