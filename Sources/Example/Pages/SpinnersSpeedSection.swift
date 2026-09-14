//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SpinnersSpeedSection.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// The Spinners page's speed controls: one speed for the whole catalogue, and a
/// frame duration of whole 1/60 s ticks for any style that should differ.
///
/// It exists so the default durations can be chosen by watching them rather
/// than by arithmetic: every control is a picker or a stepper, so all of it is
/// reachable from the keyboard, and the page shows each row's effective frame
/// duration and one line listing all of them.
struct SpinnersSpeedSection: View {
    @Binding var choice: String
    @Binding var ratePercent: Int
    @Binding var toleranceHundredths: Int
    @Binding var frameOverrides: String
    @Binding var overrideStyle: String

    var body: some View {
        let settings = SpinnerSpeedSettings(
            choice: choice, ratePercent: ratePercent,
            toleranceHundredths: toleranceHundredths, frameOverrides: frameOverrides)
        DemoSection("page.spinners.speedSection") {
            VStack(alignment: .leading, spacing: 1) {
                // Wrapped to the customiser's width, as its hint is: a long line
                // of prose would rule out every side-by-side arrangement.
                Text("page.spinners.speedHint")
                    .frame(width: 44, alignment: .leading)
                    .foregroundStyle(.palette.foregroundSecondary)

                VStack(alignment: .leading, spacing: 0) {
                    Picker("page.spinners.speed", selection: choiceBinding) {
                        Text("page.spinners.speedAutomatic").tag(SpinnerSpeedChoice.automatic)
                        Text("page.spinners.speedHalf").tag(SpinnerSpeedChoice.half)
                        Text("page.spinners.speedStandard").tag(SpinnerSpeedChoice.standard)
                        Text("page.spinners.speedDouble").tag(SpinnerSpeedChoice.double)
                        Text("page.spinners.speedCustom").tag(SpinnerSpeedChoice.custom)
                    }
                    // Disabled rather than hidden while the speed is not Custom,
                    // so the section does not change shape under the cursor, and
                    // a disabled control takes no focus, so Tab skips them.
                    Stepper(
                        "page.spinners.rate", value: ratePercentBinding,
                        in: SpinnerSpeedSettings.ratePercentRange, step: 5
                    )
                    .stepperValueText(SpinnerSpeedSettings.hundredths(settings.ratePercent))
                    .disabled(settings.choice != .custom)
                    Picker("page.spinners.tolerance", selection: toleranceBinding) {
                        ForEach(SpinnerSpeedSettings.tolerances, id: \.self) { hundredths in
                            Text(verbatim: "±" + SpinnerSpeedSettings.hundredths(hundredths))
                                .tag(hundredths)
                        }
                    }
                    .disabled(settings.choice != .custom)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SpinnerStylePicker(
                        titleKey: "page.spinners.overrideStyle", selection: $overrideStyle)
                    Stepper(
                        "page.spinners.frameTicks", value: ticksBinding,
                        in: 0...SpinnerSpeedSettings.maximumTicks
                    )
                    .stepperValueText(ticksText(settings))
                    Button("page.spinners.clearOverrides") { frameOverrides = "" }
                        .disabled(settings.overrides.isEmpty)
                }
            }
        }
    }

    /// The picker's selection, over the stored name. A name nothing matches
    /// reads as Automatic, the speed an app has when it sets none.
    private var choiceBinding: Binding<SpinnerSpeedChoice> {
        Binding(
            get: { SpinnerSpeedChoice(rawValue: choice) ?? .automatic },
            set: { choice = $0.rawValue })
    }

    /// The stored rate, held to the stepper's range whatever the store says.
    private var ratePercentBinding: Binding<Int> {
        Binding(
            get: { SpinnerSpeedSettings.clampedRatePercent(ratePercent) },
            set: { ratePercent = SpinnerSpeedSettings.clampedRatePercent($0) })
    }

    /// The stored tolerance, as one of the picker's choices.
    private var toleranceBinding: Binding<Int> {
        Binding(
            get: { SpinnerSpeedSettings.validTolerance(toleranceHundredths) },
            set: { toleranceHundredths = SpinnerSpeedSettings.validTolerance($0) })
    }

