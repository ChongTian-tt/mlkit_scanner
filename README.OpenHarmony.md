# mlkit_scanner

This project is based on [mlkit_scanner](https://github.com/dns-technologies/mlkit_scanner).

## Introduction

mlkit_scanner is a Flutter barcode recognition plugin that uses the MLKit API to provide barcode scanning capabilities, supporting camera preview, flash control, zoom, crop area settings, and camera switching.

## Download and Installation

Go to your project directory and add the following dependency in `pubspec.yaml`:

```yaml
dependencies:
  mlkit_scanner:
    git:
      url: https://gitcode.com/org/OpenHarmony-Flutter/mlkit_scanner
      ref: br_3.35_dev
```

Run:

```bash
flutter pub get
```

> TAG naming rule: `original-version-ohos-version-number`. For changes between TAGs, see CHANGELOG.md.

| Flutter Framework Version | TAG Name | Branch Name |
| --- | --- | --- |
| 3.7.12-ohos-1.1.1 | 0.6.0-ohos-1.0.0 | br_3.35_dev |
| 3.22.0-ohos | 0.6.0-ohos-1.0.0 | br_3.35_dev |
| 3.27.4-dev-oh | 0.6.0-ohos-1.0.0 | br_3.35_dev |
| 3.35.7-ohos-0.0.1 | 0.6.0-ohos-1.0.0 | br_3.35_dev |

## Constraints and Limitations

### Compatibility

Verified on the following versions:

1. Flutter: 3.7.12-ohos-1.1.1; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;
2. Flutter: 3.22.0-ohos; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 6.0.0.120 SP8;
3. Flutter: oh-3.27.4-dev; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 6.0.0.120 SP8;
4. Flutter: 3.35.7-ohos-0.0.1; SDK: 6.0.1(21); IDE: DevEco Studio: 6.0.1.260; ROM: 6.0.0.120 SP6;

### Permission Requirements

Camera permission must be configured in module.json5.

Open `entry/src/main/module.json5` and add:

```json
"requestPermissions": [
  {
    "name": "ohos.permission.CAMERA",
    "reason": "$string:camera_reason",
    "usedScene": {
      "abilities": [
        "EntryAbility"
      ],
      "when": "inuse"
    }
  }
]
```

Open `entry/src/main/resources/base/element/string.json` and add:

```json
{
  "string": [
    {
      "name": "camera_reason",
      "value": "Use camera for barcode scanning"
    }
  ]
}
```

## Usage Example

mlkit_scanner provides the `BarcodeScanner` widget. The simplest usage is as follows:

```dart
import 'package:flutter/widgets.dart';
import 'package:mlkit_scanner/mlkit_scanner.dart';

class MlkitScannerExample extends StatelessWidget {
  const MlkitScannerExample({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: BarcodeScanner(
        onScannerInitialized: (controller) async {
          // Start barcode scanning, delay is the scan interval in milliseconds
          await controller.startScan(100);
        },
        onScan: (barcode) {
          // Get recognition result
          debugPrint(barcode.rawValue);
        },
      ),
    );
  }
}
```

## Usage Instructions

### 1. Creating a BarcodeScanner

`BarcodeScanner` is the core widget, requiring `onScannerInitialized` and `onScan` callbacks:

```dart
BarcodeScanner(
  initialArguments: const OhosScannerParameters(
    cropRect: CropRect(scaleHeight: 0.7, scaleWidth: 0.7),
  ),
  onScannerInitialized: (controller) {
    // Save controller for subsequent control
  },
  onScan: (barcode) {
    // Handle recognition result
  },
)
```

### 2. Flash Control

```dart
// Toggle flash (device must support it)
await controller.toggleFlash();
```

### 3. Scanning Control

```dart
// Start barcode recognition
await controller.startScan(100);

// Cancel recognition (keep preview)
await controller.cancelScan();

// Dynamically set scan polling interval
await controller.setDelay(500);
```

### 4. Camera Control

```dart
// Pause camera preview and recognition
await controller.pauseCamera();

// Resume camera preview and recognition
await controller.resumeCamera();

// Set zoom, value range 0~1
await controller.setZoom(0.5);
```

### 5. Crop Area

```dart
// Set recognition crop area (relative to CameraPreview)
await controller.setCropArea(CropRect(scaleHeight: 0.7, scaleWidth: 0.7));
```

### 6. Camera Switching

```dart
// Get available OHOS camera list
List<OhosCamera> cameras = await MLKitUtils().getOhosAvailableCameras();

// Switch camera by position and type
await controller.setOhosCamera(
  position: OhosCameraPosition.back,
  type: OhosCameraType.CAMERA_TYPE_WIDE_ANGLE,
);
```

## API Reference

### API

> [!TIP] "OHOS Support" column: yes means supported, no means not supported, partially means partially supported.

| Name | Description | Type | Parameters | Return Value | Exceptions | OHOS Support |
| --- | --- | --- | --- | --- | --- | --- |
| toggleFlash | Toggle device flash (device must support it) | Method | None | `Future<void>` | `PlatformException(code='4')` if device has no flash | yes |
| startScan | Start barcode recognition and detect at intervals of delay | Method | `delay: int` (milliseconds) | `Future<void>` | `PlatformException(code='3')` if camera not initialized | yes |
| cancelScan | Cancel recognition flow and keep preview | Method | None | `Future<void>` | — | yes |
| setDelay | Dynamically set scan polling interval | Method | `delay: int` (milliseconds) | `Future<void>` | — | yes |
| pauseCamera | Pause camera preview (and recognition flow) | Method | None | `Future<void>` | — | yes |
| resumeCamera | Resume paused camera preview and recognition flow | Method | None | `Future<void>` | `PlatformException(code='3')` if camera not initialized | yes |
| setZoom | Set camera zoom | Method | `value: double` (0~1) | `Future<void>` | `PlatformException(code='6')` if zoom not supported | yes |
| setCropArea | Set recognition crop area (relative to CameraPreview) | Method | `rect: CropRect` | `Future<void>` | `PlatformException(code='5')` if invalid arguments | yes |
| getOhosAvailableCameras | Get available OHOS camera list on the current device | Method | None | `Future<List<OhosCamera>>` | — | yes |
| setOhosCamera | Switch OHOS camera by position and type | Method | `position: OhosCameraPosition; type: OhosCameraType` | `Future<void>` | — | yes |

> **Exception Code Reference**: `'1'` = Camera initialization failed, `'2'` = Camera permission denied, `'3'` = Camera not initialized, `'4'` = Device has no flash, `'5'` = Invalid arguments, `'6'` = Zoom not supported.

## Known Issues

None

## Directory Structure

```
|---- mlkit_scanner
|     |---- android       # Android adaptation code
|     |---- example       # Multi-platform example application
|           |---- lib     # Example code
|           |---- ohos    # OpenHarmony project
|     |---- ios           # iOS adaptation code
|     |---- lib           # Core code implementation
|           |---- models  # Data models (Barcode, CropRect, OhosCamera, etc.)
|           |---- platform # Platform channel (MlKitChannel)
|           |---- utils   # Utilities (MLKitUtils)
|           |---- widgets # Widget components (BarcodeScanner, CameraPreview)
|           |---- mlkit_scanner.dart # Library main entry file
|     |---- ohos          # OpenHarmony adaptation code
|     |---- test          # Unit test files
|     |---- CHANGELOG.md            # Changelog
|     |---- README.OpenHarmony_CN.md # Chinese documentation
|     |---- README.OpenHarmony.md   # English documentation
|     |---- README.OpenSource.md    # Open source notice
|     |---- pubspec.yaml           # Configuration file
```

## Contributing

If you encounter any issues, please submit an [Issue](https://gitcode.com/org/OpenHarmony-Flutter/mlkit_scanner/issues). Contributions via [PR](https://gitcode.com/org/OpenHarmony-Flutter/mlkit_scanner/pulls) are also welcome.

## License

This project is licensed under [MIT](https://github.com/dns-technologies/mlkit_scanner/blob/master/LICENSE).
