# Cursor reference

Every cursor slot gauntlet can replace, as observed on macOS 26.5 (Tahoe).
Use the **slot** name for a per-cursor PNG (`gloves/myglove/arrow.png`) or in a
`skip` file. Slots without a name are still covered by `default.png`, and can
be skipped by their `cursor.N` form.

Regenerate the underlying data on your own machine with
`./scripts/dump-cursors.sh` — it writes each stock cursor to a PNG plus a
labelled contact sheet, which is the fastest way to see what a slot actually
looks like.

## Named slots

These have friendly names, so `./gauntlet list` shows them and a glove can
target them individually.

| Slot | Identifier | What it is |
|---|---|---|
| `arrow` | `coregraphics.Arrow` + `ArrowS` | The main pointer |
| `ibeam` | `coregraphics.IBeam` + `IBeamS` | Text insertion |
| `ibeamxor` | `coregraphics.IBeamXOR` | Inverted text, used over dark backgrounds |
| `wait` | `coregraphics.Wait` | Spinner base |
| `ctxarrow` | `coregraphics.ArrowCtx` | Pointer with a contextual menu |
| `alias` | `coregraphics.Alias` | Making an alias / shortcut |
| `copydefault` | `coregraphics.Copy` | Copy |
| `move` | `coregraphics.Move` | Move |
| `link` | `cursor.2` | Link / alias arrow |
| `forbidden` | `cursor.3` | Not-allowed, no-drop |
| `busy` | `cursor.4` | Busy (animated, 15 frames) |
| `copydrag` | `cursor.5` | Dragging a copy (green +) |
| `crosshair` | `cursor.7` | Crosshair |
| `counting-down` | `cursor.15` | Counting down (animated, 6 frames) |
| `counting-updown` | `cursor.16` | Counting up/down (animated, 10 frames) |
| `closed` | `cursor.11` | Closed hand, mid-grab |
| `open` | `cursor.12` | Open hand, grabbable |
| `pointing` | `cursor.13` | Pointing finger, links and buttons |
| `resize-we` | `cursor.19` | Pane splitter, left-right |
| `resize-ns` | `cursor.23` | Pane splitter, up-down |
| `zoomin` | `cursor.42` | Zoom in |

## All core cursors

`com.apple.cursor.N`. A `*` marks an animated cursor — replacing one with a
static image loses the animation entirely.

| N | What it is | Group |
|---|---|---|
| 2 | Link / alias arrow | |
| 3 | Forbidden, no-drop | |
| 4 * | Busy, arrow + beachball | loading |
| 5 | Copy drag, arrow + green plus | |
| 7 | Crosshair | |
| 8 | Crosshair, second variant | |
| 9 | Camera, alternate | |
| 10 | Camera | |
| 11 | Closed hand | |
| 12 | Open hand | |
| 13 | Pointing finger | |
| 14 * | Animated hand (6 frames) | loading |
| 15 * | Counting down (6 frames) | loading |
| 16 * | Counting up/down (10 frames) | loading |
| 17 | Pane splitter, left edge | `@resize` |
| 18 | Pane splitter, right edge | `@resize` |
| 19 | Pane splitter, left-right | `@resize` |
| 20 | Plus / crosshair | |
| 21 | Pane splitter, top edge | `@resize` |
| 22 | Pane splitter, bottom edge | `@resize` |
| 23 | Pane splitter, up-down | `@resize` |
| 24 | Drag with document | |
| 25 | Poof / remove (arrow + ✕) | |
| 26 | Horizontal resize bar | `@resize` |
| 27 | Window edge, east | `@resize` |
| 28 | Window edge, east-west | `@resize` |
| 29 | Window corner, north-east | `@resize` |
| 30 | Window corner, NE-SW | `@resize` |
| 31 | Window edge, north | `@resize` |
| 32 | Window edge, north-south | `@resize` |
| 33 | Window corner, north-west | `@resize` |
| 34 | Window corner, NW-SE | `@resize` |
| 35 | Window corner, south-east | `@resize` |
| 36 | Window edge, south | `@resize` |
| 37 | Window corner, south-west | `@resize` |
| 38 | Window edge, west | `@resize` |
| 39 | Move / resize all directions | `@resize` |
| 40 | Help (`?`) | |
| 41 | Cell, spreadsheet | |
| 42 | Zoom in | |
| 43 | Zoom out | |

Notes:

- **0, 1 and 6 have no image** on Tahoe and can be ignored.
- **44 has no stock image.** Nothing restores it, so anything registered there
  persists until logout. gauntlet's sweep stops at 43 for that reason.
- Names come from observing the artwork, not from Apple. The identifiers are
  what matter; treat the descriptions as a guide.

## Groups

Skip files accept `@resize`, which expands to every `@resize` row above
(17-19, 21-23, 26-39). Direction-indicating cursors carry information a single
static pointer destroys, so most full-coverage gloves want it:

```
# gloves/myglove/skip
@resize
wait
busy
```

## The invisible cursor

`com.apple.coregraphics.Empty` is deliberately **not** in gauntlet's table.
It's how apps hide the pointer — while typing, in fullscreen video, in games.
Registering art against it would make a cursor appear where one is meant to
vanish, so it is always left alone.
