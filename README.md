# iPod Manager (iOS 16+)

Minimal SwiftUI app to browse, preview, save to Files, add, edit and delete songs on a click-wheel iPod that mounts as USB mass storage
(disk mode), using the Files app’s external-drive access. No iTunes.

## Hardware & setup
- iPod Classic / Video / older nanos have a **30-pin** connector: 30-pin→USB cable + Lightning→USB camera adapter (powered one is best).
- Put the iPod in **disk mode** (Menu+Select to reset, then hold Select+Play until the disk-mode screen shows).
- The iPod must be **FAT32 (Windows-formatted)** to write. iOS mounts HFS+ (Mac-formatted) iPods **read-only**.
- Open the app → *Choose iPod* → pick the iPod's root folder (the one containing `iPod_Control`).

## Eject / Insert
iOS cannot unmount a drive from an app. **Eject** (⏏ in the toolbar) stops playback, flushes (fsync) and releases the volume, then tells you it is
safe to unplug (you can also use the eject icon next to the drive in Files). **Insert iPod** re-opens the last iPod after you plug it back in.
Writes are refused (and nothing is changed) if the iPod disappears mid-session. The original database is backed up once as `iTunesDB.bak`.

## Supported iPods and checksums

A checksum is a signature in the database header. The iPod ignores/rejects a database whose signature is wrong, so writing requires
computing it. (Model/checksum facts follow Minpod, libgpod and pygpod.)

| iPod | Checksum | Browse · preview · save to Files | Add / edit / delete |
|---|---|---|---|
| iPod 1G–4G, Photo, Mini | none | ✅ expected (untested) | ⚠️ experimental¹ |
| iPod Video 5G / 5.5G | none | ✅ expected (untested) | ⚠️ experimental¹ |
| iPod nano 1G / 2G | none | ✅ expected (untested) | ⚠️ experimental¹ |
| iPod nano 3G / 4G | **hash58** | ✅ expected (untested) | ❌ needs hash58 signer² |
| iPod Classic 6G / 6.5G / 7G | **hash58** | ✅ expected (untested) | ❌ needs hash58 signer² |
| iPod nano 5G | **hash72** (+ compressed `iTunesCDB`) | ✅ read-only (tested) | ❌ not supported |
| iPod nano 6G / 7G | **hashAB** (+ `iTunesCDB`) | ⚠️ untested | ❌ not supported |
| iPod shuffle (all) | none, but uses `iTunesSD` | ❌ different format | ❌ |
| iPod touch / iPhone | hash72 / hashAB | ❌ | ❌ |

¹ **Experimental write support.** This app adds/edits/removes the track records and master-playlist entries, but does **not yet** rebuild the
sort indexes the iPod menus use (mhod 52/53 on the master playlist), keep both master-playlist copies in sync, or write album art into
`ArtworkDB`. Minpod reports that such songs may not appear in the iPod's menus without these. Treat add/edit/delete as work in progress and keep the backup.

² **hash58** (HMAC-SHA1 keyed from the iPod's FireWire GUID in `iPod_Control/Device/SysInfo`) is **not included**. Plug a signer into
`Checksum.signer` (`Checksum.swift`). Minpod (MIT licence, Swift) and libgpod/pygpod (LGPL) contain implementations you can port.
Until then the app refuses to write to these iPods (an experimental *write without checksum* toggle exists, but the iPod will likely show an empty library).

hash72 (nano 5G) needs extra per-device data written by iTunes, and hashAB (nano 6G/7G) is a separate scheme (see
[dstaley/hashab](https://github.com/dstaley/hashab), Unlicense, C/WASM). Neither is implemented.

## Features
- List/search songs, with cover art read from each file's embedded tags.
- Tap to play; mini player at the bottom, tap it for the full-screen player (swipe down or chevron to minimize), queue with previous/next.
- **Save to Files**: swipe right / long-press / *Select* several → copies out as "Artist - Title.ext".
- Add MP3, M4A (AAC/ALAC), WAV, AIFF from Files (see limitation ¹).

## Build
GitHub Actions (`.github/workflows/build.yml`, runner `macos-15`) generates the project with XcodeGen and uploads an **unsigned IPA**
artifact; sideload with AltStore / Sideloadly. Locally: `brew install xcodegen && xcodegen generate`.

## Credits / references
[Minpod](https://github.com/moerdowo/Minpod) (macOS iPod manager, MIT), [libgpod](https://gitlab.gnome.org/GNOME/libgpod),
[pygpod](https://pypi.org/project/pygpod/), [dstaley/hashab](https://github.com/dstaley/hashab). Not affiliated with Apple.
