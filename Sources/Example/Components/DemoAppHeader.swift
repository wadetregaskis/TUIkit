//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DemoAppHeader.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Reusable app header for all Example App pages.
///
/// Shows the page title on the left, and version + system info on the right.
/// Optionally displays a subtitle below the title row.
///
/// # Example
///
/// ```swift
/// .appHeader { DemoAppHeader("page.buttons.title") }
/// .appHeader { DemoAppHeader("app.title", subtitle: "app.subtitle") }
/// ```
///
/// Both are display prose, so both are localization keys — see ``DemoSection``
/// for the pattern. The subtitle key is not optional, because `nil` has nothing
/// to look up and would make the two initializers ambiguous.
struct DemoAppHeader: View {
    let title: String
    let subtitle: String?

    /// Creates a header with a localized title and subtitle.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the page title.
    ///   - subtitleKey: The key for the line beneath it.
    init(_ titleKey: LocalizedStringKey, subtitle subtitleKey: LocalizedStringKey) {
        self.init(titleKey.localized, subtitle: subtitleKey.localized)
    }

    /// Creates a header with a localized title and no subtitle.
    ///
    /// - Parameter titleKey: The key for the page title.
    init(_ titleKey: LocalizedStringKey) {
        self.init(titleKey.localized)
    }

    /// Creates a header shown as written, with a subtitle.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overloads above — see
    /// ``LocalizedStringKey``. Two independent lines of prose, so two type
    /// parameters: a caller may well have computed one and sliced the other.
    ///
    /// - Parameters:
    ///   - title: The page title.
    ///   - subtitle: The line beneath it.
    @_disfavoredOverload
    init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, subtitle: S2) {
        self.title = String(title)
        self.subtitle = String(subtitle)
    }

    /// Creates a header shown as written, with no subtitle.
    ///
    /// The absent subtitle is an arity here rather than the `subtitle:
    /// String? = nil` this used to be, because a generic parameter can carry
    /// neither a default nor a `nil`: there is nothing for Swift to infer `S2`
    /// from in either case. So it moves out into its own overload, the same way
    /// `QuitShortcut`'s defaulted label does. Nothing is lost — the key side
    /// already spells the two cases as two initializers, for its own reason
    /// (`nil` has no key to look up), so this only makes the disfavoured side
    /// mirror it.
    ///
    /// - Parameter title: The page title.
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S) {
        self.title = String(title)
        self.subtitle = nil
    }

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).bold().foregroundStyle(.palette.accent)
                    if let subtitle {
                        Text(subtitle)
                            .foregroundStyle(.palette.foregroundSecondary)
                            .italic()
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("TUIkit v\(tuiKitVersion)")
                    Text(systemInfo)
                }
                .foregroundStyle(.palette.foregroundTertiary)
            }
            // A column of air inside the walls, on both sides. Symmetric now
            // that the header lays itself out at the terminal's width: it used
            // to be leading-only, compensating for the page gutter narrowing
            // the header's context, which put one column on the left and two on
            // the right.
            .padding(.horizontal, 1)
        }
    }
}

// MARK: - System Info

extension DemoAppHeader {
    private var systemInfo: String {
        "\(osName) \(osVersion) · \(architecture)"
    }

    private var osName: String {
        #if os(macOS)
            return "macOS"
        #elseif os(Linux)
            return linuxDistroName
        #else
            return "Unknown"
        #endif
    }

    private var osVersion: String {
        #if os(macOS)
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion)"
        #elseif os(Linux)
            return linuxDistroVersion
        #else
            return ""
        #endif
    }

    private var architecture: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }
}

// MARK: - Linux Distro Detection

#if os(Linux)
    extension DemoAppHeader {
        /// Reads a value from /etc/os-release.
        private func osReleaseValue(for key: String) -> String? {
            guard let contents = try? String(contentsOfFile: "/etc/os-release", encoding: .utf8) else {
                return nil
            }
            for line in contents.split(separator: "\n") where line.hasPrefix("\(key)=") {
                let value = line.dropFirst(key.count + 1)
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            return nil
        }

        private var linuxDistroName: String {
            osReleaseValue(for: "NAME") ?? "Linux"
        }

        private var linuxDistroVersion: String {
            osReleaseValue(for: "VERSION_ID") ?? kernelVersion
        }

        private var kernelVersion: String {
            var uts = utsname()
            uname(&uts)
            return withUnsafePointer(to: &uts.release) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(SYS_NMLN)) {
                    String(cString: $0)
                }
            }
        }
    }
#endif
