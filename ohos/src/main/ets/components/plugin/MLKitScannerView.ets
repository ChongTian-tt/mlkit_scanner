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
import { CameraService } from './CameraService';
import { MLKitScannerOptions } from './MLKitScannerOptions';
import {
  CropRect,
  OhosInitialCamera,
  OhosScannerParameters,
  PluginConstants,
  PluginError,
  PreviewState,
} from './PluginConstants';
import { ArgsParser } from './ArgsParser';
import { ScanMethodHandler } from './ScanMethodHandler';
import { ScanResultProcessor, ScanResultCallbacks } from './ScanResultProcessor';

const TAG: string = '[MLKitScannerView:]';

let flutterMLKitScannerView: MLKitScannerView | null;

export class MLKitScannerView extends PlatformView implements MethodCallHandler {
  public context: common.Context | null = null;
  public surfaceId: string = '';
  private originalValue: string = '';
  public channel: MethodChannel | null = null;
  public methodResult: MethodResult | null = null;
  public initialScannerParameters: OhosScannerParameters | null = null;
  public isCameraInitialized: boolean = false;
  public userGrant: boolean = false;
  public flashLightStatus: boolean = false;
  public flashLightStatusBeforePause: boolean = false;
  public isScan: boolean = false;
  // 预览的分辨率,扫描器会基于这个分辨率来配置相机和处理图像数据(已按 ScanKit 支持宽高比适配)
  private previewSize: Size = { width: 0, height: 0 };
  // 容器原始尺寸(Flutter 约束 / onAreaChange 原生 vp),用于居中预览
  private containerSize: Size = { width: 0, height: 0 };
  // 扫描延迟,单位是毫秒
  public scanDelayMs: number = 100;
  public previewState: PreviewState = {
    isRunning: false, // 预览流是否开启
    isPausedByUser: false, // 是否是用户暂停
  };
  // 用户期望的缩放级别,可能在预览未就绪时设置,预览就绪后会应用
  private desiredZoom: number | null = null;
  // 当前使用的摄像头参数
  private lastHostLayoutW: number = 0;
  private lastHostLayoutH: number = 0;
  private disposePromise: Promise<void> | null = null;
  // 扫描延迟定时器 ID,用于控制扫描结果的节流输出
  private scanDelayTimerId: number = -1;
  // 扫码结果节流标志,true 表示当前在延迟窗口期间,扫码结果应被忽略
  private isDelayed: boolean = false;
  // yuv帧的高度,用于坐标转换
  private yuvFrameHeight: number = 0;
  // 当前选中的摄像头参数
  public selectedCameraPositionCode: number = 1;
  public selectedCameraTypeCode: number = 0;
  public selectedCameraId: string = '';
  private cameraService: CameraService | null = null;
  // 预览源尺寸宽高比
  private previewSourceSize: Size = {
    width: PluginConstants.PREVIEW_RATIO_W,
    height: PluginConstants.PREVIEW_RATIO_H,
  };
  // 帧监听是否已绑定到当前 ImageReceiver,initCamera 后会重置该标志以确保正确绑定
  private isFrameListenerBound: boolean = false;
  private isPreviewStarting: boolean = false;
  // 扫描方法处理器
  private scanMethodHandler: ScanMethodHandler;
  // 扫码结果处理器
  private scanResultProcessor: ScanResultProcessor;

  /**
   * 创建 MLKitScannerView 实例，初始化 MethodChannel 和 CameraService
   * @param context - Ability 上下文
   * @param messenger - Flutter 二进制消息通道
   * @param viewId - 平台视图 ID
   * @param args - Flutter 传入的初始化参数
   */
  constructor(context: common.Context, messenger: BinaryMessenger, viewId: number, args: Object) {
    super();
    flutterMLKitScannerView = this;
    this.context = context;
    this.channel = new MethodChannel(messenger, PluginConstants.CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);

    this.previewSize = this.parsePreviewSize(args);
    this.cameraService = this.createCameraService();
    this.scanMethodHandler = new ScanMethodHandler(this);
    this.scanResultProcessor = new ScanResultProcessor(this.createScanResultCallbacks());
  }

