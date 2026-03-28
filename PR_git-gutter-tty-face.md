# Fix face background not applied in TTY left-margin rendering

## Problem

In TTY frames, git-gutter signs and separators are rendered without their
configured background color.  The foreground color (the sign character itself)
appears correctly, but the background of each gutter cell falls back to the
terminal default rather than the face's background attribute.

This matters in particular with themes that give the gutter column a distinct
background — for example the built-in `modus-operandi` theme — where the gutter
should form a uniform colored stripe.  In TTY mode the stripe is broken: sign
rows have the terminal background, defeating the visual separation the theme
intends.

## Root cause

Git-gutter places signs in the left margin via a `display` text property of the
form `((margin left-margin) SIGN-STRING)`, where `SIGN-STRING` is produced by
`propertize` with a named face symbol as the `face` property.

In TTY frames, named face symbols passed as `face` properties to text rendered
through a `display` margin property are not fully resolved by the display
engine: the foreground attribute is applied but the background attribute is
silently dropped.  The same face symbol works correctly on ordinary buffer text;
the limitation is specific to text rendered inside left-margin display
properties in TTY mode.

## Fix

A new helper function `git-gutter:tty-face` is introduced.  In TTY frames, when
given a named face symbol, it resolves the face's background and foreground
attributes eagerly and returns an inline face plist
`(:foreground FG :background BG)`.  This plist is then passed as the `face`
property of the sign string instead of the face symbol.  Because the background
is encoded directly in the text properties rather than looked up from the face
database at render time, it survives the TTY margin rendering path correctly.

In GUI frames the function is a no-op: the face symbol is returned unchanged,
since GUI frames resolve named faces correctly.

`git-gutter:tty-face` is applied at three call sites:

- `git-gutter:gutter-seperator`: separator sign
- `git-gutter:propertized-sign`: added, modified, and deleted signs
- `view-for-unchanged`: unchanged sign

## Commit

`b849826` fix: git-gutter:tty-face resolves the face's own background
attribute → TTY left-margin renders correctly
