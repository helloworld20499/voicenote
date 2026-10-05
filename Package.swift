// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SenseVoicePrototype", platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "SenseVoiceCore", targets: ["SenseVoiceCore"]),
               .executable(name: "sensevoice-smoke", targets: ["Smoke"])],
    dependencies: [
        .package(url: "https://github.com/k2-fsa/sherpa-onnx.git", revision: "040afe360a38e25daaa325ce8889abf93ea02609")
    ],
    targets: [
        .target(name: "SenseVoiceCore", dependencies: [.product(name: "sherpa-onnx", package: "sherpa-onnx")], path: "Core"),
        .executableTarget(name: "Smoke", dependencies: ["SenseVoiceCore"], path: "Smoke"),
        .testTarget(name: "CoreTests", dependencies: ["SenseVoiceCore"], path: "Tests")
    ])
