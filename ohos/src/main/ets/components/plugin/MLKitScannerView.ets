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

interface PreviewState {
  isRunning: boolean;
  isWarmupInFlight: boolean;
  busyErrorCount: number;
  shouldKeep: boolean;
  isAwaitingRescan: boolean;
  rescanTimerId: number;
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
  public channel: MethodChannel | null = null;
  public methodResult: MethodResult | null = null;
  public initialScannerParameters: OhosScannerParameters | null = null;
  public isCameraInitialized: boolean = false;
  public userGrant: boolean = false;
  // isScan 表示当前是否处于扫描状态
  public isScan: boolean = false;
  // previewSize 是预览的分辨率，扫描器会基于这个分辨率来配置相机和处理图像数据
  private previewSize: Size = { width: 0, height: 0 };
  // scanDelayMs 是扫描延迟，单位是毫秒
  private scanDelayMs: number = 100;
  // stopTimeoutMs 是停止扫描的超时时间，单位是毫秒。如果扫描器在指定时间内没有成功停止，系统会强制终止扫描操作
  private readonly stopTimeoutMs: number = 1200;
  private previewState: PreviewState = {
    isRunning: false,
    isWarmupInFlight: false,
    busyErrorCount: 0,
    shouldKeep: false,
    isAwaitingRescan: false,
    rescanTimerId: -1,
  };
  private decodeState: DecodeState = {
    inFlight: false,
    lastAttemptAtMs: 0,
    scanSessionStartedAtMs: 0,
    lastEmittedRawValue: "",
    lastEmittedAtMs: 0,
    lastDecodedRawValue: "",
  };
  private readonly frameDecodeThrottleMs: number = 33;
  private readonly cropBufferRatio: number = 0.1;
  private readonly maxPlatformZoom: number = 6;
  private desiredZoom: number | null = null;
  private diagFrameCount: number = 0;
  private diagDecodeAttempts: number = 0;
  private diagDecodeHits: number = 0;
  private diagLastStatsMs: number = 0;

  constructor(context: common.Context, messenger: BinaryMessenger, viewId: number, args: ESObject) {
    super();
    flutterMLKitScannerView = this;
    this.context = context;
    this.viewId = viewId;
    this.channel = new MethodChannel(messenger, PluginConstants.channelName);
    this.channel.setMethodCallHandler(this);
    Log.i(TAG, "CameraPreviewView constructor args: " + JSON.stringify(args));

    this.previewSize = this.parsePreviewSize(args);
    Log.i(
      TAG,
      "CameraPreviewView constructor created with viewId: " +
        viewId +
        ", previewSize=" +
        JSON.stringify(this.previewSize),
    );
  }

