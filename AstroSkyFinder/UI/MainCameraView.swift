import SwiftUI
import UIKit

struct MainCameraView: View {
    @StateObject private var camera = AstroCameraManager()
    @StateObject private var sensor = SkySensorManager()

    // Independent AR layer toggles (each button controls its own component!)
    @State private var showStars = true
    @State private var showConstellations = true
    @State private var showMilkyWay = true
    @State private var showDeepSky = true
    @State private var showCompassGrid = true

    // Visual & assistant toggles
    @State private var nightVisionUI = false
    @State private var loupeZoom4x = false
    @State private var showSlidersDrawer = false
    @State private var dimScreenSaver = false
    @State private var activeTarget: AstroTarget? = nil

    // Modal sheets
    @State private var showTargetPicker = false
    @State private var showCalibrationSheet = false
    @State private var showSessionsSheet = false

    private var themeAccent: Color {
        nightVisionUI ? Color(red: 1.0, green: 0.25, blue: 0.18) : Color.cyan
    }

    private var activeFOVDeg: Double {
        camera.currentLens?.fovDeg ?? 69.0
    }

    var body: some View {
        ZStack {
            // 1. Live GPU Metal camera preview (boosted 1x..14x on screen only, RAW untouched!)
            MetalPreviewRepresentable(
                processor: camera.metalProcessor,
                boostGain: camera.autoBrightnessBoost,
                nightRed: nightVisionUI,
                loupeZoom: loupeZoom4x ? 4.0 : 1.0
            )
            .ignoresSafeArea()

            // 2. Stellarium-style Real-Time AR Sky Overlay
            ARSkyOverlayView(
                sensor: sensor,
                fovDeg: activeFOVDeg,
                showStars: showStars,
                showConstellations: showConstellations,
                showMilkyWay: showMilkyWay,
                showDeepSky: showDeepSky,
                showCompassGrid: showCompassGrid,
                nightRed: nightVisionUI,
                activeTarget: activeTarget
            )
            .ignoresSafeArea()

            // 3. Full Pro Astro HUD
            VStack(spacing: 8) {
                topStatusAndARToggleDeck
                Spacer()
                bottomCameraControlDeck
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)

            // 4. Ultra-dim Screen Saver Lock while shooting 60–300 frames on tripod
            if dimScreenSaver {
                DimSaverOverlay(
                    isCapturing: camera.isCapturing,
                    capturedCount: camera.capturedCount,
                    statusMessage: camera.statusMessage,
                    onUnlock: { dimScreenSaver = false }
                )
            }
        }
        .onAppear {
            camera.requestPermissionAndStart()
        }
        .sheet(isPresented: $showTargetPicker) {
            TargetPickerSheet(selectedTarget: $activeTarget, onSelect: { tgt in
                activeTarget = tgt
                camera.applyAutoAstroRecommendation(target: tgt)
            })
        }
        .sheet(isPresented: $showCalibrationSheet) {
            ARCalibrationSheet(sensor: sensor)
        }
        .sheet(isPresented: $showSessionsSheet) {
            SessionsSheet(camera: camera)
        }
    }