    /// The chosen style's override in ticks, 0 for none, written back into the
    /// stored list.
    private var ticksBinding: Binding<Int> {
        Binding(
            get: {
                guard let style = SpinnerStyleChoice(rawValue: overrideStyle) else { return 0 }
                return SpinnerSpeedSettings.decodeOverrides(frameOverrides)[style] ?? 0
            },
            set: { ticks in
                guard let style = SpinnerStyleChoice(rawValue: overrideStyle) else { return }
                var overrides = SpinnerSpeedSettings.decodeOverrides(frameOverrides)
                overrides[style] = ticks > 0 ? min(ticks, SpinnerSpeedSettings.maximumTicks) : nil
                frameOverrides = SpinnerSpeedSettings.encodeOverrides(overrides)
            })
    }

    /// "7 × 16.7 ms = 116.7 ms" for an override, or what no override means.
    ///
    /// The total is the instant the override's tick count begins at, not the
    /// count times a rounded tick: seven rounded ticks are 116,666,669 ns, and a
    /// readout built that way would drift further from the frame shown with
    /// every tick added.
    private func ticksText(_ settings: SpinnerSpeedSettings) -> String {
        guard let style = SpinnerStyleChoice(rawValue: overrideStyle),
            let ticks = settings.overrides[style]
        else { return L("page.spinners.frameInherit") }
        let tick = AnimationClock.nanoseconds(AnimationClock.seconds(forTicks: 1))
        return "\(ticks) × \(SpinnerSpeedSettings.milliseconds(tick)) ms = "
            + "\(SpinnerSpeedSettings.milliseconds(AnimationClock.nanoseconds(atTick: Int64(ticks)))) ms"
    }
}

/// The catalogue-wide speed the page offers: the recommended presets, and a
/// custom rate and tolerance.
enum SpinnerSpeedChoice: String, CaseIterable, Hashable {
    case automatic, half, standard, double, custom
}

/// Everything the speed controls decide, read from the page's stored values.
///
/// The stored values are whole numbers on purpose: a rate stepped by 0.05 as a
/// `Double` drifts (twenty steps up and twenty down need not return to 1), and
/// the drifted value is what would be persisted. A percent and hundredths of the
/// rate cannot drift.
struct SpinnerSpeedSettings {
    /// The rate stepper's range, in percent.
    static let ratePercentRange = 25...400
    /// The tolerance picker's choices, in hundredths of the rate unit. All are
    /// below the smallest rate, 0.25, as a tolerance must be.
    static let tolerances = [0, 2, 5, 10, 20]
    /// The most 1/60 s ticks an override offers: 18, 300 ms, twice the slowest
    /// standard interval (`.earth`'s 9 ticks).
    static let maximumTicks = 18

    let choice: SpinnerSpeedChoice
    let ratePercent: Int
    let toleranceHundredths: Int
    /// Ticks of 1/60 s per frame, by style; a style that is absent follows the
    /// speed.
    let overrides: [SpinnerStyleChoice: Int]

    init(choice: String, ratePercent: Int, toleranceHundredths: Int, frameOverrides: String) {
        self.choice = SpinnerSpeedChoice(rawValue: choice) ?? .automatic
        self.ratePercent = Self.clampedRatePercent(ratePercent)
        self.toleranceHundredths = Self.validTolerance(toleranceHundredths)
        self.overrides = Self.decodeOverrides(frameOverrides)
    }

    /// The speed the whole catalogue runs at.
    var catalogueSpeed: IndicatorAnimationSpeed {
        switch choice {
        case .automatic: .automatic
        case .half: .halfSpeed
        case .standard: .standard
        case .double: .doubleSpeed
        case .custom:
            IndicatorAnimationSpeed(
                Double(ratePercent) / 100, tolerance: Double(toleranceHundredths) / 100)
        }
    }

    /// The speed that shows `style`'s frames for its override's whole ticks, or
    /// `nil` when it has none. `nil` for the custom row, which no override reaches.
    ///
    /// Exact, with no tolerance: the interval divided by the duration wanted is
    /// the rate that gives that duration, as `SpinnerStyle.interval`'s own doc
    /// shows.
    func overrideSpeed(for style: SpinnerStyleChoice?) -> IndicatorAnimationSpeed? {
        guard let style, let ticks = overrides[style] else { return nil }
        return IndicatorAnimationSpeed(style.style.interval / AnimationClock.seconds(forTicks: ticks))
    }

