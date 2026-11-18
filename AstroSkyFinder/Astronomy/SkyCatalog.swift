import Foundation
import simd
import SwiftUI

enum SkyLayerKind {
    case stars, constellations, milkyWay, deepSky
}

struct StarEntry: Identifiable {
    let id: String
    let name: String
    let constellation: String
    let raHours: Double   // 0..24 J2000
    let decDeg: Double    // -90..+90 J2000
    let mag: Double
    let bvColor: Double   // <0 blue-white, ~0.6 cream, >1.2 orange/amber

    var displayColor: Color {
        if bvColor < 0.05 { return Color(red: 0.72, green: 0.86, blue: 1.0) }
        if bvColor < 0.45 { return Color(red: 0.94, green: 0.96, blue: 1.0) }
        if bvColor < 0.90 { return Color(red: 1.0, green: 0.93, blue: 0.76) }
        return Color(red: 1.0, green: 0.74, blue: 0.46)
    }
}

struct ConstellationLine {
    let constellation: String
    let segments: [(String, String)]
}

struct DeepSkyEntry: Identifiable {
    let id: String
    let name: String
    let viLabel: String
    let type: String      // "Galaxy", "Nebula", "Cluster"
    let raHours: Double
    let decDeg: Double
    let radiusArcmin: Double
}

struct AstroTarget: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let raHours: Double
    let decDeg: Double
    let recommendedISO: Float
    let recommendedNote: String
}

