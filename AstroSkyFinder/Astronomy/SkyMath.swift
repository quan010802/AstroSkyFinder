import Foundation
import CoreLocation
import CoreMotion
import UIKit
import simd

struct SkyProjection {
    let screenPoint: CGPoint
    let altitudeDeg: Double
    let azimuthDeg: Double
    let isVisibleInFrame: Bool
    let isAboveHorizon: Bool
}

struct TargetGuidance {
    let azimuthDeltaDeg: Double    // + right, - left
    let altitudeDeltaDeg: Double   // + up, - down
    let angularDistanceDeg: Double
    let isCentered: Bool
}

enum SkyMath {
    private static let degToRad = Double.pi / 180.0
    private static let radToDeg = 180.0 / Double.pi

    /// Julian Date from Foundation Date
    static func julianDate(from date: Date) -> Double {
        return 2440587.5 + date.timeIntervalSince1970 / 86400.0
    }

    /// Local Sidereal Time in degrees [0, 360)
    static func localSiderealTimeDeg(date: Date, longitudeDeg: Double) -> Double {
        let jd = julianDate(from: date)
        let d = jd - 2451545.0
        let gmst = 280.46061837 + 360.98564736629 * d
        var lst = (gmst + longitudeDeg).truncatingRemainder(dividingBy: 360.0)
        if lst < 0 { lst += 360.0 }
        return lst
    }

    /// IAU Galactic (l, b) -> J2000 Equatorial (RA hours, Dec deg)
    static func galacticToEquatorial(lDeg: Double, bDeg: Double) -> (raHours: Double, decDeg: Double) {
        let raNGP = 192.85948 * degToRad
        let decNGP = 27.12825 * degToRad
        let lNCP = 122.93192 * degToRad
        let l = lDeg * degToRad
        let b = bDeg * degToRad

        let sinDec = sin(decNGP) * sin(b) + cos(decNGP) * cos(b) * cos(lNCP - l)
        let dec = asin(max(-1.0, min(1.0, sinDec)))

        let y = cos(b) * sin(lNCP - l)
        let x = cos(decNGP) * sin(b) - sin(decNGP) * cos(b) * cos(lNCP - l)
        var raDeg = (raNGP + atan2(y, x)) * radToDeg
        raDeg = raDeg.truncatingRemainder(dividingBy: 360.0)
        if raDeg < 0 { raDeg += 360.0 }
        return (raDeg / 15.0, dec * radToDeg)
    }

    /// Equatorial (RAh, DecDeg) -> Horizontal (AzimuthDeg [0=N, 90=E], AltitudeDeg)
    static func equatorialToHorizontal(raHours: Double, decDeg: Double, coordinate: CLLocationCoordinate2D, date: Date) -> (azimuthDeg: Double, altitudeDeg: Double) {
        let lstDeg = localSiderealTimeDeg(date: date, longitudeDeg: coordinate.longitude)
        let ha = (lstDeg - raHours * 15.0) * degToRad
        let dec = decDeg * degToRad
        let lat = coordinate.latitude * degToRad

        let sinAlt = sin(dec) * sin(lat) + cos(dec) * cos(lat) * cos(ha)
        let alt = asin(max(-1.0, min(1.0, sinAlt)))

        let cosAlt = max(1e-7, cos(alt))
        let sinAz = -cos(dec) * sin(ha) / cosAlt
        let cosAz = (sin(dec) - sin(lat) * sinAlt) / (cos(lat) * cosAlt)
        var azDeg = atan2(sinAz, cosAz) * radToDeg
        if azDeg < 0 { azDeg += 360.0 }
        return (azDeg, alt * radToDeg)
    }

    /// CoreMotion `.xTrueNorthZVertical` vector: X = True North, Y = True West, Z = Up
    static func horizontalToRefVector(azimuthDeg: Double, altitudeDeg: Double) -> simd_double3 {
        let az = azimuthDeg * degToRad
        let alt = altitudeDeg * degToRad
        let cosAlt = cos(alt)
        let north = cosAlt * cos(az)
        let west = -cosAlt * sin(az)
        let up = sin(alt)
        return simd_double3(north, west, up)
    }

