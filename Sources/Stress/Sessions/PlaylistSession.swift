//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PlaylistSession.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - The playlist

/// Tracks in the order they will play.
@Observable
@MainActor
final class Playlist {
    struct Track: Identifiable, Equatable {
        let id: Int
        var title: String
        var artist: String
        var minutes: Int
    }

    var tracks: [Track]
    private(set) var nextID: Int

    init(tracks: [Track]) {
        self.tracks = tracks
        nextID = tracks.count
    }

    func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}

// MARK: - The page

/// A running total over a list of tracks the person can reorder and delete.
struct PlaylistPage: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(playlist.tracks.count) tracks · \(playlist.tracks.reduce(0) { $0 + $1.minutes }) min")
            List {
                ForEach(playlist.tracks) { track in TrackRow(track: track) }
                    .onMove { from, to in playlist.tracks.move(fromOffsets: from, toOffset: to) }
                    .onDelete { offsets in playlist.tracks.remove(atOffsets: offsets) }
            }
        }
    }
}

/// A track: its title, its artist, and its number — how the session reads the
/// order off the screen.
private struct TrackRow: View {
    let track: Playlist.Track

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: track.title)
            Spacer()
            Text(verbatim: track.artist).foregroundStyle(Color.gray)
            Text(verbatim: "\(track.minutes)m")
            Text(verbatim: "#\(track.id)")
        }
    }
}

// Every field compared, as the synthesized `==` does: a row equal to the one
// drawn draws the same, which is what Option C asks of a row before it
// re-checks it after a write above it. Isolated, as the view is.
extension TrackRow: @MainActor Equatable {}

// MARK: - The script

/// Someone arranging a playlist: walking up and down it, moving a track a
/// place or to an end with the keys, carrying one in move mode, dragging one
/// with the mouse, deleting the odd one — while tracks are added and renamed
/// from elsewhere.
@MainActor
final class PlaylistSession: StressSession {
    private let playlist: Playlist
    private var random: SessionRandom
    /// The steps still to come of a move in progress.
    private var pending: [SessionStep] = []
    /// The screen as it stood before this step.
    private var screen: [String] = []
    /// Whether a row is in hand (move mode): drawn at the slot it is being
    /// carried to, while the data stays put until Return places it.
    private var carrying = false

    init(config: StressConfig) {
        let seed = config.seed
        playlist = Playlist(
            tracks: (0..<config.sized(120)).map { index in
                let h = mix(seed, index)
                return Playlist.Track(
                    id: index, title: Synth.sentence(h, words: 1 + Int(h % 4)), artist: Synth.name(h >> 8),
                    minutes: 2 + Int(h % 6))
            })
        random = SessionRandom(seed: seed ^ 0x9A71)
    }

    var page: PlaylistPage { PlaylistPage(playlist: playlist) }

    var looksBeforeEachStep: Bool { true }

    func look(at screen: [String]) { self.screen = screen }

    func step(_ index: Int) -> SessionStep {
        if !pending.isEmpty {
            let next = pending.removeFirst()
            if pending.isEmpty { carrying = false }
            return next
        }
        switch random.pick([
            ("walk", 25), ("nudge", 18), ("carry", 8), ("send", 5), ("drag", 8), ("delete", 5),
            ("add", 10), ("rename", 8), ("page", 5), ("quiet", 8),
        ]) {
        case "walk":
            let key: Key = random.below(3) == 0 ? .up : .down
            return SessionStep(action: "walk", keys: Array(repeating: KeyEvent(key: key), count: random.within(1...5)))
        case "nudge":
            // One place up or down, Control and Option both — two chords
            // because no one of them reaches a program in every terminal.
            let up = random.below(2) == 0
            let key = KeyEvent(key: up ? .up : .down, ctrl: random.below(2) == 0, alt: false)
            let chord = key.ctrl ? key : KeyEvent(key: up ? .up : .down, alt: true)
            return SessionStep(action: "move", keys: Array(repeating: chord, count: random.within(1...3)))
        case "carry":
            // Pick it up, carry it a few places, and put it down — or think
            // better of it and put it back.
            let key: Key = random.below(2) == 0 ? .up : .down
            pending = Array(repeating: SessionStep(action: "move", keys: [KeyEvent(key: key)]), count: random.within(1...6))
            pending.append(SessionStep(action: "move", keys: [KeyEvent(key: random.below(4) == 0 ? .escape : .enter)]))
            carrying = true
            return SessionStep(action: "move", keys: [KeyEvent(key: .character("r"), ctrl: true)])
        case "send":
            return SessionStep(action: "move", keys: [KeyEvent(key: random.below(2) == 0 ? .home : .end, alt: true)])
        case "drag":
            return drag()
        case "delete":
            return SessionStep(action: "delete", keys: [KeyEvent(key: .delete)])
        case "add":
            let h = random.next()
            playlist.tracks.append(
                Playlist.Track(
                    id: playlist.makeID(), title: Synth.sentence(h, words: 1 + Int(h % 4)), artist: Synth.name(h >> 8),
                    minutes: 2 + Int(h % 6)))
            return SessionStep(action: "sync")
        case "rename":
            guard !playlist.tracks.isEmpty else { return SessionStep(action: "sync") }
            playlist.tracks[random.below(playlist.tracks.count)].title = Synth.sentence(random.next(), words: random.within(1...4))
            return SessionStep(action: "sync")
        case "page":
            return SessionStep(action: "walk", keys: [KeyEvent(key: random.below(2) == 0 ? .pageUp : .pageDown)])
        default:
            return SessionStep(action: "quiet")
        }
    }

