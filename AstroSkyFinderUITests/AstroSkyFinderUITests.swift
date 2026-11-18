import XCTest

final class AstroSkyFinderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchARTogglesAutoFocusAndCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Clean full-screen Stellarium AR + Virtual Metal Night Sky
        sleep(2)
        attachScreenshot(name: "01_FullScreen_AR_Viewfinder")

        // 2. Run Auto Star Focus Sweep & wait for lock (~0.935)
        let focusBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Auto Nét'")).firstMatch
        if focusBtn.waitForExistence(timeout: 3) {
            focusBtn.tap()
            let lockedBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Nét 0.'")).firstMatch
            _ = lockedBtn.waitForExistence(timeout: 9)
        }

        // 3. Pick Orion Target so AR Guidance Arrow displays clearly in full-screen sky!
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
            attachScreenshot(name: "02_AutoFocus_And_TargetArrow")
        }

        // 4. Expand Pro Controls Drawer (MF / ISO / Exposure / RAW Count)
        let slidersBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Thông số'")).firstMatch
        if slidersBtn.waitForExistence(timeout: 3) {
            slidersBtn.tap()
            sleep(1)
            attachScreenshot(name: "03_Pro_Sliders_Expanded")
            slidersBtn.tap()
        }

        // 5. Scroll top AR layer bar left to expose Night Vision Red UI button & tap it
        let layerBar = app.scrollViews.firstMatch
        if layerBar.waitForExistence(timeout: 2) {
            layerBar.swipeLeft()
            sleep(1)
        }
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