  /**
   * 创建 CameraService 实例，注入闪光灯状态读写闭包
   * @returns CameraService 实例，context 不可用时返回 null
   */
  private createCameraService(): CameraService | null {
    if (!this.context) {
      return null;
    }
    const ohosContext = this.context;
    return new CameraService(
      ohosContext,
      () => this.flashLightStatusBeforePause,
      (status: boolean) => {
        this.flashLightStatusBeforePause = status;
      },
    );
  }

  /**
   * 获取 CameraService 实例，懒创建
   * @returns CameraService 实例，创建失败时返回 null
   */
  public getCameraService(): CameraService | null {
    if (!this.cameraService) {
      this.cameraService = this.createCameraService();
    }
    return this.cameraService;
  }

  /**
   * 调整预览源尺寸，以适配 ScanKit 的宽高比要求（通常是竖屏扫码 9:16）
   * @param size - 原始预览源尺寸
   * @returns 调整后的尺寸，宽小于高时原样返回，宽大于高时交换宽高
   */
  private normalizePreviewSourceSizeForDisplay(size: Size): Size {
    if (size.width <= 0 || size.height <= 0) {
      return size;
    }
    if (size.width > size.height) {
      return {
        width: size.height,
        height: size.width,
      };
    }
    return size;
  }

  /**
   * 刷新预览源尺寸并触发预览尺寸更新流程，通常在初始化和切换摄像头后调用
   */
  private refreshPreviewSourceSize(): void {
    const service = this.getCameraService();
    const nextSize = service?.getPreferredPreviewSize(this.selectedCameraId) ?? null;
    if (!nextSize || nextSize.width <= 0 || nextSize.height <= 0) {
      return;
    }
    this.previewSourceSize = this.normalizePreviewSourceSizeForDisplay(nextSize);
  }

  /**
   * 创建扫码结果处理器回调集合
   * @returns 回调集合，桥接 MLKitScannerView 的状态读写
   */
  private createScanResultCallbacks(): ScanResultCallbacks {
    return {
      getIsScan: () => this.isScan,
      getIsDelayed: () => this.isDelayed,
      getOriginalValue: () => this.originalValue,
      setOriginalValue: (v: string) => { this.originalValue = v; },
      getYuvFrameHeight: () => this.yuvFrameHeight,
      setYuvFrameHeight: (h: number) => { this.yuvFrameHeight = h; },
      getPreviewSize: () => this.getPreviewSize(),
      getContainerSize: () => this.getContainerSize(),
      getInitialScannerParameters: () => this.initialScannerParameters,
      getChannel: () => this.channel,
      startScanDelayWindow: () => { this.startScanDelayWindow(); },
    };
  }

  /**
   * 处理帧扫码结果：委托给 ScanResultProcessor
   * @param result - ScanKit 返回的扫码结果
   */
  private onFrameResult(result: scanBarcode.ScanResult): void {
    this.scanResultProcessor.onFrameResult(result);
  }

  /**
   * 绑定帧监听器到 ImageReceiver，仅在未绑定时执行绑定
   */
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

