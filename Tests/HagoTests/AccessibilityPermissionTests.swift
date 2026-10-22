import Testing
@testable import Hago

@Suite
struct AccessibilityPermissionTests {
    @Test
    func chromePermissionChecksNeverRequestConsent() {
        var checks: [Bool] = []
        let reader = ActiveWindowReader(chromeAutomationPermission: { request in
            checks.append(request)
            return -1744
        })
        #expect(!reader.chromeAutomationIsGranted())
        #expect(!reader.chromeAutomationIsGranted())
        #expect(checks == [false, false])
    }

    @Test
    func grantedAccessDoesNotPrompt() {
        var prompts = 0
        let reader = ActiveWindowReader(
            accessibilityTrustCheck: { true },
            accessibilityPermissionPrompt: { prompts += 1 }
        )

        reader.requestAccessibilityPermission()
        reader.requestAccessibilityPermission()

        #expect(prompts == 0)
    }

    @Test
    func checkingMissingAccessNeverPrompts() {
        var prompts = 0
        let reader = ActiveWindowReader(
            accessibilityTrustCheck: { false },
            accessibilityPermissionPrompt: { prompts += 1 }
        )

        for _ in 0..<5 {
            #expect(!reader.accessibilityIsTrusted())
        }
        #expect(prompts == 0)

        reader.requestAccessibilityPermission()
        #expect(prompts == 1)
    }

    @Test
    func permissionGrantedSinceLastPollPreventsPrompt() {
        var trusted = false
        var prompts = 0
        let reader = ActiveWindowReader(
            accessibilityTrustCheck: { trusted },
            accessibilityPermissionPrompt: { prompts += 1 }
        )

        #expect(!reader.accessibilityIsTrusted())
        trusted = true
        reader.requestAccessibilityPermission()

        #expect(prompts == 0)
        #expect(reader.accessibilityIsTrusted())
    }

    @Test
    func revokingAccessAllowsExplicitRequestAgain() {
        var trusted = true
        var prompts = 0
        let reader = ActiveWindowReader(
            accessibilityTrustCheck: { trusted },
            accessibilityPermissionPrompt: { prompts += 1 }
        )

        reader.requestAccessibilityPermission()
        trusted = false
        reader.requestAccessibilityPermission()

        #expect(prompts == 1)
    }
}
