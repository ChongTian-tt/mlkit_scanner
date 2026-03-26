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
import { common } from '@kit.AbilityKit';
import {
  MethodCall,
  MethodResult,
  PlatformView,
  MethodCallHandler,
  Log,
  MethodChannel,
  BinaryMessenger,
} from '@ohos/flutter_ohos';
import { JSON } from '@kit.ArkTS';
import { camera } from '@kit.CameraKit';
import { scanBarcode } from '@kit.ScanKit';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { CameraPreviewComponent, getCurrentCameraPreviewComponent } from './CameraPreviewComponent';
import { CameraService } from './camera/CameraService';
import { MLKitScannerOptions } from './MLKitScannerOptions';
import {
  CropRect,
  OhosInitialCamera,
  OhosScannerParameters,
  PluginConstants,
  PluginError,
  PreviewState,
  OhosCameraItem,
  ScanRectLike
} from './PluginConstants';

const TAG: string = '[MLKitScannerView:]';

let flutterMLKitScannerView: MLKitScannerView;

export class MLKitScannerView extends PlatformView implements MethodCallHandler {
  private context: common.Context | null = null;
  private surfaceId: string = '';
  private originalValue: string = '';
  public channel: MethodChannel | null = null;
  public methodResult: MethodResult | null = null;
  public initialScannerParameters: OhosScannerParameters | null = null;
  public isCameraInitialized: boolean = false;
  public userGrant: boolean = false;
  public flashLightStatus: boolean = false;
  public flashLightStatusBeforePause: boolean = false;
  public isScan: boolean = false;
  // 预览的分辨率，扫描器会基于这个分辨率来配置相机和处理图像数据（已按 ScanKit 支持宽高比适配）
  private previewSize: Size = { width: 0, height: 0 };
  // 容器原始尺寸（Flutter 约束 / onAreaChange 原生 vp），用于居中预览
  private containerSize: Size = { width: 0, height: 0 };
  // 扫描延迟，单位是毫秒
  private scanDelayMs: number = 100;
  /**
   * 预览缓冲为竖屏 9:16，禁止用横向比例以免拉变形。
   * Cover：在不变形前提下等比放大直至铺满宿主，超出部分由 Stack clip 裁掉（等同 CameraView center crop）。
   */
  private static readonly PREVIEW_RATIO_W: number = 9;
  private static readonly PREVIEW_RATIO_H: number = 16;
  private previewState: PreviewState = {
    isRunning: false, // 预览流是否开启
    isPausedByUser: false, // 是否是用户暂停
  };
  private desiredZoom: number | null = null;
  private lastHostLayoutW: number = 0;
  private lastHostLayoutH: number = 0;
  private disposePromise: Promise<void> | null = null;
  private scanDelayTimerId: number = -1;
  private isDelayed: boolean = false;
  private yuvFrameHeight: number = 0;
  private selectedCameraPositionCode: number = 1;
  private selectedCameraTypeCode: number = 0;
  private selectedCameraId: string = '';
  private cameraService: CameraService | null = null;
  private isFrameListenerBound: boolean = false;
  private isPreviewStarting: boolean = false;

  constructor(context: common.Context, messenger: BinaryMessenger, viewId: number, args: ESObject) {
    super();
    flutterMLKitScannerView = this;
    this.context = context;
    this.channel = new MethodChannel(messenger, PluginConstants.channelName);
    this.channel.setMethodCallHandler(this);

    this.previewSize = this.parsePreviewSize(args);
    this.cameraService = this.createCameraService();
  }

  private createCameraService(): CameraService | null {
    if (!this.context) {
      return null;
    }
    const ohosContext = this.context as ESObject as Context;
    return new CameraService(
      ohosContext,
      () => this.flashLightStatusBeforePause,
      (status: boolean) => {
        this.flashLightStatusBeforePause = status;
      },
    );
  }

  private getCameraService(): CameraService | null {
    if (!this.cameraService) {
      this.cameraService = this.createCameraService();
    }
    return this.cameraService;
  }

