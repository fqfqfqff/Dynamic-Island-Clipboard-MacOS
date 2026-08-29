<p align="center">
  <img src="Docs/icon.png" width="128" alt="Aura">
</p>

<h1 align="center">Aura</h1>

<p align="center">
  Turns the MacBook camera notch into a live island — and gives macOS the
  clipboard history it still does not have.<br>
  Swift 6, SwiftUI and AppKit, no dependencies.
</p>

<p align="center">
  <b>0.4.0</b> · macOS 14.4+ · Apple silicon and Intel ·
  <a href="README.ru.md">Русская версия</a>
</p>

<p align="center">
  <img src="Docs/island-collapsed.png" width="620" alt="The island in the notch">
</p>

---

## What it does

**The island.** Invisible until something happens: it is exactly the shape of
the physical notch. Music, charging, screenshots, the next calendar event,
focus changes, Wi-Fi and Personal Hotspot, browser downloads, notifications
from other apps. Hover and it opens into a player; the artwork does not appear
in a new place, it flows out of the compact slot and grows.

<p align="center">
  <img src="Docs/island-player.png" width="420" alt="Player">
  <img src="Docs/island-activities.png" width="420" alt="Activities">
</p>

**Any audio source, honestly detected.** Not just Spotify. The island finds
whoever is actually playing through the CoreAudio process list — a video in a
browser tab, a voice message in a messenger. Two things make this work that
usually do not: helper processes are resolved back to their parent app, so
Chrome shows up as Chrome and not as *Google Chrome Helper*; and a per-process
audio tap tells a playing app from one that merely keeps an output stream open
and silent, which is what Telegram, Discord and most Electron apps do.

**Real spectrum.** The equaliser bars are an actual FFT over a CoreAudio
process tap, five bands with a per-band ceiling — not a looping animation.

**Notifications, the way the iPhone does them.**

<p align="center">
  <img src="Docs/island-notification.png" width="620" alt="Notification">
</p>

The notch grows downward into a card: app icon, who wrote, and what arrived —
text, voice message, video message, photo, file or a call. The rim is tinted
with the app's own colour. Afterwards a badge stays — icon on the left, unread
count on the right — until you open the app or click it away. Per-app rules
decide who gets a card, who gets only a badge, and who gets nothing. If the
system banner is still on screen, **Reply** works straight from the island;
otherwise the card opens the app.

Notifications come from two sources at once: the banner and the Notification
Center database. There may be no banner at all — a Focus mode suppresses them,
and macOS lets you switch them off per app — and then the second path carries
it. Different people get their own rows: five messages from five people are
five things to do, not a "5" on a messenger badge.

Every notification has an app icon. Installed apps are matched by bundle
identifier; for the rest the icon is grabbed from the banner itself, because
notifications mirrored from an iPhone come from apps that are not — and cannot
be — on the Mac.

**Clipboard.** A window on ⌥⌘V with search, previews, pinning, an undo for
clearing and a full log of everything ever copied. Links, images, files and
colours are recognised and previewed. There is an eyedropper for picking a
colour off the screen, and a checkbox for pasting with or without formatting.
Passwords from password managers never enter the history — the
`org.nspasteboard.*` markers are respected, and you can exclude a bank or a
password manager of your own.

Every entry knows what it is and offers an action: open a link, pretty-print
JSON, look up an address on a map. Anything copied on an iPhone is marked as
such. A verification code from a text message shows up right in the
notification, as a button — no need to open the conversation.

**Screenshots land on the clipboard.** A screenshot is saved to disk as usual
and put on the clipboard at the same time: ⌘V pastes the picture, mail attaches
the file. No need to remember ⌃⌘⇧4 in advance — you decide whether you wanted a
file or a paste *after* taking the shot.

**Headphones.** Pull them out and the music pauses. macOS does this itself,
but only for apps that bothered to handle it: Spotify does, a browser usually
does not.

**A shelf.** Drop files onto the notch and choose: keep them on the shelf, send
them by AirDrop, or compress them. Drag them back out later into a mail message
or a chat.

**On the lock screen.** macOS does not let apps draw there — the whole user
session is hidden. The one thing it does run is a screen saver, so Aura ships
one: it shows the player, artwork and synced lyrics over the locked screen.

**An open API.** Any script can put itself into the notch:

```bash
Scripts/aura push --id build --title "Building" --progress 0.4
Scripts/aura remove --id build
```

---

## Install

Everything is one command, but it is worth knowing what it does.

### 1. Requirements

- macOS 14.4 or newer (the audio process API arrived there)
- Xcode 15.3+ or the Command Line Tools — `xcode-select --install`
- Nothing else: the project has no external dependencies

### 2. The easy way

