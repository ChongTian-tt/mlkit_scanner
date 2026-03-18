/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
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
  BinaryMessenger,
} from "@ohos/flutter_ohos";
import { Callback, BusinessError, AsyncCallback } from '@kit.BasicServicesKit';
import { Params } from "@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView";
import { CameraPreviewComponent, getCurrentCameraPreviewComponent } from "./CameraPreviewComponent";
import { MLKitScannerOptions } from "./MLKitScannerOptions";
import { CropRect, OhosScannerParameters, PluginConstants, PluginError } from "./PluginConstants";
import { customScan, detectBarcode, scanBarcode, scanCore } from "@kit.ScanKit";
import { JSON } from "@kit.ArkTS";

const TAG: string = "MlkitScannerPlugin_FlutterMLKitScannerView";

interface CropPosition {
  left: number;
  top: number;
  width: number;
  height: number;
}

// 预览状态机
interface PreviewState {
  isRunning: boolean;

  // 把用户主动 pause 和宿主切后台区分开
  isPausedByUser: boolean;
}

interface DecodeState {
  inFlight: boolean;
  lastAttemptAtMs: number;
  scanSessionStartedAtMs: number;
  lastEmittedRawValue: string;
  lastEmittedAtMs: number;
  lastDecodedRawValue: string;
}

let flutterMLKitScannerView: MLKitScannerView;

export class MLKitScannerView extends PlatformView implements MethodCallHandler {
  private context: common.Context | null = null;
  private viewId: number = 0;
  private surfaceId: string = "";
  private originalValue: string = "";
  public channel: MethodChannel | null = null;
  public methodResult: MethodResult | null = null;
  public initialScannerParameters: OhosScannerParameters | null = null;
  public isCameraInitialized: boolean = false;
  public userGrant: boolean = false;
  public flashLightStatus: boolean = false;
  private flashLightStatusBeforePause: boolean = false;
  // isScan 表示当前是否处于扫描状态
  public isScan: boolean = false;
  public isProcessingResult: boolean = false;
  // previewSize 是预览的分辨率，扫描器会基于这个分辨率来配置相机和处理图像数据
  private previewSize: Size = { width: 0, height: 0 };
  private cropPosition: CropPosition = {
    width: 0,
    height: 0,
    left: 0,
    top: 0
  };
  // scanDelayMs 是扫描延迟，单位是毫秒
  private scanDelayMs: number = 100;
  private previewState: PreviewState = {
    isRunning: false, // 预览流是否开启
    isPausedByUser: false, // 是否是用户暂停
  };
  private decodeState: DecodeState = {
    inFlight: false,
    lastAttemptAtMs: 0,
    scanSessionStartedAtMs: 0,
    lastEmittedRawValue: "",
    lastEmittedAtMs: 0,
    lastDecodedRawValue: "",
  };
  private readonly cropBufferRatio: number = 0.1;
  private desiredZoom: number | null = null;
  private focusTimerId: number = -1;
  private resetFocusTimerId: number = -1;
  private yuvFrameHeight: number = 0;
  private scanCallback: AsyncCallback<Array<scanBarcode.ScanResult>> =
    (error: BusinessError, data: scanBarcode.ScanResult[]) => {
      if (error) {
        Log.e(TAG, "scan callback error: " + JSON.stringify(error));
        return;
      }
      Log.i(TAG, "scanCallback success: " + data[0].originalValue);
      // 如果识别到码,
      if (data[0].originalValue) {
        this.originalValue = data[0].originalValue;
      }

      this.handleScanCallback(data);
    }
  // 处理帧
  private frameCallback = (error: BusinessError, scanFrame: customScan.ScanFrame) => {
    if (error) {
      Log.e(TAG, "frame callback error: " + JSON.stringify(error));
      return;
    }
    if (!scanFrame.scanCodeRects?.length) {
      return;
    }
    // 动态获取YUV帧高度
    if (scanFrame.height) {
      this.yuvFrameHeight = scanFrame.height;
    }
    // 转换坐标并检查
    if (this.isScan) {
      const screenRect = this.convertYuvToScreenCoords(scanFrame.scanCodeRects[0]);
      if (this.checkResultInScanBox(screenRect) && this.originalValue) {
        Log.i(TAG, `frameCallback: 检测到二维码位置 - ${JSON.stringify(screenRect)}`);
        this.emitScanResult(this.originalValue);
      }
    }
  }

