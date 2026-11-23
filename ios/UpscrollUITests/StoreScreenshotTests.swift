import XCTest

/// App Store screenshots from native screens only (no YouTube interface or creators' videos).
/// Run: xcodebuild test -only-testing:UpscrollUITests/StoreScreenshotTests  (SCREENSHOT_DIR = output folder)
final class StoreScreenshotTests: XCTestCase {
    private var dir: String { ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory() }

    private func save(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png"); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testOnboardingPages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding", "-startURL", "about:blank"]
        app.launch()
        sleep(3)
        save("onboarding-0")
        let next = app.buttons["onboarding-next"]
        for i in 1...7 {
            guard next.waitForExistence(timeout: 4), next.isHittable else { break }
            // Pages with choices need one picked before Next works.
            for id in ["lang-ja", "why-travel", "level-beginner", "goal-1"] where app.buttons[id].exists { app.buttons[id].tap() }
            next.tap()
            sleep(app.otherElements["feed-demo"].exists ? 5 : 2)
            save("onboarding-\(i)")
        }
    }

    func testDashboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-dashboard", "-startURL", "about:blank"]
        app.launch()
        sleep(4)
        save("dashboard-home")
        for tab in ["Learn", "Progress"] where app.buttons[tab].exists {
            app.buttons[tab].tap(); sleep(2); save("dashboard-\(tab.lowercased())")
        }
    }
}