Download **Install-Aura.command** from the
[latest release](https://github.com/fqfqfqff/Dynamic-Island-Clipboard-MacOS/releases/latest),
double-click it, and you are done. It checks the macOS version, installs the
developer tools if they are missing, downloads the sources into `~/Developer/Aura`,
builds, installs and launches Aura.

macOS will refuse to open a downloaded script on the first try — right-click it
and choose **Open**, then confirm. That is Gatekeeper doing its job.

### 2b. Or from the terminal

```bash
git clone https://github.com/fqfqfqff/Dynamic-Island-Clipboard-MacOS && \
  cd Dynamic-Island-Clipboard-MacOS && ./Scripts/setup.sh
```

`setup.sh` does five things, in order:

1. **Creates a local signing certificate** (`Scripts/make-cert.sh`). This is the
   part that matters. macOS ties every permission to a code signature and a
   path; an ad-hoc signature changes on every build, so without a stable
   certificate the toggle in *Accessibility* goes grey after each rebuild and
   you have to grant everything again.
2. **Builds the app** in release configuration.
3. **Installs it into `~/Applications`** — a permanent path, for the same
   reason.
4. **Installs the screen saver** into `~/Library/Screen Savers`.
5. **Enables launch at login** and starts Aura.

### 3. First run

A first-run screen explains each permission and what it buys you. You can grant
them later from *Settings → System → Permissions*; nothing is mandatory, the
app simply does less.

### If something does not work

```bash
Scripts/aura status
```

That prints what is running and, more usefully, *why* something is not: whether
the panel is visible, which audio sources are seen, whether the level probe is
allowed, whether Accessibility is granted, what the last player poll failed on.
It also reports memory use and how long the process has been up.

If the app crashes on launch three times in a row it comes up with its sources
switched off, and a menu item brings them back — no terminal required.

### Why there is no prebuilt binary

Without a $99/year Developer ID, macOS marks a downloaded app as damaged and
refuses to open it. Building from source sidesteps that entirely and takes
under a minute.

---

## Permissions

The system asks for these itself, on first use.

| Permission | Used for | Without it |
|---|---|---|
| Accessibility | pasting from the clipboard, mirroring notifications, replying | no paste, no notifications |
| Automation | track, artwork and controls from Music and Spotify | app name only, no artwork |
| Audio capture | equaliser bars, and telling a playing app from a silent one | no bars; silent apps may show as playing |
| Calendars | the next meeting | no meeting card |
| Full disk | focus mode state (optional) | focus changes stay silent |

Nothing is recorded or uploaded. There are exactly two network requests, both
optional and both switchable off:

- **lrclib.net** — a lyrics lookup that receives a track name, an artist and a
  duration, only when lyrics are switched on;
- **open.spotify.com** — the public page of the track currently playing, to
  read the full list of artists. Spotify's own AppleScript exposes a single
  `artist` field and names only the first one. The request carries a track id
  Spotify already knows, and the answer is remembered per track.

---

## Everyday use

| | |
|---|---|
| Hover the notch | the island opens |
| Click the track name | copies *Artist — Title* |
| Hold ⌥ over the player | shows the album and the source |
| Drag the seek bar | scrubs with a time preview, seeks on release |
| Scroll sideways over the notch | previous / next track |
| Long-press the notch | quick menu: pause, hide the island, settings |
| Drop a file on the notch | shelf, AirDrop or compress |
| ⌥⌘V | clipboard history |
| ⌥⌘M | full-screen showcase |

Settings open from the menu bar icon. They start at **Minimal** — the handful
of things people actually change — and **Everything** unfolds the fine tuning:
shapes, sizes, spring curves. The whole set can be saved to a file and carried
to another machine.

---

## Development

```bash
./Scripts/run.sh        # build and run from ./build
./Scripts/install.sh    # rebuild and update the installed copy
./Scripts/shots.sh      # render the interface to PNG — no screen recording needed
./Scripts/make-icon.sh  # redraw the app icon
swift test              # 152 tests
./Scripts/bench.sh      # idle cost: CPU and memory
Scripts/aura status     # diagnostics
```

`Scripts/shots.sh` deserves a note: it draws the app's own views offscreen
through `NSHostingView` and writes PNGs. It needs no screen-recording
permission, it runs in CI, and it is how the images in this file were made.

---

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
  Settings/         settings store, window, profile export
  Snapshots/        offscreen rendering of views and of the app icon
  System/           permissions, hotkeys, audio spectrum, watchers
Sources/AuraSaver/  the screen saver plug-in
```

[HANDOFF.md](HANDOFF.md) is worth reading before changing anything: it lists
every non-obvious thing this project has already tripped over — why the private
MediaRemote framework cannot be used, why an isolated closure in a CoreAudio
callback kills the process, and what a notification banner actually looks like
from the inside.

## License

MIT
