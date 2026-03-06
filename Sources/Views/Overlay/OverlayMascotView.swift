import SwiftUI
import AVKit
import AppKit

/// SwiftUI content view for the overlay panel — plays a looping HEVC video with alpha transparency.
struct OverlayMascotView: View {
    let url: URL
    let onClose: () -> Void
    let onResize: (OverlaySize) -> Void
    let onDragResize: (Int) -> Void
    let onDragResizeEnd: (Int) -> Void
    let onSnooze: (Int) -> Void

    @AppStorage("overlay_size") private var currentSizePixels: Int = OverlaySize.medium.rawValue
    @AppStorage("overlay_resize_mode") private var resizeMode = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MascotVideoView(url: url)

            if resizeMode {
                ResizeHandle(
                    currentSize: currentSizePixels,
                    onDrag: onDragResize,
                    onDragEnd: { size in
                        onDragResizeEnd(size)
                        resizeMode = false
                    }
                )
                .frame(width: 32, height: 32)
            }
        }
    }
}

enum OverlaySize: Int, CaseIterable {
    case small = 100
    case medium = 150
    case large = 200
    case extraLarge = 300

    var cgSize: CGSize {
        CGSize(width: rawValue, height: rawValue)
    }
}

enum OverlayPosition {
    case bottomRight, bottomLeft, topRight, topLeft
}