    /// How long `style` shows each frame on the page, in nanoseconds: where the
    /// `frameTicks(standard:)` the spinner itself asks of the nearest speed ends.
    func frameNanoseconds(_ style: SpinnerStyle, choice: SpinnerStyleChoice?) -> Int64 {
        let speed = overrideSpeed(for: choice) ?? catalogueSpeed
        return AnimationClock.nanoseconds(atTick: Int64(speed.frameTicks(standard: style.interval)))
    }

    // MARK: Stored values

    static func clampedRatePercent(_ percent: Int) -> Int {
        min(max(percent, ratePercentRange.lowerBound), ratePercentRange.upperBound)
    }

    static func validTolerance(_ hundredths: Int) -> Int {
        tolerances.contains(hundredths) ? hundredths : 0
    }

    /// `"dots=4,line=6"` as ticks by style. Unknown names and counts outside
    /// `1...maximumTicks` are skipped rather than trusted.
    static func decodeOverrides(_ stored: String) -> [SpinnerStyleChoice: Int] {
        var result: [SpinnerStyleChoice: Int] = [:]
        for pair in stored.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let style = SpinnerStyleChoice(rawValue: String(parts[0])),
                let ticks = Int(parts[1]), (1...maximumTicks).contains(ticks)
            else { continue }
            result[style] = ticks
        }
        return result
    }

    /// Ticks by style as `"dots=4,line=6"`, in catalogue order so one set of
    /// overrides is always spelled one way.
    static func encodeOverrides(_ overrides: [SpinnerStyleChoice: Int]) -> String {
        SpinnerStyleChoice.allCases.compactMap { style in
            overrides[style].map { "\(style.rawValue)=\($0)" }
        }
        .joined(separator: ",")
    }

    // MARK: Readouts

    /// A whole number of hundredths as a decimal: 135 is "1.35", 5 is "0.05".
    static func hundredths(_ value: Int) -> String {
        let fraction = value % 100
        return "\(value / 100)." + (fraction < 10 ? "0" : "") + "\(fraction)"
    }

    /// Nanoseconds as milliseconds to a tenth, without a trailing ".0": 110 ms
    /// is "110", 81,481,481 ns is "81.5".
    static func milliseconds(_ nanoseconds: Int64) -> String {
        let tenths = (nanoseconds + 50_000) / 100_000
        return tenths.isMultiple(of: 10) ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }

    /// A rate to one decimal place: 46.049 is "46.0".
    static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }

    /// How many distinct instants a second at least one of these frame
    /// durations ends a step: a model of how often these spinners change
    /// together, not a count of the run loop's wakes.
    ///
    /// Durations sharing a multiple change at the same instant, so this is the
    /// union of their step grids. By inclusion and exclusion it is the sum over
    /// every non-empty subset of ±1 / lcm(subset), odd subsets added and even
    /// ones taken away. The terms are collected by their lcm, so a set on one
    /// lattice collapses to a handful of terms: seventeen durations of 1 to 17
    /// whole 25 ms steps leave one, 25 ms. A term whose lcm does not fit in 64 bits of
    /// nanoseconds is dropped, which is under 1.1e-10 of an instant a second.
    ///
    /// A real loop wakes less often than this: a wake that arrives a few
    /// milliseconds late also serves the boundaries it has passed.
    static func frameInstantsPerSecond(_ durations: [Int64]) -> Double {
        var terms: [Int64: Int] = [:]
        for duration in Set(durations) where duration > 0 {
            var next = terms
            for (multiple, sign) in terms {
                let (lcm, overflow) = (multiple / gcd(multiple, duration))
                    .multipliedReportingOverflow(by: duration)
                guard !overflow else { continue }
                next[lcm, default: 0] -= sign
            }
            next[duration, default: 0] += 1
            terms = next.filter { $0.value != 0 }
        }
        return terms.reduce(0) { $0 + Double($1.value) * 1_000_000_000 / Double($1.key) }
    }

    private static func gcd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var (a, b) = (lhs, rhs)
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}