  /**
   * 处理Flutter MethodChannel调用,根据方法名分发到对应处理函数
   * @param call - Flutter方法调用对象,包含方法名和参数
   * @param result - 方法结果回调,用于向Flutter返回结果或错误
   */
  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      switch (call.method) {
        case PluginConstants.INIT_CAMERA_METHOD:
          this.initCameraPreview(call, result);
          break;
        case PluginConstants.DISPOSE_CAMERA_METHOD:
          await this.disposeHandle(result);
          break;
        case PluginConstants.TOGGLE_FLASH_METHOD:
          this.toggleFlash(result);
          break;
        case PluginConstants.START_SCAN_METHOD:
          await this.scanMethodHandler.startScan(call, result);
          break;
        case PluginConstants.CANCEL_SCAN_METHOD:
          await this.scanMethodHandler.cancelScan(result);
          break;
        case PluginConstants.SET_SCAN_DELAY_METHOD:
          this.scanMethodHandler.setScanDelay(call, result);
          break;
        case PluginConstants.UPDATE_CONSTRAINTS_METHOD:
          this.scanMethodHandler.updateConstraints(call, result);
          break;
        case PluginConstants.PAUSE_CAMERA_METHOD:
          this.pauseCamera(result);
          break;
        case PluginConstants.RESUME_CAMERA_METHOD:
          await this.resumeCamera(call, result);
          break;
        case PluginConstants.SET_ZOOM_METHOD:
          this.setZoom(call, result);
          break;
        case PluginConstants.SET_CROP_AREA_METHOD:
          this.scanMethodHandler.setCropArea(call, result);
          break;
        case PluginConstants.GET_OHOS_AVAILABLE_CAMERAS_METHOD:
          this.scanMethodHandler.getOhosAvailableCameras(result);
          break;
        case PluginConstants.SET_OHOS_CAMERA_METHOD:
          this.scanMethodHandler.setOhosCamera(call, result);
          break;
        default:
          result.notImplemented();
          break;
      }
    } catch (error) {
      Log.e(TAG, `onMethodCall unhandled exception for method=${call.method}: ` + JSON.stringify(error));
      result.error('UNHANDLED_EXCEPTION', `Unhandled exception in ${call.method}: ${JSON.stringify(error)}`, null);
    }
  }

  /** 获取PlatformView的构建器,用于创建相机预览UI */
  public getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(CameraPreviewBuilder);
  }

  /** 获取当前预览尺寸(宽高) */
  public getPreviewSize(): Size {
    return {
      width: this.previewSize.width,
      height: this.previewSize.height,
    };
  }

  /** 获取容器尺寸(宽高) */
  public getContainerSize(): Size {
    return {
      width: this.containerSize.width,
      height: this.containerSize.height,
    };
  }

  /**
    * 处理用户对焦手势
    * @param touchX 触点X坐标,相对于预览图像左上角
    * @param touchY 触点Y坐标,相对于预览图像左上角
    * @param previewWidth 预览图像宽度
    * @param previewHeight 预览图像高度
    * @param needLock 是否需要锁定焦点(长按时为 true,单击时为 false)
    */
  public handleUserFocusGesture(
    touchX: number,
    touchY: number,
    previewWidth: number,
    previewHeight: number,
    needLock: boolean,
  ): void {
    if (!this.isCameraInitialized || this.previewState.isPausedByUser || !this.previewState.isRunning) {
      return;
    }

    try {
      const service = this.getCameraService();
      service?.focusAtPreviewPoint(touchX, touchY, previewWidth, previewHeight, needLock);
    } catch (error) {
      Log.e(TAG, 'handleUserFocusGesture error: ' + JSON.stringify(error));
    }
  }

  /**
   * 宿主区域变化(onAreaChange,单位 vp)：以原生布局为准,避免 Flutter 与 XComponent 尺寸不一致导致变形
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
    const sizeChanged = this.applyPreviewContainerSize(w, h);
    getCurrentCameraPreviewComponent()?.applyCropRect();
    if (sizeChanged && this.surfaceId && this.isCameraInitialized && this.previewState.isRunning &&
      !this.previewState.isPausedByUser) {
      void this.restartPreviewAfterLayoutChange();
    }
  }

  /**
   * 应用预览容器尺寸，计算居中裁剪后的预览尺寸
   * @param width - 容器宽度
   * @param height - 容器高度
   * @returns 预览尺寸是否发生变化
   */
  public applyPreviewContainerSize(width: number, height: number): boolean {
    this.containerSize = { width, height };
    const next = this.calcPreviewSizeAspectCover(width, height);
    const sizeChanged = next.width !== this.previewSize.width || next.height !== this.previewSize.height;
    this.previewSize = next;
    return sizeChanged;
  }

  /**
   * 布局变化后重启预览：释放旧会话、重新启动预览并应用缩放
   */
  public async restartPreviewAfterLayoutChange(): Promise<void> {
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

  /**
   * 设置XComponent的surfaceId,触发相机预览
   * @param surfaceId - XComponent提供的渲染表面ID
   */
  setSurfaceId(surfaceId: string) {
    this.surfaceId = surfaceId;
    // 触发相机预览启动（异步，不阻塞当前方法）
    void this.startPreview();
  }

  /**
   * 设置相机初始化状态,初始化成功时触发预览
   * @param isCameraInitialized - 是否已初始化
   */
  setCameraInitialized(isCameraInitialized: boolean) {
    this.isCameraInitialized = isCameraInitialized;
    if (isCameraInitialized) {
      this.beginPreviewSession();
      this.bindFrameListener();
      void this.startPreview();
    }
  }

  /**
   * 开启扫描会话，标记扫描状态为活跃
   */
  public beginScanSession(): void {
    this.isScan = true;
    getCurrentCameraPreviewComponent()?.setScanActive(true);
  }

  /**
   * 结束扫描会话，标记扫描状态为非活跃
   */
  public endScanSession(): void {
    this.isScan = false;
    getCurrentCameraPreviewComponent()?.setScanActive(false);
  }

  /** 标记预览会话开始运行 */
  public beginPreviewSession(): void {
    this.previewState.isRunning = true;
  }

  /**
   * 结束预览会话，标记预览状态为非运行
   */
  private endPreviewSession(): void {
    this.previewState.isRunning = false;
  }

  /**
   * 9:16 等比 Cover：宽或高贴齐宿主,另一维放大后居中裁剪
   */
  private calcPreviewSizeAspectCover(cw: number, ch: number): Size {
    if (cw <= 0 || ch <= 0) {
      return { width: 360, height: 640 };
    }
    const sourceWidth = this.previewSourceSize.width > 0
      ? this.previewSourceSize.width
      : PluginConstants.PREVIEW_RATIO_W;
    const sourceHeight = this.previewSourceSize.height > 0
      ? this.previewSourceSize.height
      : PluginConstants.PREVIEW_RATIO_H;
    const aspect: number = sourceWidth / sourceHeight;
    let width: number;
    let height: number;
    if (cw / ch > aspect) {
      width = Math.round(cw);
      height = Math.round((cw * sourceHeight) / sourceWidth);
    } else {
      height = Math.round(ch);
      width = Math.round((ch * sourceWidth) / sourceHeight);
    }
    return { width, height };
  }

  /**
   * 解析预览尺寸参数，计算居中裁剪后的实际预览尺寸
   * @param args - Flutter 传入的初始化参数
   * @returns 计算后的预览尺寸
   */
  private parsePreviewSize(args: Object): Size {
    const raw = ArgsParser.parsePositiveSize(ArgsParser.normalizeArgs(args));
    if (!raw) {
      this.containerSize = { width: 376, height: 200 };
      return this.calcPreviewSizeAspectCover(376, 200);
    }
    this.containerSize = { width: raw.width, height: raw.height };
    return this.calcPreviewSizeAspectCover(raw.width, raw.height);
  }

  /**
   * 清除扫描延迟定时器，重置延迟标志
   */
  public clearScanDelayTimer(): void {
    if (this.scanDelayTimerId >= 0) {
      clearTimeout(this.scanDelayTimerId);
      this.scanDelayTimerId = -1;
    }
    this.isDelayed = false;
  }

  /**
   * 启动扫描延迟窗口，在延迟期间阻止结果输出
   */
  public startScanDelayWindow(): void {
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

  /**
   * 暂停预览流：停止相机并重置帧监听绑定标志
   */
  private async pausePreviewFlow(): Promise<void> {
    if (!this.previewState.isRunning && !this.isScan) {
      return;
    }
    try {
      const service = this.getCameraService();
      await service?.stopCamera();
      // stopCamera 已通过 offImageArrival 取消了帧回调订阅，
      // 需重置绑定标志，以便 resume 时 bindFrameListener 能重新绑定
      this.isFrameListenerBound = false;
      this.endPreviewSession();
    } catch (error) {
      Log.e(TAG, 'pausePreviewFlow error: ' + JSON.stringify(error));
    }
  }

  /**
   * 恢复预览流：启动预览、应用缩放并恢复闪光灯状态
   */
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

  /**
   * 启动相机预览：创建相机设备、初始化相机会话、绑定帧监听并应用缩放
   */
  public async startPreview(): Promise<void> {
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
      // 如果 ensureImageReceiver 创建了新 ImageReceiver，需重置帧监听绑定标志
      if (service.imageReceiverRecreated) {
        this.isFrameListenerBound = false;
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
   * 初始化相机预览：解析参数、设置初始缩放和摄像头、刷新预览尺寸
   * @param call - Flutter 方法调用对象
   * @param result - 方法结果回调
   */
  private async initCameraPreview(call: MethodCall, result: MethodResult): Promise<void> {
    // 初始化相机预览
    if (!this.context) {
      result.error(PluginError.INIT_CAMERA_ERROR, 'context is undefined!', null);
      return;
    }

    if (this.isCameraInitialized) {
      result.success(true);
      return;
    }
    this.methodResult = result;

    const rawArgsMap: Object = call.args;
    const args = ArgsParser.normalizeArgs(rawArgsMap);
    // 逐字段提取并构造 OhosScannerParameters，避免直接类型断言
    if (args && Object.keys(args).length > 0) {
      const params: OhosScannerParameters = {};
      if (args['initialZoom'] !== undefined && args['initialZoom'] !== null) {
        params.initialZoom = Number(args['initialZoom']);
      }
      if (args['initialCamera'] !== undefined && args['initialCamera'] !== null) {
        const cam = args['initialCamera'] as Record<string, Object>;
        params.initialCamera = {
          position: Number(cam['position']),
          type: Number(cam['type']),
        };
      }
      if (args['initialCropRect'] !== undefined && args['initialCropRect'] !== null) {
        const rect = args['initialCropRect'] as Record<string, Object>;
        params.initialCropRect = {
          scaleWidth: Number(rect['scaleWidth']),
          scaleHeight: Number(rect['scaleHeight']),
          offsetX: Number(rect['offsetX']),
          offsetY: Number(rect['offsetY']),
        };
      }
      this.initialScannerParameters = params;
    } else {
      this.initialScannerParameters = null;
    }
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
    this.refreshPreviewSourceSize();
    this.applyPreviewContainerSize(this.containerSize.width, this.containerSize.height);

    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      comp.onInitCameraPreviewRequested();
    }
  }

  /**
   * 执行扫码资源释放：断开闭包引用并释放相机
   */
  private async runDisposeScanRelease(): Promise<void> {
    const service = this.cameraService;
    this.cameraService = null;
    if (!service) {
      return;
    }

    // 断开闭包对 MLKitScannerView 的引用，提前解除循环引用链
    service.clearSharedStateRefs();
    try {
      await service.releaseCamera();
    } catch (error) {
      Log.w(TAG, 'runDisposeScanRelease release skipped: ' + JSON.stringify(error));
    }
  }

  /**
   * 销毁后保底状态清理，避免重复进入销毁流程后状态残留
   */
  private resetStateAfterDispose(): void {
    // 保底状态清理,避免重复进入销毁流程后状态残留
    this.clearScanDelayTimer();
    this.originalValue = '';
    this.surfaceId = '';
    this.isCameraInitialized = false;
    this.endScanSession();
    this.endPreviewSession();
    this.desiredZoom = null;
    this.flashLightStatus = false;
    this.flashLightStatusBeforePause = false;
    this.previewState.isPausedByUser = false;
    this.isFrameListenerBound = false;
    this.isPreviewStarting = false;
    this.methodResult = null;
  }

  /**
   * 释放扫码资源：重置状态并释放相机服务，确保同一时间只有一个释放流程运行
   */
  private async disposeScanResources(): Promise<void> {
    if (this.disposePromise) {
      await this.disposePromise;
      return;
    }

    this.disposePromise = (async () => {
      this.resetStateAfterDispose();
      await this.runDisposeScanRelease();
    })();

    try {
      await this.disposePromise;
    } finally {
      this.disposePromise = null;
    }
  }

  /**
   * 断开 MethodChannel 处理器，停止接收 Flutter 调用
   */
  private detachChannelHandler(): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
    }
  }

  /**
   * 处理 dispose 调用：释放扫码资源并断开通道
   * @param result - 方法结果回调
   */
  private async disposeHandle(result: MethodResult): Promise<void> {
    try {
      await this.disposeScanResources();
      this.detachChannelHandler();
      result.success(true);
    } catch (error) {
      Log.e(TAG, `Failed to disposeHandle. Code: ${error.code}, message: ${error.message}`);
      result.error('DISPOSE_HANDLE_ERROR', `Failed to disposeHandle. ${error.code}, message: ${error.message}`, null);
    }
  }

  /**
   * 切换闪光灯状态：根据当前状态决定开启或关闭
   * @param result - 方法结果回调，不支持闪光灯时返回错误码 '4'
   */
  private toggleFlash(result: MethodResult): void {
    // 切换闪光灯
    if (!this.isCameraInitialized) {
      result.error(PluginError.CAMERA_IS_NOT_INITIALIZED, 'Camera is not initialized', null);
      return;
    }
    try {
      const service = this.getCameraService();
      const hasFlash = service?.hasFlash() ?? false;
      this.flashLightStatus = this.getFlashLightStatusSafely();
      // 根据当前闪光灯状态,选择开启或关闭闪光灯
      if (this.flashLightStatus) {
        this.closeFlashLightSafely();
        result.success(true);
      } else {
        if (!hasFlash) {
          result.error(PluginError.DEVICE_HAS_NOT_FLASH, 'The current camera does not support flash', null);
          return;
        }
        this.openFlashLightSafely();
        result.success(true);
      }
      this.flashLightStatusBeforePause = this.getFlashLightStatusSafely();
      // 将手电筒状态回传flutter
      this.channel?.invokeMethod(
        PluginConstants.CHANGE_TORCH_STATE_METHOD,
        this.flashLightStatusBeforePause
      );
    } catch (error) {
      Log.e(TAG, `Failed to getFlashLightStatus. Code: ${error.code}, message: ${error.message}`);
      result.error(PluginError.DEVICE_HAS_NOT_FLASH, `Failed to toggleFlash: ${error.code}, message: ${error.message}`, null);
    }
  }

  /**
   * 暂停相机：关闭闪光灯、标记用户暂停状态、停止预览流
   * @param result - 方法结果回调
   */
  private async pauseCamera(result: MethodResult): Promise<void> {
    try {
      // 暂停相机
      if (this.previewState.isPausedByUser) {
        result.success(true);
        return;
      }
      const isFlashOn = this.getFlashLightStatusSafely();
      if (isFlashOn) {
        this.closeFlashLightSafely();
      }
      // 强制恢复,因为上面的 closeFlashLightSafely 会触发回调将本类的状态设为了 false
      this.flashLightStatusBeforePause = isFlashOn;
      this.previewState.isPausedByUser = true;
      this.originalValue = '';
      this.clearScanDelayTimer();
      await this.pausePreviewFlow();
      result.success(true);
    } catch (error) {
      Log.e(TAG, 'pauseCamera failed: ' + JSON.stringify(error));
      result.error(PluginError.CAMERA_IS_NOT_INITIALIZED, 'pauseCamera failed', null);
    }
  }

  /**
   * 恢复相机预览,如果之前在扫描则恢复扫描
   * @param call - Flutter方法调用对象
   * @param result - 方法结果回调,成功返回true,失败返回错误码'3'
   */
  public async resumeCamera(call: MethodCall, result: MethodResult): Promise<void> {
    if (!this.previewState.isPausedByUser && this.previewState.isRunning) {
      result.success(true);
      return;
    }

    // 获取当前组件的状态是否是激活状态
    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      const active: boolean = comp.getScanActive();
      this.isScan = active;
    }
    this.previewState.isPausedByUser = false;
    try {
      await this.resumePreviewFlow();
      result.success(true);
    } catch (error) {
      Log.e(TAG, 'resumeCamera resumePreviewFlow failed: ' + JSON.stringify(error));
      result.error(PluginError.CAMERA_IS_NOT_INITIALIZED, 'Failed to resume camera: ' + JSON.stringify(error), null);
    }
  }

  /**
   * 安全获取闪光灯状态，异常时返回上次已知状态
   * @returns 闪光灯是否开启
   */
  public getFlashLightStatusSafely(): boolean {
    let flashLightStatus: boolean = this.flashLightStatus;
    try {
      const service = this.getCameraService();
      // 这里获取闪光灯状态时,有一个问题：进入应用,打开闪光灯,点击pause,
      // 应用切后台,再切前台,再点击startScan,此时这个接口报错,
      // 因为 ScanKit 在 pause 时会释放预览流,导致无法获取闪光灯状态。
      // 这里捕获异常,避免应用崩溃,并且在异常情况下返回上一次已知的闪光灯状态。
      flashLightStatus = service?.getFlashStatus() ?? this.flashLightStatus;
    } catch (error) {
      Log.e(TAG, `Failed to getFlashLightStatus. Code: ${error.code}, message: ${error.message}`);
    }
    return flashLightStatus;
  }

  /**
   * 安全关闭闪光灯，异常时仅记录日志
   */
  private closeFlashLightSafely(): void {
    try {
      const service = this.getCameraService();
      service?.setFlashMode(null, false);
      this.flashLightStatus = false;
    } catch (error) {
      Log.e(TAG, `Failed to closeFlashLight. Code: ${error.code}, message: ${error.message}`);
    }
  }

  /**
   * 安全开启闪光灯，异常时仅记录日志
   */
  private openFlashLightSafely(): void {
    try {
      const service = this.getCameraService();
      service?.setFlashMode(null, true);
      this.flashLightStatus = true;
    } catch (error) {
      Log.e(TAG, `Failed to openFlashLight. Code: ${error.code}, message: ${error.message}`);
    }
  }

  /**
   * 宿主应用进入后台时调用，暂停相机预览并释放相关资源
   */
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
      } catch (error) {
        Log.e(TAG,
          `Failed to onHostBackground. isPausedByUser == true. Code: ${error.code}, message: ${error.message}`);
      }
    } else {
      // 非用户暂停场景：释放会话资源而非仅停止，避免前台恢复时覆盖泄漏
      try {
        await this.pausePreviewFlow();
        const service = this.getCameraService();
        await service?.preFrontRelease(false);
      } catch (error) {
        Log.e(TAG,
          `Failed to onHostBackground. Code: ${error.code}, message: ${error.message}`);
      }
    }
  }

  /**
   * 宿主应用回到前台时调用，恢复相机预览和闪光灯状态
   */
  public async onHostForeground(): Promise<void> {
    if (!this.isCameraInitialized || !this.surfaceId) {
      return;
    }
    // 非用户触发pause后前后台切换
    if (!this.previewState.isPausedByUser) {
      try {
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

  /**
   * 设置缩放值：验证参数范围并应用
   * @param call - Flutter 方法调用对象，参数为 0~1 归一化缩放值
   * @param result - 方法结果回调
   */
  private setZoom(call: MethodCall, result: MethodResult): void {
    if (!this.isCameraInitialized) {
      result.error(
        PluginError.CAMERA_IS_NOT_INITIALIZED,
        'You need to invoke the \'initCameraPreview\' method before using zoom',
        null,
      );
      return;
    }
    const zoom = ArgsParser.parseZoomValue(call.args);
    if (zoom === null || zoom < 0 || zoom > 1) {
      result.error(
        PluginError.INVALID_ARGUMENTS,
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

    result.error(PluginError.DEVICE_HAS_NOT_ZOOM, 'Zoom is not supported on this device', null);
  }

  /**
   * 释放所有资源，等待异步释放完成后再返回
   */
  async dispose(): Promise<void> {
    await this.disposeScanResources();
    this.detachChannelHandler();
    flutterMLKitScannerView = null;
  }
}

/**
 * 相机预览 UI 构建器，创建 CameraPreviewComponent 实例
 * @param params - 平台视图参数，包含 MLKitScannerView 引用
 */
@Builder
function CameraPreviewBuilder(params: Params): void {
  CameraPreviewComponent({
    flutterMLKitScannerView: flutterMLKitScannerView,
  });
}

/**
 * 获取当前 MLKitScannerView 实例
 * @returns MLKitScannerView 实例，未初始化时返回 null
 */
export function getCurrentMLKitScannerView(): MLKitScannerView | null {
  if (flutterMLKitScannerView) {
    return flutterMLKitScannerView;
  }
  return null;
}
