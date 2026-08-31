// swift-tools-version: 6.2
import PackageDescription

// Four modules, because the bug needs a conformance declared in a module that
// owns neither the type nor the protocol:
//
//   ProtoMod  declares `P`
//   TypeMod   declares `Thing`
//   GlueMod   declares `extension Thing: P`   ← neither owns
//   App       builds the pack
let package = Package(
    name: "PackMetadataSegfault",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ProtoMod"),
        .target(name: "TypeMod"),
        .target(name: "GlueMod", dependencies: ["ProtoMod", "TypeMod"]),
        .executableTarget(name: "App", dependencies: ["GlueMod", "ProtoMod", "TypeMod"]),
    ]
)
