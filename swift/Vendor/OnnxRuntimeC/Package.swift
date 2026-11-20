// swift-tools-version:5.9
// ONNX Runtime 1.24.2 (Microsoft), for the Lewis Voice Pack.
//
// Microsoft took down its Swift package's GitHub repository (Nov 2026), so
// this takes the library straight from Microsoft's own download server, the
// same file its CocoaPods release uses, locked to its SHA-256: a different
// file is refused. The app talks to it through the C API (OnnxRuntimeC).
import PackageDescription

let package = Package(
    name: "OnnxRuntimeC",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "OnnxRuntimeC", targets: ["OnnxRuntimeC"])],
    targets: [
        .binaryTarget(
            name: "onnxruntime",
            url: "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip",
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
