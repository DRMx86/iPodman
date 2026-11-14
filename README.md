# iPod Manager (iOS 16+)

Minimal SwiftUI app to list, add, edit, delete and preview songs on an iPod Classic in disk mode.

## Hardware
iPod Classic has a 30-pin connector: 30-pin→USB cable + Lightning→USB (camera adapter, ideally the powered one).
Put the iPod in **disk mode** (Menu+Select to reset, then hold Select+Play until the disk-mode screen shows).
The iPod must be **FAT32 (Windows-formatted)** for writing; iOS mounts HFS+ read-only.

## Use
1. Open the app → *Choose iPod* → pick the iPod's root folder in Files.
2. Tap a song to preview, swipe for Edit/Delete, “+” to add MP3/M4A/WAV/AIFF from Files.
3. Eject from Files before unplugging.

## Known limitation (important)
iPod Classic 6G/7G require a **hash58-signed** iTunesDB. Signing is not included. Without it the app refuses to write
(read/list/preview works). Implement `DBSigner` (port of libgpod's `itdb_hash58.c`, LGPL; needs the iPod's FireWire GUID from
`iPod_Control/Device/SysInfo`) and set `Checksum.signer` at launch. The first original DB is backed up as `iTunesDB.bak`.
Edits only change the iPod database, not file tags. The album index is not rebuilt.

## Build
GitHub Actions (`.github/workflows/build.yml`) generates the project with XcodeGen and produces an **unsigned IPA** artifact;
sideload it with AltStore / Sideloadly. Locally: `brew install xcodegen && xcodegen generate`.