    /// A row dragged by the mouse to where another row is drawn, a press, the
    /// drag in a few steps, and the release.
    private func drag() -> SessionStep {
        let rows = screen.indices.filter { screen[$0].range(of: #"#\d+"#, options: .regularExpression) != nil }
        guard rows.count > 2 else { return SessionStep(action: "drag") }
        let from = rows[random.below(rows.count)]
        let to = rows[random.below(rows.count)]
        let x = 4
        var events = [MouseEvent(button: .left, phase: .pressed, x: x, y: from)]
        let stride = from < to ? 1 : -1
        var y = from
        while y != to {
            y += stride
            events.append(MouseEvent(button: .left, phase: .dragged, x: x, y: y))
        }
        events.append(MouseEvent(button: .left, phase: .released, x: x, y: to))
        return SessionStep(action: "drag", mouse: events)
    }

    /// The total is the model's, and the tracks on the screen, top to bottom,
    /// are a run of the playlist's own order — whatever the keys and the mouse
    /// just did to it, the list draws what the data says. Except while a row is
    /// in hand: then the list shows where it WOULD go, which is the point of
    /// carrying it, and the data waits for Return.
    func check(_ screen: [String], after index: Int) -> String? {
        let total = playlist.tracks.reduce(0) { $0 + $1.minutes }
        let header = "\(playlist.tracks.count) tracks · \(total) min"
        guard screen.contains(where: { $0.hasPrefix(header) }) else { return "the header does not say \(header)" }
        guard !carrying else { return nil }
        return listProblem(screen)
    }

    /// The tracks in the list's box, read line by line: a run of the
    /// playlist's own order, with no blank line among them.
    ///
    /// In a narrow terminal a row wraps, and its number is what it cuts: a
    /// row drawn without its number — or with it truncated (`#4…`) — is still
    /// a row. So the numbers that ARE drawn must be in the playlist's order,
    /// and a track between two of them that shows no number must have a line
    /// of its own to be on: never more of them skipped than there are lines
    /// between the two with no number. Where every row shows its number,
    /// that allows no gap at all. A blank line with a track below it is a row
    /// drawn blank, at any width; blank lines at the end are the list ending,
    /// and leave no track after the last number without a line either.
    private func listProblem(_ screen: [String]) -> String? {
        guard !playlist.tracks.isEmpty else { return nil }
        guard let top = screen.firstIndex(where: { $0.hasPrefix("╭") }),
            let bottom = screen[(top + 1)...].firstIndex(where: { $0.hasPrefix("╰") })
        else { return "the list's box is not on the screen" }
        // Each line inside the walls. The right wall may be the scroll
        // indicator, and a line is padded to the terminal's width.
        let lines = screen[(top + 1)..<bottom].map { line -> (id: Int?, blank: Bool) in
            var body = line.dropFirst()
            while body.last == " " { body = body.dropLast() }
            body = body.dropLast()
            // Nothing else on a row has a `#`: the first one is the number,
            // unless the row is cut short inside it.
            let id = body.firstMatch(of: /#(\d+)(?![\d…])/).flatMap { Int($0.output.1) }
            return (id, body.allSatisfy { $0 == " " })
        }
        guard lines.contains(where: { !$0.blank }) else { return "no track is on the screen" }
        if let blank = lines.indices.first(where: { lines[$0].blank && lines[($0 + 1)...].contains { !$0.blank } }) {
            return "line \(blank + 1) of the list is blank, with tracks below it"
        }
        let order = playlist.tracks.map(\.id)
        // The lines drawn with no number in `range`: where the tracks whose
        // numbers are not drawn can be.
        let spare = { (range: Range<Int>) in lines[range].filter { !$0.blank && $0.id == nil }.count }
        var previous: (at: Int, line: Int)?
        for (line, entry) in lines.enumerated() {
            guard let id = entry.id else { continue }
            guard let at = order.firstIndex(of: id) else { return "#\(id) is drawn but not in the playlist" }
            if let previous {
                let skipped = at - previous.at - 1
                guard skipped >= 0, skipped <= spare((previous.line + 1)..<line) else {
                    let between = order[(previous.at + 1)...].prefix(max(1, min(skipped, 6)))
                    return "#\(id) is drawn after #\(order[previous.at]), where the playlist has \(Array(between)) next"
                }
            }
            previous = (at, line)
        }
        if let previous, lines.last?.blank == true {
            let after = order.count - previous.at - 1
            guard after <= spare((previous.line + 1)..<lines.count) else {
                return "the list ends at #\(order[previous.at]), with \(after) tracks after it in the playlist"
            }
        }
        return nil
    }

    static let descriptor = SessionDescriptor(
        id: "playlist",
        summary: "a playlist rearranged with the keys and the mouse, tracks deleted, added and renamed",
        exercises:
            "onMove by Control/Option chords, by move mode (pick up, carry, place or cancel) and by a mouse "
            + "drag with live feedback, onDelete, rows added and renamed under a keyed List",
        make: { config, width, height, cold in
            DrivenSession(PlaylistSession(config: config), width: width, height: height, cold: cold)
        })
}
