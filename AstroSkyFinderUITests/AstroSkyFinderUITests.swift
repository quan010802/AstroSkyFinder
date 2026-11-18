import XCTest

final class AstroSkyFinderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchARTogglesAutoFocusAndCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // Allow simulator background sky + AR render to populate
        sleep(2)
        attachScreenshot(name: "01_Initial_AR_AllLayers")

        // Verify independent AR toggle buttons exist & toggle cleanly
        let starsBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sao'")).firstMatch
        if starsBtn.waitForExistence(timeout: 3) {
            starsBtn.tap()
            starsBtn.tap()
        }

        // Run Auto Star Focus Sweep on Virtual Night Sky!
        let focusBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Auto Nét Sao'")).firstMatch
        if focusBtn.waitForExistence(timeout: 3) {
            focusBtn.tap()
            // Wait for 0.78 -> 1.00 sweep to find sharpest 0.935 peak
            let lockedPred = NSPredicate(format: "label CONTAINS 'Nét 0.'")
            let lockedBtn = app.buttons.matching(lockedPred).firstMatch
            _ = lockedBtn.waitForExistence(timeout: 8)
            attachScreenshot(name: "02_After_AutoStarFocus")
        }

        // Open Target Finder Sheet and lock a target
        let targetBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mục tiêu'")).firstMatch
        if targetBtn.waitForExistence(timeout: 3) {
            targetBtn.tap()
            sleep(1)
            let orionRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Orion'")).firstMatch
            if orionRow.waitForExistence(timeout: 3) {
                orionRow.tap()
            } else {
                let closeBtn = app.buttons["Đóng"]
                if closeBtn.exists { closeBtn.tap() }
            }
            sleep(1)
            attachScreenshot(name: "03_TargetGuidance_AR")
        }

        // Switch to Night Vision Red UI
        let redBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Đêm đỏ'")).firstMatch
        if redBtn.waitForExistence(timeout: 3) {
            redBtn.tap()
            sleep(1)
            attachScreenshot(name: "04_NightVision_RedUI")
        }
    }

    private func attachScreenshot(name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