    /// Convert CoreMotion CMRotationMatrix (transforms Ref -> Device) into Device camera space
    static func refToDevice(vectorRef: simd_double3, rot: CMRotationMatrix) -> simd_double3 {
        return simd_double3(
            rot.m11 * vectorRef.x + rot.m12 * vectorRef.y + rot.m13 * vectorRef.z,
            rot.m21 * vectorRef.x + rot.m22 * vectorRef.y + rot.m23 * vectorRef.z,
            rot.m31 * vectorRef.x + rot.m32 * vectorRef.y + rot.m33 * vectorRef.z
        )
    }

    /// Shared 3D Reference-frame unit vector -> 2D screen point projection (handles Portrait, LandscapeLeft, LandscapeRight)
    static func projectVectorToScreen(
        vRef: simd_double3,
        rotMatrix: CMRotationMatrix,
        viewSize: CGSize,
        fovHorizontalDeg: Double,
        sensorAspectRatio: Double,
        interfaceOrientation: UIInterfaceOrientation
    ) -> CGPoint? {
        let vDev = refToDevice(vectorRef: vRef, rot: rotMatrix)
        // Back camera looks along -Z in physical device frame
        let depth = -vDev.z
        guard depth > 0.05 else { return nil }

        var sx: Double
        var sy: Double
        switch interfaceOrientation {
        case .landscapeRight:
            // Device rotated 90 deg CCW (top edge on Left, bottom on Right): screen right = -devY, screen up = +devX
            sx = -vDev.y
            sy = vDev.x
        case .landscapeLeft:
            // Device rotated 90 deg CW (top edge on Right, bottom on Left): screen right = +devY, screen up = -devX
            sx = vDev.y
            sy = -vDev.x
        default:
            // Portrait: screen right = +devX, screen up = +devY
            sx = vDev.x
            sy = vDev.y
        }

        let isLandscape = (interfaceOrientation == .landscapeLeft || interfaceOrientation == .landscapeRight)
        let wideFOVRad = fovHorizontalDeg * degToRad
        let narrowFOVRad = 2.0 * atan(tan(wideFOVRad / 2.0) / sensorAspectRatio)
        let horizFOV = isLandscape ? wideFOVRad : narrowFOVRad
        let focalPx = (Double(viewSize.width) / 2.0) / tan(horizFOV / 2.0)

        let px = Double(viewSize.width) * 0.5 + focalPx * (sx / depth)
        let py = Double(viewSize.height) * 0.5 - focalPx * (sy / depth)

        let margin = 80.0
        guard px >= -margin, px <= Double(viewSize.width) + margin,
              py >= -margin, py <= Double(viewSize.height) + margin else {
            return nil
        }
        return CGPoint(x: px, y: py)
    }

    static func projectHorizontalToScreen(
        azDeg: Double,
        altDeg: Double,
        rotMatrix: CMRotationMatrix,
        azOffsetDeg: Double,
        altOffsetDeg: Double,
        viewSize: CGSize,
        fovHorizontalDeg: Double,
        sensorAspectRatio: Double,
        interfaceOrientation: UIInterfaceOrientation
    ) -> CGPoint? {
        let adjAlt = max(-89.9, min(89.9, altDeg + altOffsetDeg))
        let vRef = horizontalToRefVector(azimuthDeg: azDeg + azOffsetDeg, altitudeDeg: adjAlt)
        return projectVectorToScreen(
            vRef: vRef,
            rotMatrix: rotMatrix,
            viewSize: viewSize,
            fovHorizontalDeg: fovHorizontalDeg,
            sensorAspectRatio: sensorAspectRatio,
            interfaceOrientation: interfaceOrientation
        )
    }

