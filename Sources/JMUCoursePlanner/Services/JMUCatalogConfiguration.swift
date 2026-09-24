import Foundation

enum JMUCatalogConfiguration {
    static let catalogYear = "2026-2027"
    static let rootURL = URL(string: "https://catalog.jmu.edu/")!
    static let programsURL = URL(string: "https://catalog.jmu.edu/program-search/?filter=1")!
    static let pdfURL = URL(string: "https://catalog.jmu.edu/pdf/JMU2026-2027UndergraduateCatalog.pdf")!
    static let pdfFilename = "JMU2026-2027UndergraduateCatalog.pdf"
    static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"

    static let generalEducationURLs = [
        "madison-foundations",
        "arts-humanities",
        "natural-world",
        "american-global-perspectives",
        "sociocultural-wellness"
    ].map { URL(string: "https://catalog.jmu.edu/general-education/\($0)/")! }
}