struct SkyCatalog {
    static let stars: [StarEntry] = [
        // ORION
        StarEntry(id: "Betelgeuse", name: "Betelgeuse", constellation: "Ori", raHours: 5.9195, decDeg: 7.407, mag: 0.42, bvColor: 1.85),
        StarEntry(id: "Rigel", name: "Rigel", constellation: "Ori", raHours: 5.2423, decDeg: -8.202, mag: 0.13, bvColor: -0.03),
        StarEntry(id: "Bellatrix", name: "Bellatrix", constellation: "Ori", raHours: 5.4188, decDeg: 6.350, mag: 1.64, bvColor: -0.22),
        StarEntry(id: "Mintaka", name: "Mintaka", constellation: "Ori", raHours: 5.5334, decDeg: -0.299, mag: 2.23, bvColor: -0.22),
        StarEntry(id: "Alnilam", name: "Alnilam", constellation: "Ori", raHours: 5.6036, decDeg: -1.202, mag: 1.69, bvColor: -0.18),
        StarEntry(id: "Alnitak", name: "Alnitak", constellation: "Ori", raHours: 5.6793, decDeg: -1.943, mag: 1.77, bvColor: -0.21),
        StarEntry(id: "Saiph", name: "Saiph", constellation: "Ori", raHours: 5.7959, decDeg: -9.670, mag: 2.09, bvColor: -0.17),
        StarEntry(id: "Meissa", name: "Meissa", constellation: "Ori", raHours: 5.5856, decDeg: 9.934, mag: 3.39, bvColor: -0.18),

        // TAURUS & PLEIADES & AURIGA & PERSEUS
        StarEntry(id: "Aldebaran", name: "Aldebaran", constellation: "Tau", raHours: 4.5987, decDeg: 16.509, mag: 0.86, bvColor: 1.54),
        StarEntry(id: "Elnath", name: "Elnath", constellation: "Tau", raHours: 5.4382, decDeg: 28.607, mag: 1.65, bvColor: -0.13),
        StarEntry(id: "Alcyone", name: "Alcyone (M45)", constellation: "Tau", raHours: 3.7914, decDeg: 24.105, mag: 2.87, bvColor: -0.09),
        StarEntry(id: "Tianguan", name: "Zeta Tau", constellation: "Tau", raHours: 5.6274, decDeg: 21.143, mag: 3.00, bvColor: -0.19),
        StarEntry(id: "Ain", name: "Ain", constellation: "Tau", raHours: 4.4777, decDeg: 19.180, mag: 3.53, bvColor: 1.01),
        StarEntry(id: "Capella", name: "Capella", constellation: "Aur", raHours: 5.2782, decDeg: 45.998, mag: 0.08, bvColor: 0.80),
        StarEntry(id: "Menkalinan", name: "Menkalinan", constellation: "Aur", raHours: 5.9921, decDeg: 44.947, mag: 1.90, bvColor: 0.03),
        StarEntry(id: "Mahasim", name: "Mahasim", constellation: "Aur", raHours: 5.9951, decDeg: 37.213, mag: 2.62, bvColor: -0.08),
        StarEntry(id: "Hassaleh", name: "Hassaleh", constellation: "Aur", raHours: 4.9499, decDeg: 33.166, mag: 2.69, bvColor: 1.53),
        StarEntry(id: "Mirfak", name: "Mirfak", constellation: "Per", raHours: 3.4054, decDeg: 49.861, mag: 1.80, bvColor: 0.48),
        StarEntry(id: "Algol", name: "Algol", constellation: "Per", raHours: 3.1361, decDeg: 40.956, mag: 2.12, bvColor: -0.05),
        StarEntry(id: "ZetaPer", name: "Zeta Per", constellation: "Per", raHours: 3.9022, decDeg: 31.884, mag: 2.85, bvColor: 0.12),
        StarEntry(id: "EpsPer", name: "Eps Per", constellation: "Per", raHours: 3.9642, decDeg: 40.010, mag: 2.89, bvColor: -0.18),

        // CASSIOPEIA & ANDROMEDA & CEPHEUS
        StarEntry(id: "Schedar", name: "Schedar", constellation: "Cas", raHours: 0.6751, decDeg: 56.537, mag: 2.23, bvColor: 1.17),
        StarEntry(id: "Caph", name: "Caph", constellation: "Cas", raHours: 0.1529, decDeg: 59.150, mag: 2.27, bvColor: 0.34),
        StarEntry(id: "GammaCas", name: "Gamma Cas", constellation: "Cas", raHours: 0.9451, decDeg: 60.717, mag: 2.47, bvColor: -0.15),
        StarEntry(id: "Ruchbah", name: "Ruchbah", constellation: "Cas", raHours: 1.4303, decDeg: 60.235, mag: 2.68, bvColor: 0.13),
        StarEntry(id: "Segin", name: "Segin", constellation: "Cas", raHours: 1.9066, decDeg: 63.670, mag: 3.37, bvColor: -0.15),
        StarEntry(id: "Alpheratz", name: "Alpheratz", constellation: "And", raHours: 0.1398, decDeg: 29.090, mag: 2.06, bvColor: -0.11),
        StarEntry(id: "Mirach", name: "Mirach", constellation: "And", raHours: 1.1622, decDeg: 35.621, mag: 2.05, bvColor: 1.58),
        StarEntry(id: "Almach", name: "Almach", constellation: "And", raHours: 2.0650, decDeg: 42.330, mag: 2.17, bvColor: 1.21),
        StarEntry(id: "Alderamin", name: "Alderamin", constellation: "Cep", raHours: 21.3096, decDeg: 62.586, mag: 2.44, bvColor: 0.22),
        StarEntry(id: "Alfirk", name: "Alfirk", constellation: "Cep", raHours: 21.4776, decDeg: 70.561, mag: 3.23, bvColor: -0.22),
        StarEntry(id: "Errai", name: "Errai", constellation: "Cep", raHours: 23.6558, decDeg: 77.632, mag: 3.21, bvColor: 1.03),
        StarEntry(id: "ZetaCep", name: "Zeta Cep", constellation: "Cep", raHours: 22.1811, decDeg: 58.201, mag: 3.35, bvColor: 1.57),

        // CYGNUS & LYRA & AQUILA (SUMMER TRIANGLE + NORTHERN CROSS)
        StarEntry(id: "Deneb", name: "Deneb", constellation: "Cyg", raHours: 20.6905, decDeg: 45.280, mag: 1.25, bvColor: 0.09),
        StarEntry(id: "Sadr", name: "Sadr", constellation: "Cyg", raHours: 20.3705, decDeg: 40.257, mag: 2.20, bvColor: 0.67),
        StarEntry(id: "GienahCyg", name: "Gienah", constellation: "Cyg", raHours: 20.7702, decDeg: 33.970, mag: 2.46, bvColor: 1.03),
        StarEntry(id: "DeltaCyg", name: "Fawaris", constellation: "Cyg", raHours: 19.7496, decDeg: 45.131, mag: 2.87, bvColor: -0.03),
        StarEntry(id: "Albireo", name: "Albireo", constellation: "Cyg", raHours: 19.5126, decDeg: 27.960, mag: 3.08, bvColor: 1.13),
        StarEntry(id: "Vega", name: "Vega", constellation: "Lyr", raHours: 18.6156, decDeg: 38.784, mag: 0.03, bvColor: 0.00),
        StarEntry(id: "Sheliak", name: "Sheliak", constellation: "Lyr", raHours: 18.8347, decDeg: 33.363, mag: 3.52, bvColor: 0.00),
        StarEntry(id: "Sulafat", name: "Sulafat", constellation: "Lyr", raHours: 18.9824, decDeg: 32.690, mag: 3.24, bvColor: -0.05),
        StarEntry(id: "Altair", name: "Altair", constellation: "Aql", raHours: 19.8464, decDeg: 8.868, mag: 0.77, bvColor: 0.22),
        StarEntry(id: "Tarazed", name: "Tarazed", constellation: "Aql", raHours: 19.7709, decDeg: 10.613, mag: 2.72, bvColor: 1.52),
        StarEntry(id: "Alshain", name: "Alshain", constellation: "Aql", raHours: 19.9219, decDeg: 6.407, mag: 3.71, bvColor: 0.86),

        // CANIS MAJOR & MINOR & GEMINI
        StarEntry(id: "Sirius", name: "Sirius", constellation: "CMa", raHours: 6.7525, decDeg: -16.716, mag: -1.46, bvColor: 0.00),
        StarEntry(id: "Adhara", name: "Adhara", constellation: "CMa", raHours: 6.9771, decDeg: -28.972, mag: 1.50, bvColor: -0.21),
        StarEntry(id: "Wezen", name: "Wezen", constellation: "CMa", raHours: 7.1398, decDeg: -26.393, mag: 1.83, bvColor: 0.67),
        StarEntry(id: "Mirzam", name: "Mirzam", constellation: "CMa", raHours: 6.3783, decDeg: -17.956, mag: 1.98, bvColor: -0.24),
        StarEntry(id: "Aludra", name: "Aludra", constellation: "CMa", raHours: 7.4016, decDeg: -29.303, mag: 2.45, bvColor: -0.08),
        StarEntry(id: "Procyon", name: "Procyon", constellation: "CMi", raHours: 7.6550, decDeg: 5.225, mag: 0.34, bvColor: 0.42),
        StarEntry(id: "Castor", name: "Castor", constellation: "Gem", raHours: 7.5767, decDeg: 31.888, mag: 1.58, bvColor: 0.03),
        StarEntry(id: "Pollux", name: "Pollux", constellation: "Gem", raHours: 7.7553, decDeg: 28.026, mag: 1.14, bvColor: 1.00),
        StarEntry(id: "Alhena", name: "Alhena", constellation: "Gem", raHours: 6.6285, decDeg: 16.399, mag: 1.93, bvColor: 0.00),
        StarEntry(id: "Mebsuta", name: "Mebsuta", constellation: "Gem", raHours: 6.7322, decDeg: 25.131, mag: 3.06, bvColor: 1.40),

        // SCORPIUS & SAGITTARIUS (MILKY WAY CORE)
        StarEntry(id: "Antares", name: "Antares", constellation: "Sco", raHours: 16.4901, decDeg: -26.432, mag: 0.96, bvColor: 1.83),
        StarEntry(id: "Shaula", name: "Shaula", constellation: "Sco", raHours: 17.5601, decDeg: -37.104, mag: 1.62, bvColor: -0.22),
        StarEntry(id: "Sargas", name: "Sargas", constellation: "Sco", raHours: 17.6220, decDeg: -42.998, mag: 1.86, bvColor: 0.40),
        StarEntry(id: "Dschubba", name: "Dschubba", constellation: "Sco", raHours: 16.0055, decDeg: -22.622, mag: 2.32, bvColor: -0.12),
        StarEntry(id: "Graffias", name: "Acrab", constellation: "Sco", raHours: 16.0906, decDeg: -19.805, mag: 2.62, bvColor: -0.07),
        StarEntry(id: "EpsSco", name: "Larawag", constellation: "Sco", raHours: 16.8361, decDeg: -34.293, mag: 2.29, bvColor: 1.15),
        StarEntry(id: "KausAus", name: "Kaus Australis", constellation: "Sgr", raHours: 18.4029, decDeg: -34.385, mag: 1.85, bvColor: -0.03),
        StarEntry(id: "Nunki", name: "Nunki", constellation: "Sgr", raHours: 18.9211, decDeg: -26.297, mag: 2.02, bvColor: -0.22),
        StarEntry(id: "Ascella", name: "Ascella", constellation: "Sgr", raHours: 19.0435, decDeg: -29.880, mag: 2.60, bvColor: 0.08),
        StarEntry(id: "KausMed", name: "Kaus Media", constellation: "Sgr", raHours: 18.3499, decDeg: -29.828, mag: 2.70, bvColor: 1.38),
        StarEntry(id: "KausBor", name: "Kaus Borealis", constellation: "Sgr", raHours: 18.4662, decDeg: -25.422, mag: 2.81, bvColor: 1.04),

        // URSA MAJOR & URSA MINOR & LEO & BOOTES
        StarEntry(id: "Polaris", name: "Polaris (Bắc Đẩu)", constellation: "UMi", raHours: 2.5303, decDeg: 89.264, mag: 1.98, bvColor: 0.60),
        StarEntry(id: "Kochab", name: "Kochab", constellation: "UMi", raHours: 14.8451, decDeg: 74.156, mag: 2.08, bvColor: 1.47),
        StarEntry(id: "Dubhe", name: "Dubhe", constellation: "UMa", raHours: 11.0621, decDeg: 61.751, mag: 1.79, bvColor: 1.07),
        StarEntry(id: "Merak", name: "Merak", constellation: "UMa", raHours: 11.0307, decDeg: 56.382, mag: 2.37, bvColor: -0.02),
        StarEntry(id: "Phecda", name: "Phecda", constellation: "UMa", raHours: 11.8972, decDeg: 53.695, mag: 2.44, bvColor: 0.00),
        StarEntry(id: "Megrez", name: "Megrez", constellation: "UMa", raHours: 12.2570, decDeg: 57.033, mag: 3.31, bvColor: 0.08),
        StarEntry(id: "Alioth", name: "Alioth", constellation: "UMa", raHours: 12.9005, decDeg: 55.960, mag: 1.77, bvColor: -0.02),
        StarEntry(id: "Mizar", name: "Mizar", constellation: "UMa", raHours: 13.3988, decDeg: 54.925, mag: 2.27, bvColor: 0.02),
        StarEntry(id: "Alkaid", name: "Alkaid", constellation: "UMa", raHours: 13.7923, decDeg: 49.313, mag: 1.86, bvColor: -0.19),
        StarEntry(id: "Arcturus", name: "Arcturus", constellation: "Boo", raHours: 14.2610, decDeg: 19.182, mag: -0.05, bvColor: 1.23),
        StarEntry(id: "Regulus", name: "Regulus", constellation: "Leo", raHours: 10.1395, decDeg: 11.967, mag: 1.35, bvColor: -0.11),
        StarEntry(id: "Denebola", name: "Denebola", constellation: "Leo", raHours: 11.8177, decDeg: 14.572, mag: 2.14, bvColor: 0.09),
        StarEntry(id: "Algieba", name: "Algieba", constellation: "Leo", raHours: 10.3329, decDeg: 19.841, mag: 2.01, bvColor: 1.15),
        StarEntry(id: "Canopus", name: "Canopus", constellation: "Car", raHours: 6.3992, decDeg: -52.696, mag: -0.74, bvColor: 0.15)
    ]

