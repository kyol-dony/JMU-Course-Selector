// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JMUCourseSelector",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PlannerCore", targets: ["PlannerCore"]),
        .executable(name: "JMUCoursePlanner", targets: ["JMUCoursePlanner"])
    ],
    targets: [
        .target(
            name: "PlannerCore",
            path: "Sources/PlannerCore"
        ),
        .executableTarget(
            name: "JMUCoursePlanner",
            dependencies: ["PlannerCore"],
            path: "Sources/JMUCoursePlanner"
        ),
        .testTarget(
            name: "PlannerCoreTests",
            dependencies: ["PlannerCore"],
            path: "Tests/PlannerCoreTests",
            exclude: [
                "_live_accounting.html",
                "_live_cs.html",
                "_live_index.html",
                "_live_gened.html",
                "_live_nursing.html",
                "_live_psyc.html"
            ]
        )
    ]
)
