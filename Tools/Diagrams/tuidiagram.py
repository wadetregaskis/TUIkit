"""Zero-dependency flowchart → SVG generator for TUIkit's DocC diagrams.

Why this exists
---------------
The DocC catalog illustrates the lifecycle / render / dispatch internals with
diagrams. Those used to be hand-drawn PNGs with no committed source, so when the
architecture changed (e.g. the run loop went demand-driven) the diagrams went
stale and there was no way to regenerate them. This module is that missing
source: diagrams are described *as data* and rendered to SVG with the Python 3
standard library only — no Graphviz, Mermaid, Node, or network, so they can be
regenerated autonomously on any machine that has `python3`.

Design
------
* **Auto-layout, not pixel-pushing.** You describe a vertical *flow* of nodes
  (plus optional side branches and a loop-back); the engine computes every
  coordinate from each node's measured height. Boxes can't overlap and arrows
  are orthogonal by construction, so a diagram is correct without anyone
  eyeballing it.
* **Self-contained, themed SVG.** One render per theme ("light"/"dark"); node
  fills are brand colours that read on either background, so only the connector
  and label colours switch. Output is plain SVG text — diffable and scalable.

See ``build.py`` for the actual diagram definitions and ``README.md`` for the
workflow.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from xml.sax.saxutils import escape

# ---- palette -------------------------------------------------------------

# Node fills (TUIkit's green-terminal aesthetic). Chosen to read as white-on-fill
# on both light and dark page backgrounds, so they are theme-independent.
FILL = {
    "normal": "#1f9b76",    # teal-green: an ordinary step
    "accent": "#13795b",    # darker teal: an emphasised step
    "decision": "#1f9b76",  # teal-green diamond: a branch
    "terminal": "#9c3d3d",  # muted red: enter/exit (setup, cleanup)
}
TEXT_ON_FILL = "#ffffff"
SUBTEXT_ON_FILL = "#dff1ea"  # slightly dimmed white for detail lines

THEME = {
    "light": {"edge": "#8a8a8a", "label": "#4a4a4a", "label_bg": "#ffffff"},
    "dark": {"edge": "#9aa0a6", "label": "#cdd1d5", "label_bg": "#1c1c1e"},
}

FONT = ("-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, "
        "Arial, sans-serif")
TITLE_SIZE = 13.0
BODY_SIZE = 10.5
TITLE_LH = 17.0   # line height for the title
BODY_LH = 14.0    # line height for detail lines
PAD_Y = 9.0       # vertical padding inside a box

# ---- geometry knobs ------------------------------------------------------

COL_MIN_W = 168.0     # min width of a main-flow box
COL_MAX_W = 330.0     # cap before a very long line is allowed to overflow
SIDE_MIN_W = 132.0    # min width of a side-branch box
CHAR_TITLE = 7.2      # ~px per character for the bold title (at TITLE_SIZE)
CHAR_BODY = 5.9       # ~px per character for detail lines (at BODY_SIZE)
TEXT_PAD_X = 30.0     # horizontal padding inside a box (both sides total)
LEFT_GUTTER = 64.0    # space reserved on the left for the loop-back arrow
RIGHT_GUTTER = 24.0
TOP_MARGIN = 18.0
BOTTOM_MARGIN = 18.0
ROW_GAP = 30.0        # vertical space between stacked boxes (room for arrows)
SIDE_GAP = 40.0       # horizontal space to a side-branch box


@dataclass
class Node:
    id: str
    title: str
    lines: list[str]
    kind: str          # normal | accent | decision | terminal
    x: float = 0.0
    y: float = 0.0
    w: float = 0.0
    h: float = 0.0

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2

    def anchor(self, side: str) -> tuple[float, float]:
        return {
            "top": (self.cx, self.y),
            "bottom": (self.cx, self.y + self.h),
            "left": (self.x, self.cy),
            "right": (self.x + self.w, self.cy),
        }[side]


@dataclass
class Edge:
    a: str
    b: str
    label: str | None = None
    route: str = "down"  # down | right | loopback


@dataclass
class Flow:
    """A top-to-bottom flow of nodes with optional side branches + a loop-back."""

    title: str = ""
    _column: list[str] = field(default_factory=list)
    _nodes: dict[str, Node] = field(default_factory=dict)
    _edges: list[Edge] = field(default_factory=list)
    _side: dict[str, str] = field(default_factory=dict)  # node id -> anchor node id

    def step(self, id, title, lines=None, kind="normal"):
        """Append a node to the main (centre) column."""
        self._nodes[id] = Node(id, title, lines or [], kind)
        self._column.append(id)
        return self

    def branch(self, id, of, title, lines=None, kind="terminal"):
        """Place a node to the right of main-column node ``of`` (same row)."""
        self._nodes[id] = Node(id, title, lines or [], kind)
        self._side[id] = of
        return self

    def edge(self, a, b, label=None, route="down"):
        self._edges.append(Edge(a, b, label, route))
        return self

    # -- layout ----------------------------------------------------------

    @staticmethod
    def _measure_h(n: Node) -> float:
        return PAD_Y * 2 + TITLE_LH + BODY_LH * len(n.lines)

    @staticmethod
    def _req_w(n: Node) -> float:
        """Estimated width needed to hold this node's widest line of text."""
        title_w = len(n.title) * CHAR_TITLE + TEXT_PAD_X
        line_w = max((len(s) for s in n.lines), default=0) * CHAR_BODY + TEXT_PAD_X
        return max(title_w, line_w)

    def _layout(self):
        # one uniform width for the centre column, sized to its widest content
        needed = max((self._req_w(self._nodes[i]) for i in self._column),
                     default=COL_MIN_W)
        col_w = min(COL_MAX_W, max(COL_MIN_W, needed))
        col_cx = LEFT_GUTTER + col_w / 2
        y = TOP_MARGIN
        for nid in self._column:
            n = self._nodes[nid]
            n.h = self._measure_h(n)
            if n.kind == "decision":
                # a diamond reads best sized just to its own text, never too flat
                n.w = max(COL_MIN_W * 0.95, self._req_w(n))
                n.h = max(n.h + 16.0, 62.0)
            else:
                n.w = col_w
            n.x = col_cx - n.w / 2
            n.y = y
            y += n.h + ROW_GAP
        total_h = y - ROW_GAP + BOTTOM_MARGIN
        # side branches: aligned to their anchor row, placed to the right
        right_extent = col_cx + col_w / 2
        for sid, anchor in self._side.items():
            s = self._nodes[sid]
            a = self._nodes[anchor]
            s.w = min(COL_MAX_W, max(SIDE_MIN_W, self._req_w(s)))
            s.h = self._measure_h(s)
            s.x = a.x + a.w + SIDE_GAP
            s.y = a.cy - s.h / 2
            right_extent = max(right_extent, s.x + s.w)
        total_w = right_extent + RIGHT_GUTTER
        return total_w, total_h

    # -- rendering -------------------------------------------------------

    def render(self, theme: str = "light") -> str:
        t = THEME[theme]
        w, h = self._layout()
        out: list[str] = []
        out.append(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.0f} {h:.0f}" '
            f'width="{w:.0f}" height="{h:.0f}" font-family="{FONT}" '
            f'role="img" aria-label="{escape(self.title)}">'
        )
        out.append(
            f'<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" '
            f'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
            f'<path d="M0,0 L10,5 L0,10 z" fill="{t["edge"]}"/></marker></defs>'
        )
        # edges first (so boxes paint on top of any arrow that grazes them)
        for e in self._edges:
            out.append(self._render_edge(e, t))
        for nid in self._column:
            out.append(self._render_node(self._nodes[nid]))
        for sid in self._side:
            out.append(self._render_node(self._nodes[sid]))
        out.append("</svg>")
        return "\n".join(out)

    def _render_node(self, n: Node) -> str:
        fill = FILL[n.kind]
        s: list[str] = []
        if n.kind == "decision":
            cx, cy = n.cx, n.cy
            hw, hh = n.w / 2, n.h / 2
            pts = f"{cx:.1f},{n.y:.1f} {n.x + n.w:.1f},{cy:.1f} {cx:.1f},{n.y + n.h:.1f} {n.x:.1f},{cy:.1f}"
            s.append(f'<polygon points="{pts}" fill="{fill}"/>')
        else:
            s.append(
                f'<rect x="{n.x:.1f}" y="{n.y:.1f}" width="{n.w:.1f}" height="{n.h:.1f}" '
                f'rx="9" ry="9" fill="{fill}"/>'
            )
        # text: title then detail lines, vertically centred as a block
        block_h = TITLE_LH + BODY_LH * len(n.lines)
        ty = n.cy - block_h / 2 + TITLE_LH * 0.72
        s.append(
            f'<text x="{n.cx:.1f}" y="{ty:.1f}" text-anchor="middle" '
            f'font-size="{TITLE_SIZE}" font-weight="600" fill="{TEXT_ON_FILL}">'
            f'{escape(n.title)}</text>'
        )
        ly = ty + (TITLE_LH - 1)
        for line in n.lines:
            s.append(
                f'<text x="{n.cx:.1f}" y="{ly:.1f}" text-anchor="middle" '
                f'font-size="{BODY_SIZE}" fill="{SUBTEXT_ON_FILL}">{escape(line)}</text>'
            )
            ly += BODY_LH
        return "".join(s)

    def _render_edge(self, e: Edge, t: dict) -> str:
        a, b = self._nodes[e.a], self._nodes[e.b]
        if e.route == "down":
            x1, y1 = a.anchor("bottom")
            x2, y2 = b.anchor("top")
            pts = [(x1, y1), (x2, y2)]
            lx, ly = (x1 + x2) / 2, (y1 + y2) / 2
        elif e.route == "right":
            x1, y1 = a.anchor("right")
            x2, y2 = b.anchor("left")
            pts = [(x1, y1), (x2, y2)]
            lx, ly = (x1 + x2) / 2, y1 - 7
        elif e.route == "loopback":
            # out the left side of a, down/up the left gutter, into the left of b
            x1, y1 = a.anchor("left")
            x2, y2 = b.anchor("left")
            gx = LEFT_GUTTER / 2 - 6
            pts = [(x1, y1), (gx, y1), (gx, y2), (x2, y2)]
            lx, ly = gx, (y1 + y2) / 2
        else:
            raise ValueError(f"unknown route {e.route!r}")
        d = "M " + " L ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        seg = (
            f'<path d="{d}" fill="none" stroke="{t["edge"]}" stroke-width="1.6" '
            f'marker-end="url(#arrow)"/>'
        )
        if not e.label:
            return seg
        # a small filled chip behind the label so it stays legible over the line
        cw = 7 + len(e.label) * 6.2
        chip = (
            f'<rect x="{lx - cw / 2:.1f}" y="{ly - 8:.1f}" width="{cw:.1f}" height="15" '
            f'rx="4" fill="{t["label_bg"]}" opacity="0.92"/>'
        )
        lbl = (
            f'<text x="{lx:.1f}" y="{ly + 3.5:.1f}" text-anchor="middle" '
            f'font-size="10" fill="{t["label"]}">{escape(e.label)}</text>'
        )
        return seg + chip + lbl


def write_pair(flow: Flow, out_dir: str, name: str) -> list[str]:
    """Render ``flow`` to ``<name>.svg`` (light) and ``<name>~dark.svg``.

    DocC swaps to the ``~dark`` variant automatically in dark mode.
    """
    import os

    written = []
    for theme, suffix in (("light", ""), ("dark", "~dark")):
        path = os.path.join(out_dir, f"{name}{suffix}.svg")
        with open(path, "w") as fh:
            fh.write(flow.render(theme) + "\n")
        written.append(path)
    return written
