import Foundation
import Testing
@testable import PlannerCore
@testable import JMUCoursePlanner

@Suite("Catalog cache fallback")
struct CatalogCacheFallbackTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "catalog-cache-fallback-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func touch(_ name: String, in directory: URL, contents: Data = Data("{}".utf8)) throws {
        try contents.write(to: directory.appending(path: name))
    }

    @Test("candidates run from this build's version down through older ones")
    func candidatesNewestFirst() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["catalog_html_cache_v9.json", "catalog_html_cache_v25.json", "catalog_html_cache_v26.json",
                     "catalog_html_cache_v28.json", "catalog_html_cache_vX.json", "notes.json"] {
            try touch(name, in: directory)
        }

        let names = CatalogRepository.cachedCatalogCandidates(in: directory, currentVersion: 27)
            .map(\.lastPathComponent)

        #expect(names == ["catalog_html_cache_v26.json", "catalog_html_cache_v25.json", "catalog_html_cache_v9.json"])
    }

    @MainActor
    @Test("an older cache loads when this version's cache is missing, skipping ones that don't decode")
    func olderCacheLoadsWhenCurrentIsMissing() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = try CatalogRepository().loadBundledCatalog()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try touch("catalog_html_cache_v25.json", in: directory, contents: try encoder.encode(catalog))
        try touch("catalog_html_cache_v26.json", in: directory, contents: Data("not json".utf8))

        let loaded = try CatalogRepository.loadNewestCachedCatalog(in: directory, currentVersion: 27)

        #expect(loaded.programs.map(\.id) == catalog.programs.map(\.id))
    }

    @MainActor
    @Test("no cache at any version is an error, so the bundled catalog takes over")
    func noCacheThrows() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: (any Error).self) {
            try CatalogRepository.loadNewestCachedCatalog(in: directory, currentVersion: 27)
        }
    }
}
