// swift-tools-version: 5.9
import PackageDescription
import Foundation

let useLocalOnly = ProcessInfo.processInfo.environment["EDUVIS_LOCAL_SPM_ONLY"] == "1"

let package = Package(
    name: "EduVisNativeAI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EduVisNativeAI", targets: ["EduVisNativeAI"])
    ],
    dependencies: useLocalOnly ? [] : [
        .package(url: "https://github.com/google-ai-edge/LiteRT-LM", from: "0.19.0")
    ],
    targets: [
        .executableTarget(
            name: "EduVisNativeAI",
            dependencies: useLocalOnly ? [] : [
                .product(name: "LiteRTLM", package: "LiteRT-LM")
            ],
            path: ".",
            exclude: [
                "EduVis Native AI.app",
                "build_native_app.sh",
                "README.md"
            ]
        )
    ]
)