    /// Project a celestial J2000 object onto SwiftUI screen coordinates, accounting for device orientation & calibration offset
    static func projectToScreen(
        raHours: Double,
        decDeg: Double,
        coordinate: CLLocationCoordinate2D,
        date: Date,
        rotMatrix: CMRotationMatrix,
        azOffsetDeg: Double,
        altOffsetDeg: Double,
        viewSize: CGSize,
        fovHorizontalDeg: Double,
        sensorAspectRatio: Double, // typically 4/3 for camera sensor
        interfaceOrientation: UIInterfaceOrientation
    ) -> SkyProjection {
        let hz = equatorialToHorizontal(raHours: raHours, decDeg: decDeg, coordinate: coordinate, date: date)
        guard let pt = projectHorizontalToScreen(
            azDeg: hz.azimuthDeg,
            altDeg: hz.altitudeDeg,
            rotMatrix: rotMatrix,
            azOffsetDeg: azOffsetDeg,
            altOffsetDeg: altOffsetDeg,
            viewSize: viewSize,
            fovHorizontalDeg: fovHorizontalDeg,
            sensorAspectRatio: sensorAspectRatio,
            interfaceOrientation: interfaceOrientation
        ) else {
            return SkyProjection(screenPoint: .zero, altitudeDeg: hz.altitudeDeg, azimuthDeg: hz.azimuthDeg, isVisibleInFrame: false, isAboveHorizon: hz.altitudeDeg >= 0)
        }

        return SkyProjection(
            screenPoint: pt,
            altitudeDeg: hz.altitudeDeg,
            azimuthDeg: hz.azimuthDeg,
            isVisibleInFrame: true,
            isAboveHorizon: hz.altitudeDeg >= 0
        )
    }

    /// Compute camera center Azimuth/Altitude & direction arrows toward a chosen AstroTarget
    static func computeGuidance(
        target: AstroTarget,
        coordinate: CLLocationCoordinate2D,
        date: Date,
        rotMatrix: CMRotationMatrix,
        azOffsetDeg: Double,
        altOffsetDeg: Double
    ) -> TargetGuidance {
        let tHz = equatorialToHorizontal(raHours: target.raHours, decDeg: target.decDeg, coordinate: coordinate, date: date)

        // Forward vector of back camera in device frame is (0, 0, -1). Map Device -> Ref using R^T
        let fwdRef = simd_double3(-rotMatrix.m31, -rotMatrix.m32, -rotMatrix.m33)
        let camAlt = asin(max(-1.0, min(1.0, fwdRef.z))) * radToDeg - altOffsetDeg
        var camAz = atan2(-fwdRef.y, fwdRef.x) * radToDeg - azOffsetDeg
        camAz = camAz.truncatingRemainder(dividingBy: 360.0)
        if camAz < 0 { camAz += 360.0 }

        var dAz = (tHz.azimuthDeg - camAz).truncatingRemainder(dividingBy: 360.0)
        if dAz > 180.0 { dAz -= 360.0 }
        if dAz < -180.0 { dAz += 360.0 }
        let dAlt = tHz.altitudeDeg - camAlt

        let vTarget = horizontalToRefVector(azimuthDeg: tHz.azimuthDeg, altitudeDeg: tHz.altitudeDeg)
        let vCam = horizontalToRefVector(azimuthDeg: camAz, altitudeDeg: camAlt)
        let angDist = acos(max(-1.0, min(1.0, simd_dot(vTarget, vCam)))) * radToDeg

        return TargetGuidance(
            azimuthDeltaDeg: dAz,
            altitudeDeltaDeg: dAlt,
            angularDistanceDeg: angDist,
            isCentered: angDist < 6.0
        )
    }

    /// NPF / 500 rule recommendation for zero star trailing based on 35mm-equiv focal length
    static func maxSharpShutterSeconds(focalLength35mm: Double) -> Double {
        let fl = max(12.0, focalLength35mm)
        return min(30.0, round((300.0 / fl) * 10.0) / 10.0)
    }

    /// Construct exact CMRotationMatrix (Ref -> Device) pointing back camera at (azDeg, altDeg)
    static func makeLookAtRotationMatrix(azDeg: Double, altDeg: Double) -> CMRotationMatrix {
        let fwd = horizontalToRefVector(azimuthDeg: azDeg, altitudeDeg: max(-85.0, min(85.0, altDeg)))
        let worldUp = simd_double3(0, 0, 1)
        var devX = simd_cross(fwd, worldUp)
        if simd_length(devX) < 1e-6 { devX = simd_double3(0, -1, 0) }
        devX = simd_normalize(devX)
        let devY = simd_normalize(simd_cross(devX, fwd))
        let devZ = -fwd
        // Rows of R transform Ref -> Device
        return CMRotationMatrix(
            m11: devX.x, m12: devX.y, m13: devX.z,
            m21: devY.x, m22: devY.y, m23: devY.z,
            m31: devZ.x, m32: devZ.y, m33: devZ.z
        )
    }
}
