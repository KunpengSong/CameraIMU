# CameraIMU

An iOS app that simultaneously records video and IMU (Inertial Measurement Unit) sensor data from the iPhone's built-in hardware.

## Features

### Video Recording
- Records video via `AVCaptureMovieFileOutput`, saved as `.mov` files
- Supports all rear-facing cameras: **Wide (1x)**, **Ultra Wide (0.5x)**, and **Telephoto (3x)**
- Camera lens can be switched before recording through a segmented picker at the bottom of the screen
- Front-facing camera is intentionally excluded

### IMU Data Capture
- Captures accelerometer, gyroscope, and magnetometer data at **30 Hz** (matching the video frame rate)
- Uses Apple's `CMMotionManager` with fused `DeviceMotion` output for synchronized multi-sensor readings
- Data is written to a `.csv` file alongside the video

### Timestamp Synchronization
- A `SyncAnchor` is captured at the start of each recording, containing:
  - `host_time_seconds` — `CMClock` host time (same clock reference as video frame PTS)
  - `system_uptime_seconds` — `ProcessInfo.systemUptime` (same epoch as CoreMotion timestamps)
  - `wall_clock` — ISO 8601 wall-clock time for human reference
- The anchor is embedded as comment lines in the CSV header, enabling precise alignment between video frames and IMU samples in post-processing

### CSV Output Format

```
# sync_host_time_seconds=123456.789012
# sync_system_uptime_seconds=123456.789012
# sync_wall_clock=2026-03-31T14:30:00.000Z
timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,mag_x,mag_y,mag_z
123456.790000,0.001234,-0.998765,0.012345,0.001000,-0.002000,0.000500,12.34,-5.67,42.10
...
```

| Column | Unit | Description |
|--------|------|-------------|
| `timestamp` | seconds | Time since device boot (CoreMotion epoch) |
| `accel_x/y/z` | G | Total acceleration (gravity + user acceleration) |
| `gyro_x/y/z` | rad/s | Rotation rate |
| `mag_x/y/z` | microtesla | Calibrated magnetic field |

## UI Design

### Recording Screen
- Full-screen camera preview as background
- Top-left: recording duration badge with red pulse indicator (frosted glass material)
- Top-right: button to browse saved recordings
- Center-bottom: real-time info panel showing IMU sample count and active lens
- Bottom: lens selector (`0.5` / `1x` / `3x`) styled as circular segment buttons, active lens highlighted in yellow
- Record button with press-scale animation and haptic feedback
- Top and bottom gradient overlays for text readability

### Recordings List
- Card-based layout with play icon, timestamp, video size, and CSV size
- Long-press context menu: share CSV file or delete recording
- Delete confirmation dialog to prevent accidental deletion
- Swipe-friendly scroll view
- Light/dark mode follows system appearance automatically using semantic colors (`systemGroupedBackground`, `.primary`, `.secondary`, etc.)

### Video Player
- Built-in playback with standard `AVPlayer` controls
- Opens as a modal sheet from the recordings list

## Architecture

```
CameraIMU/
├── CameraIMUApp.swift              App entry point
├── Info.plist                      Privacy permissions
├── Managers/
│   ├── CameraManager.swift         AVCaptureSession, multi-lens discovery, recording
│   └── MotionManager.swift         CoreMotion sampling, thread-safe sample collection
├── ViewModels/
│   └── RecordingViewModel.swift    Coordinates camera + IMU, file I/O, state management
├── Views/
│   ├── ContentView.swift           Recording screen UI
│   ├── CameraPreviewView.swift     UIViewRepresentable for AVCaptureVideoPreviewLayer
│   └── RecordingsListView.swift    Recordings browser, video player, share/delete
├── Models/
│   ├── IMUSample.swift             IMU data struct with CSV serialization
│   └── Recording.swift             Recording metadata (paths, dates, file sizes)
└── Utilities/
    ├── TimestampSync.swift         SyncAnchor for video–IMU time alignment
    └── FileManagerExtensions.swift Documents directory helpers
```

### Key Design Decisions
- **Thread safety**: IMU samples are collected on a dedicated `OperationQueue` and protected by `NSLock`. The UI is updated every ~1 second (every 30 samples) to avoid main thread contention.
- **Lens switching**: Uses `AVCaptureDevice.DiscoverySession` filtered to `position: .back` to enumerate available rear cameras. Switching is performed by swapping `AVCaptureDeviceInput` within a session configuration block.
- **IMU starts before video**: `MotionManager.startRecording()` is called before `CameraManager.startRecording()` to ensure the sync anchor is captured before the first video frame.

## Requirements

- iOS 16.0+
- Physical iPhone (camera and IMU sensors are not available in the simulator)
- Permissions: Camera, Microphone, Motion & Fitness

## Installation

See [INSTALL.md](INSTALL.md) for instructions on building and installing without a local Xcode setup.
