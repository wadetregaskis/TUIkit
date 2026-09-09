//  🖥️ TUIkit — Terminal UI Kit for Swift
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
        ///
        /// **Under the redirect's own lock**, and `.serialized` on the suite is
        /// not enough for it: that orders these tests against each other, and the
        /// thing being observed is process-global. Any sibling suite decoding a
        /// real image calls ``PlatformImageLoader/suppressingStandardError(_:)``
        /// for the CoreGraphics draw, and fd 2 legitimately points at
        /// `/dev/null` for the length of it — so an unlocked sample taken then
        /// reads the null device and the comparison fails, having observed
        /// nothing wrong.
        ///
        /// That is not hypothetical and it is not the product: driven
        /// deterministically, with one thread holding a suppression across a
        /// `usleep` and another sampling, the unlocked read returns
        /// `/dev/null`'s `(dev, ino)` while the redirect is up and the original
        /// identity after it comes down. The suppression restores correctly; the
        /// OBSERVATION was the race. Seen once as a failure of the concurrent
        /// case under `swift test --filter 'Image'`, and never alone — which is
        /// exactly the signature of a sibling suite, not of this one.
        private func stderrIdentity() -> (dev: dev_t, ino: ino_t) {
            PlatformImageLoader.stderrRedirectLock.lock()
            defer { PlatformImageLoader.stderrRedirectLock.unlock() }
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
