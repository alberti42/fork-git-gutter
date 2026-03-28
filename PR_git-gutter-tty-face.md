# Fix face background not applied in TTY left-margin rendering

## Problem

In TTY frames, git-gutter signs and separators are rendered without their
configured background color.  The foreground color (the sign character itself)
appears correctly, but the background of each gutter cell falls back to the
terminal default rather than the face's background attribute.

This is visible whenever the sign character does not fill the entire terminal
cell.  A full-block character like `█` covers the cell completely and leaves
no background exposed; but more discreet indicators like `▐` or `|` occupy
only part of the cell width, and the exposed area shows the wrong background
color — mismatched against the rest of the gutter column.  Themes that give
the gutter a distinct background color, such as the built-in `modus-operandi`
theme, are therefore broken in TTY mode: the visible background behind the sign
character does not match the intended gutter color.

## Root cause

Git-gutter places signs in the left margin via an overlay `before-string`.
That string carries a `display` text property of the form
`((margin left-margin) SIGN-STRING)`, where `SIGN-STRING` is produced by
`propertize` with a named face symbol as the `face` property.

In GUI frames, named face symbols passed as `face` properties are fully
resolved by the display engine: both foreground and background are applied
correctly.  In TTY frames, however, the margin rendering path applies the
foreground from a named face symbol but does not look up and apply the
background.  This appears to be an Emacs bug: the TTY margin rendering path
should resolve named faces fully, as it does for ordinary buffer text and as
the GUI path does for margins.  As a workaround, the face must be resolved to
an explicit attribute plist on the Lisp side before the text is handed to the
display engine.

## Fix

A new helper function `git-gutter:tty-face` is introduced.  In TTY frames,
when given a named face symbol, it resolves the face's background and foreground
attributes eagerly and returns an inline face plist
`(:foreground FG :background BG)`.  This plist is then passed as the `face`
property of the sign string instead of the face symbol.  Because the background
is encoded directly in the text properties rather than looked up from the face
database at render time, it is applied correctly by the TTY margin rendering
path.

In GUI frames the function is a no-op: the face symbol is returned unchanged,
since GUI frames apply named face backgrounds correctly in margin display
properties.

`git-gutter:tty-face` is applied at three call sites:

- `git-gutter:gutter-seperator`: separator sign
- `git-gutter:propertized-sign`: added, modified, and deleted signs
- `view-for-unchanged`: unchanged sign

## Documentation

If this PR is merged I am happy to update the manual accordingly.

## Commit

`b849826` fix: git-gutter:tty-face resolves the face's own background
attribute → TTY left-margin renders correctly
