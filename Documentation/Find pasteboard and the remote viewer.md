# Synchronising a search field with the system Find pasteboard

**Status: DECLINED, 2026-08-24.** Not built, and not to be built in this shape.
The research below stands as the record of why — the short version is that the
half with consequences (writing global system state on whichever machine the app
happens to be running on) is gated by a test that cannot be made exact, and the
terminal-native mechanism that would sidestep the question does not reach a find
pasteboard at all.

Asked once before and, as far as the repository records, never answered: there
was no code, no doc, no commit and no entry in `Parity-decisions-pending.md`
touching the find pasteboard. `SystemClipboard` reaches the *general* pasteboard
and only that, and still does.

This note is what the question is actually made of, and it turns out to be two
questions with different answers.

## What the Find pasteboard is, and the contract around it

macOS has several named pasteboards, not one: `.general`, `.find`, `.font`,
`.ruler`, `.drag`. The **find pasteboard** (`NSPasteboard.Name.find`, historically
`NSFindPboard`) holds the *current search term for the whole system*, and the
convention around it is what makes search feel joined-up between apps:

| Gesture | What it does to the find pasteboard |
|---|---|
| <kbd>⌘E</kbd> "Use Selection for Find" | **writes** the selection to it |
| <kbd>⌘G</kbd> / <kbd>⇧⌘G</kbd> "Find Next / Previous" | **reads** it and searches for that |
| Opening a find bar / panel | **reads** it, and pre-fills the field |
| Running a search from the field | **writes** the term back |

So the user-visible promise is: *search for something in one app, switch to
another, press ⌘G, and it searches for the same thing.* The find field being
pre-filled when you open it is the same promise seen from the other end.

Three details matter to anyone implementing it:

- **The essential type is plain string.** AppKit additionally writes
  `NSPasteboardTypeTextFinderOptions` — a small plist carrying
  `NSTextFinderCaseInsensitiveKey` and `NSTextFinderMatchingTypeKey` — so
  case-sensitivity and "contains / starts with / whole word" travel with the
  term. An app that writes only the string is a well-behaved participant; the
  options are an enhancement, not the contract.
- **There is no change notification.** You poll `changeCount` and re-read when
  it moves. Apps do this on activation and when the find UI appears, not
  continuously.
- **`NSTextFinder` does the whole dance for you** in a text view, which is why
  most Mac apps get this for free and why the convention is so consistent.

The write side is the one with consequences: it is **global mutable system
state**, and every other app's ⌘G is downstream of it. Reading is harmless.

## Can TUIkit reach it at all? Yes — measured

TUIkit deliberately does not link AppKit; `SystemClipboard` shells out to
`pbcopy`/`pbpaste` with hardened, deadline-bounded child I/O. Those helpers
take the pasteboard as an argument:

```
pbcopy  [-pboard {general | ruler | find | font}]
pbpaste [-pboard {general | ruler | find | font}] [-Prefer {txt | rtf | ps}]
```

Measured on macOS 15.7, saving and restoring the real find pasteboard around the
test:

```
current find pasteboard: []
printf 'tuikit-probe' | pbcopy -pboard find
pbpaste -pboard find  →  [tuikit-probe]
pbpaste -pboard find  →  [tuikit-probe]      ← non-destructive, despite the man page
restored              →  []
general pasteboard    →  unchanged
```

Two things worth having in writing. `pbpaste`'s man page says it "removes the
data from the pasteboard"; it does not — reading twice returns the same value.
And the two pasteboards really are separate: writing `find` left `general`
alone.

So the mechanism is a two-line addition to `SystemClipboard`, reusing the
existing hardened `run(tool:arguments:writing:readsOutput:)` path. `changeCount`
is not exposed by the helpers, so change detection would have to be "does the
string differ from the one we last read or wrote" — which misses only the case
where somebody else wrote the *same* term, and that case has nothing to do.

Linux has no equivalent named selection. `xclip`/`xsel` offer `primary`,
`secondary` and `clipboard`; there is no find selection to talk to, so this is
macOS-only by construction rather than by choice.

## The second question: whose pasteboard is it?

This is the real one, and the concern behind it is right. Over SSH the app runs
on the *server*, so `pbcopy` reaches the server's pasteboard — the one belonging
to whoever is logged in at that machine's screen. Writing a search term there is
mucking with a stranger's global state from across the network, for no benefit
to anyone: the person watching the terminal never sees it.

### What can be detected, and how well

