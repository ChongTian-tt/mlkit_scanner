# mlkit_scanner

This project is based on [mlkit_scanner](https://www.dns-tech.ru/) and provides barcode, text, face, and object recognition capabilities for OpenHarmony Flutter scenarios.

## 1. Installation and Usage

### 1.1 Installation
Go to your project directory and add the dependency in `pubspec.yaml`:

#### pubspec.yaml
```yaml
dependencies:
  mlkit_scanner:
    git:
      url: https://gitcode.com/org/OpenHarmony-Flutter/mlkit_scanner
      ref: main
```

Run:

```bash
flutter pub get
```

### 1.2 Usage Example
See [example](example/lib/main.dart).

The simplest usage:

```dart
import 'package:flutter/foundation.dart';
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
          // Start barcode scanning. `delay` is in milliseconds.
          await controller.startScan(100);
        },
        onScan: (barcode) {
          debugPrint(barcode.displayValue ?? barcode.rawValue);
        },
      ),
    );
  }
}
```

## 2. Constraints
1. Flutter: 3.22.0-ohos; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 6.0.0.120 SP8;
2. Flutter: oh-3.27.4-dev; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 6.0.0.120 SP8;

## 3. Version and Framework Mapping
|       | 3.7 | 3.22 | 3.27 | 3.35 |
|-------|:---:|:----:|:----:|:----:|
| 1.0.0 |  ❌  |  ✅   |  ✅   |  ❌   |

## 4. API

> [!TIP] "ohos Support" column: yes means supported; no means not supported; partially means partially supported.

| Name | Description | Type | Input | Output | ohos Support |
| --- | --- | --- | --- | --- | --- |
| initCameraPreview | Initialize camera preview and apply initial parameters (e.g. crop/zoom) | function | `initialArguments?: ScannerParameters` (optional) | `Future<void>` | yes |
| dispose | Release camera and scanning resources | function | None | `Future<void>` | yes |
| toggleFlash | Toggle device flash light (if supported by device) | function | None | `Future<void>` | yes |
| startScan | Start barcode recognition and detect at intervals of `delay` | function | `type: RecognitionType; delay: int` (milliseconds) | `Future<void>` | yes |
| cancelScan | Cancel recognition flow and keep preview | function | None | `Future<void>` | yes |
| setScanDelay | Set scan polling interval `delay` | function | `delay: int` (milliseconds) | `Future<void>` | yes |
| onScanResult | Recognition result callback (native -> Dart, triggers `BarcodeScanner.onScan`) | event | `raw_value/display_value/format/value_type` | None (event) | yes |
| updateConstraints | Update preview constraints (width/height) and re-apply crop area if needed | function | `width: double; height: double` | `Future<void>` | yes |
| pauseCameraMethod | Pause camera preview (and scanning flow) | function | None | `Future<void>` | yes |
| resumeCameraMethod | Resume camera preview and scanning flow | function | None | `Future<void>` | yes |
| setZoom | Set camera zoom. `value` range: `0~1` | function | `value: double` (0~1) | `Future<void>` | yes |
| setCropAreaMethod | Set recognition crop area (relative to `CameraPreview`) | function | `rect: CropRect` | `Future<void>` | yes |

## 5. License
This project is open source under the [MIT](LICENSE) license.

