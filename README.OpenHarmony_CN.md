# mlkit_scanner

本项目基于 [mlkit_scanner](https://www.dns-tech.ru/) 开发，为 OpenHarmony Flutter 场景提供条码、文本、人脸与物体识别能力。

## 1. 安装与使用

### 1.1 安装方式
进入工程目录并在 `pubspec.yaml` 中添加依赖：

#### pubspec.yaml
```yaml
dependencies:
  mlkit_scanner:
    git:
      url: https://gitcode.com/org/OpenHarmony-Flutter/mlkit_scanner
      ref: main
```
执行命令：

```bash
flutter pub get
```

### 1.2 使用案例
使用案例详见 [example](example/lib/main.dart)。

最简单的调用方式：

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

## 2. 约束条件
1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;
2. Flutter: 3.22.0-ohos; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 6.0.0.120 SP8;
3. Flutter: oh-3.27.4-dev; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 6.0.0.120 SP8;
4. Flutter: 3.35.7-ohos-0.0.1; SDK: 6.0.1(21); IDE: DevEco Studio: 6.0.1.260; ROM: 6.0.0.120 SP6;

## 3. 版本和框架对应关系
|       | 3.7 | 3.22 | 3.27 | 3.35 |
|-------|:---:|:----:|:----:|:----:|
| 1.0.0 |  ✅  |  ✅   |  ✅   |  ✅   |

## 4. API

> [!TIP] "ohos Support" 列：yes 表示支持；no 表示不支持；partially 表示部分支持。

| Name | Description | Type | Input | Output | ohos Support |
| --- | --- | --- | --- | --- | --- |
| initCameraPreview | 初始化相机预览，并应用初始参数（如裁剪区域/缩放） | function | `initialArguments?: ScannerParameters`（可选） | `Future<void>` | yes |
| dispose | 释放相机与扫描资源 | function | 无 | `Future<void>` | yes |
| toggleFlash | 切换设备闪光灯（需设备支持） | function | 无 | `Future<void>` | yes |
| startScan | 启动条码识别，并按 `delay` 间隔触发识别 | function | `type: RecognitionType; delay: int`（毫秒） | `Future<void>` | yes |
| cancelScan | 取消条码识别流程并保持预览 | function | 无 | `Future<void>` | yes |
| setScanDelay | 设置连续识别的轮询间隔 `delay` | function | `delay: int`（毫秒） | `Future<void>` | yes |
| onScanResult | 识别结果回调（native -> Dart，触发 `BarcodeScanner.onScan`） | event | `raw_value/display_value/format/value_type` | 无（事件） | yes |
| changeTorchStateMethod | 手电筒状态变化回调（native -> Dart，驱动 `torchToggleStream`） | event | `bool` | 无（事件） | yes |
| updateConstraints | 更新预览约束（宽高），并在需要时重新应用裁剪框 | function | `width: double; height: double` | `Future<void>` | yes |
| pauseCameraMethod | 暂停相机预览（并暂停识别流程） | function | 无 | `Future<void>` | yes |
| resumeCameraMethod | 恢复暂停后的相机预览与识别流程 | function | 无 | `Future<void>` | yes |
| setZoom | 设置相机变焦，`value` 范围为 `0~1` | function | `value: double`（0~1） | `Future<void>` | yes |
| setCropAreaMethod | 设置识别裁剪区域（相对 `CameraPreview`） | function | `rect: CropRect` | `Future<void>` | yes |
| getIosAvailableCameras | 获取当前设备可用的 OHOS 相机列表（channel 名称兼容沿用 iOS 命名） | function | 无 | `Future<List<OhosCamera>>` | yes |
| setIosCamera | 按位置与类型切换 OHOS 相机（channel 名称兼容沿用 iOS 命名） | function | `position: OhosCameraPosition; type: OhosCameraType` | `Future<void>` | yes |

## 5. 开源协议
本项目基于 [MIT](LICENSE) 开源。