  /**
   * 检查二维码是否在扫码框内
   */
  private checkResultInScanBox(scanCodeRect: scanBarcode.ScanCodeRect): boolean {
    const cropRect = this.getActiveCropRect();
    // 未设置裁剪框时默认全屏可识别
    if (!cropRect) {
      return true;
    }

    const baseWidth = this.previewSize.width;
    const baseHeight = this.previewSize.height;
    if (baseWidth <= 0 || baseHeight <= 0) {
      return false;
    }

    Log.i(TAG, 'baseWidth: ' + JSON.stringify(baseWidth));
    Log.i(TAG, 'cropRect: ' + JSON.stringify(cropRect));
    Log.i(TAG, 'scanCodeRect: ' + JSON.stringify(scanCodeRect));

    const cropWidth = baseWidth * cropRect.scaleWidth;
    const cropHeight = baseHeight * cropRect.scaleHeight;
    const cropLeft = (baseWidth / 2) * (1 + cropRect.offsetX) - cropWidth / 2;
    const cropTop = (baseHeight / 2) * (1 + cropRect.offsetY) - cropHeight / 2;
    const cropRight = cropLeft + cropWidth;
    const cropBottom = cropTop + cropHeight;

    const codeLeft = Math.min(scanCodeRect.left, scanCodeRect.right);
    const codeRight = Math.max(scanCodeRect.left, scanCodeRect.right);
    const codeTop = Math.min(scanCodeRect.top, scanCodeRect.bottom);
    const codeBottom = Math.max(scanCodeRect.top, scanCodeRect.bottom);
    // 改为边界全包含：二维码四边都必须落在扫描框内才上报
    const inScanBox =
      codeLeft >= cropLeft &&
        codeRight <= cropRight &&
        codeTop >= cropTop &&
        codeBottom <= cropBottom;

    Log.i(
      TAG,
      "checkResultInScanBox code=(" + codeLeft + "," + codeTop + "," + codeRight + "," + codeBottom + ")" +
        ", crop=(" + cropLeft + "," + cropTop + "," + cropRight + "," + cropBottom + ")" +
        ", inScanBox=" + inScanBox,
    );

    return inScanBox;
  }

  /**
   * 将YUV帧坐标转换为屏幕坐标
   */
  private convertYuvToScreenCoords(yuvRect: scanBarcode.ScanCodeRect): scanBarcode.ScanCodeRect {
    if (!this.yuvFrameHeight) {
      return yuvRect;
    }
    const ratio = this.previewSize.width / this.yuvFrameHeight;
    const convertedLeft = (this.yuvFrameHeight - yuvRect.bottom) * ratio;
    const convertedTop = yuvRect.left * ratio;
    const convertedRight = (this.yuvFrameHeight - yuvRect.top) * ratio;
    const convertedBottom = yuvRect.right * ratio;
    return {
      left: Math.round(convertedLeft),
      top: Math.round(convertedTop),
      right: Math.round(convertedRight),
      bottom: Math.round(convertedBottom)
    };
  }

  constructor(context: common.Context, messenger: BinaryMessenger, viewId: number, args: ESObject) {
    super();
    flutterMLKitScannerView = this;
    this.context = context;
    this.viewId = viewId;
    this.channel = new MethodChannel(messenger, PluginConstants.channelName);
    this.channel.setMethodCallHandler(this);

    this.previewSize = this.parsePreviewSize(args);
  }

