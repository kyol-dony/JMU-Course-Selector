import Testing
@testable import JMUCoursePlanner

@Suite("Build version notice")
struct AppBuildIdentityTests {
    @Test func devAndPrereleaseNoticesKeepFullCatalogVersion() {
        for version in ["0.3.0-alpha.1+catalog.28", "0.3.1+catalog.28", "1.1.0-beta.2+catalog.29"] {
            #expect(AppBuildIdentity.notice(version: version, developmentBuild: false)
                    == "\(AppBuildIdentity.affiliationNotice) (dev v\(version))")
        }
        #expect(AppBuildIdentity.notice(version: "1.0.0+catalog.28", developmentBuild: true)
                == "\(AppBuildIdentity.affiliationNotice) (dev v1.0.0+catalog.28)")
    }

    @Test func stableOrMissingVersionKeepsOriginalNotice() {
        for version in [nil, "", "1.0.0+catalog.28", "1.0.0+catalog.custom-build"] {
            #expect(AppBuildIdentity.notice(version: version, developmentBuild: false)
                    == AppBuildIdentity.affiliationNotice)
        }
        #expect(AppBuildIdentity.notice(version: nil, developmentBuild: true)
                == AppBuildIdentity.affiliationNotice)
    }
}
