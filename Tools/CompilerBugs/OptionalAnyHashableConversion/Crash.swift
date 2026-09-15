//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Crash.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// swiftc -emit-silgen -o /dev/null Crash.swift
//
// That is enough for a swift.org toolchain on macOS. Xcode's swiftc, called by
// its path, also needs `-sdk`, from an xcrun that DEVELOPER_DIR points at Xcode
// (a prefix assignment would not reach the xcrun inside `$(...)`):
//
//   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
//   "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -emit-silgen \
//       -sdk "$(xcrun --sdk macosx --show-sdk-path)" -o /dev/null Crash.swift
//
// Aborts SILGen on an assertions-enabled compiler, while it emits the
// reabstraction thunk for the conversion:
//
//   TYPE MISMATCH IN ARGUMENT 0 OF APPLY AT <<debugloc at "<compiler-generated>":0:0>>
//     argument type: $*Int
//     parameter type: $*Optional<Int>
//
// A compiler without assertions compiles it to WRONG CODE. The thunk unwraps
// the Optional as if it were implicitly unwrapped, so nil traps, then hands
// `_convertToAnyHashable<Optional<Int>>` the address of an Int. With
// `-Xfrontend -sil-verify-all` those compilers reject the SIL instead.

// A function that takes AnyHashable, converted to one that takes an Optional.
_ = { (_: AnyHashable) in } as (Int?) -> Void
