#if os(iOS)
import AVKit
import MediaPlayer
import SwiftUI
import UIKit

struct NativePlayerVolumeControl: View {
    var body: some View {
        HStack(spacing: 10) {
            NativePlayerVolumeSlider()
                .frame(height: 18)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .nativePlayerIOSGlassCapsule()
    }
}

struct NativePlayerRoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.backgroundColor = .clear
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = .white
        view.activeTintColor = .systemBlue
    }
}

private struct NativePlayerVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        view.backgroundColor = .clear
        style(view)
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        style(view)
    }

    private func style(_ view: MPVolumeView) {
        for subview in view.subviews {
            guard let slider = subview as? UISlider else { continue }
            slider.minimumTrackTintColor = .white
            slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.34)
            slider.thumbTintColor = .clear
            slider.setThumbImage(Self.clearThumbImage, for: .normal)
            slider.setThumbImage(Self.clearThumbImage, for: .highlighted)
        }
    }

    private static let clearThumbImage: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }()
}
#endif
