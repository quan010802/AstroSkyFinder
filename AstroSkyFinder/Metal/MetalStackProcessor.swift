import Foundation
import Metal
import MetalKit
import CoreImage
import CoreVideo
import Accelerate
import UniformTypeIdentifiers
import UIKit

struct PreviewUniforms {
    var gain: Float
    var nightRed: Float
    var centerX: Float
    var centerY: Float
    var loupeZoom: Float
    var outWidth: Float
    var outHeight: Float
    var inWidth: Float
    var inHeight: Float
}

struct StackUniforms {
    var shiftX: Float
    var shiftY: Float
    var cosTheta: Float
    var sinTheta: Float
    var centerX: Float
    var centerY: Float
    var weight: Float
}

struct StretchUniforms {
    var invFrameCount: Float
    var applyStretch: Float
    var beta: Float
    var floorLevel: Float
}

struct SimSkyUniforms {
    var width: Float
    var height: Float
    var focusSigma: Float
    var skyScale: Float
    var starScale: Float
    var shiftX: Float
    var shiftY: Float
}

struct FrameAlignmentResult {
    let shiftX: Float
    let shiftY: Float
    let thetaRad: Float
}

final class MetalStackProcessor: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let ciContext: CIContext

    private var previewPipeline: MTLComputePipelineState?
    private var accumPipeline: MTLComputePipelineState?
    private var stretchPipeline: MTLComputePipelineState?
    private var simSkyPipeline: MTLComputePipelineState?
    private var textureCache: CVMetalTextureCache?
    private var simPreviewTex: MTLTexture?
    private var simReadbackBuf = [UInt8](repeating: 0, count: 768 * 576 * 4)

    // Live camera preview controls updated from main thread / camera queue
    var latestPreviewTexture: MTLTexture?
    var previewGain: Float = 4.0
    var nightRedMode: Bool = false
    var loupeZoom: Float = 1.0

    private let previewLock = NSLock()

    override init() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            fatalError("Metal device unavailable on iOS hardware")
        }
        self.device = dev
        self.commandQueue = queue
        let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        self.ciContext = CIContext(mtlDevice: dev, options: [
            .workingColorSpace: linearSpace,
            .cacheIntermediates: false
        ])

        super.init()

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &textureCache)
        if let lib = dev.makeDefaultLibrary() {
            if let f1 = lib.makeFunction(name: "livePreviewBoost") {
                previewPipeline = try? dev.makeComputePipelineState(function: f1)
            }
            if let f2 = lib.makeFunction(name: "stackShiftAccumulate") {
                accumPipeline = try? dev.makeComputePipelineState(function: f2)
            }
            if let f3 = lib.makeFunction(name: "stackNormalizeStretch") {
                stretchPipeline = try? dev.makeComputePipelineState(function: f3)
            }
            if let f4 = lib.makeFunction(name: "renderSimulatedNightSky") {
                simSkyPipeline = try? dev.makeComputePipelineState(function: f4)
            }
        }
    }

    func updateSimulatedPreviewFrame(lensPosition: Float, iso: Float, exposureSec: Double, shiftX: Float, shiftY: Float) -> (sharpness: Double, medianSkyADU: Double) {
        let w = 768
        let h = 576
        if simPreviewTex == nil {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            simPreviewTex = device.makeTexture(descriptor: desc)
        }
        guard let tex = simPreviewTex, let pipe = simSkyPipeline, let cmdBuf = commandQueue.makeCommandBuffer(), let enc = cmdBuf.makeComputeCommandEncoder() else {
            return (0, 0)
        }

        // Focus sigma narrows cleanly to sharpest pinpoint at lensPosition == 0.935!
        let focusErr = abs(lensPosition - 0.935)
        let focusSigma = Float(1.30 + Double(focusErr) * 82.0)
        let expoScale = max(0.35, Float((iso / 640.0) * Float(exposureSec)))
        var u = SimSkyUniforms(
            width: Float(w),
            height: Float(h),
            focusSigma: focusSigma,
            skyScale: min(2.4, expoScale),
            starScale: min(2.2, expoScale),
            shiftX: shiftX,
            shiftY: shiftY
        )

        enc.setComputePipelineState(pipe)
        enc.setTexture(tex, index: 0)
        enc.setBytes(&u, length: MemoryLayout<SimSkyUniforms>.stride, index: 0)
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: (w + 15) / 16, height: (h + 15) / 16, depth: 1)
        enc.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        tex.getBytes(&simReadbackBuf, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let metrics = simReadbackBuf.withUnsafeBufferPointer { bp in
            Self.computeSharpnessFromBGRA(ptr: bp.baseAddress!, w: w, h: h, bpr: w * 4)
        }

        previewLock.lock()
        latestPreviewTexture = tex
        previewLock.unlock()
        return metrics
    }

    func generateSimulatedNightCIImage(lensPosition: Float, iso: Float, exposureSec: Double, shiftX: Float, shiftY: Float, width: Int = 1024, height: Int = 768) -> CIImage? {
        guard let pipe = simSkyPipeline, let cmdBuf = commandQueue.makeCommandBuffer(), let enc = cmdBuf.makeComputeCommandEncoder() else {
            return nil
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        let focusSigma = Float(1.40 + Double(abs(lensPosition - 0.935)) * 90.0)
        let expoScale = max(0.35, Float((iso / 640.0) * Float(exposureSec)))
        var u = SimSkyUniforms(
            width: Float(width), height: Float(height),
            focusSigma: focusSigma, skyScale: min(2.0, expoScale), starScale: min(2.0, expoScale),
            shiftX: shiftX, shiftY: shiftY
        )
        enc.setComputePipelineState(pipe)
        enc.setTexture(tex, index: 0)
        enc.setBytes(&u, length: MemoryLayout<SimSkyUniforms>.stride, index: 0)
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        enc.dispatchThreadgroups(MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1), threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        return CIImage(mtlTexture: tex, options: [.colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
    }

    func updateLiveSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let cache = textureCache,
              let pixBuf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixBuf)
        let h = CVPixelBufferGetHeight(pixBuf)
        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixBuf, nil,
            .bgra8Unorm, w, h, 0, &cvTex
        )
        guard status == kCVReturnSuccess, let cvT = cvTex, let mtlTex = CVMetalTextureGetTexture(cvT) else { return }

        previewLock.lock()
        latestPreviewTexture = mtlTex
        previewLock.unlock()
    }

    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        previewLock.lock()
        let srcTex = latestPreviewTexture
        previewLock.unlock()

        guard let inTex = srcTex,
              let pipeline = previewPipeline,
              let drawable = view.currentDrawable,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let enc = cmdBuf.makeComputeCommandEncoder() else { return }

        let dstTex = drawable.texture
        var uniforms = PreviewUniforms(
            gain: previewGain,
            nightRed: nightRedMode ? 1.0 : 0.0,
            centerX: 0.5,
            centerY: 0.5,
            loupeZoom: loupeZoom,
            outWidth: Float(dstTex.width),
            outHeight: Float(dstTex.height),
            inWidth: Float(inTex.width),
            inHeight: Float(inTex.height)
        )

        enc.setComputePipelineState(pipeline)
        enc.setTexture(inTex, index: 0)
        enc.setTexture(dstTex, index: 1)
        enc.setBytes(&uniforms, length: MemoryLayout<PreviewUniforms>.stride, index: 0)

        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: (dstTex.width + 15) / 16, height: (dstTex.height + 15) / 16, depth: 1)
        enc.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Real-time Star Sharpness & Sky Brightness Analysis on Center ROI
    static func measureCenterStarMetrics(sampleBuffer: CMSampleBuffer) -> (sharpness: Double, medianSkyADU: Double) {
        guard let pixBuf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return (0, 0) }
        CVPixelBufferLockBaseAddress(pixBuf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixBuf, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixBuf) else { return (0, 0) }
        let w = CVPixelBufferGetWidth(pixBuf)
        let h = CVPixelBufferGetHeight(pixBuf)
        let bpr = CVPixelBufferGetBytesPerRow(pixBuf)
        return computeSharpnessFromBGRA(ptr: base.assumingMemoryBound(to: UInt8.self), w: w, h: h, bpr: bpr)
    }

    static func computeSharpnessFromBGRA(ptr: UnsafePointer<UInt8>, w: Int, h: Int, bpr: Int) -> (sharpness: Double, medianSkyADU: Double) {
        let roiSize = min(180, min(w, h) - 6)
        guard roiSize > 10 else { return (0, 0) }
        let x0 = max(2, (w - roiSize) / 2)
        let y0 = max(2, (h - roiSize) / 2)
        let x1 = min(w - 2, x0 + roiSize)
        let y1 = min(h - 2, y0 + roiSize)

        var vals = [Float]()
        vals.reserveCapacity((y1 - y0) * (x1 - x0))
        var gradSum: Double = 0.0

        for y in y0..<y1 {
            let row = ptr + y * bpr
            let rowUp = ptr + (y - 1) * bpr
            let rowDn = ptr + (y + 1) * bpr
            for x in x0..<x1 {
                let off = x * 4
                let l = 0.2126 * Float(row[off + 2]) + 0.7152 * Float(row[off + 1]) + 0.0722 * Float(row[off])
                vals.append(l)

                let gx = Float(row[off + 5]) - Float(row[off - 3])
                let gy = Float(rowDn[off + 1]) - Float(rowUp[off + 1])
                gradSum += Double(gx * gx + gy * gy)
            }
        }

        guard !vals.isEmpty else { return (0, 0) }
        vals.sort()
        let med = Double(vals[vals.count / 2])
        let p999 = Double(vals[Int(Double(vals.count - 1) * 0.999)])
        let contrastPeak = max(0.0, p999 - med)
        let sharpness = sqrt(gradSum / Double(vals.count)) + contrastPeak * 0.35
        return (sharpness, med)
    }

    // MARK: - On-Device RAW DNG & Synthetic Linear Multi-Frame Aligned Stacker (Metal + Accelerate)
    func stackRawDNGFrames(dngDatas: [Data], progressHandler: @escaping (Int, Int) -> Void) -> (linearTIFFData: Data?, previewImage: UIImage?) {
        let dngHint = UTType(filenameExtension: "dng")?.identifier ?? "com.adobe.raw-image"
        let ciList: [CIImage] = dngDatas.compactMap { dng in
            guard let rawFilter = CIRAWFilter(imageData: dng, identifierHint: dngHint) else { return nil }
            if rawFilter.isLuminanceNoiseReductionSupported { rawFilter.luminanceNoiseReductionAmount = 0.0 }
            if rawFilter.isColorNoiseReductionSupported { rawFilter.colorNoiseReductionAmount = 0.0 }
            if rawFilter.isSharpnessSupported { rawFilter.sharpnessAmount = 0.0 }
            return rawFilter.outputImage
        }
        return stackLinearCIImages(ciList, progressHandler: progressHandler)
    }

    func stackLinearCIImages(_ images: [CIImage], progressHandler: @escaping (Int, Int) -> Void) -> (linearTIFFData: Data?, previewImage: UIImage?) {
        guard !images.isEmpty,
              let accumPipe = accumPipeline,
              let stretchPipe = stretchPipeline else { return (nil, nil) }

        var accA: MTLTexture?
        var accB: MTLTexture?
        var refPatchL: [Float]?
        var refPatchR: [Float]?
        var width = 0
        var height = 0
        let dsScale: CGFloat = 0.25

        for (idx, ciImg) in images.enumerated() {
            autoreleasepool {
                let ext = ciImg.extent
                if idx == 0 {
                    width = Int(ext.width)
                    height = Int(ext.height)
                    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
                    desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
                    accA = device.makeTexture(descriptor: desc)
                    accB = device.makeTexture(descriptor: desc)
                }

                guard let dstA = accA, let dstB = accB else { return }
                let frameDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
                frameDesc.usage = [.shaderRead, .renderTarget]
                guard let frameTex = device.makeTexture(descriptor: frameDesc),
                      let cmdBuf = commandQueue.makeCommandBuffer() else { return }

                let linSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
                ciContext.render(ciImg, to: frameTex, commandBuffer: cmdBuf, bounds: ext, colorSpace: linSpace)
                cmdBuf.commit()
                cmdBuf.waitUntilCompleted()

                let (pL, pR) = extractTwoStarPatches(ciImage: ciImg, scale: dsScale)
                var alignment = FrameAlignmentResult(shiftX: 0, shiftY: 0, thetaRad: 0)
                if idx == 0 {
                    refPatchL = pL
                    refPatchR = pR
                    clearTexture(dstA)
                } else if let rL = refPatchL, let rR = refPatchR {
                    alignment = estimateShiftAndRotation(refL: rL, refR: rR, curL: pL, curR: pR, dsFactor: Float(1.0 / dsScale), fullW: Float(width))
                }

                let srcAcc = (idx % 2 == 0) ? dstA : dstB
                let outAcc = (idx % 2 == 0) ? dstB : dstA

                guard let accCmd = commandQueue.makeCommandBuffer(),
                      let enc = accCmd.makeComputeCommandEncoder() else { return }
                var su = StackUniforms(
                    shiftX: alignment.shiftX,
                    shiftY: alignment.shiftY,
                    cosTheta: cos(alignment.thetaRad),
                    sinTheta: sin(alignment.thetaRad),
                    centerX: Float(width) * 0.5,
                    centerY: Float(height) * 0.5,
                    weight: 1.0
                )
                enc.setComputePipelineState(accumPipe)
                enc.setTexture(frameTex, index: 0)
                enc.setTexture(srcAcc, index: 1)
                enc.setTexture(outAcc, index: 2)
                enc.setBytes(&su, length: MemoryLayout<StackUniforms>.stride, index: 0)
                let tg = MTLSize(width: 16, height: 16, depth: 1)
                let grid = MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1)
                enc.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
                enc.endEncoding()
                accCmd.commit()
                accCmd.waitUntilCompleted()
            }
            DispatchQueue.main.async {
                progressHandler(idx + 1, images.count)
            }
        }

        let finalSumTex = (images.count % 2 == 1) ? accB : accA
        guard let sumTex = finalSumTex, width > 0, height > 0 else { return (nil, nil) }

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        outDesc.usage = [.shaderRead, .shaderWrite]
        guard let linTex = device.makeTexture(descriptor: outDesc),
              let stretchTex = device.makeTexture(descriptor: outDesc) else { return (nil, nil) }

        runStretchPass(pipeline: stretchPipe, sumTex: sumTex, outTex: linTex, applyStretch: false, count: images.count)
        runStretchPass(pipeline: stretchPipe, sumTex: sumTex, outTex: stretchTex, applyStretch: true, count: images.count)

        let p3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        var tiffData: Data?
        if let ciLin = CIImage(mtlTexture: linTex, options: [.colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!]) {
            tiffData = ciContext.tiffRepresentation(of: ciLin, format: .RGBA16, colorSpace: p3, options: [:])
        }

        var previewUI: UIImage?
        if let ciPrev = CIImage(mtlTexture: stretchTex, options: [.colorSpace: p3]) {
            if let cg = ciContext.createCGImage(ciPrev, from: ciPrev.extent) {
                previewUI = UIImage(cgImage: cg)
            }
        }
        return (tiffData, previewUI)
    }

    private func runStretchPass(pipeline: MTLComputePipelineState, sumTex: MTLTexture, outTex: MTLTexture, applyStretch: Bool, count: Int) {
        guard let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { return }
        var u = StretchUniforms(
            invFrameCount: 1.0 / Float(max(1, count)),
            applyStretch: applyStretch ? 1.0 : 0.0,
            beta: 26.0,
            floorLevel: 0.045
        )
        enc.setComputePipelineState(pipeline)
        enc.setTexture(sumTex, index: 0)
        enc.setTexture(outTex, index: 1)
        enc.setBytes(&u, length: MemoryLayout<StretchUniforms>.stride, index: 0)
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: (outTex.width + 15) / 16, height: (outTex.height + 15) / 16, depth: 1)
        enc.dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    private func clearTexture(_ tex: MTLTexture) {
        let zeroCount = tex.width * tex.height * 4
        var zeros = [UInt16](repeating: 0, count: zeroCount)
        tex.replace(region: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0, withBytes: &zeros, bytesPerRow: tex.width * 8)
    }

    // Downsampled 2-zone high-pass star patch extraction (96x96 each at 0.25x scale = 384x384px full-res regions)
    private func extractTwoStarPatches(ciImage: CIImage, scale: CGFloat) -> ([Float], [Float]) {
        let small = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let ext = small.extent
        let ps = 96
        let leftRect = CGRect(x: ext.minX + ext.width * 0.22 - CGFloat(ps / 2), y: ext.midY - CGFloat(ps / 2), width: CGFloat(ps), height: CGFloat(ps))
        let rightRect = CGRect(x: ext.minX + ext.width * 0.78 - CGFloat(ps / 2), y: ext.midY - CGFloat(ps / 2), width: CGFloat(ps), height: CGFloat(ps))
        return (renderLumaPatch(small, rect: leftRect, size: ps), renderLumaPatch(small, rect: rightRect, size: ps))
    }

    private func renderLumaPatch(_ img: CIImage, rect: CGRect, size: Int) -> [Float] {
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        ciContext.render(img, toBitmap: &rgba, rowBytes: size * 4, bounds: rect, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var luma = [Float](repeating: 0, count: size * size)
        var mean: Float = 0
        for i in 0..<(size * size) {
            let l = 0.2126 * Float(rgba[i * 4]) + 0.7152 * Float(rgba[i * 4 + 1]) + 0.0722 * Float(rgba[i * 4 + 2])
            luma[i] = l
            mean += l
        }
        mean /= Float(max(1, size * size))
        for i in 0..<luma.count { luma[i] = max(0, luma[i] - mean) }
        return luma
    }

    private func findPatchShift(ref: [Float], cur: [Float], size: Int = 96, maxLag: Int = 14) -> (Float, Float) {
        var bestScore: Float = -1e9
        var bestDy = 0
        var bestDx = 0
        let win = size - 2 * maxLag

        for dy in -maxLag...maxLag {
            for dx in -maxLag...maxLag {
                var sum: Float = 0
                for y in maxLag..<(maxLag + win) {
                    let rOff = y * size + maxLag
                    let cOff = (y + dy) * size + (maxLag + dx)
                    var dot: Float = 0
                    ref.withUnsafeBufferPointer { rp in
                        cur.withUnsafeBufferPointer { cp in
                            vDSP_dotpr(rp.baseAddress! + rOff, 1, cp.baseAddress! + cOff, 1, &dot, vDSP_Length(win))
                        }
                    }
                    sum += dot
                }
                if sum > bestScore {
                    bestScore = sum
                    bestDy = dy
                    bestDx = dx
                }
            }
        }
        return (Float(bestDx), Float(bestDy))
    }

    private func estimateShiftAndRotation(refL: [Float], refR: [Float], curL: [Float], curR: [Float], dsFactor: Float, fullW: Float) -> FrameAlignmentResult {
        let (dxL, dyL) = findPatchShift(ref: refL, cur: curL)
        let (dxR, dyR) = findPatchShift(ref: refR, cur: curR)
        let sx = 0.5 * (dxL + dxR) * dsFactor
        let sy = 0.5 * (dyL + dyR) * dsFactor
        // Separation between patch centers is 0.56 * fullW
        let sep = max(100.0, 0.56 * fullW)
        let dTheta = atan2((dyR - dyL) * dsFactor, sep)
        return FrameAlignmentResult(shiftX: sx, shiftY: sy, thetaRad: dTheta)
    }
}
