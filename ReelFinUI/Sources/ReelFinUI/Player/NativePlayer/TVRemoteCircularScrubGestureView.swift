import SwiftUI

#if os(tvOS)
import UIKit

struct TVRemoteCircularScrubGestureView: UIViewRepresentable {
    let onBegin: (TVRemoteScrubSample) -> Void
    let onChange: (TVRemoteScrubSample) -> Void
    let onCancel: () -> Void
    let onAvailabilityChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onBegin: onBegin,
            onChange: onChange,
            onCancel: onCancel,
            onAvailabilityChanged: onAvailabilityChanged
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let recognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        context.coordinator.hostView = view
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.reportUnavailableUntilCoordinatesArrive()
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onBegin = onBegin
        context.coordinator.onChange = onChange
        context.coordinator.onCancel = onCancel
        context.coordinator.onAvailabilityChanged = onAvailabilityChanged
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var hostView: UIView?
        var onBegin: (TVRemoteScrubSample) -> Void
        var onChange: (TVRemoteScrubSample) -> Void
        var onCancel: () -> Void
        var onAvailabilityChanged: (Bool) -> Void
        private var deliveredIndirectCoordinates = false
        private var gestureState = TVRemoteCircularScrubGestureState()

        init(
            onBegin: @escaping (TVRemoteScrubSample) -> Void,
            onChange: @escaping (TVRemoteScrubSample) -> Void,
            onCancel: @escaping () -> Void,
            onAvailabilityChanged: @escaping (Bool) -> Void
        ) {
            self.onBegin = onBegin
            self.onChange = onChange
            self.onCancel = onCancel
            self.onAvailabilityChanged = onAvailabilityChanged
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let hostView else { return }
            let action: TVRemoteCircularScrubGestureAction = switch recognizer.state {
            case .began: gestureState.handle(.began)
            case .changed: gestureState.handle(.changed)
            case .ended: gestureState.handle(.ended)
            case .cancelled: gestureState.handle(.cancelled)
            case .failed: gestureState.handle(.failed)
            case .possible: .none
            @unknown default: .none
            }
            switch action {
            case .beginSample, .changeSample:
                let location = recognizer.location(in: hostView)
                let sample = TVRemoteScrubSample(
                    location: location,
                    center: CGPoint(x: hostView.bounds.midX, y: hostView.bounds.midY),
                    timestamp: ProcessInfo.processInfo.systemUptime
                )
                if !deliveredIndirectCoordinates {
                    deliveredIndirectCoordinates = true
                    onAvailabilityChanged(true)
                }
                if action == .beginSample {
                    onBegin(sample)
                } else {
                    onChange(sample)
                }
            case .cancel:
                onCancel()
            case .none:
                break
            }
        }

        func reportUnavailableUntilCoordinatesArrive() {
            guard !deliveredIndirectCoordinates else { return }
            onAvailabilityChanged(false)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif
