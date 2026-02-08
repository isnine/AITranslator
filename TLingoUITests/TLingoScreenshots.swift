import XCTest

@MainActor
class TLingoScreenshots: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        // Wait for the app to settle after launch
        sleep(3)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screenshot Tests

    func test01Home() {
        // Home tab is selected by default on launch
        // Wait for content to load
        sleep(2)
        snapshot("01_Home")
    }

    func test02Conversation() {
        // Show the home screen with a translation result
        // The mock data should display a conversation-like state
        // Wait for mock content to appear
        sleep(2)
        snapshot("02_Conversation")
    }

    func test03Actions() {
        navigateToTab("Actions")
        sleep(2)
        snapshot("03_Actions")
    }

    func test04Models() {
        navigateToTab("Models")
        sleep(2)
        snapshot("04_Models")
    }

    func test05Settings() {
        navigateToTab("Settings")
        sleep(2)
        snapshot("05_Settings")
    }

    // MARK: - Navigation Helpers

    /// Navigate to a tab using its accessibility identifier.
    /// Each Tab in RootTabView has `.accessibilityIdentifier("tab_<name>")`.
    /// This approach works on both iPhone (tab bar buttons) and iPad
    /// (radio buttons in the sidebarAdaptable top bar).
    private func navigateToTab(_ tabName: String) {
        let identifier = "tab_\(tabName.lowercased())"

        // Primary: find by accessibility identifier (works on both iPhone and iPad)
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if element.waitForExistence(timeout: 5), element.isHittable {
            element.tap()
            return
        }

        // Fallback 1: try tab bar button by label (iPhone)
        let tabButton = app.tabBars.buttons[tabName]
        if tabButton.waitForExistence(timeout: 3), tabButton.isHittable {
            tabButton.tap()
            return
        }

        // Fallback 2: try radio button by label (iPad)
        let radioButton = app.radioButtons[tabName]
        if radioButton.waitForExistence(timeout: 3), radioButton.isHittable {
            radioButton.tap()
            return
        }

        // Fallback 3: try any button by label
        let anyButton = app.buttons[tabName]
        if anyButton.waitForExistence(timeout: 3), anyButton.isHittable {
            anyButton.tap()
            return
        }

        XCTFail("Could not find tab: \(tabName)")
    }
}
