# Fix gutter sign on visual-line continuation rows (TTY)

## Background: visual lines and soft-wrapping

Emacs distinguishes *buffer lines* (separated by newline characters) from
*visual lines* (screen rows).  When soft-wrapping is active — because text
exceeds the window width, or because a right margin has been set to constrain
line length for readability — a single buffer line is displayed across multiple
visual rows.  The extra rows are called *continuation rows*.

`git-gutter:visual-line` does not enable soft-wrapping; it tells git-gutter
that soft-wrapping is already in use and that gutter indicators should appear
on every visual row of a hunk line, not just the first.

Many modern themes give the left-margin column a distinct background color to
visually separate it from the buffer text — for example the built-in
`modus-operandi` theme (see https://protesilaos.com/emacs/modus-themes-pictures).
This makes a consistent gutter background across all rows, including
continuation rows, visually important.

## Problem

In a TTY frame with `git-gutter:visual-line t`, when a buffer line wraps into
multiple visual rows, the gutter sign (`▐` or any other indicator) appears only
on the first visual row.  On every continuation row the left margin falls back
to the buffer background instead of the gutter background, producing a
color-mismatched stripe wherever soft-wrap occurs.

## Root cause

Git-gutter renders TTY signs by attaching a `before-string` to a *zero-length*
overlay at the start of each buffer line.  A zero-length overlay fires at
exactly one buffer position; it has no mechanism to inject content on
continuation rows produced by the display engine for the same logical line.

The previous approach tried to work around this by enumerating visual row
starts explicitly, using `next-line` (upstream) or `vertical-motion` (early
attempts in this branch).  Both are unreliable in modern Emacs 30+:

- `vertical-motion` lands at the last character of the current screen row, not
  at the start of the next one, so the computed position is off by one.
- `visual-wrap-prefix-mode` (see below) inserts continuation indentation via
  `wrap-prefix` text properties, which shifts where visual rows begin in a way
  that `vertical-motion` does not account for.  The result is two overlays on
  the same screen row and a gap on the next.

There is no Lisp-accessible hook that fires once per screen row during
redisplay the way `display-line-numbers` works internally in `xdisp.c`; any
Lisp enumeration of visual row positions is inherently a heuristic.

## The clean fix: `wrap-prefix`

Investigating how `display-line-numbers` handles continuation rows in
`xdisp.c` was the key insight.  Line numbers appear correctly on every visual
row because the C display loop runs `maybe_produce_line_number` once per screen
row with direct access to row geometry.  That path is not available from Lisp.

However, the same investigation revealed that `wrap-prefix` — the overlay
property that `visual-wrap-prefix-mode` uses to repeat continuation
indentation — is driven by exactly the same display-loop mechanism and *is*
accessible from Lisp.

**Glossary for context:**

- `before-string`: an overlay property whose text is prepended at the overlay
  start position, before the visible buffer text.  It applies only to the first
  visual row of the logical line.  Used by git-gutter to place a sign in the
  left margin on that row.
- `wrap-prefix`: an overlay (or text) property whose text is prepended to every
  *continuation* row of the line the overlay spans, before the visible buffer
  text begins on that row.  It is explicitly skipped on the first visual row,
  making it complementary to `before-string`.  Used by `visual-wrap-prefix-mode`
  to repeat indentation on wrapped lines.
- `visual-wrap-prefix-mode`: built into Emacs 30+ (formerly the external
  `adaptive-wrap` package), it makes soft-wrapped lines look indented to the
  level of their content, by setting `wrap-prefix` on each line.  See
  https://emacsredux.com/blog/2026/03/01/soft-wrapping-done-right-with-visual-wrap-prefix-mode/

**The fix:** when `git-gutter:visual-line` is non-nil, one overlay is created
per buffer line in the hunk, spanning from `pos` to `(line-end-position)`
instead of being zero-length.  `before-string` places the sign on the first
visual row as before; since `wrap-prefix` is skipped on the first visual row,
both properties are needed and cover complementary, non-overlapping sets of
rows.  `wrap-prefix` is set to the same margin string so the display engine
repeats it automatically on every continuation row of that buffer line.  This
replaces the previous approach of one overlay per visual row: instead of
attempting to enumerate visual row positions from Lisp — which is unreliable —
we delegate continuation row rendering entirely to the C display loop, which
is the only place that has precise, authoritative knowledge of screen row
geometry.

When a `wrap-prefix` text property already exists at `pos` (e.g. from
`visual-wrap-prefix-mode`), the gutter sign is prepended to it so that
continuation indentation is preserved on wrapped rows.  Emacs does not provide
a left-margin compositor that would automatically combine contributions from
multiple sources (see https://www.reddit.com/r/emacs/comments/1rpclmq/), so
this manual prepending is currently the only way to ensure coexistence with
other packages that set `wrap-prefix`.

The spanning overlay and `wrap-prefix` are applied only in TTY + visual-line
mode; GUI frames and non-visual-line mode are unaffected.

## Related fixes included in this branch

**`view-set-overlays`: use `line-end-position` as end position**

`view-set-overlays` loops over the buffer lines of a hunk to collect the
positions where signs should be placed.  The position used to stop the loop was
`(point)` captured after stepping to the last line of the hunk with the built-in
Emacs function `forward-line`, which places point at the beginning of the line
following the hunk.  When stepping by visual lines, a single wrapped hunk line
caused the loop to exit after one iteration: the first visual-line step moves
point past `bol` of that following line, but the logical line is still within the
hunk, so the stop condition was met too early and sign positions on subsequent
visual rows were never collected.  Using `line-end-position` ensures the loop
covers the full extent of the last hunk line regardless of how point advances.
With the main fix in place, both `view-set-overlays` and `view-for-unchanged`
now always step using the built-in Emacs function `forward-line`, which advances
by logical (buffer) lines — one newline at a time — rather than by visual rows.

**Priority 10 on non-whitespace signs**

Changed, added, and deleted signs share the same buffer positions as separator
and unchanged overlays.  Without an explicit priority, overlay display order is
undefined, so a separator or unchanged overlay can render on top of a hunk
sign.  Setting `priority 10` on any sign whose text contains a non-whitespace
character ensures hunk signs win when overlays overlap at the same position.

## Commits

1. `a6f52d0` fix: use line-end-position as loop bound in view-set-overlays
2. `ce515a9` fix: ensure non-whitespace signs take priority over separator overlays
3. `382341c` fix: use wrap-prefix overlay for visual-line continuation rows
