# Bespoke

Light, stateless action bars for **World of Warcraft: Forever** (interface `16001`).
No libraries, no paging, no secure snippets.

Bars: action bars 1–8 (Blizzard's Action Bars 1–8: same spell slots, same keybindings),
pet bar, stance bar, bag bar and micro menu. Per bar: show/hide, columns or rows,
grow up/down, scale (40–200%), padding (−2 to 20), fade until mouseover.
Named profiles shared across characters, with a choice of profile for new characters.

## Install

1. Install from CurseForge (WoW: Forever), or download `Bespoke-<version>.zip` from the
   [Releases](../../releases) page.
2. Unzip it into your Forever client's `Interface/AddOns` folder, so you have
   `Interface/AddOns/Bespoke/Bespoke.toc`. On the beta that's under `_classic_beta_`.
3. Remove other action bar addons (they'd fight over Blizzard's bars), then log in.

## Use

- `/bespoke` opens the options window (also under Options → AddOns → Bespoke).
- `/bespoke unlock` shows every bar with a label so you can drag it; `/bespoke lock` when done.
  Pet and stance bars preview all 10 slots while unlocked, on any character.
- Keybinds: bind keys to Blizzard's "Action Bar 1–8" entries in the normal Keybindings
  menu (or Quick Keybind mode); Bespoke's bars use them. Pet and stance keybinds work as usual.
- Profiles are shared by all characters on the account. Each character picks its own,
  and you choose which profile new characters start on.
- `/bespoke help` lists all slash commands; `/bespoke which` names whatever is under the mouse.

## Terms

This repository is published to be read, not contributed to: pull requests and issues
are turned off. No license is granted, so all rights are reserved. You can view the
code and use the addon; you may not redistribute it or publish modified versions.

## Layout

```
Bespoke.toc
Bespoke.lua         bars, layout, profiles, slash commands
Options.lua         options window
tests/
  test_harness.lua  runs the real addon files against a stubbed WoW client
.pkgmeta            packager settings (what's left out of the zip)
.github/workflows/  CI (test.yml) and releases (release.yml)
```

The addon files sit at the repository root because the packager expects the TOC there.

## Develop

Link the repository into the Forever client as `Bespoke`, so edits show up after `/reload`
(macOS path shown; adjust to your install). The client only loads what the TOC lists,
so the tests and docs in the folder are ignored:

```sh
ln -s "$PWD" "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/Bespoke"
```

If the client doesn't pick up the symlink, copy the folder instead.
Remove any other `Bespoke` folder in `AddOns` first.

## Test

WoW runs Lua 5.1, so the tests use it too:

```sh
brew install lua@5.1        # or: apt-get install lua5.1
luac5.1 -p *.lua
lua5.1 tests/test_harness.lua Bespoke.lua
```

The harness loads the real `Bespoke.lua` and `Options.lua` into a stubbed client
(frames, secure templates, Blizzard's pet/stance/bag/micro bars, Edit Mode behaviour)
and checks every behaviour, including bugs found in game. Every scenario also fails on:

- any script error, including inside Blizzard code the addon triggers
- any protected action attempted in combat
- anything visible on a Bespoke bar that's still sitting at a Blizzard position

When fixing an in-game bug, first add a test that reproduces it and fails on the
current code, then fix. CI runs the harness on every push.

## Release

1. Bump `## Version:` in `Bespoke.toc` and add a `CHANGELOG.md` entry.
2. Commit, then tag and push:

```sh
git tag v1.4.4
git push origin main --tags
```

The release workflow tests, checks the tag matches the TOC version, then packages once
with [BigWigsMods/packager](https://github.com/BigWigsMods/packager) and publishes the
same zip to CurseForge (as WoW: Forever) and as a GitHub release. CurseForge shows
`CHANGELOG.md` as the changelog.

One-time setup, already done if CurseForge releases are appearing:

- `## X-Curse-Project-ID: <id>` in `Bespoke.toc` (the number on the CurseForge project page).
- A CurseForge API token (CurseForge account settings → API tokens) saved as the
  repository secret `CF_API_KEY` (GitHub → Settings → Secrets and variables → Actions).

The workflow stops with a clear message if either is missing, rather than skipping the upload.

## Forever notes (verified against client build 69977)

- The client reports `WOW_PROJECT_MAINLINE` but interface `16001` (Blizzard's internal
  name for Forever is `camelot`). Its UI is the modern 12.x one, with Forever-specific
  overrides in `Camelot` folders (micro menu, bag bar).
- **Secure snippets don't compile on the beta:** `Blizzard_EnvironmentCleanup.toc`
  omits `camelot` from its dependency on `Blizzard_RestrictedAddOnEnvironment`, so
  `loadstring_untainted` is removed (`EnvironmentCleanup.lua:279`) before the
  restricted environment captures it. Bespoke avoids snippets entirely:
  action buttons use a fixed `actionpage` resolved by Blizzard's own secure code.
- **Visibility drivers are safe** (`RegisterStateDriver(frame, "visibility", ...)`):
  Blizzard's state manager shows/hides the frame directly, with no snippet. Used for
  the pet bar.
- `GetMouseFocus()` doesn't exist; use `GetMouseFoci()`.
- Blizzard's micro menu errors (`GetEdgeButton`) if only unpositioned, hidden buttons
  remain in it: take all of its `layoutIndex` buttons, hidden ones first.
- Edit Mode force-shows all 10 stance buttons; with 0 forms nothing hides them again.
  Park stance buttons beyond the form count on a hidden frame.

Useful sources: [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source)
(branch `forever`) for Blizzard's UI code, and the community-captured API baseline in
[Thunderz96/forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit).
