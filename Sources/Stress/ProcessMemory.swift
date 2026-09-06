//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProcessMemory.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - What the process is costing in RAM

/// The bench's memory counterpart to `threadCPUNanoseconds()`.
///
/// CPU has had a careful number here for a while and memory has had none, which
/// made "is this change cheaper?" a question about one resource out of two. A
/// render cache is the clearest case: it buys an order of magnitude of CPU by
/// keeping buffers, and until now nothing in the tooling said what that costs.
///
/// Two numbers rather than one, because they answer different questions:
///
/// - **Peak** is what has to fit. It is the number that decides whether a
///   long-running TUI is a good citizen on a small machine, and it never goes
///   down, so a single reading at the end is the whole truth.
/// - **Average** is what the process typically holds. A peak reached once
///   during a resize is a different thing from a peak held for the whole run,
///   and only sampling can tell them apart.
///
/// `#if canImport` rather than `#if os(...)`, per the project's rule: the
/// question is whether the platform HAS the facility, not what it is called.
enum ProcessMemory {

    /// The largest resident set this process has ever held, in bytes — or
    /// `nil` where the platform will not say.
    ///
    /// `ru_maxrss` is the one portable spelling, and its UNIT is not portable:
    /// Darwin reports bytes, Linux reports kilobytes. Getting that wrong is a
    /// silent factor of 1024, which is exactly the kind of number somebody
    /// would quote in a commit message, so it is converted here and once.
    static func peakResidentBytes() -> UInt64? {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0, usage.ru_maxrss > 0 else { return nil }
        let raw = UInt64(usage.ru_maxrss)
        #if canImport(Darwin)
        return raw
        #else
        return raw &* 1024
        #endif
        #else
        return nil
        #endif
    }

    /// What the process is holding resident *right now*, in bytes — or `nil`
    /// where the platform will not say.
    ///
    /// There is no portable spelling of this one at all, so it is two
    /// implementations. Sampled rather than integrated: the caller reads it
    /// every so many frames, which costs a syscall at that cadence instead of
    /// one per frame.
    static func currentResidentBytes() -> UInt64? {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
        #elseif canImport(Glibc) || canImport(Musl)
        // `statm`'s second field is resident pages. `/proc/self/stat`'s rss
        // field is the same number; statm is read because it is short enough
        // that one small read is always the whole file.
        guard let handle = fopen("/proc/self/statm", "r") else { return nil }
        defer { fclose(handle) }
        // `fgets` and a split rather than `fscanf`: `fscanf` is variadic, and
        // Swift will not pass `&resident` to a `CVarArg...` parameter — on
        // Linux that is a hard error ("'&' used with non-inout argument of
        // type 'Any'"), which a Darwin build never sees because this whole
        // branch is `#elseif`'d out there.
        var line = [CChar](repeating: 0, count: 128)
        guard fgets(&line, Int32(line.count), handle) != nil else { return nil }
        let fields = String(cString: line).split(separator: " ")
        guard fields.count > 1, let resident = UInt64(fields[1]) else { return nil }
        return resident &* UInt64(sysconf(_SC_PAGESIZE))
        #else
        return nil
        #endif
    }

    /// Running mean and peak of a sampled resident size.
    struct Samples {
        private var total: UInt64 = 0
        private var readings: UInt64 = 0
        private(set) var peakSampled: UInt64 = 0

        mutating func sample() {
            guard let bytes = ProcessMemory.currentResidentBytes() else { return }
            total &+= bytes
            readings &+= 1
            peakSampled = max(peakSampled, bytes)
        }

        /// `nil` until something has actually been sampled — an average of no
        /// readings is not zero, it is unknown, and printing 0.0 MB would read
        /// as a measurement.
        var meanBytes: UInt64? { readings == 0 ? nil : total / readings }
    }
}