    static let constellationLines: [ConstellationLine] = [
        ConstellationLine(constellation: "Orion", segments: [
            ("Betelgeuse", "Bellatrix"), ("Bellatrix", "Mintaka"), ("Mintaka", "Alnilam"), ("Alnilam", "Alnitak"),
            ("Alnitak", "Betelgeuse"), ("Mintaka", "Rigel"), ("Alnitak", "Saiph"), ("Rigel", "Saiph"),
            ("Betelgeuse", "Meissa"), ("Bellatrix", "Meissa")
        ]),
        ConstellationLine(constellation: "Cassiopeia", segments: [
            ("Caph", "Schedar"), ("Schedar", "GammaCas"), ("GammaCas", "Ruchbah"), ("Ruchbah", "Segin")
        ]),
        ConstellationLine(constellation: "Cygnus", segments: [
            ("Deneb", "Sadr"), ("Sadr", "Albireo"), ("DeltaCyg", "Sadr"), ("Sadr", "GienahCyg")
        ]),
        ConstellationLine(constellation: "Lyra", segments: [
            ("Vega", "Sheliak"), ("Sheliak", "Sulafat"), ("Sulafat", "Vega")
        ]),
        ConstellationLine(constellation: "Aquila", segments: [
            ("Tarazed", "Altair"), ("Altair", "Alshain")
        ]),
        ConstellationLine(constellation: "Auriga", segments: [
            ("Capella", "Menkalinan"), ("Menkalinan", "Mahasim"), ("Mahasim", "Elnath"),
            ("Elnath", "Hassaleh"), ("Hassaleh", "Capella")
        ]),
        ConstellationLine(constellation: "Taurus", segments: [
            ("Elnath", "Ain"), ("Ain", "Aldebaran"), ("Aldebaran", "Tianguan"), ("Ain", "Alcyone")
        ]),
        ConstellationLine(constellation: "Perseus", segments: [
            ("Segin", "Mirfak"), ("Mirfak", "Algol"), ("Mirfak", "EpsPer"), ("EpsPer", "ZetaPer")
        ]),
        ConstellationLine(constellation: "Andromeda", segments: [
            ("Alpheratz", "Mirach"), ("Mirach", "Almach")
        ]),
        ConstellationLine(constellation: "Canis Major", segments: [
            ("Mirzam", "Sirius"), ("Sirius", "Wezen"), ("Wezen", "Adhara"), ("Wezen", "Aludra")
        ]),
        ConstellationLine(constellation: "Gemini", segments: [
            ("Castor", "Pollux"), ("Castor", "Mebsuta"), ("Pollux", "Alhena")
        ]),
        ConstellationLine(constellation: "Ursa Major", segments: [
            ("Dubhe", "Merak"), ("Merak", "Phecda"), ("Phecda", "Megrez"),
            ("Megrez", "Dubhe"), ("Megrez", "Alioth"), ("Alioth", "Mizar"), ("Mizar", "Alkaid")
        ]),
        ConstellationLine(constellation: "Scorpius", segments: [
            ("Graffias", "Dschubba"), ("Dschubba", "Antares"), ("Antares", "EpsSco"),
            ("EpsSco", "Sargas"), ("Sargas", "Shaula")
        ]),
        ConstellationLine(constellation: "Sagittarius", segments: [
            ("KausBor", "KausMed"), ("KausMed", "KausAus"), ("KausAus", "Ascella"),
            ("Ascella", "Nunki"), ("Nunki", "KausBor")
        ]),
        ConstellationLine(constellation: "Leo", segments: [
            ("Regulus", "Algieba"), ("Algieba", "Denebola"), ("Denebola", "Regulus")
        ])
    ]

