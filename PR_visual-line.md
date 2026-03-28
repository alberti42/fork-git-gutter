# Fix gutter sign on visual-line continuation rows (TTY)

## Problem

When `git-gutter:visual-line` is `t` in a TTY frame and a buffer line wraps
into multiple visual rows, the gutter sign (`▐` or any other indicator) appears
only on the first visual row.  Every continuation row shows the terminal
background instead.

The symptom is a vertical stripe that is interrupted at every soft-wrap point,
making the gutter look broken on narrow windows or long lines.

## Root cause

Git-gutter renders TTY signs by attaching a `before-string` to a *zero-length*
overlay at the start of each buffer line.  A zero-length overlay fires at
exactly one buffer position; it has no way to inject content on continuation
rows that are produced by the display engine for the same logical line.

The previous approach tried to work around this by enumerating visual row
starts explicitly, using `next-line` (upstream) or `vertical-motion` (our
local copy).  Both are fundamentally unreliable:

- `vertical-motion` lands at the last character of the current screen row, not
  at the start of the next one, so the computed position is off by one.
- `visual-wrap-prefix-mode` (Emacs 30+) inserts continuation indentation via
  `wrap-prefix` text properties, which shifts where visual rows begin in a way
  that `vertical-motion` does not account for.  The result is two overlays on
  the same screen row, and a gap on the next.

There is no Lisp-accessible hook that fires once per screen row during
redisplay the way `display-line-numbers` works internally; any Lisp enumeration
of visual rows is inherently a heuristic.

## Fix

The `wrap-prefix` overlay property is exactly what the display engine uses to
render content at the start of continuation rows — it is the same mechanism
`visual-wrap-prefix-mode` uses for indentation.  By making the overlay span
from `pos` to `(line-end-position)` instead of being zero-length, and setting
`wrap-prefix` to the same margin string as `before-string`, the sign appears on
every visual row of a hunk line via a single overlay.  The display engine
handles continuation row placement correctly, with no Lisp enumeration needed.

When a `wrap-prefix` text property already exists at `pos` (e.g. from
`visual-wrap-prefix-mode`), the gutter sign is prepended to it so that
continuation indentation is preserved.

The spanning overlay and `wrap-prefix` are only applied in TTY + visual-line
mode; GUI frames and non-visual-line mode are unaffected.

## Related fixes included in this branch

**`view-set-overlays`: use `line-end-position` as loop bound**

The loop bound was computed as `(point)` after `forward-line`, which lands at
the beginning of the next line.  When stepping by visual lines, a single
wrapped hunk line would cause the loop to exit after one iteration: the first
visual-line step moves point past `bol` of the end-line but still within the
same logical line, so the bound check fails and subsequent visual rows were
never collected.  Using `line-end-position` ensures the bound covers the full
extent of the hunk line regardless of how point advances.

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
