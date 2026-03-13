/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import { common } from "@kit.AbilityKit";
import {
  MethodCall,
  MethodResult,
  PlatformView,
  MethodCallHandler,
  Log,
  MethodChannel,
  BinaryMessenger
} from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { CameraPreviewComponent, getCurrentCameraPreview } from "./CameraPreviewComponent";
import { MLKitScannerOptions } from "./MLKitScannerOptions";
import { CropRect, OhosScannerParameters, PluginConstants, PluginError } from "./PluginConstants";
import { customScan, scanBarcode, scanCore } from "@kit.ScanKit";

const TAG: string = 'MlkitScannerPlugin_FlutterMLKitScannerView';

let flutterMLKitScannerView: MLKitScannerView;

export class MLKitScannerView extends PlatformView implements MethodCallHandler, MethodCallHandler {
  private context: common.Context | null = null;
  public channel: MethodChannel | null = null;
  private viewId: number = 0;
  public isCameraInitialized: boolean = false;
  private surfaceId: string = '';
  private previewSize: Size = { width: 100, height: 100 };
  private scanDelayMs: number = 100;
  public isScan: boolean = false;
  public userGrant: boolean = false;
  public methodResult: MethodResult | null = null;
  public initialScannerParameters: OhosScannerParameters | null = null;

  constructor(context: common.Context, messenger: BinaryMessenger, viewId: number, args: ESObject) {
    super();
    this.context = context;
    this.viewId = viewId;
    this.channel = new MethodChannel(messenger, PluginConstants.channelName);
    this.channel.setMethodCallHandler(this);
    this.previewSize = this.parsePreviewSize(args);
    flutterMLKitScannerView = this;
    Log.i(TAG, 'CameraPreviewView constructor created with viewId: ' + viewId + ', previewSize=' +
    JSON.stringify(this.previewSize));
  }