    // MARK: - Top HUD: Lens/Telemetry + Individual AR Layer Buttons
    private var topStatusAndARToggleDeck: some View {
        VStack(spacing: 6) {
            // Compact Single-Line Telemetry + Lens + Target + Calibrate Row
            HStack(spacing: 5) {
                if let lens = camera.currentLens {
                    Text(String(format: "f/%.1f · %.0fmm", lens.aperture, lens.eqFocalMm))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.62))
                        .foregroundColor(themeAccent)
                        .clipShape(Capsule())
                }

                ForEach(Array(camera.availableLenses.enumerated()), id: \.element.id) { idx, lens in
                    Button(lens.label) {
                        camera.switchLens(to: idx)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(camera.selectedLensIndex == idx ? themeAccent : Color.black.opacity(0.58))
                    .foregroundColor(camera.selectedLensIndex == idx ? .black : .white)
                    .clipShape(Capsule())
                }

                Spacer(minLength: 2)

                Button {
                    showTargetPicker = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "scope").font(.system(size: 10))
                        Text(activeTarget == nil ? "Mục tiêu" : "Đổi").lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(activeTarget != nil ? themeAccent.opacity(0.9) : Color.black.opacity(0.62))
                    .foregroundColor(activeTarget != nil ? .black : themeAccent)
                    .clipShape(Capsule())
                }

                Button {
                    showCalibrationSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "gyroscope").font(.system(size: 10))
                        Text("Cân AR").lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.62))
                    .foregroundColor(themeAccent)
                    .clipShape(Capsule())
                }
            }

            // Independent Stellarium AR Layer Toggle Bar (1 button per element!)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    LayerToggleButton(title: "Sao", icon: "star.fill", isOn: $showStars, accent: themeAccent)
                    LayerToggleButton(title: "Chòm sao", icon: "sparkles", isOn: $showConstellations, accent: themeAccent)
                    LayerToggleButton(title: "Ngân Hà", icon: "hurricane", isOn: $showMilkyWay, accent: themeAccent)
                    LayerToggleButton(title: "Deep-Sky", icon: "circle.dotted", isOn: $showDeepSky, accent: themeAccent)
                    LayerToggleButton(title: "La bàn", icon: "safari", isOn: $showCompassGrid, accent: themeAccent)

                    Button {
                        let anyOff = !(showStars && showConstellations && showMilkyWay && showDeepSky && showCompassGrid)
                        showStars = anyOff
                        showConstellations = anyOff
                        showMilkyWay = anyOff
                        showDeepSky = anyOff
                        showCompassGrid = anyOff
                    } label: {
                        Text((showStars && showConstellations && showMilkyWay && showDeepSky && showCompassGrid) ? "Ẩn AR" : "Hiện Hết")
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.16))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }

                    LayerToggleButton(title: "Zoom 4x", icon: "plus.magnifyingglass", isOn: $loupeZoom4x, accent: .yellow)
                    LayerToggleButton(title: "Đêm đỏ", icon: "eye.fill", isOn: $nightVisionUI, accent: .red)
                }
            }

            // Compact Status & Live Sharpness Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(camera.isFocusLocked ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(camera.statusMessage)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "Nét %.1f · Sky %.0f", camera.liveSharpnessScore, camera.liveSkyADU))
                    .font(.system(size: 10, design: .monospaced))
                    .fixedSize()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(nightVisionUI ? .red : .white.opacity(0.92))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
        }
    }

    // MARK: - Bottom Control Deck: Compact Viewfinder-First + Expandable Pro Sliders
    private var bottomCameraControlDeck: some View {
        VStack(spacing: 7) {
            // Quick Assist Row: Auto Focus, Auto ISO, Preview Boost, Sliders Toggle, Dim Mode
            HStack(spacing: 5) {
                Button {
                    camera.startAutoStarFocus()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: camera.isAutoFocusing ? "hourglass" : "scope")
                        Text(camera.isAutoFocusing ? "Đang quét..." : (camera.isFocusLocked ? String(format: "Nét %.3f", camera.lensPosition) : "Auto Nét"))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(camera.isFocusLocked ? Color.green.opacity(0.9) : themeAccent)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                }
                .disabled(camera.isCapturing || camera.isAutoFocusing)

                Button {
                    camera.applyAutoAstroRecommendation(target: activeTarget)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "wand.and.stars")
                        Text("Auto ISO").lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.68))
                    .foregroundColor(themeAccent)
                    .overlay(Capsule().stroke(themeAccent.opacity(0.45), lineWidth: 1))
                    .clipShape(Capsule())
                }
                .disabled(camera.isCapturing)

                Button {
                    let levels: [Float] = [1.0, 4.0, 8.0, 14.0]
                    if let idx = levels.firstIndex(where: { abs($0 - camera.autoBrightnessBoost) < 0.5 }) {
                        camera.autoBrightnessBoost = levels[(idx + 1) % levels.count]
                    } else {
                        camera.autoBrightnessBoost = 4.0
                    }
                } label: {
                    Text(String(format: "%.0fx", camera.autoBrightnessBoost))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.68))
                        .foregroundColor(.yellow)
                        .clipShape(Capsule())
                }

                Spacer(minLength: 2)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSlidersDrawer.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: showSlidersDrawer ? "chevron.down" : "slider.horizontal.3")
                        Text("Thông số").lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(showSlidersDrawer ? themeAccent : Color.black.opacity(0.68))
                    .foregroundColor(showSlidersDrawer ? .black : .white)
                    .clipShape(Capsule())
                }

                Button {
                    dimScreenSaver = true
                } label: {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 12))
                        .padding(6)
                        .background(Color.black.opacity(0.68))
                        .foregroundColor(themeAccent)
                        .clipShape(Circle())
                }
            }

            // Main Compact/Expandable Control Card
            VStack(spacing: 6) {
                // Always visible compact summary strip (tap to expand sliders!)
                if !showSlidersDrawer {
                    HStack(spacing: 10) {
                        Text(camera.captureMode.rawValue)
                            .foregroundColor(themeAccent)
                            .bold()
                        Text(String(format: "MF %.3f", camera.lensPosition))
                        Text(String(format: "ISO %.0f", camera.isoValue))
                        Text(String(format: "%.2fs", camera.exposureSeconds))
                        Spacer()
                        Text(camera.captureMode == .metalStack ? "Gộp \(camera.syntheticFrames)" : "\(camera.sequenceCount) RAW")
                            .foregroundColor(themeAccent)
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showSlidersDrawer = true }
                    }
                } else {
                    expandedSlidersSection
                }

                // Bottom Shutter + Timer + Library Row
                HStack(spacing: 14) {
                    Button {
                        showSessionsSheet = true
                    } label: {
                        if let preview = camera.latestStackedPreview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 42, height: 42)
                                .overlay(Image(systemName: "photo.stack").foregroundColor(.white))
                        }
                    }

                    Button {
                        let delays = [0, 3, 10]
                        if let i = delays.firstIndex(of: camera.delaySeconds) {
                            camera.delaySeconds = delays[(i + 1) % delays.count]
                        } else {
                            camera.delaySeconds = 3
                        }
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "timer").font(.system(size: 12))
                            Text("\(camera.delaySeconds)s").font(.system(size: 10, weight: .bold))
                        }
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                    }
                    .disabled(camera.isCapturing)

                    Spacer()

                    Button {
                        if camera.isCapturing {
                            camera.cancelCapture()
                        } else {
                            camera.startCapturePipeline()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 62, height: 62)
                            if camera.isCapturing {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red)
                                    .frame(width: 24, height: 24)
                            } else {
                                Circle()
                                    .fill(nightVisionUI ? Color.red : Color.white)
                                    .frame(width: 50, height: 50)
                            }
                        }
                    }
                    .disabled(camera.isStackingOnMetal)

                    Spacer()

                    Toggle(isOn: $camera.saveDNGToPhotos) {
                        VStack(spacing: 1) {
                            Image(systemName: "square.and.arrow.down").font(.system(size: 12))
                            Text("Ảnh").font(.system(size: 9))
                        }
                    }
                    .toggleStyle(.button)
                    .tint(themeAccent)
                    .frame(width: 48, height: 42)
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var expandedSlidersSection: some View {
        VStack(spacing: 5) {
            Picker("Chế độ", selection: $camera.captureMode) {
                ForEach(CapturePipelineMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(camera.isCapturing)

            HStack(spacing: 8) {
                Text("MF Nét").frame(width: 56, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(camera.lensPosition) },
                    set: { camera.applyManualFocus(position: Float($0)) }
                ), in: 0.60...1.00, step: 0.002)
                Text(String(format: "%.3f", camera.lensPosition)).frame(width: 46, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white)

            let minI = Double(camera.currentLens?.minISO ?? 50)
            let maxI = Double(max(minI + 50, Double(camera.currentLens?.maxISO ?? 3200)))
            HStack(spacing: 8) {
                Text("ISO").frame(width: 56, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(camera.isoValue) },
                    set: {
                        camera.isoValue = Float($0)
                        camera.applyExposureSettings()
                    }
                ), in: minI...maxI, step: 10)
                Text(String(format: "%.0f", camera.isoValue)).frame(width: 46, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white)

            let minE = max(0.05, camera.currentLens?.minExposureSec ?? 0.05)
            let maxE = max(minE + 0.1, min(30.0, camera.currentLens?.maxExposureSec ?? 1.0))
            HStack(spacing: 8) {
                Text("Phơi/tấm").frame(width: 56, alignment: .leading)
                Slider(value: Binding(
                    get: { camera.exposureSeconds },
                    set: {
                        camera.exposureSeconds = $0
                        camera.applyExposureSettings()
                    }
                ), in: minE...maxE, step: 0.05)
                Text(String(format: "%.2fs", camera.exposureSeconds)).frame(width: 46, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white)

            if camera.captureMode == .metalStack {
                HStack(spacing: 8) {
                    Text("Gộp Metal").frame(width: 56, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(camera.syntheticFrames) },
                        set: { camera.syntheticFrames = Int($0) }
                    ), in: 3...30, step: 1)
                    Text("\(camera.syntheticFrames) tấm").frame(width: 46, alignment: .trailing)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeAccent)
            } else {
                HStack(spacing: 8) {
                    Text("Số RAW").frame(width: 56, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(camera.sequenceCount) },
                        set: { camera.sequenceCount = Int($0) }
                    ), in: 5...300, step: 5)
                    Text("\(camera.sequenceCount) tấm").frame(width: 46, alignment: .trailing)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(themeAccent)
            }
        }
    }
}