    static let deepSkyObjects: [DeepSkyEntry] = [
        DeepSkyEntry(id: "M31", name: "M31 Andromeda", viLabel: "Thiên hà Tiên Nữ (M31)", type: "Galaxy", raHours: 0.712, decDeg: 41.269, radiusArcmin: 95),
        DeepSkyEntry(id: "M42", name: "M42 Orion Nebula", viLabel: "Tinh vân Lạp Hộ (M42)", type: "Nebula", raHours: 5.588, decDeg: -5.391, radiusArcmin: 45),
        DeepSkyEntry(id: "M45", name: "M45 Pleiades", viLabel: "Cụm sao Thất Nữ (M45)", type: "Cluster", raHours: 3.783, decDeg: 24.117, radiusArcmin: 55),
        DeepSkyEntry(id: "NGC869", name: "Double Cluster", viLabel: "Cụm sao Đôi Perseus", type: "Cluster", raHours: 2.333, decDeg: 57.133, radiusArcmin: 40),
        DeepSkyEntry(id: "NGC7000", name: "NGC 7000", viLabel: "Tinh vân Bắc Mỹ", type: "Nebula", raHours: 20.988, decDeg: 44.330, radiusArcmin: 60),
        DeepSkyEntry(id: "IC434", name: "Flame / Horsehead", viLabel: "Tinh vân Ngọn Lửa & Đầu Ngựa", type: "Nebula", raHours: 5.683, decDeg: -2.458, radiusArcmin: 35),
        DeepSkyEntry(id: "NGC1499", name: "California Nebula", viLabel: "Tinh vân California", type: "Nebula", raHours: 4.054, decDeg: 36.420, radiusArcmin: 70),
        DeepSkyEntry(id: "M8", name: "M8 Lagoon Nebula", viLabel: "Tinh vân Lagoon (Lõi Ngân Hà)", type: "Nebula", raHours: 18.060, decDeg: -24.387, radiusArcmin: 45),
        DeepSkyEntry(id: "M24", name: "M24 Star Cloud", viLabel: "Đám mây sao Sagittarius", type: "Cluster", raHours: 18.282, decDeg: -18.483, radiusArcmin: 65),
        DeepSkyEntry(id: "M13", name: "M13 Hercules", viLabel: "Cụm cầu Hercules (M13)", type: "Cluster", raHours: 16.695, decDeg: 36.461, radiusArcmin: 20),
        DeepSkyEntry(id: "M33", name: "M33 Triangulum", viLabel: "Thiên hà Tam Giác (M33)", type: "Galaxy", raHours: 1.564, decDeg: 30.660, radiusArcmin: 35),
        DeepSkyEntry(id: "IC1805", name: "Heart Nebula", viLabel: "Tinh vân Trái Tim", type: "Nebula", raHours: 2.545, decDeg: 61.450, radiusArcmin: 45)
    ]

