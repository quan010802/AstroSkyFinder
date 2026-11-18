import SwiftUI
import UIKit

@main
struct AstroSkyFinderApp: App {
    init() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            MainCameraView()
                .preferredColorScheme(.dark)
        }
    }
}