  public getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(CameraPreviewBuilder);
  }

  setSurfaceId(surfaceId: string) {
    this.surfaceId = surfaceId;
    Log.i(TAG, "setSurfaceId success: " + this.surfaceId);
    this.beginPreviewSession();
    this.startPreview();
  }

  setCameraInitialized(isCameraInitialized: boolean) {
    this.isCameraInitialized = isCameraInitialized;
    if (isCameraInitialized) {
      this.beginPreviewSession();
      this.startPreview();
    }
  }

  private resetDecodeState(): void {
    this.decodeState.inFlight = false;
    this.decodeState.lastAttemptAtMs = 0;
    this.decodeState.scanSessionStartedAtMs = 0;
    this.decodeState.lastEmittedRawValue = "";
    this.decodeState.lastEmittedAtMs = 0;
    this.decodeState.lastDecodedRawValue = "";
  }

  // 开启扫描
  private beginScanSession(): void {
    this.isScan = true;
    getCurrentCameraPreviewComponent()?.setScanActive(true);
  }

  // 取消扫描
  private endScanSession(): void {
    Log.i(TAG, 'endScanSession  ');
    this.isScan = false;
    getCurrentCameraPreviewComponent()?.setScanActive(false);
  }

  // 开启预览流
  public beginPreviewSession(): void {
    this.previewState.isRunning = true;
  }

  // 取消预览流
  private endPreviewSession(): void {
    this.previewState.isRunning = false;
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

  private normalizeArgs(rawArgs: ESObject): Record<string, Object> {
    if (!rawArgs || typeof rawArgs !== "object") {
      return {};
    }

    if (typeof rawArgs.forEach === "function") {
      const args: Record<string, Object> = {};
      rawArgs.forEach((value: ESObject, key: string) => {
        args[key] = this.recursivelyConvertMap(value);
      });
      return args;
    }

    return this.recursivelyConvertMap(rawArgs) as Record<string, Object>;
  }

  // 解析正数尺寸
  private parsePositiveSize(args: Record<string, Object>): Size | null {
    const width = Number(args["width"]);
    const height = Number(args["height"]);
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return null;
    }
    return { width: Math.round(width), height: Math.round(height) };
  }

  private parsePreviewSize(args: ESObject): Size {
    return this.parsePositiveSize(this.normalizeArgs(args)) ?? { width: 376, height: 200 };
  }

  private async waitDelay(): Promise<void> {
    if (this.scanDelayMs <= 0) {
      return;
    }
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), this.scanDelayMs);
    });
  }

  // private getFocusPointForCropCenter(): scanBarcode.Point {
  //   const crop = this.getPreviewCropRect();
  //   const centerX = crop.left + crop.width / 2;
  //   const centerY = crop.top + crop.height / 2;
  //   const focusX = this.clamp(centerY / this.previewSize.height, 0, 1);
  //   const focusY = this.clamp(1 - centerX / this.previewSize.width, 0, 1);
  //   return { x: focusX, y: focusY };
  // }

  // private getFocusPointForZoom(): scanBarcode.Point {
  //   const crop = this.getPreviewCropRect();
  //   const focusTargetX = crop.left + crop.width / 2;
  //   const focusTargetY = crop.top + crop.height * 0.42;
  //   const focusX = this.clamp(focusTargetY / this.previewSize.height, 0, 1);
  //   const focusY = this.clamp(1 - focusTargetX / this.previewSize.width, 0, 1);
  //   return { x: focusX, y: focusY };
  // }


  // private applyInitialFocus(): void {
  // 默认使用系统相机焦点配置，不主动设置焦点。
  // this.clearFocusTimers();
  // this.focusTimerId = setTimeout(() => {
  //   this.focusTimerId = -1;
  //   if (!this.previewState.isRunning) {
  //     return;
  //   }
  //   try {
  //     const point = this.getFocusPointForCropCenter();
  //     customScan.setFocusPoint(point);
  //     Log.i(
  //       TAG,
  //       "setFocusPoint to crop center: x=" + point.x.toFixed(3) + ", y=" + point.y.toFixed(3),
  //     );
  //   } catch (error) {
  //     Log.e(TAG, "setFocusPoint error: " + JSON.stringify(error));
  //   }
  //   this.resetFocusTimerId = setTimeout(() => {
  //     this.resetFocusTimerId = -1;
  //     if (!this.previewState.isRunning) {
  //       return;
  //     }
  //     try {
  //       customScan.resetFocus();
  //       Log.i(TAG, "resetFocus to continuous AF");
  //     } catch (error) {
  //       Log.e(TAG, "resetFocus error: " + JSON.stringify(error));
  //     }
  //   }, 1500) as number;
  // }, 500) as number;
  // }

  private clearFocusTimers(): void {
    if (this.focusTimerId >= 0) {
      clearTimeout(this.focusTimerId);
      this.focusTimerId = -1;
    }
    if (this.resetFocusTimerId >= 0) {
      clearTimeout(this.resetFocusTimerId);
      this.resetFocusTimerId = -1;
    }
  }

  // 暂停预览流，存储闪关灯状态
  private async pausePreviewFlow(): Promise<void> {
    if (!this.previewState.isRunning && !this.isScan) {
      return;
    }
    this.endPreviewSession();
    await customScan.stop();
    await customScan.release();
  }

  // 开启预览流，恢复闪光灯状态
  private resumePreviewFlow(): void {
    Log.i(TAG, 'resumePreviewFlow this.previewState: ' + JSON.stringify(this.previewState));
    if (this.previewState.isRunning) {
      return;
    }
    this.beginPreviewSession();
    // 重新初始化并启动扫描
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: false,
    };
    customScan.init(options);
    customScan.start(this.buildViewControl(), this.scanCallback, this.frameCallback);
  }

  private buildViewControl(): customScan.ViewControl {
    return {
      width: this.previewSize.width,
      height: this.previewSize.height,
      surfaceId: this.surfaceId,
    };
  }

  private getErrorCode(error: Object): number {
    if (!error || typeof error !== "object") {
      return -1;
    }
    const code = Number((error as Record<string, Object>)["code"]);
    // 确保 code 是一个有限的数字，否则返回 -1 作为默认错误码
    return Number.isFinite(code) ? code : -1;
  }

  private getActiveCropRect(): CropRect | null {
    return this.initialScannerParameters?.initialCropRect ?? null;
  }

  private getDecodeOptions(): scanBarcode.ScanOptions {
    return {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: false,
    };
  }

  private handleScanCallback(data: scanBarcode.ScanResult[]): void {
    void data;
    if (!this.isScan) {
      return;
    }
    try {
      customScan.rescan();
    } catch (error) {
      Log.e(TAG, "triggerRescan error: " + JSON.stringify(error));
    }
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }

  private getPreviewCropRect(): CropPosition {
    const cropRect = this.getActiveCropRect();
    if (!cropRect) {
      return {
        left: 0,
        top: 0,
        width: this.previewSize.width,
        height: this.previewSize.height,
      };
    }

    const width = this.previewSize.width * cropRect.scaleWidth;
    const height = this.previewSize.height * cropRect.scaleHeight;
    const left = (this.previewSize.width / 2) * (1 + cropRect.offsetX) - width / 2;
    const top = (this.previewSize.height / 2) * (1 + cropRect.offsetY) - height / 2;
    return {
      left: this.clamp(left, 0, this.previewSize.width),
      top: this.clamp(top, 0, this.previewSize.height),
      width: this.clamp(width, 0, this.previewSize.width),
      height: this.clamp(height, 0, this.previewSize.height),
    };
  }

  private alignEvenCropRect(
    left: number,
    top: number,
    right: number,
    bottom: number,
    frameWidth: number,
    frameHeight: number,
  ): CropPosition | null {
    let alignedLeft = Math.max(0, Math.floor(Math.min(left, right)));
    let alignedTop = Math.max(0, Math.floor(Math.min(top, bottom)));
    alignedLeft -= alignedLeft % 2;
    alignedTop -= alignedTop % 2;

    const maxWidth = frameWidth - alignedLeft;
    const maxHeight = frameHeight - alignedTop;
    let width = Math.ceil(Math.abs(right - left));
    let height = Math.ceil(Math.abs(bottom - top));
    width = Math.max(width, 2);
    height = Math.max(height, 2);
    if (width % 2 !== 0) {
      width += 1;
    }
    if (height % 2 !== 0) {
      height += 1;
    }
    width = Math.min(width, maxWidth - (maxWidth % 2));
    height = Math.min(height, maxHeight - (maxHeight % 2));
    if (width < 2 || height < 2) {
      return null;
    }
    return {
      left: alignedLeft,
      top: alignedTop,
      width,
      height
    };
  }

  private getFrameCropRect(frame: customScan.ScanFrame): CropPosition | null {
    const frameWidth = Number(frame["width"]);
    const frameHeight = Number(frame["height"]);
    if (
      !Number.isFinite(frameWidth) ||
        !Number.isFinite(frameHeight) ||
        frameWidth < 2 ||
        frameHeight < 2
    ) {
      return null;
    }

    const previewCrop = this.getPreviewCropRect();
    const rotatedLeft = (previewCrop.left * frameHeight) / this.previewSize.width;
    const rotatedRight =
      ((previewCrop.left + previewCrop.width) * frameHeight) / this.previewSize.width;
    const rotatedTop = (previewCrop.top * frameWidth) / this.previewSize.height;
    const rotatedBottom =
      ((previewCrop.top + previewCrop.height) * frameWidth) / this.previewSize.height;
    let left = rotatedTop;
    let right = rotatedBottom;
    let top = frameHeight - rotatedRight;
    let bottom = frameHeight - rotatedLeft;
    const bufW = (right - left) * this.cropBufferRatio;
    const bufH = (bottom - top) * this.cropBufferRatio;
    left -= bufW;
    top -= bufH;
    right += bufW;
    bottom += bufH;
    return this.alignEvenCropRect(left, top, right, bottom, frameWidth, frameHeight);
  }

  private emitScanResult(result: string): void {
    this.channel?.invokeMethod(PluginConstants.scanResultMethod, {
      raw_value: result,
      display_value: result,
      format: Number(result["scanType"]) || 0,
      value_type: 0,
    });
  }

  private startPreview(): void {
    Log.i(TAG, 'startPreview11111111')
    if (!this.isCameraInitialized || !this.surfaceId || this.previewState.isPausedByUser) {
      return;
    }
    try {
      customScan.start(
        this.buildViewControl(),
        this.scanCallback,
        this.frameCallback,
      );
      Log.i(TAG, "startPreview success");
    } catch (error) {
      Log.e(TAG, "startPreview error " + JSON.stringify(error));
    }
  }

  private async initCameraPreview(call: MethodCall, result: MethodResult): Promise<void> {
    // 初始化相机预览
    if (!this.context) {
      result.error(PluginError.InitCameraError, "context is undefined!", null);
      return;
    }

    if (this.isCameraInitialized) {
      result.success(true);
      return;
    }
    this.methodResult = result;

    const rawArgsMap: ESObject = call.args as ESObject;
    const args = this.normalizeArgs(rawArgsMap);
    Log.i(TAG, "initCameraPreview args " + JSON.stringify(args));
    this.initialScannerParameters = (args && (args as OhosScannerParameters)) || null;

    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      comp.onInitCameraPreviewRequested();
    }
  }

  private recursivelyConvertMap(obj: ESObject): Object {
    if (obj === null || typeof obj !== "object") {
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
    if (typeof (obj as ESObject).forEach === "function") {
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
    this.endScanSession();
    this.endPreviewSession();
    this.resetDecodeState();
    this.desiredZoom = null;
    this.flashLightStatusBeforePause = false;
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
    try {
      this.flashLightStatus = this.getFlashLightStatusSafely();
      // 根据当前闪光灯状态，选择开启或关闭闪光灯
      if (this.flashLightStatus) {
        this.closeFlashLightSafely();
        result.success(true);
      } else {
        this.openFlashLightSafely();
        result.success(true);
      }
    } catch (error) {
      Log.e(TAG, `Failed to getFlashLightStatus. Code: ${error.code}, message: ${error.message}`);
    }
  }

  // 开启扫描，开启预览流
  private async startScan(call: MethodCall, result: MethodResult): Promise<void> {
    Log.i(TAG, "cancelScan called this.isScan: " + this.isScan + ', this.previewState.isRunning: ' + this.previewState.isRunning);
    const args = this.normalizeArgs(call.args as ESObject);
    let options: MLKitScannerOptions;
    try {
      options = MLKitScannerOptions.fromMap(args);
    } catch (error) {
      result.error(
        PluginError.InvalidArguments,
        "Invalid startScan arguments: " + JSON.stringify(error),
        null,
      );
      return;
    }
    this.scanDelayMs = options.periodMs;

    if (!this.isCameraInitialized) {
      result.error(PluginError.CameraIsNotInitialized, "Camera is not initialized", null);
      return;
    }
    if (!this.surfaceId) {
      result.error(PluginError.CameraIsNotInitialized, "Camera surface is not ready", null);
      return;
    }
    // 处于扫描状态 或者 用户触发了pause时不做处理
    if (this.isScan || this.previewState.isPausedByUser) {
      result.success(true);
      return;
    }

    if (this.previewState.isRunning) {
      await customScan.stop();
    }

    await this.waitDelay();
    // 开启扫描，开启预览流
    this.beginScanSession();
    this.beginPreviewSession();
    this.startPreview();
    result.success(true);
  }

  // 取消扫描，保持预览
  private async cancelScan(result: MethodResult): Promise<void> {
    Log.i(TAG, "cancelScan called this.isScan: " + this.isScan + ', this.previewState.isRunning: ' + this.previewState.isRunning);
    try {
      if (this.isScan || this.previewState.isRunning) {
        if (this.previewState.isPausedByUser) {
          //   只停止扫描的状态
          this.endScanSession();
          return;
        }
        // 停止扫描状态然后再次开启预览流
        Log.i(TAG, 'cancelScan: 正在停止扫描...');
        await customScan.stop();
        await customScan.release();
        this.endScanSession();
        // 再次开启预览流
        this.beginPreviewSession();
        this.startPreview();
        result.success(true);
      }
    } catch (error) {
      Log.e(TAG, `cancelScan error - ${error}`);
      this.endScanSession();
    }
  }

  private setScanDelay(call: MethodCall, result: MethodResult): void {
    // 设置扫描延迟
    const delay: ESObject = call.args as ESObject;
    if (typeof delay !== "number" || !Number.isFinite(delay)) {
      result.error(
        PluginError.InvalidArguments,
        "Invalid argument passed, Number type is expected",
        null,
      );
      return;
    }
    if (delay < 0) {
      result.error(
        PluginError.InvalidArguments,
        "Invalid argument passed, value must be >= 0",
        null,
      );
      return;
    }
    // 将扫描延迟设置为传入值的整数部分
    this.scanDelayMs = Math.trunc(delay);
    Log.i(TAG, "setScanDelay called, scanDelayMs=" + this.scanDelayMs);
    result.success(true);
  }

  // 更新预览约束,如果新的预览尺寸与当前相同则直接返回成功,否则更新预览尺寸并应用新的约束,如果相机未初始化则返回错误
  private updateConstraints(call: MethodCall, result: MethodResult): void {
    const args = this.normalizeArgs(call.args as ESObject);
    const newSize = this.parsePositiveSize(args);
    if (!newSize) {
      result.error(
        PluginError.InvalidArguments,
        "Invalid constraints, positive width/height expected",
        null,
      );
      return;
    }
    if (this.previewSize.width === newSize.width && this.previewSize.height === newSize.height) {
      result.success(true);
      return;
    }

    this.previewSize = newSize;
    const comp = getCurrentCameraPreviewComponent();
    if (comp && this.initialScannerParameters?.initialCropRect) {
      comp.applyCropRect();
    }
    Log.i(TAG, "updateConstraints called, previewSize=" + JSON.stringify(this.previewSize));
    result.success(true);
  }

  private async pauseCamera(result: MethodResult): Promise<void> {
    // 暂停相机
    Log.i(TAG, "pauseCamera called");
    if (this.previewState.isPausedByUser) {
      result.success(true);
      return;
    }
    this.flashLightStatusBeforePause = this.getFlashLightStatusSafely();
    if (this.flashLightStatusBeforePause) {
      this.closeFlashLightSafely();
    }
    this.previewState.isPausedByUser = true;
    await this.pausePreviewFlow();
    result.success(true);
  }

  public resumeCamera(result: MethodResult): void {
    // 恢复相机
    Log.i(TAG, "resumeCamera called");
    if (!this.isCameraInitialized) {
      result.error(PluginError.CameraIsNotInitialized, "Camera is not initialized", null);
      return;
    }
    if (!this.previewState.isPausedByUser) {
      result.success(true);
      return;
    }
    this.previewState.isPausedByUser = false;
    this.resumePreviewFlow();
    if (this.flashLightStatusBeforePause) {
      this.openFlashLightSafely();
    }
    this.flashLightStatusBeforePause = false;
    result.success(true);
  }

  private getFlashLightStatusSafely(): boolean {
    try {
      this.flashLightStatus = customScan.getFlashLightStatus();
    } catch (error) {
      Log.e(TAG, `Failed to getFlashLightStatus. Code: ${error.code}, message: ${error.message}`);
    }
    return this.flashLightStatus;
  }

  private closeFlashLightSafely(): void {
    try {
      customScan.closeFlashLight();
      this.flashLightStatus = false;
      Log.i(TAG, "closeFlashLight success");
    } catch (error) {
      Log.e(TAG, `Failed to closeFlashLight. Code: ${error.code}, message: ${error.message}`);
    }
  }

  private openFlashLightSafely(): void {
    try {
      customScan.openFlashLight();
      this.flashLightStatus = true;
      Log.i(TAG, "openFlashLight success");
    } catch (error) {
      Log.e(TAG, `Failed to openFlashLight. Code: ${error.code}, message: ${error.message}`);
    }
  }

  public onHostBackground(): void {
    if (!this.isCameraInitialized) {
      return;
    }
    Log.i(TAG, "onHostBackground called");
    this.pausePreviewFlow();
  }

  public onHostForeground(): void {
    if (!this.isCameraInitialized || !this.surfaceId) {
      return;
    }
    Log.i(TAG, "onHostForeground called this.previewState.isPausedByUser: " + this.previewState.isPausedByUser);
    if (!this.previewState.isPausedByUser) {
      this.resumePreviewFlow();
    }
  }

  private setZoom(call: MethodCall, result: MethodResult): void {
    // 设置缩放
    Log.i(TAG, "setZoom called");
    // if (!this.isCameraInitialized) {
    //   result.error(
    //     PluginError.CameraIsNotInitialized,
    //     'You need to invoke the "initCameraPreview" method before using zoom',
    //     null,
    //   );
    //   return;
    // }
    // const zoom = this.parseZoomValue(call.args as ESObject);
    // if (zoom === null || zoom < 0 || zoom > 1) {
    //   result.error(
    //     PluginError.InvalidArguments,
    //     "Invalid argument passed, Number type is expected with value in range 0...1",
    //     null,
    //   );
    //   Log.e(TAG, "setZoom invalid argument: " + JSON.stringify(call.args));
    //   return;
    // }
    //
    // this.desiredZoom = zoom;
    // Log.i(TAG, "setZoom ignored, use default camera zoom configuration");
    // if (!this.previewState.isRunning) {
    //   Log.i(TAG, "setZoom deferred until preview starts, zoom=" + zoom);
    //   result.success(true);
    //   return;
    // }
    //
    // if (this.applyDesiredZoomIfPossible()) {
    //   result.success(true);
    //   return;
    // }
    //
    // result.error(PluginError.DeviceHasNotZoom, "Zoom is not supported on this device", null);
  }

  // 设置扫描区域
  private setCropArea(call: MethodCall, result: MethodResult): void {
    Log.i(TAG, "setCropArea called");
    const rawArgsMap: ESObject = call.args as ESObject;
    const args = this.normalizeArgs(rawArgsMap);
    const rect: CropRect = {
      scaleWidth: Number(args["scaleWidth"]) || 1,
      scaleHeight: Number(args["scaleHeight"]) || 1,
      offsetX: Number(args["offsetX"]) || 0,
      offsetY: Number(args["offsetY"]) || 0,
    };
    this.initialScannerParameters = this.initialScannerParameters || {};
    this.initialScannerParameters.initialCropRect = rect;
    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      comp.applyCropRect();
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
