# MacPulse

A native macOS app (SwiftUI) to keep track of what is happening on your Mac, clean up disk junk, and stop processes that are slowing it down.

## Features

**Overview**
- Real-time CPU usage (user/system, load average, history chart)
- Memory measured the same way Activity Monitor does it (app, wired, compressed, cached, swap, pressure)
- Startup disk usage (used, available, purgeable)
- Top processes by CPU and memory, plus quick actions

**Disks**
- All mounted volumes with capacity, free space and purgeable space; eject external volumes
- **Space analyzer**: size of every item in a folder. Double-click a folder to drill into it
- **Large files**: lists files above 100 MB / 500 MB / 1 GB / 5 GB, with options to reveal in Finder or move to the Trash

**Cleanup**
| Category | Default | Action |
|---|---|---|
| App caches (`~/Library/Caches`) | selected | deletes |
| Logs and crash reports (`~/Library/Logs`) | selected | deletes |
| Trash (`~/.Trash`) | selected | deletes |
| Xcode DerivedData, Simulator caches | selected | deletes |
| Dev caches: npm, Yarn, pnpm, Gradle, Cargo, pip | selected | deletes |
| Xcode Device Support | not selected | deletes |
| Downloads older than 90 days | not selected | **moves to Trash** |
| iPhone/iPad backups | not selected | **moves to Trash** |

Each category can be expanded so you can pick individual items. A confirmation is always shown before anything is cleaned.

**Maintenance** (asks for the administrator password through macOS's own dialog)
- Free inactive memory (`purge`)
- Flush the DNS cache
- Empty the Trash via Finder (works without Full Disk Access)
- Delete local Time Machine snapshots (frees "purgeable" space)

**Processes**
- Full process list with search, filters (All / Apps / Mine / System) and sorting by any column
- Quit or force quit; system processes can be terminated as administrator
- Essential processes (`kernel_task`, `launchd`, `WindowServer`, `loginwindow`…) are blocked to avoid freezing the Mac

**Menu bar**: CPU, memory, disk and top processes always one click away.

> The app's interface is in Brazilian Portuguese.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode or the Command Line Tools (`xcode-select --install`)

## Running

```bash
make open        # builds dist/MacPulse.app and opens it
make install     # copies the app to /Applications
make run         # runs straight from SwiftPM (development)
```

Or open `Package.swift` in Xcode and run the `MacPulse` target.

### Full Disk Access (optional, recommended)

Some folders, such as the Trash, are protected by macOS. To let MacPulse scan them:

1. Install the app (`make install`).
2. Go to **System Settings › Privacy & Security › Full Disk Access**.
3. Add `MacPulse.app` and reopen the app.

> The app is ad-hoc signed. Every new build changes the signature, so you may need to grant the permission again after rebuilding.

## Project structure

```
Sources/MacPulse/
├── App/          # app entry point, main window, menu bar extra
├── Services/     # CPU/memory readers (Mach), volumes, ps, file scanning, cleanup targets
├── Stores/       # observable state (@Observable) for each area
├── Components/   # cards, gauges, bars, charts
└── Views/        # Overview, Disks, Cleanup, Processes
scripts/
├── build-app.sh  # assembles and signs dist/MacPulse.app
└── make-icon.swift
```

### Development snapshots

In debug builds, `MACPULSE_SNAPSHOT_DIR=/tmp/shots swift run` walks through every tab, saves a PNG of each one and quits the app.

## Safety

- Nothing is removed without confirmation. Only caches, logs and build artifacts (data that regenerates) are deleted outright; everything else goes to the Trash.
- Sensitive iCloud/Keychain entries inside `~/Library/Caches` are skipped.
- The app never sees your password: administrator actions use the native macOS dialog.
