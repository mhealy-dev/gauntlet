# gauntlet

Tiny system-wide custom cursor tool for macOS, including **macOS 26 Tahoe**.
One ~350-line Objective-C file — no GUI, no privileged helper, no daemon.
Compiles with Command Line Tools alone.

Named for its original mission: a World of Warcraft gauntlet pointer.

## How it works

macOS draws cursors from images registered against WindowServer cursor
identifiers. gauntlet registers your own images against those identifiers via
private CoreGraphics APIs (`CGSRegisterCursorWithImages`).

On macOS 26 there's a catch: Tahoe renders **"S-variant" identifiers**
(`com.apple.coregraphics.ArrowS`, `IBeamS` — found in the dyld shared cache
strings) rather than the long-documented legacy names. Register only the legacy
names and you get a success return code with no visible change. gauntlet
registers both.

Registrations live in the WindowServer session, so logging out fully resets
everything — you can't get stuck with a broken cursor.

## Usage

```sh
clang -fobjc-arc -fmodules -o gauntlet gauntlet.m \
  -framework AppKit -framework ApplicationServices

./gauntlet use <name>    # apply gloves/<name> and make it current
./gauntlet use           # re-apply current glove (login agent calls this)
./gauntlet gloves        # list installed gloves (* = current)
./gauntlet apply <dir>   # apply an arbitrary glove directory
./gauntlet reset         # restore stock cursors, clear current glove
./gauntlet list          # supported cursor slot names
```

## Making a glove

A glove (a set of cursors) is a directory in `gloves/`:

```
gloves/myglove/
  arrow.png        # art for one slot: 1x image (32×32 is typical)
  arrow@2x.png     # optional retina rep (double pixels)
  pointing.png
  default.png      # optional: fallback for every slot with no PNG of its own
  skip             # optional: slot names to leave stock, one per line
  hotspots.json    # optional: {"arrow": {"x": 4, "y": 2}} in 1x pixel coords
```

Slot names come from `./gauntlet list` (arrow, ibeam, pointing, link,
forbidden, copydrag, …) — **[CURSORS.md](CURSORS.md) documents every slot**,
what it looks like and what triggers it. Only the slots you provide are
replaced; everything else stays stock. Then `./gauntlet use myglove`. Each
`use` starts by restoring the stock set, so gloves never bleed into each other.

Tip: leave `ibeam` alone unless your art is thin — text selection with a chunky
cursor is misery.

### One pointer for everything

Drop a `default.png` in the glove. Any slot without its own art gets it, and
gauntlet also sweeps the unnamed core cursors (`com.apple.cursor.0`–`44`) — so
resize handles, cell crosshairs and the rest stop changing shape too.

Use `skip` to carve out exceptions — two are worth keeping stock. Loading
cursors are animated, and a spinner is genuine feedback that something is
happening. Resize cursors exist to show *which direction* an edge will move,
which one static pointer destroys; `@resize` covers all 20 of them in a line.

```
# gloves/myglove/skip
@resize           # window edges, corners, pane splitters
wait
busy
counting-down
counting-updown
cursor.7          # bare core cursors work too
```

The bundled `wow-solid` glove ships with exactly that skip file.

**Limit:** this covers cursors macOS draws from its own registry. Apps that
draw their own — browsers honouring CSS `cursor`, image and video editors,
games, anything using a fully custom NSCursor image — bypass it entirely, and
no tool of this kind can reach them.

## The WoW glove

Blizzard's retail cursor art is not redistributable, so `gloves/wow/` is not in
the repo. Build it locally:

```sh
./scripts/make-wow-glove.sh  # needs python3; fetches NeticSoul/retail-cursor-pack
./gauntlet use wow
```

The script downloads the art pack's MPQ archive, decrypts and extracts it
(`mpqx.py` — mpyq plus the MPQ block cipher), decodes the BLP2 cursor textures
(`blp2png.py` — Pillow mishandles palettized 1-bit alpha), and maps them onto
cursor slots: gauntlet pointer, red "unable" gauntlet on forbidden, loot bag
while dragging. Personal use only.

## Persist across reboots

Install a LaunchAgent that runs `gauntlet use` at login
(`~/Library/LaunchAgents/dev.<you>.gauntlet.plist`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>dev.you.gauntlet</string>
    <key>ProgramArguments</key> <array>
        <string>/path/to/gauntlet</string>
        <string>use</string>
    </array>
    <key>RunAtLoad</key>        <true/>
</dict>
</plist>
```

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.you.gauntlet.plist
```

## Notes and credits

- These are private macOS APIs. They can change or break in any OS release;
  the failure mode is a cursor that ignores you until you log out.
- The private cursor API signatures were originally reverse-engineered by
  Joe Ranieri and Alex Zielenski.