    static let popularTargets: [AstroTarget] = [
        AstroTarget(id: "mw_core", title: "Lõi Ngân Hà (Sagittarius / M8)", subtitle: "Dày bụi vàng nâu & sáng nhất", raHours: 17.95, decDeg: -26.5, recommendedISO: 800, recommendedNote: "Khuyến nghị ISO 800 · Gộp 15s–20s hoặc 100+ RAW"),
        AstroTarget(id: "cas_m31", title: "Cassiopeia & M31 (Nhánh Thu–Đông)", subtitle: "M31 + Cụm sao Đôi + Ngân Hà", raHours: 0.85, decDeg: 52.0, recommendedISO: 640, recommendedNote: "Khuyến nghị ISO 640 · 150+ RAW để lên mượt M31 & bụi"),
        AstroTarget(id: "cygnus", title: "Cygnus (NGC 7000 & Sadr)", subtitle: "Dải bụi Ngân Hà đậm qua Thiên Nga", raHours: 20.65, decDeg: 41.5, recommendedISO: 800, recommendedNote: "Khuyến nghị ISO 800 · Rất đẹp khi hướng gần thiên đỉnh"),
        AstroTarget(id: "orion", title: "Orion & Tinh vân M42", subtitle: "Đai Orion, M42, Flame Nebula", raHours: 5.58, decDeg: -2.0, recommendedISO: 400, recommendedNote: "Khuyến nghị ISO 400–640 · Khóa nét sao cực gắt cho M42"),
        AstroTarget(id: "taurus_m45", title: "Taurus & Thất Nữ M45 – Auriga", subtitle: "Cụm sao xanh M45 + Aldebaran", raHours: 4.45, decDeg: 26.5, recommendedISO: 640, recommendedNote: "Khuyến nghị ISO 640–800 · 80+ RAW để giữ nét M45"),
        AstroTarget(id: "polaris", title: "Sao Bắc Đẩu (Polaris)", subtitle: "Định hướng trục Bắc / Tránh vệt sao", raHours: 2.53, decDeg: 89.26, recommendedISO: 400, recommendedNote: "Dùng để canh chân máy theo hướng Bắc thực")
    ]