  public getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(CameraPreviewBuilder);
  }

  setSurfaceId(surfaceId: string) {
    this.surfaceId = surfaceId;
    Log.i(TAG, 'setSurfaceId success: ' + this.surfaceId);
  }


  setCameraInitialized(isCameraInitialized: boolean) {
    this.isCameraInitialized = isCameraInitialized;
  }

  private normalizeArgs(rawArgs: ESObject): Record<string, Object> {
    if (!rawArgs || typeof rawArgs !== 'object') {
      return {};
    }

    if (typeof rawArgs.forEach === 'function') {
      const args: Record<string, Object> = {};
      rawArgs.forEach((value: ESObject, key: string) => {
        Log.i(TAG, `Map Key: ${key}, Value: ${value}, Type: ${typeof value}`);
        args[key] = this.recursivelyConvertMap(value);
      });
      return args;
    }

    return this.recursivelyConvertMap(rawArgs) as Record<string, Object>;
  }

  private parsePreviewSize(args: ESObject): Size {
    const defaultSize: Size = { width: 100, height: 100 };
    const normalizedArgs = this.normalizeArgs(args);
    if (Object.keys(normalizedArgs).length === 0) {
      return defaultSize;
    }

    const width = Number(normalizedArgs['width']);
    const height = Number(normalizedArgs['height']);
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return defaultSize;
    }
    return {
      width: Math.round(width),
      height: Math.round(height),
    };
  }

  private convertArgsToRecord(rawArgsMap: ESObject): Record<string, Object> {
    return this.normalizeArgs(rawArgsMap);
  }

  private async waitDelay(ms: number): Promise<void> {
    if (ms <= 0) {
      return;
    }
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }

  private async runScanLoop(viewControl: customScan.ViewControl): Promise<void> {
    while (this.isScan) {
      const data: scanBarcode.ScanResult[] = await customScan.start(viewControl);
      Log.i(TAG, 'customScan.start data: ' + JSON.stringify(data));
      if (data && data.length > 0) {
        const firstResult = data[0];
        const rawValue = String(firstResult['originalValue'] ?? '');
        if (rawValue) {
          this.channel?.invokeMethod(PluginConstants.scanResultMethod, {
            raw_value: rawValue,
            display_value: rawValue,
            format: Number(firstResult['scanType']) || 0,
            value_type: 0,
          });
        } else {
          Log.i(TAG, 'customScan.start first result has empty originalValue');
        }
      } else {
        Log.i(TAG, 'customScan.start completed with empty results');
      }

      if (!this.isScan) {
        break;
      }
      await this.waitDelay(this.scanDelayMs);
    }
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case "initCameraPreview":
        this.initCameraPreview(call, result);
        break;
      case "dispose":
        this.disposeHandle(result);
        break;
      case "toggleFlash":
        this.toggleFlash(result);
        break;
      case "startScan":
        await this.startScan(call, result);
        break;
      case "cancelScan":
        this.cancelScan(result);
        break;
      case "setScanDelay":
        this.setScanDelay(call, result);
        break;
      case "updateConstraints":
        this.updateConstraints(call, result);
        break;
      case "pauseCameraMethod":
        this.pauseCamera(result);
        break;
      case "resumeCameraMethod":
        this.resumeCamera(result);
        break;
      case "setZoom":
        this.setZoom(call, result);
        break;
      case "setCropAreaMethod":
        this.setCropArea(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private async initCameraPreview(call: MethodCall, result: MethodResult): Promise<void> {
    // 初始化相机预览
    if (!this.context) {
      result.error(PluginError.InitCameraError, 'context is undefined!', null);
      return;
    }

    if (this.isCameraInitialized) {
      result.success(true);
      return;
    }
    this.methodResult = result;

    const rawArgsMap: ESObject = call.args as ESObject;
    const args = this.convertArgsToRecord(rawArgsMap);
    Log.i(TAG, 'initCameraPreview args ' + JSON.stringify(args));
    this.initialScannerParameters = (args && (args as OhosScannerParameters)) || null;
  }

  private recursivelyConvertMap(obj: ESObject): Object {
    if (obj === null || typeof obj !== 'object') {
      return obj;
    }

    // 先检查是否是数组（数组也有 forEach 方法，必须先判断）
    if (Array.isArray(obj)) {
      const result: Object[] = [];
      for (let i = 0; i < obj.length; i++) {
        result.push(this.recursivelyConvertMap(obj[i]));
      }
      return result;
    }

    // 检查是否是 Map 对象（有 forEach 方法但不是数组）
    if (typeof (obj as ESObject).forEach === 'function') {
      const converted: Record<string, Object> = {};
      (obj as ESObject).forEach((value: ESObject, key: string) => {
        converted[key] = this.recursivelyConvertMap(value);
      });
      return converted;
    }

    // 如果是普通对象
    const converted: Record<string, Object> = {};
    const keys = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      converted[key] = this.recursivelyConvertMap(obj[key]);
    }
    return converted;
  }

  private disposeHandle(result: MethodResult): void {
    // 释放相机资源
    Log.i(TAG, "dispose called");
    this.isCameraInitialized = false;
    this.isScan = false;
    result.success(true);
  }

  dispose() {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
    }
  }

  private toggleFlash(result: MethodResult): void {
    // 切换闪光灯
    Log.i(TAG, "toggleFlash called");
    if (!this.isCameraInitialized) {
      result.error(PluginError.CameraIsNotInitialized, "Camera is not initialized", null);
      return;
    }
    result.success(true);
  }

  private async startScan(call: MethodCall, result: MethodResult): Promise<void> {
    // 开始扫描
    const comp = getCurrentCameraPreview();
    const actualSurfaceId = this.surfaceId || comp?.getSurfaceId() || '';
    const args = this.convertArgsToRecord(call.args as ESObject);
    let options: MLKitScannerOptions;
    try {
      options = MLKitScannerOptions.fromMap(args);
    } catch (error) {
      const errMsg = 'Invalid startScan arguments: ' + JSON.stringify(error);
      Log.e(TAG, errMsg);
      result.error(PluginError.InvalidArguments, errMsg, null);
      return;
    }

    this.scanDelayMs = options.periodMs;
    Log.i(TAG, "startScan called cached surfaceId: " + this.surfaceId + ', actual surfaceId: ' + actualSurfaceId);
    Log.i(TAG, 'startScan state isCameraInitialized=' + this.isCameraInitialized + ', isScan=' + this.isScan +
      ', scanDelayMs=' + this.scanDelayMs + ', recognizeType=' + options.recognizeType);
    if (!this.isCameraInitialized) {
      Log.e(TAG, 'startScan aborted: camera is not initialized');
      result.error(PluginError.CameraIsNotInitialized, "Camera is not initialized", null);
      return;
    }
    if (this.isScan) {
      Log.i(TAG, 'startScan skipped: scan already active');
      result.success(true);
      return
    }
    if (!actualSurfaceId) {
      Log.e(TAG, 'startScan aborted: surfaceId is empty');
      result.error(PluginError.CameraIsNotInitialized, 'Camera surface is not ready', null);
      return;
    }

    try {
      Log.i(TAG,
        'startScan preparing viewControl width=' + this.previewSize.width + ', height=' + this.previewSize.height);
      const viewControl: customScan.ViewControl = {
        width: this.previewSize.width,
        height: this.previewSize.height,
        surfaceId: actualSurfaceId
      };
      Log.i(TAG, 'startScan viewControl ready surfaceId=' + actualSurfaceId);

      this.surfaceId = actualSurfaceId;
      this.isScan = true
      if (comp) {
        comp.setScanActive(true);
      }

      Log.i(TAG, 'startScan invoking customScan.start');
      await customScan.stop();
      result.success(true);
      this.runScanLoop(viewControl).catch((error: BusinessError) => {
        this.isScan = false;
        comp?.setScanActive(false);
        Log.e(TAG, 'Catch: startScan loop error = ' + JSON.stringify(error));
      });
      return;
    } catch (error) {
      this.isScan = false;
      comp?.setScanActive(false);
      Log.e(TAG, 'Catch: startScan error = ' + JSON.stringify(error));
      result.error(PluginError.InitCameraError, 'customScan.start failed', JSON.stringify(error));
      return;
    }
  }

  private cancelScan(result: MethodResult): void {
    // 取消扫描
    Log.i(TAG, "cancelScan called");
    this.isScan = false;
    customScan.stop();
    const comp = getCurrentCameraPreview();
    if (comp) {
      comp.setScanActive(false);
    }
    result.success(true);
  }

  private setScanDelay(call: MethodCall, result: MethodResult): void {
    // 设置扫描延迟
    const delay: ESObject = call.args as ESObject;
    if (typeof delay !== 'number' || !Number.isFinite(delay)) {
      result.error(PluginError.InvalidArguments, 'Invalid argument passed, Number type is expected', null);
      return;
    }
    if (delay < 0) {
      result.error(PluginError.InvalidArguments, 'Invalid argument passed, value must be >= 0', null);
      return;
    }
    // Android 端的分析器周期是通过设置扫描延迟来实现的，这个周期控制了连续扫描之间的时间间隔。
    // 通过 setScanDelay 方法，Flutter 端可以动态调整这个间隔，以适应不同的使用场景。
    // 例如，在需要快速连续扫描时，可以将延迟设置为较小的值；在需要减少设备负载或避免重复扫描时，可以将延迟设置为较大的值。
    this.scanDelayMs = Math.trunc(delay);
    Log.i(TAG, "setScanDelay called, scanDelayMs=" + this.scanDelayMs);
    result.success(true);
  }

  private updateConstraints(call: MethodCall, result: MethodResult): void {
    // 更新约束
    Log.i(TAG, "updateConstraints called");
    result.success(true);
  }

  private pauseCamera(result: MethodResult): void {
    // 暂停相机
    Log.i(TAG, "pauseCamera called");
    result.success(true);
  }

  public resumeCamera(result: MethodResult): void {
    // 恢复相机
    Log.i(TAG, "resumeCamera called");
    if (!this.isCameraInitialized) {
      result.error(PluginError.CameraIsNotInitialized, "Camera is not initialized", null);
      return;
    }
    result.success(true);
  }

  private setZoom(call: MethodCall, result: MethodResult): void {
    // 设置缩放
    Log.i(TAG, "setZoom called");
    if (!this.isCameraInitialized) {
      result.error(PluginError.CameraIsNotInitialized, "Camera is not initialized", null);
      return;
    }
    result.success(true);
  }

  private setCropArea(call: MethodCall, result: MethodResult): void {
    // 设置扫描区域
    Log.i(TAG, "setCropArea called");
    const rawArgsMap: ESObject = call.args as ESObject;
    const args = this.convertArgsToRecord(rawArgsMap);
    const rect: CropRect = {
      scaleWidth: Number(args['scaleWidth']) || 1,
      scaleHeight: Number(args['scaleHeight']) || 1,
      offsetX: Number(args['offsetX']) || 0,
      offsetY: Number(args['offsetY']) || 0,
    };
    this.initialScannerParameters = this.initialScannerParameters || {};
    this.initialScannerParameters.initialCropRect = rect;
    const comp = getCurrentCameraPreview();
    if (comp) {
      comp.applyCropRect(rect);
    }

    result.success(true);
  }

  private getAvailableCameras(result: MethodResult): void {
    // 获取可用相机
    Log.i(TAG, "getAvailableCameras called");
    result.success([]);
  }

  private setCamera(call: MethodCall, result: MethodResult): void {
    // 设置相机
    Log.i(TAG, "setCamera called");
    result.success(true);
  }
}

@Builder
function CameraPreviewBuilder(params: Params): void {
  CameraPreviewComponent({
    flutterMLKitScannerView: flutterMLKitScannerView,
  });
}

export function getCurrentMLKitScannerView(): MLKitScannerView {
  return flutterMLKitScannerView;
}