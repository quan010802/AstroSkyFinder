import Foundation
import CoreLocation
import CoreMotion
import UIKit
import Combine
import simd

final class SkySensorManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()

    @Published var coordinate = CLLocationCoordinate2D(latitude: 10.8231, longitude: 106.6297) // Default VN until GPS locks
    @Published var hasGPSLock: Bool = false
    @Published var rotationMatrix: CMRotationMatrix = CMRotationMatrix(
        m11: 1, m12: 0, m13: 0,
        m21: 0, m22: 1, m23: 0,
        m31: 0, m32: 0, m33: 1
    )
    @Published var rollLevelDeg: Double = 0.0
    @Published var pitchDeg: Double = 0.0
    @Published var azimuthHeadingDeg: Double = 0.0
    @Published var altitudeCenterDeg: Double = 0.0
    @Published var isTripodStable: Bool = true
    @Published var interfaceOrientation: UIInterfaceOrientation = .portrait

    // Manual AR calibration offsets to cancel metal tripod / car-roof magnetic compass interference
    @Published var azCalibrationOffsetDeg: Double = 0.0
    @Published var altCalibrationOffsetDeg: Double = 0.0

    private var prevMatrix: CMRotationMatrix?
    private var accelHistory: [Double] = []
    private var simTimer: Timer?
    private var simPhase: Double = 0.0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        startMotionUpdates()
    }

    deinit {
        simTimer?.invalidate()
        motionManager.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
    }

    func startMotionUpdates() {
        #if targetEnvironment(simulator)
        startSimulatorMotionFallback()
        return
        #else
        guard motionManager.isDeviceMotionAvailable else {
            startSimulatorMotionFallback()
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0

        let frame: CMAttitudeReferenceFrame = CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical)
            ? .xTrueNorthZVertical
            : .xArbitraryCorrectedZVertical

        motionManager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let self = self, let m = motion else { return }

            // Smooth CMRotationMatrix directly with Gram-Schmidt orthonormalization (zero quaternion convention ambiguity!)
            let mr = m.attitude.rotationMatrix
            let rawR: CMRotationMatrix
            if let pr = self.prevMatrix {
                let a = 0.28
                var c0 = simd_double3((1 - a) * pr.m11 + a * mr.m11, (1 - a) * pr.m21 + a * mr.m21, (1 - a) * pr.m31 + a * mr.m31)
                var c1 = simd_double3((1 - a) * pr.m12 + a * mr.m12, (1 - a) * pr.m22 + a * mr.m22, (1 - a) * pr.m32 + a * mr.m32)
                c0 = simd_normalize(c0)
                c1 = simd_normalize(c1 - simd_dot(c1, c0) * c0)
                let c2 = simd_cross(c0, c1)
                rawR = CMRotationMatrix(m11: c0.x, m12: c1.x, m13: c2.x, m21: c0.y, m22: c1.y, m23: c2.y, m31: c0.z, m32: c1.z, m33: c2.z)
            } else {
                rawR = mr
            }
            self.prevMatrix = rawR
            self.rotationMatrix = rawR

            // Back camera forward axis in device frame is (0, 0, -1) -> Reference frame: R^T * (0, 0, -1) = (-m31, -m32, -m33)
            let fx = -rawR.m31
            let fy = -rawR.m32
            let fz = -rawR.m33
            let alt = asin(max(-1.0, min(1.0, fz))) * 180.0 / .pi
            var az = atan2(-fy, fx) * 180.0 / .pi
            if az < 0 { az += 360.0 }

            self.azimuthHeadingDeg = (az - self.azCalibrationOffsetDeg + 360.0).truncatingRemainder(dividingBy: 360.0)
            self.altitudeCenterDeg = alt - self.altCalibrationOffsetDeg

            // Horizon spirit level angle (angle of device X-axis vs horizontal)
            self.rollLevelDeg = asin(max(-1.0, min(1.0, rawR.m13))) * 180.0 / .pi
            self.pitchDeg = alt

            // Tripod stability monitor via userAcceleration magnitude (detects wind / footsteps!)
            let accMag = sqrt(m.userAcceleration.x * m.userAcceleration.x + m.userAcceleration.y * m.userAcceleration.y + m.userAcceleration.z * m.userAcceleration.z)
            self.accelHistory.append(accMag)
            if self.accelHistory.count > 12 { self.accelHistory.removeFirst() }
            let avgVib = self.accelHistory.reduce(0, +) / Double(max(1, self.accelHistory.count))
            self.isTripodStable = (avgVib < 0.015)

            // Sync current interface orientation
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                self.interfaceOrientation = scene.interfaceOrientation
            }
        }
        #endif
    }

    private func startSimulatorMotionFallback() {
        simTimer?.invalidate()
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.simPhase += 0.025
            // Pick highest visible showcase target above horizon so AR overlay is always populated on Simulator
            let now = Date()
            let bestHz = SkyCatalog.popularTargets
                .map { SkyMath.equatorialToHorizontal(raHours: $0.raHours, decDeg: $0.decDeg, coordinate: self.coordinate, date: now) }
                .max(by: { $0.altitudeDeg < $1.altitudeDeg }) ?? (azimuthDeg: 145.0, altitudeDeg: 42.0)

            let targetAlt = max(22.0, min(72.0, bestHz.altitudeDeg)) + 1.2 * sin(self.simPhase * 0.7)
            let targetAz = bestHz.azimuthDeg + 2.5 * sin(self.simPhase * 0.5)
            let r = SkyMath.makeLookAtRotationMatrix(azDeg: targetAz, altDeg: targetAlt)
            self.rotationMatrix = r
            self.azimuthHeadingDeg = (targetAz - self.azCalibrationOffsetDeg + 360.0).truncatingRemainder(dividingBy: 360.0)
            self.altitudeCenterDeg = targetAlt - self.altCalibrationOffsetDeg
            self.rollLevelDeg = 0.3 * sin(self.simPhase * 0.4)
            self.isTripodStable = true
        }
    }

    func calibrateARToKnownStar(star: StarEntry) {
        let now = Date()
        let trueHz = SkyMath.equatorialToHorizontal(raHours: star.raHours, decDeg: star.decDeg, coordinate: coordinate, date: now)
        let fwdRef = simd_double3(-rotationMatrix.m31, -rotationMatrix.m32, -rotationMatrix.m33)
        let camAlt = asin(max(-1.0, min(1.0, fwdRef.z))) * 180.0 / .pi
        var camAz = atan2(-fwdRef.y, fwdRef.x) * 180.0 / .pi
        if camAz < 0 { camAz += 360.0 }

        var dAz = trueHz.azimuthDeg - camAz
        if dAz > 180 { dAz -= 360 }
        if dAz < -180 { dAz += 360 }
        azCalibrationOffsetDeg = dAz
        altCalibrationOffsetDeg = trueHz.altitudeDeg - camAlt
    }

    func resetARCalibration() {
        azCalibrationOffsetDeg = 0.0
        altCalibrationOffsetDeg = 0.0
    }

    // MARK: CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.coordinate = loc.coordinate
            self.hasGPSLock = true
        }
    }
}
