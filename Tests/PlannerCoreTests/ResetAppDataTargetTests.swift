import Foundation
import Testing
@testable import JMUCoursePlanner

@Suite("Reset App Data targets")
struct ResetAppDataTargetTests {
    private let support = URL(fileURLWithPath: "/tmp/JMUCoursePlanner", isDirectory: true)

    @Test("public reset clears plans but keeps the downloaded catalog")
    func publicResetKeepsCatalog() {
        let targets = CatalogRepository.resetTargets(in: support, includeCatalog: false)
        #expect(targets.map(\.lastPathComponent) == ["Plans"])
    }

    @Test("developer reset also clears the catalog cache")
    func developerResetClearsCatalog() {
        let targets = CatalogRepository.resetTargets(in: support, includeCatalog: true)
        #expect(Set(targets.map(\.lastPathComponent)) == ["Catalog", "Plans"])
    }

    @Test("default build keeps the catalog on reset")
    func defaultBuildKeepsCatalog() {
        #if JMU_DEV_TOOLS
        #expect(CatalogRepository.resetClearsCatalog)
        #else
        #expect(!CatalogRepository.resetClearsCatalog)
        #endif
    }
}