  public getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(CameraPreviewBuilder);
  }

  setSurfaceId(surfaceId: string) {
    this.surfaceId = surfaceId;
    this.previewState.shouldKeep = true;
    Log.i(TAG, "setSurfaceId success: " + this.surfaceId);
    this.startPreviewIfNeeded();
  }

  setCameraInitialized(isCameraInitialized: boolean) {
    this.isCameraInitialized = isCameraInitialized;
    if (isCameraInitialized) {
      this.previewState.shouldKeep = true;
      this.startPreviewIfNeeded();
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

  private resetDecodeTiming(): void {
    this.decodeState.lastAttemptAtMs = 0;
  }

  private resetPreviewState(): void {
    this.previewState.isRunning = false;
    this.previewState.isWarmupInFlight = false;
    this.previewState.busyErrorCount = 0;
    this.previewState.shouldKeep = false;
    this.previewState.isAwaitingRescan = false;
    this.clearPendingRescan();
    this.clearFocusTimers();
  }

  private markPreviewStartPending(): void {
    this.previewState.isWarmupInFlight = true;
  }

  private markPreviewStarted(): void {
    this.previewState.isRunning = true;
    this.previewState.isWarmupInFlight = false;
    this.previewState.busyErrorCount = 0;
    this.previewState.isAwaitingRescan = false;
  }

  private markPreviewStartFailed(): void {
    this.previewState.isRunning = false;
    this.previewState.isWarmupInFlight = false;
    this.previewState.isAwaitingRescan = false;
    this.previewState.busyErrorCount = 0;
  }

  private beginScanSession(): void {
    this.isScan = true;
    this.previewState.shouldKeep = true;
    this.previewState.isAwaitingRescan = true;
    this.decodeState.scanSessionStartedAtMs = Date.now();
    this.resetDecodeTiming();
    this.diagFrameCount = 0;
    this.diagDecodeAttempts = 0;
    this.diagDecodeHits = 0;
    this.diagLastStatsMs = 0;
    getCurrentCameraPreviewComponent()?.setScanActive(true);
  }

  private endScanSession(keepPreview: boolean): void {
    this.isScan = false;
    this.previewState.busyErrorCount = 0;
    this.previewState.shouldKeep = keepPreview;
    this.previewState.isAwaitingRescan = false;
    this.decodeState.scanSessionStartedAtMs = 0;
    this.resetDecodeTiming();
    this.clearPendingRescan();
    getCurrentCameraPreviewComponent()?.setScanActive(false);
  }

  private normalizeArgs(rawArgs: ESObject): Record<string, Object> {
    if (!rawArgs || typeof rawArgs !== "object") {
      return {};
    }

    if (typeof rawArgs.forEach === "function") {
      const args: Record<string, Object> = {};
      rawArgs.forEach((value: ESObject, key: string) => {
        Log.i(TAG, `Map Key: ${key}, Value: ${value}, Type: ${typeof value}`);
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

  private async waitDelay(ms: number): Promise<void> {
    if (ms <= 0) {
      return;
    }
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }

  // 安全停止扫描
  private async stopScanSafely(timeoutMs: number = this.stopTimeoutMs): Promise<void> {
    let retriesLeft = 2;
    while (retriesLeft >= 0) {
      try {
        await Promise.race<void>([
          customScan.stop(),
          new Promise<void>((resolve) => {
            setTimeout(() => resolve(), timeoutMs);
          }),
        ]);
        return;
      } catch (error) {
        const errorCode = this.getErrorCode(error as Object);
        if (errorCode === 1000500001 && retriesLeft > 0) {
          retriesLeft -= 1;
          await this.waitDelay(120);
          continue;
        }
        Log.e(TAG, "stopScanSafely error: " + JSON.stringify(error));
        return;
      }
    }
  }

  private getFocusPointForCropCenter(): scanBarcode.Point {
    const crop = this.getPreviewCropRect();
    const centerX = crop.left + crop.width / 2;
    const centerY = crop.top + crop.height / 2;
    const focusX = this.clamp(centerY / this.previewSize.height, 0, 1);
    const focusY = this.clamp(1 - centerX / this.previewSize.width, 0, 1);
    return { x: focusX, y: focusY };
  }

  private focusTimerId: number = -1;
  private resetFocusTimerId: number = -1;

  private applyInitialFocus(): void {
    this.clearFocusTimers();
    this.focusTimerId = setTimeout(() => {
      this.focusTimerId = -1;
      if (!this.previewState.isRunning) {
        return;
      }
      try {
        const point = this.getFocusPointForCropCenter();
        customScan.setFocusPoint(point);
        Log.i(
          TAG,
          "setFocusPoint to crop center: x=" + point.x.toFixed(3) + ", y=" + point.y.toFixed(3),
        );
      } catch (error) {
        Log.e(TAG, "setFocusPoint error: " + JSON.stringify(error));
      }
      this.resetFocusTimerId = setTimeout(() => {
        this.resetFocusTimerId = -1;
        if (!this.previewState.isRunning) {
          return;
        }
        try {
          customScan.resetFocus();
          Log.i(TAG, "resetFocus to continuous AF");
        } catch (error) {
          Log.e(TAG, "resetFocus error: " + JSON.stringify(error));
        }
      }, 1500) as number;
    }, 500) as number;
  }

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

  private parseZoomValue(rawArgs: ESObject): number | null {
    if (typeof rawArgs === "number") {
      return rawArgs;
    }

    if (!rawArgs || typeof rawArgs !== "object") {
      return null;
    }

    const args = this.normalizeArgs(rawArgs);
    const zoom = Number(args["zoom"] ?? args["initialZoom"]);
    return Number.isFinite(zoom) ? zoom : null;
  }

  private applyDesiredZoomIfPossible(): boolean {
    if (this.desiredZoom === null || !this.previewState.isRunning) {
      return false;
    }

    try {
      const platformZoom = this.toPlatformZoom(this.desiredZoom);
      customScan.setZoom(platformZoom);
      Log.i(
        TAG,
        "setZoom success, normalizedZoom=" + this.desiredZoom + ", platformZoom=" + platformZoom,
      );
      return true;
    } catch (error) {
      Log.e(TAG, "setZoom error: " + JSON.stringify(error));
      return false;
    }
  }

  private toPlatformZoom(normalizedZoom: number): number {
    return 1 + normalizedZoom * (this.maxPlatformZoom - 1);
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

  private clearPendingRescan(): void {
    if (this.previewState.rescanTimerId < 0) {
      return;
    }
    clearTimeout(this.previewState.rescanTimerId);
    this.previewState.rescanTimerId = -1;
  }

  private triggerRescan(): void {
    if (
      !this.previewState.shouldKeep ||
      !this.previewState.isRunning ||
      !this.previewState.isAwaitingRescan
    ) {
      return;
    }
    try {
      customScan.rescan();
      this.previewState.isAwaitingRescan = false;
    } catch (error) {
      Log.e(TAG, "triggerRescan error: " + JSON.stringify(error));
    }
  }

  private scheduleRescan(delayMs: number): void {
    this.clearPendingRescan();
    this.previewState.rescanTimerId = setTimeout(
      () => {
        this.previewState.rescanTimerId = -1;
        if (!this.isScan) {
          return;
        }
        this.triggerRescan();
      },
      Math.max(delayMs, 0),
    ) as number;
  }

  private handleScanCallback(data: scanBarcode.ScanResult[]): void {
    void data;
    this.previewState.busyErrorCount = 0;
    this.previewState.isRunning = true;
    this.previewState.isAwaitingRescan = true;
    if (!this.isScan) {
      return;
    }
    this.scheduleRescan(0);
  }

  private handleStartPreviewError(error: Object, retriesLeft: number): void {
    const errorCode = this.getErrorCode(error);
    Log.e(TAG, "startPreview error: " + JSON.stringify(error));
    if (errorCode === 1000500001 && retriesLeft > 0) {
      this.previewState.busyErrorCount += 1;
      this.waitDelay(180).then(() => this.tryStartPreview(retriesLeft - 1));
      return;
    }
    this.markPreviewStartFailed();
  }

  private emitScanResult(result: scanBarcode.ScanResult): void {
    const rawValue = String(result["originalValue"] ?? "");
    if (!rawValue) {
      Log.i(TAG, "decodeImage result has empty originalValue");
      return;
    }
    const nowMs = Date.now();
    const isSameAsLast = rawValue === this.decodeState.lastEmittedRawValue;
    if (isSameAsLast && nowMs - this.decodeState.lastEmittedAtMs < this.scanDelayMs) {
      return;
    }

    this.decodeState.lastEmittedRawValue = rawValue;
    this.decodeState.lastEmittedAtMs = nowMs;
    const elapsedMs =
      this.decodeState.scanSessionStartedAtMs > 0
        ? nowMs - this.decodeState.scanSessionStartedAtMs
        : -1;
    Log.i(TAG, "decodeImage result success, elapsedMs=" + elapsedMs + ", rawValue=" + rawValue);
    this.channel?.invokeMethod(PluginConstants.scanResultMethod, {
      raw_value: rawValue,
      display_value: rawValue,
      format: Number(result["scanType"]) || 0,
      value_type: 0,
    });
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
    return { left: alignedLeft, top: alignedTop, width, height };
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

  private cropNv21Buffer(
    sourceBuffer: ArrayBuffer,
    sourceWidth: number,
    sourceHeight: number,
    position: CropPosition,
  ): ArrayBuffer {
    const source = new Uint8Array(sourceBuffer);
    const croppedBuffer = new ArrayBuffer((position.width * position.height * 3) / 2);
    const target = new Uint8Array(croppedBuffer);
    const lumaSize = sourceWidth * sourceHeight;
    const cropLumaSize = position.width * position.height;

    for (let row = 0; row < position.height; row++) {
      const sourceOffset = (position.top + row) * sourceWidth + position.left;
      const targetOffset = row * position.width;
      target.set(source.subarray(sourceOffset, sourceOffset + position.width), targetOffset);
    }

    const chromaTop = position.top / 2;
    const chromaHeight = position.height / 2;
    for (let row = 0; row < chromaHeight; row++) {
      const sourceOffset = lumaSize + (chromaTop + row) * sourceWidth + position.left;
      const targetOffset = cropLumaSize + row * position.width;
      target.set(source.subarray(sourceOffset, sourceOffset + position.width), targetOffset);
    }

    return croppedBuffer;
  }

  private createCroppedByteImage(frame: customScan.ScanFrame): detectBarcode.ByteImage | null {
    const frameWidth = Number(frame["width"]);
    const frameHeight = Number(frame["height"]);
    const byteBuffer = frame["byteBuffer"] as ArrayBuffer;
    if (!Number.isFinite(frameWidth) || !Number.isFinite(frameHeight) || !byteBuffer) {
      return null;
    }

    const cropRect = this.getFrameCropRect(frame);
    if (!cropRect) {
      return null;
    }

    return {
      byteBuffer: this.cropNv21Buffer(byteBuffer, frameWidth, frameHeight, cropRect),
      width: cropRect.width,
      height: cropRect.height,
      format: detectBarcode.ImageFormat.NV21,
    };
  }

  private shouldDecodeFrame(nowMs: number): boolean {
    if (
      !this.isScan ||
      !this.previewState.shouldKeep ||
      !this.previewState.isRunning ||
      this.decodeState.inFlight
    ) {
      return false;
    }
    return nowMs - this.decodeState.lastAttemptAtMs >= this.frameDecodeThrottleMs;
  }

  private async decodeCroppedFrame(image: detectBarcode.ByteImage): Promise<void> {
    try {
      const detectResult = await detectBarcode.decodeImage(image, this.getDecodeOptions());
      if (!this.isScan) {
        return;
      }

      const results = detectResult?.scanResults ?? [];
      if (!results.length) {
        return;
      }
      this.diagDecodeHits++;
      const rawValue = String(results[0]["originalValue"] ?? "");
      const prevDecoded = this.decodeState.lastDecodedRawValue;
      this.decodeState.lastDecodedRawValue = rawValue;
      if (!rawValue || rawValue !== prevDecoded) {
        return;
      }
      this.emitScanResult(results[0]);
    } catch (error) {
      const errorCode = this.getErrorCode(error as Object);
      if (errorCode !== 1000500001) {
        Log.e(TAG, "decodeCroppedFrame error: " + JSON.stringify(error));
      }
    } finally {
      this.decodeState.inFlight = false;
    }
  }

  private handlePreviewFrame(frame: customScan.ScanFrame): void {
    this.previewState.isRunning = true;
    this.diagFrameCount++;
    const nowMs = Date.now();
    if (this.isScan && nowMs - this.diagLastStatsMs >= 3000) {
      this.diagLastStatsMs = nowMs;
      Log.i(
        TAG,
        "[diag] frames=" +
          this.diagFrameCount +
          " attempts=" +
          this.diagDecodeAttempts +
          " hits=" +
          this.diagDecodeHits,
      );
    }
    if (!this.shouldDecodeFrame(nowMs)) {
      return;
    }

    const image = this.createCroppedByteImage(frame);
    if (!image) {
      return;
    }
    if (this.diagDecodeAttempts === 0) {
      const fw = Number(frame["width"]);
      const fh = Number(frame["height"]);
      Log.i(TAG, "[diag] frame=" + fw + "x" + fh + " crop=" + image.width + "x" + image.height);
    }
    this.diagDecodeAttempts++;
    this.decodeState.lastAttemptAtMs = nowMs;
    this.decodeState.inFlight = true;
    void this.decodeCroppedFrame(image);
  }

  // 启动预览流(仅开启相机画面,不进入扫描循环)。调用 customScan.start 建立预览,
  // 扫描结果通过 callback 返回。start 只启动一次,后续识别通过 rescan 继续触发。
  private startPreviewIfNeeded(): void {
    if (
      !this.isCameraInitialized ||
      !this.surfaceId ||
      !this.previewState.shouldKeep ||
      this.previewState.isRunning
    ) {
      return;
    }
    if (this.previewState.isWarmupInFlight) {
      return;
    }
    this.markPreviewStartPending();
    this.tryStartPreview(2);
  }

  private tryStartPreview(retriesLeft: number): void {
    if (!this.previewState.shouldKeep || !this.isCameraInitialized || !this.surfaceId) {
      this.previewState.isWarmupInFlight = false;
      return;
    }
    try {
      customScan.start(
        this.buildViewControl(),
        (error: BusinessError, data: scanBarcode.ScanResult[]) => {
          if (error) {
            Log.e(TAG, "scan callback error: " + JSON.stringify(error));
            return;
          }
          this.handleScanCallback(data);
        },
        (error: BusinessError, frame: customScan.ScanFrame) => {
          if (error) {
            Log.e(TAG, "frame callback error: " + JSON.stringify(error));
            return;
          }
          this.handlePreviewFrame(frame);
        },
      );
      this.markPreviewStarted();
      this.applyDesiredZoomIfPossible();
      this.applyInitialFocus();
      Log.i(TAG, "startPreview success");
    } catch (error) {
      this.handleStartPreviewError(error as Object, retriesLeft);
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
    const initialZoom = Number(this.initialScannerParameters?.initialZoom);
    if (Number.isFinite(initialZoom) && initialZoom >= 0 && initialZoom <= 1) {
      this.desiredZoom = initialZoom;
    }

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
    this.endScanSession(false);
    this.resetPreviewState();
    this.resetDecodeState();
    this.desiredZoom = null;
    this.stopScanSafely();
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
    if (this.isScan) {
      result.success(true);
      return;
    }
    if (!this.surfaceId) {
      result.error(PluginError.CameraIsNotInitialized, "Camera surface is not ready", null);
      return;
    }

    this.beginScanSession();
    this.startPreviewIfNeeded();
    this.triggerRescan();
    result.success(true);
  }

  private async cancelScan(result: MethodResult): Promise<void> {
    Log.i(TAG, "cancelScan called");
    this.endScanSession(true);
    this.startPreviewIfNeeded();
    result.success(true);
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
    this.resetDecodeTiming();
    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      comp.applyPreviewConstraints(newSize.width, newSize.height);
      if (this.initialScannerParameters?.initialCropRect) {
        comp.applyCropRect();
      }
    }
    Log.i(TAG, "updateConstraints called, previewSize=" + JSON.stringify(this.previewSize));
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
      result.error(
        PluginError.CameraIsNotInitialized,
        'You need to invoke the "initCameraPreview" method before using zoom',
        null,
      );
      return;
    }
    const zoom = this.parseZoomValue(call.args as ESObject);
    if (zoom === null || zoom < 0 || zoom > 1) {
      result.error(
        PluginError.InvalidArguments,
        "Invalid argument passed, Number type is expected with value in range 0...1",
        null,
      );
      Log.e(TAG, "setZoom invalid argument: " + JSON.stringify(call.args));
      return;
    }

    this.desiredZoom = zoom;
    if (!this.previewState.isRunning) {
      Log.i(TAG, "setZoom deferred until preview starts, zoom=" + zoom);
      result.success(true);
      return;
    }

    if (this.applyDesiredZoomIfPossible()) {
      result.success(true);
      return;
    }

    result.error(PluginError.DeviceHasNotZoom, "Zoom is not supported on this device", null);
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
    this.resetDecodeTiming();
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
