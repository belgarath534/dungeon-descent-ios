// swift-tools-version:5.9
// ONNX Runtime 1.24.2 (Microsoft), for the Lewis Voice Pack.
//
// Microsoft took down its Swift package's GitHub repository, then its
// download server began answering with a certificate for another name (both
// Nov 2026). So this is Microsoft's own zip (the one its CocoaPods release
// uses), kept in swift/Vendor/archives and published as this repository's
// "onnxruntime-1.24.2" release (voice-pack-mirror.yml), locked to its
// SHA-256: a different file is refused. The app talks to it through the C API.
import PackageDescription

let package = Package(
    name: "OnnxRuntimeC",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "OnnxRuntimeC", targets: ["OnnxRuntimeC"])],
    targets: [
        .binaryTarget(
            name: "onnxruntime",
            url: "https://github.com/belgarath534/dungeon-descent-ios/releases/download/onnxruntime-1.24.2/pod-archive-onnxruntime-c-1.24.2.zip",
            checksum: "f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54"),
        .target(
            name: "OnnxRuntimeC",
            dependencies: ["onnxruntime"],
            linkerSettings: [
                // A static C++ library, built with Core ML support.
                .linkedLibrary("c++"),
                .linkedFramework("CoreML"),
                .linkedFramework("Foundation"),
            ]),
    ])
