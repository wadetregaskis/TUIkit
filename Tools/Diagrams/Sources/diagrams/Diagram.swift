import Foundation

/// The visual role of a node, which picks its fill colour and shape.
/// Fills are TUIkit's green-terminal palette; text is always white, so the
/// fills read on both light and dark page backgrounds.
enum NodeKind {
    case normal     // an ordinary step (teal)
    case accent     // an emphasised step (darker teal)
    case terminal   // enter / exit (red)
    case decision   // a branch (teal diamond)

    var fill: String {
        switch self {
        case .normal: return "#1f9b76"
        case .accent: return "#13795b"
        case .terminal: return "#9c3d3d"
        case .decision: return "#1f9b76"
        }
    }
}

struct Node {
    let id: String
    let title: String
    var detail: [String] = []
    var kind: NodeKind = .normal
}

struct Edge {
    let from: String
    let to: String
    var label: String?
    /// A back-edge (e.g. a loop): drawn without influencing rank order, so it
    /// doesn't distort the layout.
    var loop: Bool

    init(_ from: String, _ to: String, label: String? = nil, loop: Bool = false) {
        self.from = from
        self.to = to
        self.label = label
        self.loop = loop
    }
}

struct Diagram {
    let name: String      // output file stem, e.g. "lifecycle-main-loop"
    let title: String     // SVG accessibility label
    var nodes: [Node]
    var edges: [Edge]
}

extension Diagram {
    /// Render this diagram as a Graphviz DOT document.
    func dot() -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        func label(_ n: Node) -> String {
            ([n.title] + n.detail).map(esc).joined(separator: "\\n")
        }

        var out: [String] = []
        out.append("digraph \"\(esc(name))\" {")
        out.append("  rankdir=TB; bgcolor=\"transparent\"; nodesep=0.35; ranksep=0.45;")
        out.append("  node [shape=box, style=\"rounded,filled\", penwidth=0, "
            + "fontname=\"Helvetica\", fontsize=11, fontcolor=\"white\", margin=\"0.16,0.07\"];")
        out.append("  edge [color=\"#8a8a8a\", fontname=\"Helvetica\", fontsize=9, "
            + "fontcolor=\"#555555\", arrowsize=0.7];")
        for n in nodes {
            var attrs = ["label=\"\(label(n))\"", "fillcolor=\"\(n.kind.fill)\""]
            if n.kind == .decision {
                attrs.append("shape=diamond")
                attrs.append("margin=\"0.04,0.0\"")
            }
            out.append("  \"\(esc(n.id))\" [\(attrs.joined(separator: ", "))];")
        }
        for e in edges {
            var attrs: [String] = []
            if let l = e.label { attrs.append("label=\"\(esc(l))\"") }
            if e.loop { attrs.append("constraint=false") }
            let suffix = attrs.isEmpty ? "" : " [\(attrs.joined(separator: ", "))]"
            out.append("  \"\(esc(e.from))\" -> \"\(esc(e.to))\"\(suffix);")
        }
        out.append("}")
        return out.joined(separator: "\n") + "\n"
    }
}
