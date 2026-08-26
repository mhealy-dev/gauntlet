# gauntlet

Tiny system-wide custom cursor tool for macOS — **works on macOS 26 Tahoe**,
where [Mousecape](https://github.com/alexzielenski/Mousecape)'s 2020 release
silently fails. One ~350-line Objective-C file, no GUI, no helper daemon,
compiles with Command Line Tools alone.

Named for its original mission: a World of Warcraft gauntlet pointer.

## Why Tahoe breaks other tools

Cursor replacement works by registering images against WindowServer cursor
identifiers via private CoreGraphics APIs (`CGSRegisterCursorWithImages`).
macOS 26 renders new **"S-variant" identifiers** (`com.apple.coregraphics.ArrowS`,
`IBeamS` — visible in the dyld shared cache strings). Tools that register only
the legacy names get a success return code and no visible change. gauntlet
registers both.

Registrations live in the WindowServer session — logout fully resets
everything, so you can't get stuck.

## Usage

```sh
clang -fobjc-arc -fmodules -o gauntlet gauntlet.m \
  -framework AppKit -framework ApplicationServices

./gauntlet use <name>    # apply capes/<name> and make it current
./gauntlet use           # re-apply current cape (login agent calls this)
./gauntlet capes         # list installed capes (* = current)
./gauntlet apply <dir>   # apply an arbitrary cape directory
./gauntlet reset         # restore stock cursors, clear current cape
./gauntlet list          # supported cursor slot names
```

## Making a cape

A cape is a directory in `capes/`:

```
capes/mycape/
  arrow.png        # required per slot you want: 1x image (32×32 is typical)
  arrow@2x.png     # optional retina rep (double pixels)
  pointing.png
  hotspots.json    # optional: {"arrow": {"x": 4, "y": 2}} in 1x pixel coords
```

Slot names come from `./gauntlet list` (arrow, ibeam, pointing, link,
forbidden, copydrag, …). Only the slots you provide are replaced; everything
else stays stock. Then `./gauntlet use mycape`. Swapping between capes is one
command; each `use` starts from the stock set, so capes never bleed into each
other.

Tip: leave `ibeam` alone unless your art is thin — text selection with a chunky
cursor is misery.

## The WoW cape

Blizzard's retail cursor art is not redistributable, so `capes/wow/` is not in
the repo. Build it locally:

```sh
./scripts/make-wow-cape.sh   # needs python3; fetches NeticSoul/retail-cursor-pack
./gauntlet use wow
```

The script downloads the art pack's MPQ archive, decrypts/extracts it
(`mpqx.py` — mpyq plus the MPQ block cipher), decodes the BLP2 cursor
textures (`blp2png.py` — Pillow mishandles palettized 1-bit alpha), and maps
them onto cursor slots: gauntlet pointer, red "unable" gauntlet on forbidden,
loot bag while dragging. Personal use only.

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

## Credits

- API surface distilled from [Mousecape](https://github.com/alexzielenski/Mousecape)
  by Alex Zielenski (CGSInternal headers reversed by Alex Zielenski and Joe Ranieri).
- WoW cursor art © Blizzard Entertainment, packaged by
  [NeticSoul/retail-cursor-pack](https://github.com/NeticSoul/retail-cursor-pack).
  Not included in this repo; fetched locally for personal use.
- Uses private macOS APIs. They can break in any release; worst case is a
  cursor that ignores you until logout.
