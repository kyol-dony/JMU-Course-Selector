import Foundation

enum AppBuildIdentity {
    static let affiliationNotice = "Unofficial planning tool · Not affiliated with or endorsed by James Madison University"

    static var notice: String {
        #if DEBUG || JMU_DEV_TOOLS
        let developmentBuild = true
        #else
        let developmentBuild = false
        #endif
        return notice(
            version: Bundle.main.object(forInfoDictionaryKey: "JMUPlannerSemanticVersion") as? String,
            developmentBuild: developmentBuild
        )
    }

    static func notice(version: String?, developmentBuild: Bool) -> String {
        guard let version, !version.isEmpty else { return affiliationNotice }
        // Build metadata may contain hyphens; only the portion before '+'
        // determines whether this is a prerelease. All 0.x builds are development.
        let release = version.split(separator: "+", maxSplits: 1)[0]
        guard developmentBuild || release.hasPrefix("0.") || release.contains("-") else {
            return affiliationNotice
        }
        return "\(affiliationNotice) (dev v\(version))"
    }
}
