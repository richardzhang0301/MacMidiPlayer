# MacMidiPlayer

A lightweight macOS MIDI file player built with SwiftUI. Load `.mid`/`.midi` files and route playback to any connected MIDI output device.

## Features

- Play, pause, stop, and seek through Standard MIDI Files
- Drag-and-drop file loading
- Select output MIDI device for routing to external synths/hardware
- Monitor incoming MIDI input and display last received message
- Auto-detect MIDI standards (GM, GM2, GS, XG, MT-32) with color-coded badges
- Real-time beat position tracking and tempo display

## Requirements

- macOS 13.0+ (Ventura)
- Swift 5.9+

## Build

```bash
# Build with Swift Package Manager
swift build -c release

# Or create a standalone .app bundle
./build_mac.sh
```

No external dependencies — uses only Apple frameworks (CoreMIDI, AudioToolbox, SwiftUI).

## Usage

1. Launch the app
2. Select an output MIDI device from the dropdown
3. Open a MIDI file via the file picker or drag-and-drop
4. Use transport controls or keyboard shortcuts:
   - **Space** — Play / Pause
   - **Cmd + .** — Stop
