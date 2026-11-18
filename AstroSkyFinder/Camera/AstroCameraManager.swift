import Foundation
import AVFoundation
import CoreVideo
import CoreImage
import Photos
import UIKit
import Combine
import UniformTypeIdentifiers

enum CapturePipelineMode: String, CaseIterable, Identifiable {
    case rawSequence = "RAW DNG"
    case metalStack = "Gộp Metal"
    case both = "Cả 2 (RAW+Gộp)"
    var id: String { rawValue }
}

struct CameraLensOption: Identifiable, Equatable {
    let id: String
    let label: String
    let device: AVCaptureDevice?
    let aperture: Float
    let fovDeg: Double
    let eqFocalMm: Double
    let minISO: Float
    let maxISO: Float
    let minExposureSec: Double
    let maxExposureSec: Double
}

struct SessionSummary: Identifiable {
    let id: String
    let folderURL: URL
    let date: Date
    let rawCount: Int
    let stackedImageURL: URL?
    let stackedTIFFURL: URL?
}

final class AstroCameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    let metalProcessor = MetalStackProcessor()

    private let sessionQueue = DispatchQueue(label: "com.astro.camera.sessionQueue")
    private let videoQueue = DispatchQueue(label: "com.astro.camera.videoQueue")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()

    private var videoInput: AVCaptureDeviceInput?
    private var videoConnection: AVCaptureConnection?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObserver: NSKeyValueObservation?

    // Discovered back cameras & selected lens
    @Published var availableLenses: [CameraLensOption] = []
    @Published var selectedLensIndex: Int = 0

    // Manual & Auto exposure / focus controls
    @Published var isoValue: Float = 640
    @Published var exposureSeconds: Double = 1.0
    @Published var lensPosition: Float = 0.92
    @Published var isFocusLocked: Bool = false
    @Published var isAutoFocusing: Bool = false
    @Published var autoFocusStatus: String = "Chưa khóa nét sao"
    @Published var liveSharpnessScore: Double = 0.0
    @Published var liveSkyADU: Double = 0.0
    @Published var npfMaxShutterSec: Double = 11.5

    // Sequence / Metal Stacker settings
    @Published var captureMode: CapturePipelineMode = .both
    @Published var sequenceCount: Int = 60
    @Published var syntheticFrames: Int = 10   // e.g. 10 x 1.0s = 10s Metal aligned stack
    @Published var delaySeconds: Int = 3
    @Published var saveDNGToPhotos: Bool = false
    @Published var autoBrightnessBoost: Float = 4.0

    // Live capture run state
    @Published var isCapturing: Bool = false
    @Published var countdownRemaining: Int = 0
    @Published var capturedCount: Int = 0
    @Published var isStackingOnMetal: Bool = false
    @Published var stackingProgressText: String = ""
    @Published var statusMessage: String = "Sẵn sàng"
    @Published var latestStackedPreview: UIImage?
    @Published var savedSessions: [SessionSummary] = []

    // Internal auto-focus sampling & sequence tracking
    private var focusSampleLock = NSLock()
    private var recentSharpnessSamples: [Double] = []
    private var activeSessionDir: URL?
    private var activeFrameTarget: Int = 0
    private var capturedDNGURLs: [URL] = []
    private var simCapturedImages: [CIImage] = []
    private var cancelRequested: Bool = false
    private var countdownTimer: Timer?
    private var simPreviewTimer: Timer?
    private var isSimulatorMode: Bool = false
    private var simShiftTick: Float = 0.0

    override init() {
        super.init()
        loadSavedSessions()
    }

    deinit {
        simPreviewTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    func requestPermissionAndStart() {
        #if targetEnvironment(simulator)
        setupSimulatorVirtualCamera()
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configureSession() }
            }
        default:
            DispatchQueue.main.async {
                self.statusMessage = "Thiếu quyền Camera — hãy bật trong Cài đặt"
            }
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
        #endif
    }

    private func setupSimulatorVirtualCamera() {
        isSimulatorMode = true
        let wideOpt = CameraLensOption(id: "sim_wide", label: "1x", device: nil, aperture: 1.6, fovDeg: 69.0, eqFocalMm: 26.0, minISO: 50, maxISO: 3200, minExposureSec: 0.05, maxExposureSec: 1.0)
        let uwOpt = CameraLensOption(id: "sim_uw", label: "0.5x", device: nil, aperture: 2.2, fovDeg: 109.0, eqFocalMm: 13.0, minISO: 50, maxISO: 1600, minExposureSec: 0.05, maxExposureSec: 1.0)
        availableLenses = [wideOpt, uwOpt]
        selectedLensIndex = 0
        isoValue = 640
        exposureSeconds = 1.0
        lensPosition = 0.86
        npfMaxShutterSec = SkyMath.maxSharpShutterSeconds(focalLength35mm: 26.0)
        statusMessage = "Chế độ Giả lập Simulator (Bầu trời Metal + AR)"

        simPreviewTimer?.invalidate()
        simPreviewTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.simShiftTick += 0.05
            let lp = self.lensPosition
            let iso = self.isoValue
            let exp = self.exposureSeconds
            let m = self.metalProcessor.updateSimulatedPreviewFrame(
                lensPosition: lp, iso: iso, exposureSec: exp,
                shiftX: 2.0 * sin(self.simShiftTick), shiftY: 1.5 * cos(self.simShiftTick * 0.7)
            )
            self.focusSampleLock.lock()
            self.recentSharpnessSamples.append(m.sharpness)
            if self.recentSharpnessSamples.count > 6 { self.recentSharpnessSamples.removeFirst() }
            self.focusSampleLock.unlock()
            self.liveSharpnessScore = m.sharpness
            self.liveSkyADU = m.medianSkyADU
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
                mediaType: .video,
                position: .back
            )

            var options: [CameraLensOption] = []
            for dev in discovery.devices {
                let fov = Double(dev.activeFormat.videoFieldOfView)
                // Standard 35mm sensor width 36mm -> eqFocal = 18 / tan(fov/2)
                let eqFocal = 18.0 / max(0.08, tan((fov * .pi / 180.0) * 0.5))
                let shortName: String
                switch dev.deviceType {
                case .builtInUltraWideCamera: shortName = "0.5x"
                case .builtInWideAngleCamera: shortName = "1x"
                case .builtInTelephotoCamera: shortName = "Tele"
                default: shortName = "Cam"
                }
                let opt = CameraLensOption(
                    id: dev.uniqueID,
                    label: shortName,
                    device: dev,
                    aperture: dev.lensAperture,
                    fovDeg: fov,
                    eqFocalMm: eqFocal,
                    minISO: dev.activeFormat.minISO,
                    maxISO: dev.activeFormat.maxISO,
                    minExposureSec: dev.activeFormat.minExposureDuration.seconds,
                    maxExposureSec: dev.activeFormat.maxExposureDuration.seconds
                )
                options.append(opt)
            }

            // Prefer 1x Wide first
            options.sort { a, b in
                if a.label == "1x" { return true }
                if b.label == "1x" { return false }
                return a.label < b.label
            }

            DispatchQueue.main.async {
                self.availableLenses = options
                self.selectedLensIndex = 0
            }

            guard let firstLens = options.first, let firstDev = firstLens.device else {
                DispatchQueue.main.async { self.setupSimulatorVirtualCamera() }
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            do {
                let input = try AVCaptureDeviceInput(device: firstDev)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoInput = input
                }

                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                    self.videoConnection = self.videoOutput.connection(with: .video)
                }

                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    if let rawDim = firstDev.activeFormat.supportedMaxPhotoDimensions.last(where: { Int64($0.width) * Int64($0.height) <= 13_000_000 }) {
                        self.photoOutput.maxPhotoDimensions = rawDim
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Lỗi khởi tạo camera: \(error.localizedDescription)"
                }
            }

            self.session.commitConfiguration()
            self.setupRotationCoordinator(for: firstDev)
            self.syncInitialCameraSettings(lens: firstLens)
            self.session.startRunning()
        }
    }

    private func setupRotationCoordinator(for device: AVCaptureDevice) {
        let coord = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        self.rotationCoordinator = coord
        if let conn = self.videoConnection {
            let initAngle = coord.videoRotationAngleForHorizonLevelPreview
            if conn.isVideoRotationAngleSupported(initAngle) {
                conn.videoRotationAngle = initAngle
            }
        }
        self.rotationObserver = coord.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, ch in
            guard let self = self, let angle = ch.newValue, let conn = self.videoConnection else { return }
            self.sessionQueue.async {
                if conn.isVideoRotationAngleSupported(angle) {
                    conn.videoRotationAngle = angle
                }
            }
        }
    }

    private func syncInitialCameraSettings(lens: CameraLensOption) {
        let targetISO = min(lens.maxISO, max(lens.minISO, 640))
        let targetExp = min(lens.maxExposureSec, 1.0)
        let npf = SkyMath.maxSharpShutterSeconds(focalLength35mm: lens.eqFocalMm)

        DispatchQueue.main.async {
            self.isoValue = targetISO
            self.exposureSeconds = targetExp
            self.npfMaxShutterSec = npf
            self.lensPosition = 0.90
            self.applyExposureSettings()
        }
    }

    func switchLens(to index: Int) {
        guard index >= 0, index < availableLenses.count, !isCapturing else { return }
        let lens = availableLenses[index]
        selectedLensIndex = index
        if isSimulatorMode {
            syncInitialCameraSettings(lens: lens)
            return
        }
        guard let dev = lens.device else { return }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            if let old = self.videoInput { self.session.removeInput(old) }
            do {
                let newIn = try AVCaptureDeviceInput(device: dev)
                if self.session.canAddInput(newIn) {
                    self.session.addInput(newIn)
                    self.videoInput = newIn
                    self.videoConnection = self.videoOutput.connection(with: .video)
                    if let rawDim = dev.activeFormat.supportedMaxPhotoDimensions.last(where: { Int64($0.width) * Int64($0.height) <= 13_000_000 }) {
                        self.photoOutput.maxPhotoDimensions = rawDim
                    }
                }
            } catch {
                DispatchQueue.main.async { self.statusMessage = "Lỗi đổi ống kính" }
            }
            self.session.commitConfiguration()
            self.setupRotationCoordinator(for: dev)
            self.syncInitialCameraSettings(lens: lens)
        }
    }

    var currentLens: CameraLensOption? {
        guard selectedLensIndex >= 0, selectedLensIndex < availableLenses.count else { return nil }
        return availableLenses[selectedLensIndex]
    }

    func applyExposureSettings() {
        guard let dev = videoInput?.device else { return }
        let clampedISO = max(dev.activeFormat.minISO, min(dev.activeFormat.maxISO, isoValue))
        let clampedSec = max(dev.activeFormat.minExposureDuration.seconds, min(dev.activeFormat.maxExposureDuration.seconds, exposureSeconds))
        let cmDur = CMTime(seconds: clampedSec, preferredTimescale: 1_000_000)

        sessionQueue.async {
            do {
                try dev.lockForConfiguration()
                dev.setExposureModeCustom(duration: cmDur, iso: clampedISO, completionHandler: nil)
                dev.unlockForConfiguration()
            } catch {}
        }
    }

    func applyManualFocus(position: Float) {
        let pos = max(0.0, min(1.0, position))
        lensPosition = pos
        isFocusLocked = true
        autoFocusStatus = String(format: "MF khóa: %.3f", pos)
        guard !isSimulatorMode, let dev = videoInput?.device, dev.isLockingFocusWithCustomLensPositionSupported else { return }

        sessionQueue.async {
            do {
                try dev.lockForConfiguration()
                dev.setFocusModeLocked(lensPosition: pos, completionHandler: nil)
                dev.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: - Auto Star Focus Sweep (Solves Even Longer 18.9px Out-of-Focus Bug!)
    func startAutoStarFocus() {
        guard !isAutoFocusing, !isCapturing else { return }
        if !isSimulatorMode {
            guard let dev = videoInput?.device, dev.isLockingFocusWithCustomLensPositionSupported else { return }
        }
        isAutoFocusing = true
        autoFocusStatus = "Đang quét nét sao (0.78 → 1.00)..."
        metalProcessor.loupeZoom = 4.0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var bestPos: Float = 0.90
            var bestScore: Double = -1.0

            // Coarse sweep from 0.78 to 1.00 in 0.02 increments
            var p: Float = 0.78
            while p <= 1.001 {
                let score = self.measureFocusPosition(device: self.videoInput?.device, pos: p)
                if score > bestScore {
                    bestScore = score
                    bestPos = p
                }
                DispatchQueue.main.async {
                    self.lensPosition = p
                    self.autoFocusStatus = String(format: "Quét %.2f · Nét: %.1f", p, score)
                }
                p += 0.02
            }

            // Fine sweep ±0.015 around peak in 0.005 increments
            var fineBestPos = bestPos
            var fineBestScore = bestScore
            let fStart = max(0.0, bestPos - 0.015)
            let fEnd = min(1.0, bestPos + 0.015)
            var fp = fStart
            while fp <= fEnd + 0.0005 {
                let score = self.measureFocusPosition(device: self.videoInput?.device, pos: fp)
                if score > fineBestScore {
                    fineBestScore = score
                    fineBestPos = fp
                }
                fp += 0.005
            }

            if let dev = self.videoInput?.device {
                try? dev.lockForConfiguration()
                dev.setFocusModeLocked(lensPosition: fineBestPos, completionHandler: nil)
                dev.unlockForConfiguration()
            }

            DispatchQueue.main.async {
                self.lensPosition = fineBestPos
                self.isFocusLocked = true
                self.isAutoFocusing = false
                self.metalProcessor.loupeZoom = 1.0
                self.autoFocusStatus = String(format: "Đã khóa nét chuẩn sao: %.3f (Đỉnh %.1f)", fineBestPos, fineBestScore)
                self.statusMessage = self.autoFocusStatus
            }
        }
    }

    private func measureFocusPosition(device: AVCaptureDevice?, pos: Float) -> Double {
        let clamped = min(1.0, max(0.0, pos))
        if let dev = device {
            let sem = DispatchSemaphore(value: 0)
            try? dev.lockForConfiguration()
            dev.setFocusModeLocked(lensPosition: clamped) { _ in sem.signal() }
            dev.unlockForConfiguration()
            _ = sem.wait(timeout: .now() + 0.5)
        } else {
            DispatchQueue.main.async { self.lensPosition = clamped }
        }

        // Wait for new frames at settled lensPosition and clear older buffer
        focusSampleLock.lock()
        recentSharpnessSamples.removeAll()
        focusSampleLock.unlock()

        Thread.sleep(forTimeInterval: device == nil ? 0.12 : 0.24)

        focusSampleLock.lock()
        let samples = recentSharpnessSamples
        focusSampleLock.unlock()
        guard !samples.isEmpty else { return 0.0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    // MARK: - Auto Astro Exposure Calibration based on Live Sky Brightness
    func applyAutoAstroRecommendation(target: AstroTarget?) {
        guard let lens = currentLens else { return }
        let sky = liveSkyADU
        var recISO: Float = target?.recommendedISO ?? 640
        if sky < 12.0 {
            recISO = min(lens.maxISO, max(recISO, 800))
        } else if sky > 55.0 {
            // Light-polluted / moonlit sky -> keep ISO modest to avoid highlight clipping
            recISO = min(lens.maxISO, max(lens.minISO, 320))
        }
        isoValue = max(lens.minISO, min(lens.maxISO, recISO))
        exposureSeconds = lens.maxExposureSec
        applyExposureSettings()
        statusMessage = String(format: "Auto Thiên văn: f/%.1f · ISO %.0f · %.2fs", lens.aperture, isoValue, exposureSeconds)
    }

    // MARK: - Capture Start / Stop
    func startCapturePipeline() {
        guard !isCapturing, !isStackingOnMetal else { return }
        cancelRequested = false
        capturedCount = 0
        capturedDNGURLs.removeAll()
        simCapturedImages.removeAll()

        let countToShoot: Int = (captureMode == .metalStack) ? syntheticFrames : sequenceCount
        activeFrameTarget = max(1, countToShoot)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let dirName = "Session_\(fmt.string(from: Date()))"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sessionDir = docs.appendingPathComponent("AstroSkyFinder", isDirectory: true).appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        activeSessionDir = sessionDir

        isCapturing = true
        if delaySeconds > 0 {
            countdownRemaining = delaySeconds
            statusMessage = "Chờ ổn định chân máy: \(countdownRemaining)s..."
            countdownTimer?.invalidate()
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
                guard let self = self else { t.invalidate(); return }
                if self.cancelRequested {
                    t.invalidate()
                    self.finishCapture(cancelled: true)
                    return
                }
                self.countdownRemaining -= 1
                if self.countdownRemaining <= 0 {
                    t.invalidate()
                    self.statusMessage = "Đang chụp 0/\(self.activeFrameTarget)..."
                    self.triggerNextRawShot()
                } else {
                    self.statusMessage = "Chờ ổn định chân máy: \(self.countdownRemaining)s..."
                }
            }
        } else {
            statusMessage = "Đang chụp 0/\(activeFrameTarget)..."
            triggerNextRawShot()
        }
    }

    func cancelCapture() {
        cancelRequested = true
        countdownTimer?.invalidate()
        if capturedCount > 0 && (captureMode == .metalStack || captureMode == .both) {
            statusMessage = "Đang dừng & gộp \(capturedCount) ảnh đã chụp..."
        } else {
            finishCapture(cancelled: true)
        }
    }

    private func triggerNextRawShot() {
        guard !cancelRequested else {
            finishCapture(cancelled: false)
            return
        }
        if isSimulatorMode {
            let nextIdx = capturedCount + 1
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                let sx = Float(nextIdx - 1) * 1.6
                let sy = Float(nextIdx - 1) * -0.9
                if let ci = self.metalProcessor.generateSimulatedNightCIImage(lensPosition: self.lensPosition, iso: self.isoValue, exposureSec: self.exposureSeconds, shiftX: sx, shiftY: sy) {
                    self.simCapturedImages.append(ci)
                }
                DispatchQueue.main.async {
                    self.capturedCount = nextIdx
                    self.statusMessage = "Simulator giả lập \(nextIdx)/\(self.activeFrameTarget)"
                    if nextIdx < self.activeFrameTarget && !self.cancelRequested {
                        self.triggerNextRawShot()
                    } else {
                        self.finishCapture(cancelled: false)
                    }
                }
            }
            return
        }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let types = self.photoOutput.availableRawPhotoPixelFormatTypes
            // Prefer true linear Bayer RAW over Apple ProRAW to prevent internal iOS denoising!
            let rawType = types.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) ?? types.first

            guard let rawFmt = rawType else {
                DispatchQueue.main.async {
                    self.statusMessage = "Ống kính hiện tại không hỗ trợ RAW (.DNG)"
                    self.finishCapture(cancelled: true)
                }
                return
            }

            let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFmt, processedFormat: nil)
            if settings.isAutoStillImageStabilizationSupported {
                settings.isAutoStillImageStabilizationEnabled = false
            }
            if let conn = self.photoOutput.connection(with: .video),
               let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
               conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func finishCapture(cancelled: Bool) {
        DispatchQueue.main.async {
            self.isCapturing = false
            self.countdownRemaining = 0
        }

        if cancelled && capturedDNGURLs.isEmpty && simCapturedImages.isEmpty {
            DispatchQueue.main.async { self.statusMessage = "Đã hủy chụp" }
            return
        }

        if isSimulatorMode && !simCapturedImages.isEmpty {
            runMetalStackOnSimulatorFrames(images: simCapturedImages)
            return
        }

        if (captureMode == .metalStack || captureMode == .both), !capturedDNGURLs.isEmpty {
            runMetalStackOnSession(urls: capturedDNGURLs, keepRawFiles: captureMode == .both)
        } else {
            loadSavedSessions()
            DispatchQueue.main.async {
                self.statusMessage = "Xong! Đã lưu \(self.capturedDNGURLs.count) ảnh RAW (.DNG) vào Tệp"
            }
        }
    }

    private func runMetalStackOnSimulatorFrames(images: [CIImage]) {
        DispatchQueue.main.async {
            self.isStackingOnMetal = true
            self.stackingProgressText = "Gộp Metal giả lập 0/\(images.count)..."
            self.statusMessage = self.stackingProgressText
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let dir = self.activeSessionDir else { return }
            let result = self.metalProcessor.stackLinearCIImages(images) { done, total in
                self.stackingProgressText = "Gộp Metal giả lập \(done)/\(total)..."
                self.statusMessage = self.stackingProgressText
            }
            if let tiff = result.linearTIFFData {
                try? tiff.write(to: dir.appendingPathComponent("stacked_linear_16bit.tiff"))
            }
            if let ui = result.previewImage, let jpg = ui.jpegData(compressionQuality: 0.95) {
                try? jpg.write(to: dir.appendingPathComponent("stacked_astro_preview.jpg"))
            }
            DispatchQueue.main.async {
                self.isStackingOnMetal = false
                self.latestStackedPreview = result.previewImage
                self.loadSavedSessions()
                self.statusMessage = "Simulator gộp Metal xong \(images.count) ảnh!"
            }
        }
    }

    private func runMetalStackOnSession(urls: [URL], keepRawFiles: Bool) {
        DispatchQueue.main.async {
            self.isStackingOnMetal = true
            self.stackingProgressText = "Đang căn chỉnh & gộp Metal 0/\(urls.count)..."
            self.statusMessage = self.stackingProgressText
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let dir = self.activeSessionDir else { return }
            let dngs = urls.compactMap { try? Data(contentsOf: $0) }
            let result = self.metalProcessor.stackRawDNGFrames(dngDatas: dngs) { done, total in
                self.stackingProgressText = "Đang căn chỉnh & gộp Metal \(done)/\(total)..."
                self.statusMessage = self.stackingProgressText
            }

            if let tiff = result.linearTIFFData {
                let tiffURL = dir.appendingPathComponent("stacked_linear_16bit.tiff")
                try? tiff.write(to: tiffURL)
            }

            if let ui = result.previewImage, let jpgData = ui.jpegData(compressionQuality: 0.96) {
                let jpgURL = dir.appendingPathComponent("stacked_astro_preview.jpg")
                try? jpgData.write(to: jpgURL)
                self.saveImageToPhotos(data: jpgData)
            }

            if !keepRawFiles {
                for u in urls { try? FileManager.default.removeItem(at: u) }
            }

            DispatchQueue.main.async {
                self.isStackingOnMetal = false
                self.latestStackedPreview = result.previewImage
                self.loadSavedSessions()
                self.statusMessage = "Hoàn tất gộp Metal \(urls.count) ảnh! Đã lưu vào Ảnh & Tệp."
            }
        }
    }

    private func saveDNGToPhotosIfRequested(data: Data) {
        guard saveDNGToPhotos else { return }
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCreationRequest.forAsset()
            let opts = PHAssetResourceCreationOptions()
            opts.uniformTypeIdentifier = UTType.rawImage.identifier
            req.addResource(with: .photo, data: data, options: opts)
        }, completionHandler: nil)
    }

    private func saveImageToPhotos(data: Data) {
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: data, options: nil)
        }, completionHandler: nil)
    }

    func loadSavedSessions() {
        DispatchQueue.global(qos: .utility).async {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let root = docs.appendingPathComponent("AstroSkyFinder", isDirectory: true)
            guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else {
                return
            }
            var list: [SessionSummary] = []
            for d in dirs {
                let contents = (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
                let raws = contents.filter { $0.pathExtension.lowercased() == "dng" }
                let jpg = contents.first(where: { $0.lastPathComponent == "stacked_astro_preview.jpg" })
                let tiff = contents.first(where: { $0.lastPathComponent == "stacked_linear_16bit.tiff" })
                let attrs = try? d.resourceValues(forKeys: [.creationDateKey])
                list.append(SessionSummary(id: d.lastPathComponent, folderURL: d, date: attrs?.creationDate ?? Date(), rawCount: raws.count, stackedImageURL: jpg, stackedTIFFURL: tiff))
            }
            list.sort { $0.date > $1.date }
            DispatchQueue.main.async {
                self.savedSessions = list
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        metalProcessor.updateLiveSampleBuffer(sampleBuffer)

        let metrics = MetalStackProcessor.measureCenterStarMetrics(sampleBuffer: sampleBuffer)
        focusSampleLock.lock()
        recentSharpnessSamples.append(metrics.sharpness)
        if recentSharpnessSamples.count > 6 { recentSharpnessSamples.removeFirst() }
        focusSampleLock.unlock()

        DispatchQueue.main.async {
            self.liveSharpnessScore = metrics.sharpness
            self.liveSkyADU = metrics.medianSkyADU
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let dngData = photo.fileDataRepresentation(), let dir = activeSessionDir else {
            DispatchQueue.main.async {
                self.statusMessage = "Lỗi chụp RAW: \(error?.localizedDescription ?? "Không rõ")"
            }
            finishCapture(cancelled: true)
            return
        }

        let nextIdx = capturedCount + 1
        let fileURL = dir.appendingPathComponent(String(format: "ASTRO_%04d.DNG", nextIdx))
        try? dngData.write(to: fileURL)
        capturedDNGURLs.append(fileURL)
        saveDNGToPhotosIfRequested(data: dngData)

        DispatchQueue.main.async {
            self.capturedCount = nextIdx
            self.statusMessage = "Đã chụp \(nextIdx)/\(self.activeFrameTarget) RAW (.DNG)"
        }

        if nextIdx < activeFrameTarget && !cancelRequested {
            // Brief 0.12s yield to keep thermal/buffer queue smooth during long sequences
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.triggerNextRawShot()
            }
        } else {
            finishCapture(cancelled: false)
        }
    }
}
