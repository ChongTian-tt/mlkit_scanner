# mlkit_scanner

本项目基于 [mlkit_scanner](https://github.com/dns-technologies/mlkit_scanner) 开发。

## 简介

mlkit_scanner 是一个 Flutter 条码识别插件，使用 MLKit API 提供条码扫描能力，支持相机预览、闪光灯控制、变焦、裁剪区域设置及相机切换等功能。

## 下载安装

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

```yaml
dependencies:
  mlkit_scanner:
    git:
      url: https://gitcode.com/org/OpenHarmony-Flutter/mlkit_scanner
      ref: 0.6.0-ohos-1.0.0
```

执行命令：

```bash
flutter pub get
```

> TAG 命名规则：`原库版本-ohos-版本号`，不同 TAG 之间的变更详见 CHANGELOG.md。

| Flutter 框架版本 | TAG 名称 | 备注 |
| --- | --- | --- |
| 3.7.12-ohos-1.0.6 | 0.6.0-ohos-1.0.0 | 首次适配 |
| 3.22.0-ohos | 0.6.0-ohos-1.0.0 | |
| 3.27.4-dev-oh | 0.6.0-ohos-1.0.0 | |
| 3.35.7-ohos-0.0.1 | 0.6.0-ohos-1.0.0 | |

## 约束与限制

### 兼容性

在下述版本验证通过：

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;
2. Flutter: 3.22.0-ohos; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 6.0.0.120 SP8;
3. Flutter: oh-3.27.4-dev; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 6.0.0.120 SP8;
4. Flutter: 3.35.7-ohos-0.0.1; SDK: 6.0.1(21); IDE: DevEco Studio: 6.0.1.260; ROM: 6.0.0.120 SP6;

### 权限要求

需要在 module.json5 中配置相机权限。

打开 `entry/src/main/module.json5`，添加：

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

打开 `entry/src/main/resources/base/element/string.json`，添加：

```json
{
  "string": [
    {
      "name": "camera_reason",
      "value": "使用相机进行条码扫描"
    }
  ]
}
```

## 使用示例

mlkit_scanner 提供了 `BarcodeScanner` Widget，以下为最简单的使用方式：

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
          // 启动条码识别，delay 为识别间隔（毫秒）
          await controller.startScan(100);
        },
        onScan: (barcode) {
          // 获取识别结果
          debugPrint(barcode.rawValue);
        },
      ),
    );
  }
}
```

## 使用说明

### 1. 创建 BarcodeScanner

`BarcodeScanner` 是核心组件，需传入 `onScannerInitialized` 和 `onScan` 回调：

```dart
BarcodeScanner(
  initialArguments: const OhosScannerParameters(
    cropRect: CropRect(scaleHeight: 0.7, scaleWidth: 0.7),
  ),
  onScannerInitialized: (controller) {
    // 保存 controller 用于后续控制
  },
  onScan: (barcode) {
    // 处理识别结果
  },
)
```

### 2. 闪光灯控制

```dart
// 切换闪光灯（需设备支持）
await controller.toggleFlash();
```

### 3. 扫描控制

```dart
// 启动条码识别
await controller.startScan(100);

// 取消识别（保持预览）
await controller.cancelScan();

// 动态设置识别轮询间隔
await controller.setDelay(500);
```

### 4. 相机控制

```dart
// 暂停相机预览与识别
await controller.pauseCamera();

// 恢复相机预览与识别
await controller.resumeCamera();

// 设置变焦，value 范围 0~1
await controller.setZoom(0.5);
```

### 5. 裁剪区域

```dart
// 设置识别裁剪区域（相对 CameraPreview）
await controller.setCropArea(CropRect(scaleHeight: 0.7, scaleWidth: 0.7));
```

### 6. 相机切换

```dart
// 获取可用的 OHOS 相机列表
List<OhosCamera> cameras = await MLKitUtils().getOhosAvailableCameras();

// 按位置与类型切换相机
await controller.setOhosCamera(
  position: OhosCameraPosition.back,
  type: OhosCameraType.wideAngle,
);
```

## 接口说明

### API

> [!TIP] "OHOS 平台支持"列：yes 表示支持，no 表示不支持，partially 表示部分支持。

| 名称 | 描述 | 类型 | 参数 | 返回值 | OHOS 平台支持 |
| --- | --- | --- | --- | --- | --- |
| toggleFlash | 切换设备闪光灯（需设备支持） | 方法 | 无 | `Future<void>` | yes |
| startScan | 启动条码识别，并按 delay 间隔触发识别 | 方法 | `type: RecognitionType; delay: int`（毫秒） | `Future<void>` | yes |
| cancelScan | 取消条码识别流程并保持预览 | 方法 | 无 | `Future<void>` | yes |
| setDelay | 动态设置识别轮询间隔 | 方法 | `delay: int`（毫秒） | `Future<void>` | yes |
| pauseCamera | 暂停相机预览（并暂停识别流程） | 方法 | 无 | `Future<void>` | yes |
| resumeCamera | 恢复暂停后的相机预览与识别流程 | 方法 | 无 | `Future<void>` | yes |
| setZoom | 设置相机变焦 | 方法 | `value: double`（0~1） | `Future<void>` | yes |
| setCropArea | 设置识别裁剪区域（相对 CameraPreview） | 方法 | `rect: CropRect` | `Future<void>` | yes |
| getOhosAvailableCameras | 获取当前设备可用的 OHOS 相机列表 | 方法 | 无 | `Future<List<OhosCamera>>` | yes |
| setOhosCamera | 按位置与类型切换 OHOS 相机 | 方法 | `position: OhosCameraPosition; type: OhosCameraType` | `Future<void>` | yes |

## 遗留问题

无

## 目录结构

```
|---- mlkit_scanner
|     |---- android       # Android 适配代码
|     |---- example       # 多平台的完整示例应用
|           |---- lib     # 示例代码
|           |---- ohos    # 鸿蒙工程
|     |---- ios           # iOS 适配代码
|     |---- lib           # 核心代码实现
|           |---- models  # 数据模型（Barcode、CropRect、OhosCamera 等）
|           |---- platform # 平台通道（MlKitChannel）
|           |---- utils   # 工具类（MLKitUtils）
|           |---- widgets # Widget 组件（BarcodeScanner、CameraPreview）
|           |---- mlkit_scanner.dart # 库的主入口文件
|     |---- ohos          # 鸿蒙适配代码
|     |---- test          # 单元测试文件
|     |---- CHANGELOG.md            # 更新日志
|     |---- README.OpenHarmony_CN.md # 中文说明文档
|     |---- README.OpenHarmony.md   # 英文说明文档
|     |---- README.OpenSource.md    # 开源说明
|     |---- pubspec.yaml           # 配置文件
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/org/OpenHarmony-Flutter/mlkit_scanner/issues)，当然，也非常欢迎发 [PR](https://gitcode.com/org/OpenHarmony-Flutter/mlkit_scanner/pulls) 共建。

## 开源协议

本项目基于 [MIT](https://github.com/dns-technologies/mlkit_scanner/blob/master/LICENSE) 开源，请自由地享受和参与开源。