struct LayerToggleButton: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let accent: Color

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isOn ? accent.opacity(0.92) : Color.black.opacity(0.62))
            .foregroundColor(isOn ? .black : .white.opacity(0.8))
            .overlay(Capsule().stroke(isOn ? accent : Color.white.opacity(0.25), lineWidth: 1))
            .clipShape(Capsule())
        }
    }
}

struct DimSaverOverlay: View {
    let isCapturing: Bool
    let capturedCount: Int
    let statusMessage: String
    let onUnlock: () -> Void

    var body: some View {
        Color.black.opacity(0.96)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 12) {
                    Text(isCapturing ? "Đang chụp chuỗi: \(capturedCount)" : "Chế độ Tiết kiệm pin")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.red.opacity(0.65))
                    Text(statusMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.red.opacity(0.5))
                    Text("Chạm đúp màn hình để mở lại")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.4))
                }
            }
            .onTapGesture(count: 2) {
                onUnlock()
            }
    }
}

struct TargetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTarget: AstroTarget?
    let onSelect: (AstroTarget) -> Void

    var body: some View {
        NavigationView {
            List {
                if selectedTarget != nil {
                    Button("Bỏ chọn dẫn hướng AR", role: .destructive) {
                        selectedTarget = nil
                        dismiss()
                    }
                }
                Section("Mục tiêu thiên văn gợi ý") {
                    ForEach(SkyCatalog.popularTargets) { tgt in
                        Button {
                            onSelect(tgt)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tgt.title).font(.headline).foregroundColor(.primary)
                                Text(tgt.subtitle).font(.subheadline).foregroundColor(.secondary)
                                Text(tgt.recommendedNote).font(.caption).foregroundColor(.cyan)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Tìm Mục Tiêu AR")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}

struct ARCalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sensor: SkySensorManager

    private let anchorStars = ["Sirius", "Rigel", "Betelgeuse", "Aldebaran", "Capella", "Vega", "Altair", "Antares", "Polaris", "Schedar", "Deneb"]

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Khử lệch la bàn khi gắn tripod kim loại / nóc ô tô"),
                        footer: Text("Hướng tâm vòng tròn màn hình chính xác vào ngôi sao thật ngoài bầu trời rồi chạm tên ngôi sao đó.")) {
                    ForEach(anchorStars, id: \.self) { sid in
                        if let st = SkyCatalog.starById[sid] {
                            Button("Khớp tâm vào sao: \(st.name)") {
                                sensor.calibrateARToKnownStar(star: st)
                                dismiss()
                            }
                        }
                    }
                }
                Section {
                    Button("Đặt lại độ lệch AR (0°)", role: .destructive) {
                        sensor.resetARCalibration()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Cân Khớp AR 1 Sao")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}

struct SessionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var camera: AstroCameraManager

    var body: some View {
        NavigationView {
            List {
                Section(footer: Text("Mở app Tệp (Files) → Trên iPhone này → AstroSkyFinder để chép trọn thư mục .DNG sang PC stack hoặc chia sẻ.")) {
                    if camera.savedSessions.isEmpty {
                        Text("Chưa có phiên chụp nào.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(camera.savedSessions) { sess in
                            HStack(spacing: 12) {
                                if let jpg = sess.stackedImageURL, let ui = UIImage(contentsOfFile: jpg.path) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 56, height: 56)
                                        .overlay(Image(systemName: "camera.aperture"))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sess.id).font(.subheadline.bold())
                                    Text("RAW .DNG: \(sess.rawCount) tấm")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if sess.stackedTIFFURL != nil {
                                        Text("Có bản gộp Metal 16-bit TIFF + JPG")
                                            .font(.caption2)
                                            .foregroundColor(.cyan)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Phiên Chụp Đã Lưu")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                camera.loadSavedSessions()
            }
        }
    }
}
