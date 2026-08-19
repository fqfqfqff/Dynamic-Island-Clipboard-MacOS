# Aura

Turns the MacBook camera notch into a live island, and gives macOS a proper
clipboard history. Written in Swift, no dependencies.

> Русская версия — [README.ru.md](README.ru.md)

## What it does

**The island.** Sits in the notch, invisible until something happens. Shows
what is playing, headphone battery, charging, volume, screenshots, the next
calendar event, focus mode changes and notifications from other apps. Expands
on hover into a player with artwork, a seek bar and controls.

**Any audio source.** Not just Spotify. The island finds whoever is playing
sound through the CoreAudio process list, so a video in the browser or a voice
message in a messenger shows up too. Music and Spotify additionally give track
name, artwork, position and playback control.

**Real spectrum.** The equaliser bars are driven by an actual FFT over a
CoreAudio process tap, not by a looping animation.

**Clipboard.** A separate window on ⌥⌘V with search, previews, pinning and a
full log of everything ever copied. Passwords from password managers never
enter the history — the `org.nspasteboard.*` markers are respected.

**A shelf.** Drop files onto the notch, drag them out later into a mail
message or a chat.

**On the lock screen.** macOS does not let apps draw there — the whole user
session is hidden. The one thing it does run is a screen saver, so Aura ships
one: it shows the player, artwork and synced lyrics over the locked screen.

**An open API.** Any script can put itself into the notch:

```bash
Scripts/aura push --id build --title "Building" --progress 0.4
```

## Install

One command. It creates a signing certificate so permissions survive rebuilds,
builds the app, installs it into `~/Applications`, installs the screen saver
and enables launch at login.

```bash
git clone https://github.com/<you>/aura && cd aura && ./Scripts/setup.sh
```

There is no prebuilt binary on purpose: without a $99/year Developer ID macOS
calls downloaded apps damaged. Building from source avoids that entirely and
takes under a minute.

macOS 14.4 or newer, Apple silicon or Intel.

### Permissions

The system asks for these itself, on first use. A first-run screen explains
what each one buys you.

| Permission | Used for |
|---|---|
| Accessibility | pasting from the clipboard, mirroring notifications |
| Automation | track info from Music and Spotify |
| Audio capture | equaliser bars driven by real frequencies |
| Bluetooth | headphone battery |
| Calendars | the next meeting |
| Full disk | focus mode state (optional) |

Nothing is recorded, uploaded or sent anywhere. The only network request is an
optional lyrics lookup at lrclib.net, which receives a track name, an artist
and a duration — and only if lyrics are switched on.

## Development

```bash
./Scripts/run.sh       # build and run from ./build
./Scripts/install.sh   # update the installed copy
swift test             # 75 tests
Scripts/aura status    # what works right now and why something does not
```

## Layout

```
Sources/Aura/       entry point only, so the rest stays testable
Sources/AuraCore/
  App/              delegate, menu bar, external commands
  Notch/            notch geometry, panel window, shape, states
  Activities/       activity queue with priorities and its providers
  Clipboard/        pasteboard polling, history window, archive
  Showcase/         full-screen player and the snapshot the saver reads
  Shelf/            files dropped onto the notch
  Onboarding/       first-run permission walkthrough
  Settings/         settings store and window
  System/           permissions, hotkeys, audio spectrum, watchers
Sources/AuraSaver/  the screen saver plug-in
```

Design notes and the reasoning behind non-obvious decisions live in
[PLAN.md](PLAN.md) — including why the private MediaRemote framework cannot be
used, and the three-time lesson about `Info.plist` usage keys.

## License

MIT
