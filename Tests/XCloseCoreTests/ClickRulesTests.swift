import CoreGraphics
import Testing
import XCloseCore

private let buttonFrame = CGRect(x: 108, y: 140, width: 14, height: 16)
private let insideButton = CGPoint(x: 115, y: 148)

private func facts(role: String? = "AXButton", subrole: String? = "AXCloseButton", enabled: Bool? = true,
                   frame: CGRect? = buttonFrame, pid: Int32 = 500, windowRole: String? = "AXWindow",
                   windowSubrole: String? = "AXStandardWindow", own: Bool = true) -> CloseButtonFacts {
    CloseButtonFacts(role: role, subrole: subrole, isEnabled: enabled, frame: frame, pid: pid,
                     windowRole: windowRole, windowSubrole: windowSubrole, isWindowsOwnCloseButton: own)
}

@Suite("Click rules")
struct ClickRulesTests {
    @Test func plainClickWhileActivePassesPrecheck() {
        #expect(ClickRules.precheck(isActive: true, isSynthetic: false, modifiers: []) == nil)
    }

    @Test func optionClickBypasses() {
        #expect(ClickRules.precheck(isActive: true, isSynthetic: false, modifiers: .option) == .optionBypass)
        #expect(ClickRules.precheck(isActive: true, isSynthetic: false, modifiers: [.option, .shift]) == .optionBypass)
    }

    @Test(arguments: [ModifierState.command, .control, .shift])
    func otherModifiersPassThrough(modifier: ModifierState) {
        #expect(ClickRules.precheck(isActive: true, isSynthetic: false, modifiers: modifier) == .otherModifier)
    }

    @Test func inactiveOrSyntheticPassesThrough() {
        #expect(ClickRules.precheck(isActive: false, isSynthetic: false, modifiers: []) == .inactive)
        #expect(ClickRules.precheck(isActive: true, isSynthetic: true, modifiers: []) == .syntheticEvent)
    }

    @Test func titleBarBandIsTopOfWindowOnly() {
        let window = CGRect(x: 100, y: 130, width: 800, height: 600)
        #expect(ClickRules.isInTitleBarBand(point: CGPoint(x: 115, y: 148), windowBounds: window))
        #expect(ClickRules.isInTitleBarBand(point: CGPoint(x: 880, y: 140), windowBounds: window)) // RTL layouts
        #expect(!ClickRules.isInTitleBarBand(point: CGPoint(x: 115, y: 400), windowBounds: window))
        #expect(!ClickRules.isInTitleBarBand(point: CGPoint(x: 50, y: 140), windowBounds: window))
    }

    @Test func titleBarBandWorksOnSecondaryDisplaysWithNegativeCoordinates() {
        let window = CGRect(x: -1800, y: -900, width: 1200, height: 800)
        #expect(ClickRules.isInTitleBarBand(point: CGPoint(x: -1790, y: -890), windowBounds: window))
    }

    @Test func standardWindowCloseButtonValidates() {
        #expect(ClickRules.validate(facts(), point: insideButton, expectedPID: 500) == .success(buttonFrame))
    }

    @Test func contentButtonNamedCloseIsRejected() {
        // A web page or dialog "Close" button is an AXButton without the close subrole.
        #expect(ClickRules.validate(facts(subrole: nil), point: insideButton, expectedPID: 500) == .failure(.notCloseButton))
        #expect(ClickRules.validate(facts(role: "AXLink"), point: insideButton, expectedPID: 500) == .failure(.notCloseButton))
    }

    @Test func closeSubroleThatIsNotTheWindowsCloseButtonIsRejected() {
        #expect(ClickRules.validate(facts(own: false), point: insideButton, expectedPID: 500) == .failure(.notWindowCloseButton))
    }

    @Test(arguments: ["AXDialog", "AXFloatingWindow", "AXSystemDialog", "AXSheet"])
    func panelsDialogsAndSheetsKeepNormalBehavior(subrole: String) {
        #expect(ClickRules.validate(facts(windowSubrole: subrole), point: insideButton, expectedPID: 500) == .failure(.notStandardWindow))
    }

    @Test func disabledOrUnknownEnabledStatePassesThrough() {
        #expect(ClickRules.validate(facts(enabled: false), point: insideButton, expectedPID: 500) == .failure(.closeButtonDisabled))
        #expect(ClickRules.validate(facts(enabled: nil), point: insideButton, expectedPID: 500) == .failure(.closeButtonDisabled))
    }

    @Test func ownerMustMatchWindowServerOwner() {
        // Resolves ownership from the clicked window, not the frontmost app.
        #expect(ClickRules.validate(facts(pid: 501), point: insideButton, expectedPID: 500) == .failure(.ownerMismatch))
    }

    @Test func pointMustBeOnTheButton() {
        #expect(ClickRules.validate(facts(), point: CGPoint(x: 160, y: 148), expectedPID: 500) == .failure(.pointOutsideButton))
        #expect(ClickRules.validate(facts(frame: nil), point: insideButton, expectedPID: 500) == .failure(.accessibilityError))
    }
}
