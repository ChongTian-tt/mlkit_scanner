# mlkit_scanner 鸿蒙化规格书

## 项目基本信息
- 名称：mlkit_scanner
- 版本：0.6.0
- 类型：Flutter 插件
- 描述：为 OpenHarmony Flutter 应用提供相机预览、条码识别、识别区域控制、相机切换与闪光灯控制能力。
- 主页：https://www.dns-tech.ru/

## 项目描述
为 OpenHarmony Flutter 应用提供相机预览、条码识别、识别区域控制、相机切换与闪光灯控制能力。

## 用户场景
开发过程中需要用到三方库 mlkit_scanner，但该库未做鸿蒙化适配，为此需要做 mlkit_scanner 鸿蒙化适配，提供 mlkit_scanner SDK，提供相机预览、条码识别、扫描区域控制、变焦、闪光灯控制与相机切换能力，适用于在 Flutter 应用中集成扫码识别与预览交互的场景。

## 需求价值
mlkit_scanner 鸿蒙化适配，开发过程中需用 mlkit_scanner 实现相机预览、条码识别、扫描区域控制、变焦、闪光灯控制与相机切换的能力。

## 需求场景
开发过程中需要用到三方库 mlkit_scanner，但该库未做鸿蒙化适配，为此需要做 mlkit_scanner 鸿蒙化适配，提供 mlkit_scanner SDK，提供相机预览、条码识别、扫描区域控制、变焦、闪光灯控制与相机切换能力，适用于在 Flutter 应用中集成扫码识别与预览交互的场景。

## 可选场景
- 可选：支持在初始化预览时传入 ScannerParameters，配置初始缩放、初始相机与初始裁剪区域。
- 可选：支持在扫描过程中动态调整识别轮询间隔 delay，控制识别频率与资源占用。
- 可选：支持通过 setZoom 设置 0~1 范围内的相机缩放比例。
- 可选：支持通过 setCropAreaMethod 按预览相对比例设置识别区域。
- 可选：支持通过 getIosAvailableCameras 获取当前设备可用的 OHOS 相机列表，再通过 setIosCamera 切换指定相机。

## 逆向场景
- 当扫描进行中调用 cancelScan 时，预期停止识别流程但保持相机预览继续显示。
- 当相机预览已暂停时调用 resumeCameraMethod，预期恢复预览并继续先前已启动的识别流程。
- 当组件销毁或调用 dispose 时，预期释放相机与识别资源，后续不再回调识别结果。

## 边界场景
- 当 setZoom 传入 0 或 1 时，预期分别表现为最小与最大缩放比例。
- 当 setScanDelay 传入 0 时，预期关闭额外轮询间隔并按帧持续识别；传入大于 0 的值时按毫秒间隔触发识别。
- 当 setCropAreaMethod 传入超出 CameraPreview 范围的裁剪区域时，预期不产生识别结果而不崩溃。
- 当 updateConstraints 传入新的宽高后，预期预览尺寸与裁剪区域重新按新约束生效。

## 异常场景
- 当未先调用 initCameraPreview 就调用 startScan、resumeCameraMethod、setZoom 或 setCropAreaMethod 时，预期返回平台异常而不崩溃。
- 当设备不支持闪光灯时调用 toggleFlash，预期返回异常信息并保持应用稳定。
- 当相机权限未授予或设备相机初始化失败时调用 initCameraPreview，预期返回初始化失败信息并中止预览创建。

## 功能测试点
- 支持初始化 OpenHarmony 相机预览，并在初始化时应用初始扫描参数。
- 支持释放相机预览与扫描资源，并在释放后停止原生回调。
- 支持切换设备闪光灯，并向 Dart 层同步手电筒状态变化事件。
- 支持启动条码识别，并按 delay 毫秒间隔返回识别结果。
- 支持取消条码识别流程，并保持相机预览持续显示。
- 支持动态设置识别轮询间隔 delay。
- 支持通过 onScanResult 回调返回 raw_value、display_value、format、value_type 等识别字段。
- 支持根据 Flutter 侧布局变化更新预览宽高约束。
- 支持暂停与恢复相机预览，并在恢复后延续已启动的识别流程。
- 支持设置 0~1 范围内的相机缩放比例。
- 支持按相对比例设置识别裁剪区域；当裁剪区域超出预览范围时不产生识别结果。
- 支持查询当前设备可用的 OHOS 相机列表。
- 支持按相机位置与类型切换 OHOS 相机。

## API 表格
| 序号 | 接口名称 | 接口功能 | 备注 |
|------|----------|----------|------|
| 1 | initCameraPreview | 初始化相机预览并应用初始扫描参数 | initialArguments：可选，支持传入初始缩放、初始相机、初始裁剪区域 |
| 2 | dispose | 释放相机与扫描资源 | 无 |
| 3 | toggleFlash | 切换设备闪光灯状态 | 无 |
| 4 | startScan | 启动条码识别流程 | type：RecognitionType；delay：识别轮询间隔，单位毫秒 |
| 5 | cancelScan | 取消识别流程并保持预览 | 无 |
| 6 | setScanDelay | 设置扫描轮询间隔 | delay：识别轮询间隔，单位毫秒 |
| 7 | onScanResult | 回传条码识别结果事件 | raw_value/display_value/format/value_type：识别结果字段 |
| 8 | changeTorchStateMethod | 回传闪光灯状态变化事件 | bool：当前闪光灯状态 |
| 9 | updateConstraints | 更新预览区域宽高约束 | width：预览宽度；height：预览高度 |
| 10 | pauseCameraMethod | 暂停相机预览与识别流程 | 无 |
| 11 | resumeCameraMethod | 恢复相机预览与识别流程 | 无 |
| 12 | setZoom | 设置相机缩放比例 | value：double，范围 0~1 |
| 13 | setCropAreaMethod | 设置识别裁剪区域 | rect：CropRect，包含 scaleWidth、scaleHeight、offsetX、offsetY |
| 14 | getIosAvailableCameras | 获取当前设备可用的 OHOS 相机列表 | 无 |
| 15 | setIosCamera | 按位置与类型切换 OHOS 相机 | position：OhosCameraPosition；type：OhosCameraType |