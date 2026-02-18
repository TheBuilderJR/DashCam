# Dashcam

A lightweight macOS menu bar app that continuously records your screen and audio in the background — like a dashcam for your computer. Capture snapshots of the last 5–30 minutes on demand.

## Features

- **Continuous screen recording** — runs quietly in your menu bar at 1080p/15fps
- **Audio capture** — records microphone audio alongside your screen
- **Rolling buffer** — keeps up to 2 hours of footage, automatically discarding old segments
- **On-demand snapshots** — save the last few minutes as a reviewable clip whenever you need it
- **Clipboard history** — tracks clipboard changes with timestamps alongside recordings
- **Export to MP4** — export any snapshot for sharing or archiving
- **No external dependencies** — built entirely with native macOS frameworks

## Requirements

- macOS 14 (Sonoma) or later
- Screen Recording permission
- Microphone permission

## Install

1. Go to the [latest release](https://github.com/TheBuilderJR/DashCam/releases/latest)
2. Download **Dashcam-x.x.x.dmg**
3. Open the DMG and drag **Dashcam** to your Applications folder
4. Launch Dashcam from Applications

On first launch, macOS will ask you to grant **Screen Recording** and **Microphone** permissions in System Settings > Privacy & Security.

> **Note:** Since the app is signed and notarized with an Apple Developer ID, you should not see a Gatekeeper warning. If you do, right-click the app and select "Open".

## Usage

Dashcam lives in your menu bar. Click the icon to:

- **Start/stop recording**
- **Take a snapshot** — saves the last few minutes of footage
- **Open Snapshots** — browse, play back, and export your saved snapshots

Recordings are stored in `~/Library/Application Support/Dashcam/buffer/` and snapshots in `~/Library/Application Support/Dashcam/snapshots/`.

## Build from source

Requires Xcode 16.

```sh
git clone git@github.com:TheBuilderJR/DashCam.git
cd DashCam
open Dashcam.xcodeproj
```

Build and run with **Cmd+R** in Xcode.

## License

MIT
