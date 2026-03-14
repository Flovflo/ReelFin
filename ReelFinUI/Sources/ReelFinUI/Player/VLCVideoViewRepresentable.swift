import SwiftUI

#if os(iOS)
import UIKit
#elseif os(tvOS)
import UIKit
#endif

struct VLCVideoViewRepresentable: UIViewRepresentable {
    let videoView: UIView

    func makeUIView(context: Context) -> UIView {
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return videoView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