- **`SSH_CONNECTION` / `SSH_CLIENT` / `SSH_TTY`.** Set by `sshd` for an
  interactive session. Their presence is a *reliable positive*: if they are
  there, this session came in over SSH.
- **`SSH_AUTH_SOCK` is not one of them.** Measured on a local macOS session:
  `SSH_AUTH_SOCK=/private/tmp/com.apple.launchd.…/Listeners` is present with no
  SSH anywhere in sight — launchd provides it for the Keychain agent. A test
  that matches on the `SSH_` prefix therefore reports every local Mac session as
  remote. Name the three variables.
- **`launchctl managername`** answers `Aqua` for a GUI login session. Measured
  local. It is *documented* to answer `Background` or `System` elsewhere,
  including an SSH login — **not measured here**, and it should be, with a probe,
  before anything depends on it.

### Where all of that fails

The environment is captured when a process is created, so anything that outlives
the login defeats it:

- A **tmux or screen session created locally and re-attached over SSH** keeps the
  environment of the shell that created it. Every pane still says "local"; the
  person looking at it is not. `tmux show-environment` and the client's own
  `#{client_tty}` know better, but only if the app asks tmux, which is a second
  mechanism with its own detection problem.
- **mosh** re-execs its server, and does not leave `SSH_CONNECTION` behind.
- `sudo -i`, `su -`, a re-exec through a login shell, a systemd unit, a cron
  job: each strips or replaces the environment in its own way.

None of these is exotic. The honest summary is that the environment gives a
**dependable "definitely remote"** and an **unreliable "probably local"**, which
is the wrong way round for a feature whose dangerous half is the write.

### OSC 52 is the terminal-native answer, and it does not have a find selection

The correct instinct for a terminal app is to stop asking where it is running
and instead talk to the *terminal*, which is by definition where the user is.
That is OSC 52: `ESC ] 52 ; c ; <base64> BEL` writes the client's clipboard, and
`ESC ] 52 ; c ; ? BEL` asks for it. It travels down the same PTY as everything
else, so it crosses SSH, tmux and mosh without any of them being consulted.

It cannot help here. OSC 52's selection names are `c` (clipboard), `p`
(primary), `s`, and the cut buffers `0`–`7`. **There is no find selection**, and
there is no reasonable way to invent one — the find pasteboard is a macOS
concept and OSC 52 is a terminal one. Whether reads are even permitted varies by
terminal and is usually off by default; that would need measuring with the
probes in `Tools/TerminalProbes/` if it ever mattered.

So: the local case is reachable by exactly one mechanism, and the remote case is
reachable by none.

## What was recommended, and what was decided

The recommendation was to ship it defaulted off and opted into per app. That was
**declined**: see the status at the top. The list is kept because it is the
design anyone reopening this would otherwise have to derive again, and because
points 3 and 4 are the parts that would still be right in any future shape.

1. **Default off.** The write is global state, the "is the viewer local" test
   has a known false-positive, and nobody loses anything they had. An opt-in
   modifier — `.searchUsesFindPasteboard(_:)` or similar, macOS-only — makes it
   the app author's decision, which is the level where the deployment is
   actually known.
2. **Split the two directions.** Reading is safe and useful even under a wrong
   guess: at worst a search field is pre-filled with something unexpected, which
   the user overtypes. Writing is the half that needs the gate. They could
   reasonably be two settings.
3. **Write on submit, not on keystroke.** The convention is that a *search*
   publishes the term; a half-typed query is not a search. `.onSubmit(of:
   .search)` is exactly the hook, and `SearchableModifier` already scopes the
   query field to that role.
4. **Read when the field takes focus.** `onEditingChanged` in
   `SearchableModifier` is the transition, and it is where a Mac app would read
   it (find bar appears → read). Not on every render.
5. **Gate on `SSH_CONNECTION`/`SSH_CLIENT`/`SSH_TTY` plus a measured
   `launchctl managername`** — and *document the tmux hole* rather than pretend
   it is closed. A user who re-attaches a local session from elsewhere gets a
   stale search term written to a Mac they are not sitting at; that is survivable
   and worth saying out loud.
6. **Do not attempt the TextFinder options plist.** Case-sensitivity and match
   mode are the app's business here, `pbcopy` writes plain text, and a partial
   plist would be worse than none.

The value is real but small: it is one of those touches that makes a terminal
app feel like it belongs on the machine. The cost is a platform-specific side
effect on global state, gated by a test that cannot be made exact — and a
terminal app is the kind of program most likely to be run somewhere other than
where it is being watched, which is exactly the case the gate gets wrong. That
is the trade, and it was taken against.
