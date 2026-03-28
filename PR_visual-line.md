# Fix gutter sign on visual-line continuation rows (TTY)

## Problem

ANDREA: Unclear. You need to remind what visual lines are. These appear when we have soft-wrapping (typically the text exceed the window width, or a right margin was set to constrain the maximum length for better readability). It is not true that `git-gutter:visual-line` causes soft-wrapping, rather that we instruct git-gutter to handle visual lines. When it is set to nil, simply no signs/symbols are shown there, yet the background color need to match the background color of the left margin.

ANDREA: We should mention that many modern themes use left margins with background colors, like built-in theme modus-operandi (see https://protesilaos.com/emacs/modus-themes-pictures).

When `git-gutter:visual-line` is `t` in a TTY frame and a buffer line wraps
into multiple visual rows, the gutter sign (`▐` or any other indicator) appears
only on the first visual row.  Every continuation row shows the terminal
background instead.

ANDREA: Symptoms are wrong background color in the visual lines, where the background color falls back to the fallback case of the buffer background.

The symptom is a vertical stripe that is interrupted at every soft-wrap point,
making the gutter look broken on narrow windows or long lines.

## Root cause

Git-gutter renders TTY signs by attaching a `before-string` to a *zero-length*
overlay at the start of each buffer line.  A zero-length overlay fires at
exactly one buffer position; it has no way to inject content on continuation
rows that are produced by the display engine for the same logical line.

The previous approach tried to work around this by enumerating visual row
starts explicitly, using `next-line` (upstream) or `vertical-motion` (early attempts of mine that produce no success).  Both are fundamentally unreliable (at least in modern Emacs 30+):

- `vertical-motion` lands at the last character of the current screen row, not
  at the start of the next one, so the computed position is off by one.
- `visual-wrap-prefix-mode` (Emacs 30+) inserts continuation indentation via
  `wrap-prefix` text properties, which shifts where visual rows begin in a way
  that `vertical-motion` does not account for.  The result is two overlays on
  the same screen row, and a gap on the next.

There is no Lisp-accessible hook that fires once per screen row during
redisplay the way `display-line-numbers` works internally; any Lisp enumeration
of visual rows is inherently a heuristic.

## The clean fix

ANDREA: We should mention that we inspected how xdisp.c handles the case of line numbers on the left margin and took it as the exemplary pattern to follow. We should state that this investigation was quite revealing. It led to a different and clean design. [yes, it is ok and good to have a bit of story telling; this is not a PR for a software house].

ANDREA: We need to add an explanation/glossary of what wrap-prefix, before-string, and indentation for visual lines.

ANDREA: We should mention that visual-wrap-prefix-mode is the new standard way to perform wrapping in Emacs (https://emacsredux.com/blog/2026/03/01/soft-wrapping-done-right-with-visual-wrap-prefix-mode/; formerlt adaptive-wrap module, now built-in with Emacs 30+).

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
