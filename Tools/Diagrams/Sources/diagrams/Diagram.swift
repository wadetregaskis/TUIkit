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
    /// Drawn dashed — e.g. a runtime reference rather than an ownership edge.
    var dashed: Bool

    init(_ from: String, _ to: String, label: String? = nil,
         loop: Bool = false, dashed: Bool = false) {
        self.from = from
        self.to = to
        self.label = label
        self.loop = loop
        self.dashed = dashed
    }
}

/// A labelled, rounded box drawn around a group of nodes (a Graphviz cluster) —
/// e.g. the children a container owns.
struct Cluster {
    let label: String
    let nodes: [String]
}

struct Diagram {
    let name: String      // output file stem, e.g. "lifecycle-main-loop"
    let title: String     // SVG accessibility label
    var nodes: [Node]
    var edges: [Edge]
    var rankdir: String = "TB"     // "TB" (top→bottom) or "LR" (left→right)
    var clusters: [Cluster] = []
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
        func nodeLine(_ n: Node, indent: String) -> String {
            var attrs = ["label=\"\(label(n))\"", "fillcolor=\"\(n.kind.fill)\""]
            if n.kind == .decision {
                attrs.append("shape=diamond")
                attrs.append("margin=\"0.04,0.0\"")
            }
            return "\(indent)\"\(esc(n.id))\" [\(attrs.joined(separator: ", "))];"
        }

        var out: [String] = []
        out.append("digraph \"\(esc(name))\" {")
        out.append("  rankdir=\(rankdir); bgcolor=\"transparent\"; nodesep=0.35; ranksep=0.5;")
        out.append("  node [shape=box, style=\"rounded,filled\", penwidth=0, "
            + "fontname=\"Helvetica\", fontsize=11, fontcolor=\"white\", margin=\"0.16,0.07\"];")
        out.append("  edge [color=\"#8a8a8a\", penwidth=1.2, fontname=\"Helvetica\", "
            + "fontsize=9, fontcolor=\"#555555\", arrowsize=0.7];")

        // Nodes that belong to a cluster are emitted inside its subgraph.
        let clustered = Set(clusters.flatMap(\.nodes))
        for (i, c) in clusters.enumerated() {
            out.append("  subgraph \"cluster_\(i)\" {")
            out.append("    label=\"\(esc(c.label))\"; labelloc=t; labeljust=l; "
                + "fontname=\"Helvetica\"; fontsize=10; fontcolor=\"#888888\"; "
                + "color=\"#c8c8c8\"; style=\"rounded\"; margin=10;")
            for id in c.nodes {
                if let n = nodes.first(where: { $0.id == id }) {
                    out.append(nodeLine(n, indent: "    "))
                }
            }
            out.append("  }")
        }
        for n in nodes where !clustered.contains(n.id) {
            out.append(nodeLine(n, indent: "  "))
        }
        for e in edges {
            var attrs: [String] = []
            if let l = e.label { attrs.append("label=\"\(esc(l))\"") }
            if e.loop { attrs.append("constraint=false") }
            if e.dashed { attrs.append("style=dashed") }
            let suffix = attrs.isEmpty ? "" : " [\(attrs.joined(separator: ", "))]"
            out.append("  \"\(esc(e.from))\" -> \"\(esc(e.to))\"\(suffix);")
        }
        out.append("}")
        return out.joined(separator: "\n") + "\n"
    }
}