  private extractScanRect(result: scanBarcode.ScanResult): ScanRectLike | null {
    const rec = result as ESObject as Record<string, Object>;
    const candidates: Array<Object | undefined> = [
      rec['scanCodeRect'],
      rec['scanRect'],
      rec['borderRect'],
    ];
    for (const item of candidates) {
      if (!item || typeof item !== 'object') {
        continue;
      }
      const rect = item as Record<string, Object>;
      const left = Number(rect['left']);
      const top = Number(rect['top']);
      const right = Number(rect['right']);
      const bottom = Number(rect['bottom']);
      if ([left, top, right, bottom].every((n) => Number.isFinite(n))) {
        return {
          left,
          top,
          right,
          bottom
        } as ScanRectLike;
      }
    }
    return null;
  }

  private fallbackCenterRect(): ScanRectLike {
    const w = this.previewSize.width > 0 ? this.previewSize.width : this.containerSize.width;
    const h = this.previewSize.height > 0 ? this.previewSize.height : this.containerSize.height;
    const left = Math.round(w * 0.35);
    const top = Math.round(h * 0.35);
    const right = Math.round(w * 0.65);
    const bottom = Math.round(h * 0.65);
    return {
      left,
      top,
      right,
      bottom
    } as ScanRectLike;
  }

  private onFrameResult(result: scanBarcode.ScanResult): void {
    if (!this.isScan || this.isDelayed) {
      return;
    }
    if (!result.originalValue) {
      return;
    }

    this.originalValue = result.originalValue;
    const resultMap = result as ESObject as Record<string, Object>;
    const frameHeight = Number(resultMap['frameHeight']);
    if (Number.isFinite(frameHeight) && frameHeight > 0) {
      this.yuvFrameHeight = Math.round(frameHeight);
    }
    const rectLikeRaw = this.extractScanRect(result);
    const rectLike = rectLikeRaw ?? this.fallbackCenterRect();
    const scanRect: scanBarcode.ScanCodeRect = {
      left: Math.round(rectLike.left),
      top: Math.round(rectLike.top),
      right: Math.round(rectLike.right),
      bottom: Math.round(rectLike.bottom),
    };
    const matchedByRawRect = rectLikeRaw ? this.checkResultInScanBox(scanRect) : false;
    const convertedScanRect = rectLikeRaw ? this.convertYuvToScreenCoords(scanRect) : scanRect;
    const matchedByConvertedRect = rectLikeRaw ? this.checkResultInScanBox(convertedScanRect) : false;
    const fallbackRect = this.fallbackCenterRect();
    const matchedByFallback = !rectLikeRaw && this.checkResultInScanBox({
      left: Math.round(fallbackRect.left),
      top: Math.round(fallbackRect.top),
      right: Math.round(fallbackRect.right),
      bottom: Math.round(fallbackRect.bottom),
    });

    if (matchedByRawRect || matchedByConvertedRect || matchedByFallback) {
      this.emitScanResult(this.originalValue);
      this.originalValue = '';
      this.startScanDelayWindow();
    }
  }

