import XCTest
import CoreLocation
import CoreMotion
@testable import AstroSkyFinder

final class AstroSkyFinderTests: XCTestCase {

    func testGalacticCenterAndAntiCenterEquatorial() {
        let gc = SkyMath.galacticToEquatorial(lDeg: 0.0, bDeg: 0.0)
        XCTAssertEqual(gc.raHours, 17.76, accuracy: 0.05)
        XCTAssertEqual(gc.decDeg, -28.94, accuracy: 0.15)

        let ac = SkyMath.galacticToEquatorial(lDeg: 180.0, bDeg: 0.0)
        XCTAssertEqual(ac.raHours, 5.76, accuracy: 0.05)
        XCTAssertEqual(ac.decDeg, 28.94, accuracy: 0.15)
    }

    func testMilkyWayRibbonGeneration() {
        let ribbon = SkyCatalog.milkyWayRibbon(stepDeg: 6.0)
        XCTAssertGreaterThan(ribbon.count, 55)
        XCTAssertFalse(SkyCatalog.stars.isEmpty)
        XCTAssertFalse(SkyCatalog.deepSkyObjects.isEmpty)
        XCTAssertNotNil(SkyCatalog.starById["Betelgeuse"])
        XCTAssertNotNil(SkyCatalog.starById["Polaris"])
    }

    func testLookAtProjectionCentersTarget() {
        let coord = CLLocationCoordinate2D(latitude: 10.8231, longitude: 106.6297)
        let now = Date()
        let betelgeuse = SkyCatalog.starById["Betelgeuse"]!
        let hz = SkyMath.equatorialToHorizontal(raHours: betelgeuse.raHours, decDeg: betelgeuse.decDeg, coordinate: coord, date: now)
        let rot = SkyMath.makeLookAtRotationMatrix(azDeg: hz.azimuthDeg, altDeg: hz.altitudeDeg)

        let proj = SkyMath.projectToScreen(
            raHours: betelgeuse.raHours,
            decDeg: betelgeuse.decDeg,
            coordinate: coord,
            date: now,
            rotMatrix: rot,
            azOffsetDeg: 0.0,
            altOffsetDeg: 0.0,
            viewSize: CGSize(width: 400, height: 800),
            fovHorizontalDeg: 69.0,
            sensorAspectRatio: 4.0 / 3.0,
            interfaceOrientation: .portrait
        )

        XCTAssertTrue(proj.isVisibleInFrame)
        XCTAssertEqual(Double(proj.screenPoint.x), 200.0, accuracy: 2.0)
        XCTAssertEqual(Double(proj.screenPoint.y), 400.0, accuracy: 2.0)
    }

    func testTargetGuidanceWhenAligned() {
        let coord = CLLocationCoordinate2D(latitude: 10.8231, longitude: 106.6297)
        let now = Date()
        let target = SkyCatalog.popularTargets[0]
        let hz = SkyMath.equatorialToHorizontal(raHours: target.raHours, decDeg: target.decDeg, coordinate: coord, date: now)
        let rot = SkyMath.makeLookAtRotationMatrix(azDeg: hz.azimuthDeg, altDeg: hz.altitudeDeg)

        let guidance = SkyMath.computeGuidance(target: target, coordinate: coord, date: now, rotMatrix: rot, azOffsetDeg: 0.0, altOffsetDeg: 0.0)
        XCTAssertTrue(guidance.isCentered)
        XCTAssertLessThan(guidance.angularDistanceDeg, 1.0)
    }

    func testNPFSharpShutterRule() {
        let max26 = SkyMath.maxSharpShutterSeconds(focalLength35mm: 26.0)
        XCTAssertGreaterThan(max26, 10.0)
        XCTAssertLessThan(max26, 15.0)
    }

    func testMetalStackProcessorGeneratesAndStacksSimulatedFrames() {
        let proc = MetalStackProcessor()
        let mBlur = proc.updateSimulatedPreviewFrame(lensPosition: 0.78, iso: 640, exposureSec: 1.0, shiftX: 0, shiftY: 0)
        let mSharp = proc.updateSimulatedPreviewFrame(lensPosition: 0.935, iso: 640, exposureSec: 1.0, shiftX: 0, shiftY: 0)
        // Pinpoint focused stars MUST score sharper than blurred stars!
        XCTAssertGreaterThan(mSharp.sharpness, mBlur.sharpness)

        let f1 = proc.generateSimulatedNightCIImage(lensPosition: 0.935, iso: 640, exposureSec: 1.0, shiftX: 0, shiftY: 0, width: 512, height: 384)
        let f2 = proc.generateSimulatedNightCIImage(lensPosition: 0.935, iso: 640, exposureSec: 1.0, shiftX: 3.0, shiftY: -2.0, width: 512, height: 384)
        let f3 = proc.generateSimulatedNightCIImage(lensPosition: 0.935, iso: 640, exposureSec: 1.0, shiftX: 6.0, shiftY: -4.0, width: 512, height: 384)
        let imgs = [f1, f2, f3].compactMap { $0 }
        XCTAssertEqual(imgs.count, 3)

        let res = proc.stackLinearCIImages(imgs) { _, _ in }
        XCTAssertNotNil(res.previewImage)
        XCTAssertNotNil(res.linearTIFFData)
    }
}