    /// Generates exact Milky Way Centerline + Upper/Lower Envelope points in J2000 (RAh, DecDeg) via IAU Galactic rotation.
    static func milkyWayRibbon(stepDeg: Double = 6.0) -> [(center: (Double, Double), upper: (Double, Double), lower: (Double, Double))] {
        var pts: [(center: (Double, Double), upper: (Double, Double), lower: (Double, Double))] = []
        var l = 0.0
        while l <= 360.0 + 0.1 {
            // Bulge widens near Galactic Center (l ~ 0 or 360) and Cygnus (l ~ 75), narrows slightly near Anticenter (180)
            let radL = l * .pi / 180.0
            let halfWidth = 7.5 + 5.5 * max(0.0, cos(radL)) + 2.5 * exp(-pow((l - 80.0) / 35.0, 2.0))
            pts.append((
                center: SkyMath.galacticToEquatorial(lDeg: l, bDeg: 0.0),
                upper: SkyMath.galacticToEquatorial(lDeg: l, bDeg: halfWidth),
                lower: SkyMath.galacticToEquatorial(lDeg: l, bDeg: -halfWidth)
            ))
            l += stepDeg
        }
        return pts
    }

    static let starById: [String: StarEntry] = Dictionary(uniqueKeysWithValues: stars.map { ($0.id, $0) })
}