  private bindFrameListener(): void {
    if (this.isFrameListenerBound) {
      return;
    }
    const service = this.getCameraService();
    if (!service) {
      return;
    }
    service.onImageArrival((result: scanBarcode.ScanResult) => {
      this.onFrameResult(result);
    });
    this.isFrameListenerBound = true;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case PluginConstants.initCameraMethod:
        this.initCameraPreview(call, result);
        break;
      case PluginConstants.disposeCameraMethod:
        await this.disposeHandle(result);
        break;
      case PluginConstants.toggleFlashMethod:
        this.toggleFlash(result);
        break;
      case PluginConstants.startScanMethod:
        await this.startScan(call, result);
        break;
      case PluginConstants.cancelScanMethod:
        this.cancelScan(result);
        break;
      case PluginConstants.setScanDelayMethod:
        this.setScanDelay(call, result);
        break;
      case PluginConstants.updateConstraintsMethod:
        this.updateConstraints(call, result);
        break;
      case PluginConstants.pauseCameraMethod:
        this.pauseCamera(result);
        break;
      case PluginConstants.resumeCameraMethod:
        this.resumeCamera(result);
        break;
      case PluginConstants.setZoomMethod:
        this.setZoom(call, result);
        break;
      case PluginConstants.setCropAreaMethod:
        this.setCropArea(call, result);
        break;
      case PluginConstants.getOhosAvailableCamerasMethod:
        this.getOhosAvailableCameras(result);
        break;
      case PluginConstants.setOhosCameraMethod:
        this.setOhosCamera(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  public getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(CameraPreviewBuilder);
  }

  public getPreviewSize(): Size {
    return {
      width: this.previewSize.width,
      height: this.previewSize.height,
    };
  }

  public getContainerSize(): Size {
    return {
      width: this.containerSize.width,
      height: this.containerSize.height,
    };
  }

  /**
   * 宿主区域变化（onAreaChange，单位 vp）：以原生布局为准，避免 Flutter 与 XComponent 尺寸不一致导致变形
   */
  public onPreviewHostAreaChange(vpWidth: number, vpHeight: number): void {
    const w = Math.round(vpWidth);
    const h = Math.round(vpHeight);
    if (w < 2 || h < 2) {
      return;
    }
    if (w === this.lastHostLayoutW && h === this.lastHostLayoutH) {
      return;
    }
    this.lastHostLayoutW = w;
    this.lastHostLayoutH = h;
    this.containerSize = { width: w, height: h };
    const next = this.calcPreviewSizeAspectCover(w, h);
    const sizeChanged = next.width !== this.previewSize.width || next.height !== this.previewSize.height;
    this.previewSize = next;
    getCurrentCameraPreviewComponent()?.applyCropRect();
    if (sizeChanged && this.surfaceId && this.isCameraInitialized && this.previewState.isRunning &&
      !this.previewState.isPausedByUser) {
      void this.restartPreviewAfterLayoutChange();
    }
  }

  private async restartPreviewAfterLayoutChange(): Promise<void> {
    if (!this.surfaceId || !this.isCameraInitialized) {
      return;
    }
    try {
      const service = this.getCameraService();
      await service?.preFrontRelease(false);
      this.endPreviewSession();
      await this.startPreview();
      this.applyDesiredZoomIfPossible();
    } catch (error) {
      Log.e(TAG, 'restartPreviewAfterLayoutChange error: ' + JSON.stringify(error));
    }
  }

  setSurfaceId(surfaceId: string) {
    this.surfaceId = surfaceId;
    // 异步触发不等待
    void this.startPreview();
  }

  setCameraInitialized(isCameraInitialized: boolean) {
    this.isCameraInitialized = isCameraInitialized;
    if (isCameraInitialized) {
      this.beginPreviewSession();
      this.bindFrameListener();
      void this.startPreview();
    }
  }

  // 开启扫描
  private beginScanSession(): void {
    this.isScan = true;
    getCurrentCameraPreviewComponent()?.setScanActive(true);
  }

  // 取消扫描
  private endScanSession(): void {
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

  // 归一化参数
  private normalizeArgs(rawArgs: ESObject): Record<string, Object> {
    if (!rawArgs || typeof rawArgs !== 'object') {
      return {};
    }

    if (typeof rawArgs.forEach === 'function') {
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
    const width = Number(args['width']);
    const height = Number(args['height']);
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return null;
    }
    return { width: Math.round(width), height: Math.round(height) };
  }

  /**
   * 9:16 等比 Cover：宽或高贴齐宿主，另一维放大后居中裁剪
   */
  private calcPreviewSizeAspectCover(cw: number, ch: number): Size {
    if (cw <= 0 || ch <= 0) {
      return { width: 360, height: 640 };
    }
    const aspect: number = MLKitScannerView.PREVIEW_RATIO_W / MLKitScannerView.PREVIEW_RATIO_H;
    let width: number;
    let height: number;
    if (cw / ch > aspect) {
      width = Math.round(cw);
      height = Math.round((cw * MLKitScannerView.PREVIEW_RATIO_H) / MLKitScannerView.PREVIEW_RATIO_W);
    } else {
      height = Math.round(ch);
      width = Math.round((ch * MLKitScannerView.PREVIEW_RATIO_W) / MLKitScannerView.PREVIEW_RATIO_H);
    }
    return { width, height };
  }

  private parsePreviewSize(args: ESObject): Size {
    const raw = this.parsePositiveSize(this.normalizeArgs(args));
    if (!raw) {
      this.containerSize = { width: 376, height: 200 };
      return this.calcPreviewSizeAspectCover(376, 200);
    }
    this.containerSize = { width: raw.width, height: raw.height };
    return this.calcPreviewSizeAspectCover(raw.width, raw.height);
  }

  private clearScanDelayTimer(): void {
    if (this.scanDelayTimerId >= 0) {
      clearTimeout(this.scanDelayTimerId);
      this.scanDelayTimerId = -1;
    }
    this.isDelayed = false;
  }

  // 在延迟窗口期间阻止结果输出
  private startScanDelayWindow(): void {
    this.clearScanDelayTimer();
    if (this.scanDelayMs <= 0) {
      return;
    }
    this.isDelayed = true;
    this.scanDelayTimerId = setTimeout(() => {
      this.scanDelayTimerId = -1;
      this.isDelayed = false;
    }, this.scanDelayMs) as number;
  }

  // 暂停预览流
  private async pausePreviewFlow(): Promise<void> {
    if (!this.previewState.isRunning && !this.isScan) {
      return;
    }
    try {
      const service = this.getCameraService();
      await service?.stopCamera();
      this.endPreviewSession();
    } catch (error) {
      Log.e(TAG, 'pausePreviewFlow error: ' + JSON.stringify(error));
    }
  }

  // 开启预览流，恢复闪光灯状态
  private async resumePreviewFlow(): Promise<void> {
    // 预览流是开启状态
    if (this.previewState.isRunning) {
      if (this.flashLightStatusBeforePause) {
        this.openFlashLightSafely();
      }
      return;
    }
    try {
      await this.startPreview();
      this.applyDesiredZoomIfPossible();
      if (this.flashLightStatusBeforePause) {
        this.openFlashLightSafely();
      }
    } catch (error) {
      Log.e(TAG, 'resumePreviewFlow error: ' + JSON.stringify(error));
    }
  }

  private getActiveCropRect(): CropRect | null {
    return this.initialScannerParameters?.initialCropRect ?? null;
  }

  private emitScanResult(result: string): void {
    // 将扫码解析后的结果回传flutter
    this.channel?.invokeMethod(PluginConstants.scanResultMethod, {
      raw_value: result,
      display_value: result,
      format: Number(result['scanType']) || 0,
      value_type: 0,
    });
  }

  private async startPreview(): Promise<void> {
    if (!this.isCameraInitialized || !this.surfaceId || this.previewState.isPausedByUser) {
      Log.w(
        TAG,
        `startPreview skipped: isCameraInitialized=${this.isCameraInitialized}, ` +
          `surfaceId=${this.surfaceId}, paused=${this.previewState.isPausedByUser}`,
      );
      return;
    }
    if (this.previewState.isRunning || this.isPreviewStarting) {
      return;
    }
    this.isPreviewStarting = true;
    try {
      const service = this.getCameraService();
      if (!service || !this.context) {
        Log.w(TAG, 'startPreview skipped: camera service/context unavailable');
        return;
      }
      await service.createCamera(camera.getCameraManager(this.context));
      const started = await service.initCamera(this.surfaceId, this.selectedCameraId);
      if (!started) {
        Log.e(TAG, `startPreview failed: initCamera returned false, cameraId=${this.selectedCameraId}`);
        return;
      }
      this.bindFrameListener();
      this.beginPreviewSession();
      this.applyDesiredZoomIfPossible();
    } catch (error) {
      Log.e(TAG, 'startPreview error ' + JSON.stringify(error));
    } finally {
      this.isPreviewStarting = false;
    }
  }

  /**
   * 检查二维码是否在扫码框内（crop 相对于可见区域）
   */
  private checkResultInScanBox(scanCodeRect: scanBarcode.ScanCodeRect): boolean {
    const cropRect = this.getActiveCropRect();
    // 未设置裁剪框时默认全屏可识别
    if (!cropRect) {
      return true;
    }

    const baseWidth = this.containerSize.width;
    const baseHeight = this.containerSize.height;
    if (baseWidth <= 0 || baseHeight <= 0) {
      return false;
    }

    const cropWidth = baseWidth * cropRect.scaleWidth;
    const cropHeight = baseHeight * cropRect.scaleHeight;
    const cropLeft = (baseWidth / 2) * (1 + cropRect.offsetX) - cropWidth / 2;
    const cropTop = (baseHeight / 2) * (1 + cropRect.offsetY) - cropHeight / 2;
    const cropRight = cropLeft + cropWidth;
    const cropBottom = cropTop + cropHeight;

    let codeLeft = Math.min(scanCodeRect.left, scanCodeRect.right);
    let codeRight = Math.max(scanCodeRect.left, scanCodeRect.right);
    let codeTop = Math.min(scanCodeRect.top, scanCodeRect.bottom);
    let codeBottom = Math.max(scanCodeRect.top, scanCodeRect.bottom);
    if (this.previewSize.width <= this.containerSize.width) {
      const padX = (this.containerSize.width - this.previewSize.width) / 2;
      codeLeft += padX;
      codeRight += padX;
    } else {
      const cropX = (this.previewSize.width - this.containerSize.width) / 2;
      codeLeft -= cropX;
      codeRight -= cropX;
    }
    if (this.previewSize.height <= this.containerSize.height) {
      const padY = (this.containerSize.height - this.previewSize.height) / 2;
      codeTop += padY;
      codeBottom += padY;
    } else {
      const cropY = (this.previewSize.height - this.containerSize.height) / 2;
      codeTop -= cropY;
      codeBottom -= cropY;
    }
    const inScanBox =
      codeLeft >= cropLeft &&
        codeRight <= cropRight &&
        codeTop >= cropTop &&
        codeBottom <= cropBottom;

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
    const args = this.normalizeArgs(rawArgsMap);
    this.initialScannerParameters = (args && (args as OhosScannerParameters)) || null;
    const initialZoom = this.initialScannerParameters?.initialZoom;
    if (initialZoom !== undefined && initialZoom !== null && initialZoom >= 0 && initialZoom <= 1) {
      this.desiredZoom = initialZoom;
    }
    const initialCamera: OhosInitialCamera | undefined = this.initialScannerParameters?.initialCamera;
    if (initialCamera) {
      this.selectedCameraPositionCode = Math.trunc(Number(initialCamera.position));
      this.selectedCameraTypeCode = Math.trunc(Number(initialCamera.type));
      const service = this.getCameraService();
      if (service) {
        this.selectedCameraId =
          service.findCameraIdByOhosCodes(this.selectedCameraPositionCode, this.selectedCameraTypeCode) ?? '';
      }
    }

    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      comp.onInitCameraPreviewRequested();
    }
  }

  // 递归转换映射
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

  private async runDisposeScanRelease(): Promise<void> {
    try {
      const service = this.getCameraService();
      await service?.releaseCamera();
    } catch (error) {
      Log.w(TAG, 'disposeScanResources release skipped: ' + JSON.stringify(error));
    }
  }

  private resetStateAfterDispose(): void {
    // 保底状态清理，避免重复进入销毁流程后状态残留
    this.clearScanDelayTimer();
    this.isCameraInitialized = false;
    this.endScanSession();
    this.endPreviewSession();
    this.desiredZoom = null;
    this.flashLightStatusBeforePause = false;
    this.previewState.isPausedByUser = false;
  }

  private async disposeScanResources(): Promise<void> {
    if (!this.disposePromise) {
      this.disposePromise = this.runDisposeScanRelease();
    }

    try {
      await this.disposePromise;
    } finally {
      this.resetStateAfterDispose();
    }
  }

  private async disposeHandle(result: MethodResult): Promise<void> {
    try {
      await this.disposeScanResources();
      if (this.channel != null) {
        this.channel.setMethodCallHandler(null);
      }
      result.success(true);
    } catch (error) {
      Log.e(TAG, `Failed to disposeHandle. Code: ${error.code}, message: ${error.message}`);
      result.error('disposeHandle ', `Failed to disposeHandle. ${error.code}, message: ${error.message}`, null);
    }
  }

  private toggleFlash(result: MethodResult): void {
    // 切换闪光灯
    if (!this.isCameraInitialized) {
      result.error(PluginError.CameraIsNotInitialized, 'Camera is not initialized', null);
      return;
    }
    try {
      const service = this.getCameraService();
      const hasFlash = service?.hasFlash() ?? false;
      this.flashLightStatus = this.getFlashLightStatusSafely();
      // 根据当前闪光灯状态，选择开启或关闭闪光灯
      if (this.flashLightStatus) {
        this.closeFlashLightSafely();
        result.success(true);
      } else {
        if (!hasFlash) {
          result.error(PluginError.DeviceHasNotFlash, 'The current camera does not support flash', null);
          return;
        }
        this.openFlashLightSafely();
        result.success(true);
      }
      this.flashLightStatusBeforePause = this.getFlashLightStatusSafely();
      // 将手电筒状态回传flutter
      this.channel?.invokeMethod(
        PluginConstants.changeTorchStateMethod,
        this.flashLightStatusBeforePause
      );
    } catch (error) {
      Log.e(TAG, `Failed to getFlashLightStatus. Code: ${error.code}, message: ${error.message}`);
      result.error('toggleFlash ', `Failed to toggleFlash. ${error.code}, message: ${error.message}`, null);
    }
  }

  // 开启扫描，开启预览流
  private async startScan(call: MethodCall, result: MethodResult): Promise<void> {
    const args = this.normalizeArgs(call.args as ESObject);
    let options: MLKitScannerOptions;
    try {
      options = MLKitScannerOptions.fromMap(args);
    } catch (error) {
      result.error(
        PluginError.InvalidArguments,
        'Invalid startScan arguments: ' + JSON.stringify(error),
        null,
      );
      return;
    }
    this.scanDelayMs = options.periodMs;
    if (!this.previewState.isPausedByUser) {
      this.flashLightStatusBeforePause = this.getFlashLightStatusSafely();
    }
    if (!this.isCameraInitialized) {
      if (this.previewState.isPausedByUser) {
        getCurrentCameraPreviewComponent()?.setScanActive(true);
        result.success(true);
        return;
      }
      result.error(PluginError.CameraIsNotInitialized, 'Camera is not initialized', null);
      return;
    }
    if (!this.surfaceId) {
      result.error(PluginError.CameraIsNotInitialized, 'Camera surface is not ready', null);
      return;
    }
    // 处于扫描状态 或者 用户触发了pause时不做处理 只标记开启扫描
    if (this.isScan || this.previewState.isPausedByUser) {
      this.beginScanSession();
      result.success(true);
      return;
    }

    // 开启扫描，开启预览流
    this.beginScanSession();
    this.startScanDelayWindow();
    if (!this.previewState.isRunning) {
      await this.startPreview();
    }
    result.success(true);
  }

  // 取消扫描，保持预览
  private async cancelScan(result: MethodResult): Promise<void> {
    try {
      this.clearScanDelayTimer();
      if (!this.isCameraInitialized) {
        if (this.previewState.isPausedByUser) {
          getCurrentCameraPreviewComponent()?.setScanActive(false);
          result.success(true);
          return;
        }
        result.error(PluginError.CameraIsNotInitialized, 'Camera is not initialized', null);
        return;
      }
      // cancel 只停止扫描，不重启预览流，避免卡顿与闪光灯状态抖动。
      if (this.isScan) {
        this.endScanSession();
      }
      result.success(true);
    } catch (error) {
      Log.e(TAG, `cancelScan error - ${error}`);
      this.endScanSession();
    }
  }

  private setScanDelay(call: MethodCall, result: MethodResult): void {
    // 设置扫描延迟
    const delay: ESObject = call.args as ESObject;
    if (typeof delay !== 'number' || !Number.isFinite(delay)) {
      result.error(
        PluginError.InvalidArguments,
        'Invalid argument passed, Number type is expected',
        null,
      );
      return;
    }
    if (delay < 0) {
      result.error(
        PluginError.InvalidArguments,
        'Invalid argument passed, value must be >= 0',
        null,
      );
      return;
    }
    // 将扫描延迟设置为传入值的整数部分
    this.scanDelayMs = Math.trunc(delay);
    result.success(true);
  }

  // 更新预览约束,如果新的预览尺寸与当前相同则直接返回成功,否则更新预览尺寸并应用新的约束,如果相机未初始化则返回错误
  private updateConstraints(call: MethodCall, result: MethodResult): void {
    const args = this.normalizeArgs(call.args as ESObject);
    const rawSize = this.parsePositiveSize(args);
    if (!rawSize) {
      result.error(
        PluginError.InvalidArguments,
        'Invalid constraints, positive width/height expected',
        null,
      );
      return;
    }
    this.containerSize = { width: rawSize.width, height: rawSize.height };
    const newSize = this.calcPreviewSizeAspectCover(rawSize.width, rawSize.height);
    if (this.previewSize.width === newSize.width && this.previewSize.height === newSize.height) {
      result.success(true);
      return;
    }

    this.previewSize = newSize;
    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      comp.applyCropRect();
    }
    result.success(true);
  }

