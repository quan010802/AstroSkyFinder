import SwiftUI
import MetalKit

struct MetalPreviewRepresentable: UIViewRepresentable {
    let processor: MetalStackProcessor
    var boostGain: Float
    var nightRed: Bool
    var loupeZoom: Float

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: processor.device)
        view.delegate = processor
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 30
        view.colorPixelFormat = .bgra8Unorm
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        processor.previewGain = boostGain
        processor.nightRedMode = nightRed
        processor.loupeZoom = loupeZoom
    }
}
