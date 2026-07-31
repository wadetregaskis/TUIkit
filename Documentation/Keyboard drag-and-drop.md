# Keyboard drag-and-drop between views

**Status:** tabled, 2026-07-30. Not rejected on feasibility — rejected for now on
**modality**. Kept as the record of what was considered and what the deciding
argument was, so it does not have to be re-derived if the question returns.

**The gap:** a row can be reordered from the keyboard within one control
(<kbd>Ctrl</kbd>+<kbd>R</kbd>, movement keys, <kbd>Return</kbd>), and a
`.draggable` view can be carried anywhere with the mouse. There is no keyboard
route between views: `.draggable` registers a mouse handle, not a focus stop, so
there is nothing to pick up from.

---

## The idea that prompted this

Allow <kbd>Tab</kbd> during a keyboard move, restricting the focus ring — while
that mode is on — to views that accept the dragged payload.

It works on paper, and two thirds of it already exist: `setTargeted(true)` is
exactly "the drag is over me" and would be driven by focus instead of the cursor,
and a row-level destination already opens a landing slot the movement keys
already know how to move. What it needs that does not exist is a ring: drop
destinations are `DragAndDropSession.Target`s (a mouse-region id plus closures),
not focus stops, so a restricted ring has to be synthesised from the frame's
targets and given focus identities.

**Where it stops: one screen.** A restricted ring can only contain destinations
that registered *this frame*. Carrying a payload to another page is exactly what
the mouse path was built to do, and restricting focus forbids the navigation that
makes it possible. So this is not the keyboard equivalent of the mouse drag; it
is a weaker, different feature that happens to share a chord.

## The alternative that was preferred on capability

A **carry**: navigation stays unrestricted, any accepting view lights up when
focused, <kbd>Return</kbd> drops, and the pick-up chord toggles to put the item
back (no new cancel key, no conflict with <kbd>Escape</kbd>, which navigation
needs — the same reasoning that made no key cancel a mouse drag). This matches
the mouse contract exactly, including across pages, and needs *less* machinery
than the restricted ring.

## Why both are tabled

Both are **long-lived modes**, and that is the objection that decides it:

- The user may not understand what they did to enter it. A chord pressed by
  accident starts a mode with no gesture holding it open — unlike a mouse drag,
  which ends when the button comes up.
- They may forget they are in it. Nothing about ordinary navigation reminds
  them; a status-bar line is the only cue, and status-bar lines are the first
  thing people stop reading.
- The exit is a key that means something else everywhere else. Arriving at some
  unrelated `List` an unbounded time later and pressing <kbd>Return</kbd> to
  activate a row would instead *conclude the drop there*. That is a silent,
  destructive misfire, and it is the whole cost of unbounded modality.

The within-one-control keyboard reorder does not have this problem, and that is
not luck: it is bounded by the control it started in, everything it does is
visible in that control, and every key it claims it claims only while a row is
demonstrably in hand and on screen.

## If it is revisited

Three things would have to be true, and they are worth stating now:

1. **The mode has to be continuously visible where the user is looking** — not
   in the status bar. Something that travels with the payload, the way the mouse
   float does.
2. **The exit has to be cheap and obvious**, and must not overload a key that
   means "activate" somewhere else. The pick-up chord toggling is the best
   candidate precisely because it is not otherwise bound during the carry.
3. **The carry should probably expire** — on page change, on a timeout, or on the
   first interaction that is clearly about something else. An unbounded carry is
   the failure mode above; a bounded one is a gesture.

## Cheaper things that would close most of the gap

- **`.draggable` becomes focusable** (or honours an app-supplied `.focusable()`).
  This is the prerequisite for any keyboard carry, and on its own it lets an app
  build its own transfer UI without the framework taking a position on modality.
- **Cut/paste** (<kbd>Ctrl</kbd>+<kbd>X</kbd> / <kbd>Ctrl</kbd>+<kbd>V</kbd>):
  the same capability with a clipboard metaphor people already hold. Still
  stateful, but the state is one people expect to persist, and pasting is
  explicit rather than a side effect of activating something.
- **A "Move to…" command** in a context menu: the most discoverable, no new focus
  rules, no mode at all — but the destination list is app knowledge, which the
  framework cannot enumerate across pages.