  private async pauseCamera(result: MethodResult): Promise<void> {
    // 暂停相机
    if (this.previewState.isPausedByUser) {
      result.success(true);
      return;
    }
    const isFlashOn = this.getFlashLightStatusSafely();
    if (isFlashOn) {
      this.closeFlashLightSafely();
    }
    // 强制恢复，因为上面的 closeFlashLightSafely 会触发回调将本类的状态设为了 false
    this.flashLightStatusBeforePause = isFlashOn;
    this.previewState.isPausedByUser = true;
    this.originalValue = '';
    this.clearScanDelayTimer();
    await this.pausePreviewFlow();
    result.success(true);
  }

  public resumeCamera(result: MethodResult): void {
    if (!this.previewState.isPausedByUser && this.previewState.isRunning) {
      result.success(true);
      return;
    }
    // 恢复相机
    if (!this.isCameraInitialized) {
      this.isCameraInitialized = true;
    }

    // 获取当前组件的状态是否是激活状态
    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      const active: boolean = comp.getScanActive();
      this.isScan = active;
    }
    this.previewState.isPausedByUser = false;
    void this.resumePreviewFlow();
    result.success(true);
  }

  private getFlashLightStatusSafely(): boolean {
    let flashLightStatus: boolean = this.flashLightStatus;
    try {
      const service = this.getCameraService();
      // 这里获取闪光灯状态时，有一个问题：进入应用，打开闪光灯，点击pause,应用切后台，再切前台，再点击startScan，此时这个接口报错，因为 ScanKit 在 pause 时会释放预览流，导致无法获取闪光灯状态。这里捕获异常，避免应用崩溃，并且在异常情况下返回上一次已知的闪光灯状态。
      flashLightStatus = service?.getFlashStatus() ?? this.flashLightStatus;
    } catch (error) {
      Log.e(TAG, `Failed to getFlashLightStatus. Code: ${error.code}, message: ${error.message}`);
    }
    return flashLightStatus;
  }

  private closeFlashLightSafely(): void {
    try {
      const service = this.getCameraService();
      service?.setFlashMode(null, false);
      this.flashLightStatus = false;
    } catch (error) {
      Log.e(TAG, `Failed to closeFlashLight. Code: ${error.code}, message: ${error.message}`);
    }
  }

  private openFlashLightSafely(): void {
    try {
      const service = this.getCameraService();
      service?.setFlashMode(null, true);
      this.flashLightStatus = true;
    } catch (error) {
      Log.e(TAG, `Failed to openFlashLight. Code: ${error.code}, message: ${error.message}`);
    }
  }

  public async onHostBackground(): Promise<void> {
    if (!this.isCameraInitialized) {
      return;
    }
    // 用户触发pause后前后台切换
    if (this.previewState.isPausedByUser) {
      // 释放之前的预览流
      try {
        const service = this.getCameraService();
        await service?.preFrontRelease(true);
        this.isCameraInitialized = false;
      } catch (error) {
        Log.e(TAG,
          `Failed to onHostBackground. isPausedByUser == true. Code: ${error.code}, message: ${error.message}`);
      }
    } else {
      await this.pausePreviewFlow();
    }
  }

  public async onHostForeground(): Promise<void> {
    if (!this.isCameraInitialized || !this.surfaceId) {
      return;
    }
    // 非用户触发pause后前后台切换
    if (!this.previewState.isPausedByUser) {
      try {
        // const service = this.getCameraService();
        // await service?.preFrontRelease(false);
        this.originalValue = '';
        await this.startPreview();
        this.applyDesiredZoomIfPossible();

        if (this.flashLightStatusBeforePause) {
          this.openFlashLightSafely();
        }
      } catch (error) {
        Log.e(TAG, `Failed to onHostForeground. Code: ${error.code}, message: ${error.message}`);
      }
    }
  }

  private parseZoomValue(args: ESObject): number | null {
    if (args === null || args === undefined) {
      return null;
    }
    const num = Number(args);
    if (Number.isFinite(num)) {
      return num;
    }
    const map = this.normalizeArgs(args) as Record<string, Object>;
    const val = map['value'] ?? map['zoom'];
    const n = Number(val);
    return Number.isFinite(n) ? n : null;
  }

  /**
   * 将 Flutter 的 0~1 归一化值映射为 ScanKit 的绝对变焦比
   * ScanKit: 1.0~maxZoom
   */
  private applyDesiredZoomIfPossible(): boolean {
    if (this.desiredZoom === null) {
      return false;
    }
    try {
      const service = this.getCameraService();
      if (!service) {
        return false;
      }
      return service.setZoomNormalized(this.desiredZoom);
    } catch (error) {
      Log.e(TAG, 'setZoom failed: ' + JSON.stringify(error));
      return false;
    }
  }

  private setZoom(call: MethodCall, result: MethodResult): void {
    if (!this.isCameraInitialized) {
      result.error(
        PluginError.CameraIsNotInitialized,
        'You need to invoke the \'initCameraPreview\' method before using zoom',
        null,
      );
      return;
    }
    const zoom = this.parseZoomValue(call.args as ESObject);
    if (zoom === null || zoom < 0 || zoom > 1) {
      result.error(
        PluginError.InvalidArguments,
        'Invalid argument passed, Number type is expected with value in range 0...1',
        null,
      );
      Log.e(TAG, 'setZoom invalid argument: ' + JSON.stringify(call.args));
      return;
    }

    this.desiredZoom = zoom;
    if (!this.previewState.isRunning) {
      result.success(true);
      return;
    }

    if (this.applyDesiredZoomIfPossible()) {
      result.success(true);
      return;
    }

    result.error(PluginError.DeviceHasNotZoom, 'Zoom is not supported on this device', null);
  }

  // 设置扫描区域
  private setCropArea(call: MethodCall, result: MethodResult): void {
    const rawArgsMap: ESObject = call.args as ESObject;
    const args = this.normalizeArgs(rawArgsMap);
    const rect: CropRect = {
      scaleWidth: Number(args['scaleWidth']) || 1,
      scaleHeight: Number(args['scaleHeight']) || 1,
      offsetX: Number(args['offsetX']) || 0,
      offsetY: Number(args['offsetY']) || 0,
    };
    this.initialScannerParameters = this.initialScannerParameters || {};
    this.initialScannerParameters.initialCropRect = rect;
    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      comp.applyCropRect();
    }

    result.success(true);
  }

  private getOhosAvailableCameras(result: MethodResult): void {
    if (!this.context) {
      result.error(PluginError.InitCameraError, 'context is undefined!', null);
      return;
    }

    try {
      const service = this.getCameraService();
      if (!service) {
        result.error(PluginError.InitCameraError, 'camera service is unavailable', null);
        return;
      }

      const devices = service.getAvailableCameras();
      const available: Array<Record<string, number>> = [];
      for (const device of devices) {
        const item = device as ESObject as OhosCameraItem;
        available.push({
          'position': item.position,
          'type': item.type,
        });
      }
      result.success(available);
    } catch (error) {
      result.error(PluginError.InitCameraError, 'Failed to get camera list: ' + JSON.stringify(error), null);
    }
  }

  private setOhosCamera(call: MethodCall, result: MethodResult): void {
    const args = this.normalizeArgs(call.args as ESObject);
    const position = Number(args['position']);
    const type = Number(args['type']);
    if (!Number.isFinite(position) || !Number.isFinite(type)) {
      result.error(PluginError.InvalidArguments, 'Invalid camera arguments, position/type required', null);
      return;
    }

    if (!this.context) {
      result.error(PluginError.InitCameraError, 'context is undefined!', null);
      return;
    }

    const reqPosition = Math.trunc(position);
    const reqType = Math.trunc(type);
    try {
      const service = this.getCameraService();
      if (!service) {
        result.error(PluginError.InitCameraError, 'camera service is unavailable', null);
        return;
      }

      const cameraId = service.findCameraIdByOhosCodes(reqPosition, reqType);
      if (!cameraId) {
        result.error(
          PluginError.InvalidArguments,
          `No camera matches position=${reqPosition}, type=${reqType}`,
          null,
        );
        return;
      }

      this.selectedCameraId = cameraId;
    } catch (error) {
      result.error(PluginError.InitCameraError, 'Failed to query camera list: ' + JSON.stringify(error), null);
      return;
    }

    this.selectedCameraPositionCode = reqPosition;
    this.selectedCameraTypeCode = reqType;

    if (this.isCameraInitialized && this.surfaceId && !this.previewState.isPausedByUser) {
      void this.restartPreviewAfterLayoutChange();
    }

    result.success(true);
  }

  dispose() {
    void this.disposeScanResources();
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
    }
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
