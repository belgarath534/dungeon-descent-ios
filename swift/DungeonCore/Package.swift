// swift-tools-version:5.9
// DungeonCore is the game's rules with no screens attached: characters,
// gold, enemies and combat math. The SwiftUI app sits on top of it. Keeping
// it free of UIKit/SwiftUI means it can be built and tested anywhere,
// including on Linux, without a simulator.
import PackageDescription

let package = Package(
    name: "DungeonCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "DungeonCore", targets: ["DungeonCore"])
    ],
    targets: [
        .target(name: "DungeonCore", resources: [.copy("Resources/gamedata.json")]),
        .testTarget(name: "DungeonCoreTests", dependencies: ["DungeonCore"])
    ]
)
