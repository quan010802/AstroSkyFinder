import SwiftUI
import CoreLocation
import CoreMotion

struct ARSkyOverlayView: View {
    @ObservedObject var sensor: SkySensorManager
    let fovDeg: Double
    let showStars: Bool
    let showConstellations: Bool
    let showMilkyWay: Bool
    let showDeepSky: Bool
    let showCompassGrid: Bool
    let nightRed: Bool
    let activeTarget: AstroTarget?

    private static let cachedMilkyWay = SkyCatalog.milkyWayRibbon(stepDeg: 6.0)

    private var accentColor: Color {
        nightRed ? Color(red: 1.0, green: 0.25, blue: 0.20) : Color.cyan
    }

    private var warmColor: Color {
        nightRed ? Color(red: 1.0, green: 0.35, blue: 0.22) : Color(red: 1.0, green: 0.78, blue: 0.42)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let now = timeline.date
            GeometryReader { geo in
                ZStack {
                    Canvas { ctx, size in
                        let projFunc: (Double, Double) -> SkyProjection = { ra, dec in
                            SkyMath.projectToScreen(
                                raHours: ra,
                                decDeg: dec,
                                coordinate: sensor.coordinate,
                                date: now,
                                rotMatrix: sensor.rotationMatrix,
                                azOffsetDeg: sensor.azCalibrationOffsetDeg,
                                altOffsetDeg: sensor.altCalibrationOffsetDeg,
                                viewSize: size,
                                fovHorizontalDeg: fovDeg,
                                sensorAspectRatio: 4.0 / 3.0,
                                interfaceOrientation: sensor.interfaceOrientation
                            )
                        }

                        if showMilkyWay {
                            drawMilkyWay(context: &ctx, size: size, proj: projFunc)
                        }
                        if showCompassGrid {
                            drawHorizonAndGrid(context: &ctx, size: size, date: now)
                        }
                        if showConstellations {
                            drawConstellations(context: &ctx, proj: projFunc)
                        }
                        if showDeepSky {
                            drawDeepSkyObjects(context: &ctx, proj: projFunc)
                        }
                        if showStars {
                            drawStars(context: &ctx, proj: projFunc)
                        }
                    }
                    .allowsHitTesting(false)

                    // Center aiming reticle + horizon bubble level
                    if showCompassGrid {
                        CenterReticleView(
                            rollDeg: sensor.rollLevelDeg,
                            azimuthDeg: sensor.azimuthHeadingDeg,
                            altitudeDeg: sensor.altitudeCenterDeg,
                            isStable: sensor.isTripodStable,
                            nightRed: nightRed
                        )
                        .allowsHitTesting(false)
                    }

                    // Active AR Target Finder Arrow overlay
                    if let target = activeTarget {
                        let guidance = SkyMath.computeGuidance(
                            target: target,
                            coordinate: sensor.coordinate,
                            date: now,
                            rotMatrix: sensor.rotationMatrix,
                            azOffsetDeg: sensor.azCalibrationOffsetDeg,
                            altOffsetDeg: sensor.altCalibrationOffsetDeg
                        )
                        TargetGuidanceBadge(target: target, guidance: guidance, nightRed: nightRed)
                            .position(x: geo.size.width * 0.5, y: 205)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - Modular Drawing Passes
    private func drawMilkyWay(context: inout GraphicsContext, size: CGSize, proj: (Double, Double) -> SkyProjection) {
        let ribbon = Self.cachedMilkyWay
        guard ribbon.count > 2 else { return }

        // Draw translucent glowing segments connecting upper-lower polygon strips along the Galactic Plane
        for i in 0..<(ribbon.count - 1) {
            let p1 = ribbon[i]
            let p2 = ribbon[i + 1]
            let u1 = proj(p1.upper.0, p1.upper.1)
            let l1 = proj(p1.lower.0, p1.lower.1)
            let u2 = proj(p2.upper.0, p2.upper.1)
            let l2 = proj(p2.lower.0, p2.lower.1)
            let c1 = proj(p1.center.0, p1.center.1)

            guard (u1.isVisibleInFrame || l1.isVisibleInFrame || u2.isVisibleInFrame || l2.isVisibleInFrame),
                  u1.screenPoint != .zero, l1.screenPoint != .zero,
                  u2.screenPoint != .zero, l2.screenPoint != .zero else { continue }

            // Wrap guard against huge projection jumps across screen edge
            let d = hypot(u1.screenPoint.x - u2.screenPoint.x, u1.screenPoint.y - u2.screenPoint.y)
            guard d < size.width * 0.7 else { continue }

            var quad = Path()
            quad.move(to: u1.screenPoint)
            quad.addLine(to: u2.screenPoint)
            quad.addLine(to: l2.screenPoint)
            quad.addLine(to: l1.screenPoint)
            quad.closeSubpath()

            // Galactic core region (indices near l ~ 0..40 or 320..360) shines warmer golden
            let isCore = (i <= 7 || i >= ribbon.count - 7)
            let fillCol: Color = nightRed
                ? Color.red.opacity(isCore ? 0.16 : 0.09)
                : (isCore ? warmColor.opacity(0.16) : Color(red: 0.45, green: 0.68, blue: 1.0).opacity(0.11))
            context.fill(quad, with: .color(fillCol))

            if c1.isVisibleInFrame && i % 4 == 0 {
                let c2 = proj(p2.center.0, p2.center.1)
                if c2.isVisibleInFrame {
                    var spine = Path()
                    spine.move(to: c1.screenPoint)
                    spine.addLine(to: c2.screenPoint)
                    context.stroke(spine, with: .color(warmColor.opacity(0.32)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 5]))
                }
            }
        }
    }

    private func drawConstellations(context: inout GraphicsContext, proj: (Double, Double) -> SkyProjection) {
        let lineColor = accentColor.opacity(0.42)
        for group in SkyCatalog.constellationLines {
            var labelPoints: [CGPoint] = []
            for (idA, idB) in group.segments {
                guard let sA = SkyCatalog.starById[idA], let sB = SkyCatalog.starById[idB] else { continue }
                let pA = proj(sA.raHours, sA.decDeg)
                let pB = proj(sB.raHours, sB.decDeg)
                guard pA.isVisibleInFrame || pB.isVisibleInFrame, pA.screenPoint != .zero, pB.screenPoint != .zero else { continue }
                guard hypot(pA.screenPoint.x - pB.screenPoint.x, pA.screenPoint.y - pB.screenPoint.y) < 900 else { continue }

                var path = Path()
                path.move(to: pA.screenPoint)
                path.addLine(to: pB.screenPoint)
                context.stroke(path, with: .color(lineColor), lineWidth: 1.1)

                if pA.isVisibleInFrame { labelPoints.append(pA.screenPoint) }
                if pB.isVisibleInFrame { labelPoints.append(pB.screenPoint) }
            }

            if !labelPoints.isEmpty {
                let cx = labelPoints.map(\.x).reduce(0, +) / CGFloat(labelPoints.count)
                let cy = labelPoints.map(\.y).reduce(0, +) / CGFloat(labelPoints.count)
                let txt = Text(group.constellation.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor.opacity(0.75))
                context.draw(txt, at: CGPoint(x: cx, y: cy - 14))
            }
        }
    }

    private func drawStars(context: inout GraphicsContext, proj: (Double, Double) -> SkyProjection) {
        for star in SkyCatalog.stars {
            let p = proj(star.raHours, star.decDeg)
            guard p.isVisibleInFrame else { continue }

            let r: CGFloat = max(2.0, CGFloat(3.8 - star.mag) * 1.35)
            let col = nightRed ? Color.red.opacity(0.95) : star.displayColor
            let ringRect = CGRect(x: p.screenPoint.x - r, y: p.screenPoint.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: ringRect), with: .color(col.opacity(0.85)), lineWidth: 1.2)

            let dotR: CGFloat = 1.6
            let dotRect = CGRect(x: p.screenPoint.x - dotR, y: p.screenPoint.y - dotR, width: dotR * 2, height: dotR * 2)
            context.fill(Path(ellipseIn: dotRect), with: .color(col))

            if star.mag < 2.35 || star.id == "Polaris" {
                let label = Text(star.name)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(col.opacity(0.92))
                context.draw(label, at: CGPoint(x: p.screenPoint.x, y: p.screenPoint.y + r + 8))
            }
        }
    }

    private func drawDeepSkyObjects(context: inout GraphicsContext, proj: (Double, Double) -> SkyProjection) {
        let dsoColor = nightRed ? Color.red.opacity(0.85) : warmColor
        for obj in SkyCatalog.deepSkyObjects {
            let p = proj(obj.raHours, obj.decDeg)
            guard p.isVisibleInFrame else { continue }

            let boxR: CGFloat = 11.0
            let rect = CGRect(x: p.screenPoint.x - boxR, y: p.screenPoint.y - boxR, width: boxR * 2, height: boxR * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(dsoColor.opacity(0.9)), style: StrokeStyle(lineWidth: 1.3, dash: [3, 3]))

            let title = Text(obj.name)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(dsoColor)
            context.draw(title, at: CGPoint(x: p.screenPoint.x, y: p.screenPoint.y - boxR - 9))
        }
    }

    private func drawHorizonAndGrid(context: inout GraphicsContext, size: CGSize, date: Date) {
        let cardinals: [(Double, String)] = [(0, "BẮC (N)"), (45, "ĐB"), (90, "ĐÔNG (E)"), (135, "ĐN"), (180, "NAM (S)"), (225, "TN"), (270, "TÂY (W)"), (315, "TB")]
        let horizonColor = nightRed ? Color.red.opacity(0.45) : Color.green.opacity(0.55)

        // Draw horizon circle Az 0..360 at Alt = 0 deg
        var prevPt: CGPoint? = nil
        for stepAz in stride(from: 0.0, through: 360.0, by: 10.0) {
            if let pt = projectHorizontalPoint(azDeg: stepAz, altDeg: 0.0, size: size) {
                if let p0 = prevPt, hypot(pt.x - p0.x, pt.y - p0.y) < size.width * 0.5 {
                    var seg = Path()
                    seg.move(to: p0)
                    seg.addLine(to: pt)
                    context.stroke(seg, with: .color(horizonColor), style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
                }
                prevPt = pt
            } else {
                prevPt = nil
            }
        }

        for (az, label) in cardinals {
            if let pt = projectHorizontalPoint(azDeg: az, altDeg: 3.5, size: size) {
                let t = Text(label)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(horizonColor.opacity(0.9))
                context.draw(t, at: pt)
            }
        }
    }

    private func projectHorizontalPoint(azDeg: Double, altDeg: Double, size: CGSize) -> CGPoint? {
        return SkyMath.projectHorizontalToScreen(
            azDeg: azDeg,
            altDeg: altDeg,
            rotMatrix: sensor.rotationMatrix,
            azOffsetDeg: sensor.azCalibrationOffsetDeg,
            altOffsetDeg: sensor.altCalibrationOffsetDeg,
            viewSize: size,
            fovHorizontalDeg: fovDeg,
            sensorAspectRatio: 4.0 / 3.0,
            interfaceOrientation: sensor.interfaceOrientation
        )
    }
}

struct CenterReticleView: View {
    let rollDeg: Double
    let azimuthDeg: Double
    let altitudeDeg: Double
    let isStable: Bool
    let nightRed: Bool

    var body: some View {
        let isLevel = abs(rollDeg) < 1.5
        let col: Color = nightRed ? .red : (isLevel ? .green : .white.opacity(0.65))
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(col.opacity(0.55), lineWidth: 1.0)
                    .frame(width: 46, height: 46)
                Rectangle()
                    .fill(col)
                    .frame(width: 28, height: 1.5)
                    .rotationEffect(.degrees(-rollDeg))
                Circle()
                    .fill(col)
                    .frame(width: 3, height: 3)
            }
            HStack(spacing: 8) {
                Text(String(format: "Az %.0f° · Alt %.0f°", azimuthDeg, altitudeDeg))
                Text(isStable ? "• Chân vững" : "• ĐANG RUNG!")
                    .foregroundColor(isStable ? col : .orange)
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(col)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
        }
    }
}

struct TargetGuidanceBadge: View {
    let target: AstroTarget
    let guidance: TargetGuidance
    let nightRed: Bool

    var body: some View {
        let col: Color = nightRed ? .red : (guidance.isCentered ? .green : .yellow)
        HStack(spacing: 8) {
            Image(systemName: guidance.isCentered ? "checkmark.circle.fill" : arrowSymbol)
                .font(.system(size: 15, weight: .bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(target.title)
                    .font(.system(size: 11, weight: .bold))
                Text(guidance.isCentered
                     ? "ĐÃ VÀO TÂM KHUNG — NÉT & CHỤP!"
                     : String(format: "%@ %.0f° · %@ %.0f°",
                              guidance.azimuthDeltaDeg >= 0 ? "Quay Phải" : "Quay Trái",
                              abs(guidance.azimuthDeltaDeg),
                              guidance.altitudeDeltaDeg >= 0 ? "Ngẩng Lên" : "Hạ Xuống",
                              abs(guidance.altitudeDeltaDeg)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
        }
        .foregroundColor(col)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.68))
        .overlay(Capsule().stroke(col.opacity(0.6), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var arrowSymbol: String {
        if abs(guidance.azimuthDeltaDeg) > abs(guidance.altitudeDeltaDeg) {
            return guidance.azimuthDeltaDeg >= 0 ? "arrow.right.circle.fill" : "arrow.left.circle.fill"
        } else {
            return guidance.altitudeDeltaDeg >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
        }
    }
}
