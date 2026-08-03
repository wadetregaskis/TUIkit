//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StderrSuppressionTests.swift
//
//  The stderr redirection around CoreGraphics' first-rasterization IOKit probe
//  mutates the process-global file-descriptor table. Image decodes run
//  concurrently, so unserialized suppressions could interleave: a second
//  load's `dup` captures fd 2 while a first has it pointed at `/dev/null`,
//  and its "restore" then pins stderr to the null device for the rest of the
//  process — every later diagnostic silently vanishes.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(AppKit)

    import Darwin
    import Foundation
    import Testing

    @testable import TUIkitImage

    @Suite("stderr suppression", .serialized)
    struct StderrSuppressionTests {

        /// Where fd 2 currently points, by device and inode — path strings are
        /// not stable for pipes/ttys, but `fstat` identity is.
        private func stderrIdentity() -> (dev: dev_t, ino: ino_t) {
            var status = stat()
            fstat(STDERR_FILENO, &status)
            return (status.st_dev, status.st_ino)
        }

        @Test("stderr is restored after a suppression")
        func restoredAfterOne() {
            let before = stderrIdentity()
            PlatformImageLoader.suppressingStandardError {}
            let after = stderrIdentity()
            #expect(before == after, "fd 2 points where it did")
        }

        /// The race: hammer concurrent suppressions and verify fd 2 still
        /// points at the original target. Pre-fix the interleaving
        /// dup/dup2/restore triples routinely leave it on `/dev/null`.
        @Test("Concurrent suppressions never leave stderr on /dev/null")
        func concurrentSuppressionsRestore() async {
            let before = stderrIdentity()

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        for _ in 0..<200 {
                            PlatformImageLoader.suppressingStandardError {}
                        }
                    }
                }
            }

            let after = stderrIdentity()
            #expect(
                before == after,
                "stderr survived \(4 * 200) concurrent suppressions: \(before) vs \(after)")
        }
    }

#endif
