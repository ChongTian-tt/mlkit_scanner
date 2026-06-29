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

import image from '@ohos.multimedia.image';
import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log, MethodResult } from '@ohos/flutter_ohos';
import { scanBarcode } from '@kit.ScanKit';
import { PluginConstants, Size } from './PluginConstants';
import { CameraDeviceManager } from './CameraDeviceManager';
import { ScanDecoder } from './ScanDecoder';

const TAG: string = '[CameraService]:';

export class CameraService {
  private deviceManager: CameraDeviceManager;
  public decoder: ScanDecoder;
  // 当前使用的相机设备
  private currentCameraDevice: camera.CameraDevice | undefined = undefined;
  // 相机设备输入对象
  private cameraInput: camera.CameraInput | undefined = undefined;
  // 预览输出类
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  // 第二预览输出（输出到 ImageReceiver 用于扫码解码）
  private previewOutput2: camera.PreviewOutput | undefined = undefined;
  // 普通拍照模式会话类
  private photoSession: camera.PhotoSession | null = null;
  private context: Context | null = null;
  // 由外部注入的闪光灯状态读写器（共享 MLKitScannerView 中的状态）
  // 非 readonly 以便在 dispose 时通过 clearSharedStateRefs() 断开循环引用
  private getSharedFlashStatus: () => boolean;
  private setSharedFlashStatus: (status: boolean) => void;

  /**
   * 获取相机管理器实例（委托到 CameraDeviceManager）
   */
  get cameraManager(): camera.CameraManager | undefined {
    return this.deviceManager.cameraManager;
  }

  /**
   * 创建 CameraService 实例
   * @param context - Ability 上下文
   * @param getSharedFlashStatus - 获取共享闪光灯状态的闭包
   * @param setSharedFlashStatus - 设置共享闪光灯状态的闭包
   * @param imgReceiver - 可选的 ImageReceiver 实例，不传则使用默认配置创建
   */
  constructor(
    context: Context,
    getSharedFlashStatus?: () => boolean,
    setSharedFlashStatus?: (status: boolean) => void,
    imgReceiver?: image.ImageReceiver,
  ) {
    this.context = context;
    this.getSharedFlashStatus = getSharedFlashStatus ?? (() => false);
    this.setSharedFlashStatus = setSharedFlashStatus ?? ((_: boolean) => {
    });
    this.deviceManager = new CameraDeviceManager(context);
    this.decoder = new ScanDecoder(
      { width: PluginConstants.DEFAULT_PREVIEW_WIDTH, height: PluginConstants.DEFAULT_PREVIEW_HEIGHT },
      imgReceiver,
    );
  }

  /**
   * 初始化相机，创建会话、配置预览并启动
   * @param XComponentSurfaceId - XComponent渲染表面ID
   * @param cameraId - 可选的相机设备ID，不传则使用默认相机
   * @returns 初始化是否成功
   */
  async initCamera(XComponentSurfaceId: string, cameraId?: string): Promise<boolean> {
    try {
      if (!this.deviceManager.safeLoadCameras() || !this.deviceManager.cameraManager) {
        Log.e(TAG, 'initCamera failed: camera manager unavailable');
        return false;
      }
    } catch (error) {
      Log.e(TAG, 'initCamera safeLoadCameras failed: ' + JSON.stringify(error));
      return false;
    }

    const device = this.deviceManager.resolveCameraDevice(cameraId);
    if (!device) {
      Log.e(TAG, 'initCamera failed: camera device unavailable');
      return false;
    }

    try {
      // 先释放旧会话资源，防止覆盖泄漏
      // clearSessionRefs 会将 currentCameraDevice 置空，因此在释放后再赋值
      await this.releaseSessionResources();
      this.currentCameraDevice = device;

      const previewProfile = this.deviceManager.validateAndGetPreviewProfile(device);
      if (!previewProfile) {
        return false;
      }

      await this.decoder.ensureImageReceiver({
        width: previewProfile.size.width,
        height: previewProfile.size.height,
      });

      await this.configurePhotoSession(previewProfile, XComponentSurfaceId);
      this.setFocusMode(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO);
      this.decoder.setStop(false);
      return true;
    } catch (error) {
      // 失败时释放已创建的资源
      await this.releaseSessionResources();
      Log.e(TAG, 'initCamera failed: ' + JSON.stringify(error));
      return false;
    }
  }

  /**
   * 配置相机会话：创建输入/输出、提交并启动
   * @param previewProfile - 预览 Profile
   * @param surfaceId - XComponent 渲染表面 ID
   */
  private async configurePhotoSession(previewProfile: camera.Profile, surfaceId: string): Promise<void> {
    this.previewOutput = this.deviceManager.cameraManager!.createPreviewOutput(previewProfile, surfaceId);
    const imageSurfaceId = await this.decoder.imageReceiver.getReceivingSurfaceId();
    this.previewOutput2 = this.deviceManager.cameraManager!.createPreviewOutput(previewProfile, imageSurfaceId);
    this.cameraInput = this.deviceManager.cameraManager!.createCameraInput(this.currentCameraDevice!);
    await this.cameraInput.open();

    this.photoSession = this.deviceManager.cameraManager!.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
    this.photoSession.beginConfig();
    this.photoSession.addInput(this.cameraInput);
    this.photoSession.addOutput(this.previewOutput);
    this.photoSession.addOutput(this.previewOutput2);
    await this.photoSession.commitConfig();
    await this.photoSession.start();
  }

  /**
   * 清空会话引用，将会话、输入、输出和设备引用置空
   */
  private clearSessionRefs(): void {
    this.photoSession = null;
    this.cameraInput = undefined;
    this.previewOutput = undefined;
    this.previewOutput2 = undefined;
    this.currentCameraDevice = undefined;
  }

  /**
   * 释放会话资源：清空引用后依次释放会话、输入、预览输出
   */
  private async releaseSessionResources(): Promise<void> {
    const session = this.photoSession;
    const input = this.cameraInput;
    const preview = this.previewOutput;
    const preview2 = this.previewOutput2;
    this.clearSessionRefs();

    try {
      await session?.release();
    } catch (error) {
      Log.w(TAG, 'releaseSessionResources session skipped: ' + JSON.stringify(error));
    }

    try {
      await input?.close();
    } catch (error) {
      Log.w(TAG, 'releaseSessionResources input skipped: ' + JSON.stringify(error));
    }

    try {
      await preview?.release();
    } catch (error) {
      Log.w(TAG, 'releaseSessionResources preview skipped: ' + JSON.stringify(error));
    }

    try {
      await preview2?.release();
    } catch (error) {
      Log.w(TAG, 'releaseSessionResources preview2 skipped: ' + JSON.stringify(error));
    }
  }

  /**
   * 设置对焦模式
   * @param focusMode - 对焦模式枚举值
   * @returns 无返回值
   */
  setFocusMode(focusMode: camera.FocusMode): void {
    if (!this.photoSession) {
      return;
    }
    try {
      // 检测对焦模式是否支持
      const supported = this.photoSession.isFocusModeSupported(focusMode);
      if (supported) {
        this.photoSession.setFocusMode(focusMode);
      }
    } catch (error) {
      Log.e(TAG, 'setFocusMode failed: ' + JSON.stringify(error));
    }
  }

  /**
   * 将数值夹取到 [0, 1] 区间，非有限数值返回 0
   * @param value - 输入数值
   * @returns 夹取后的数值
   */
  private clamp01(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }

  /**
   * 将预览坐标转换到 Focus.setFocusPoint 所需坐标系。
   *
   * HarmonyOS 对焦点坐标系定义：以"充电口在右侧"的横屏方向为基准。
   * 本插件预览默认按竖屏展示，因此使用官方建议转换：{x, y} -> {y/h, 1-x/w}。
   */
  private toFocusPointFromPreview(x: number, y: number, width: number, height: number): camera.Point {
    const nx = this.clamp01(y / height);
    const ny = this.clamp01(1 - x / width);
    return {
      x: nx,
      y: ny,
    } as camera.Point;
  }

  /**
   * 轻触/长按触发对焦。
   * needLock=true：切到对焦锁定
   * needLock=false：切回自动对焦
   * @param x - 触点X坐标，相对于预览图像左上角
   * @param y - 触点Y坐标，相对于预览图像左上角
   * @param previewWidth - 预览图像宽度
   * @param previewHeight - 预览图像高度
   * @param needLock - 是否需要锁定焦点（长按为true，轻触为false）
   * @returns 是否成功设置对焦点
   */
  focusAtPreviewPoint(
    x: number,
    y: number,
    previewWidth: number,
    previewHeight: number,
    needLock: boolean,
  ): boolean {
    if (!this.photoSession || previewWidth <= 0 || previewHeight <= 0) {
      return false;
    }

    try {
      const focusPoint = this.toFocusPointFromPreview(x, y, previewWidth, previewHeight);
      this.photoSession.setFocusPoint(focusPoint);

      const targetMode = needLock
        // 对焦锁定
        ? camera.FocusMode.FOCUS_MODE_LOCKED
        // 自动对焦
        : camera.FocusMode.FOCUS_MODE_AUTO;
      if (this.photoSession.isFocusModeSupported(targetMode)) {
        this.photoSession.setFocusMode(targetMode);
      }
      return true;
    } catch (error) {
      Log.e(TAG, 'focusAtPreviewPoint failed: ' + JSON.stringify(error));
      return false;
    }
  }

  /**
   * 获取闪光灯当前状态，异常时返回上次已知状态
   * @returns 闪光灯是否开启
   */
  getFlashStatus(): boolean {
    if (!this.photoSession) {
      return this.getSharedFlashStatus();
    }
    try {
      // 获取当前设备的闪光灯模式
      const flashMode = this.photoSession.getFlashMode();
      const isOpen = flashMode === camera.FlashMode.FLASH_MODE_ALWAYS_OPEN;
      this.setSharedFlashStatus(isOpen);
      return isOpen;
    } catch (error) {
      Log.e(TAG, 'getFlashStatus failed: ' + JSON.stringify(error));
      // 返回上一次已知的闪光灯状态
      const lastKnownStatus = this.getSharedFlashStatus();
      Log.e(TAG, 'Returning shared flash status: ' + lastKnownStatus);
      return lastKnownStatus;
    }
  }

  /**
   * 设置闪光灯模式
   * @param result - Flutter方法结果回调，设备不支持时返回错误码'4'
   * @param isOpen - 是否开启闪光灯
   */
  setFlashMode(result: MethodResult | null, isOpen: boolean): void {
    if (!this.hasFlash()) {
      result?.success(isOpen);
      Log.e(TAG, 'The camera device does not have flash.');
      return;
    }

    const newMode = isOpen ? camera.FlashMode.FLASH_MODE_ALWAYS_OPEN : camera.FlashMode.FLASH_MODE_CLOSE;
    if (!this.isFlashModeSupported(newMode)) {
      result?.success(isOpen);
      Log.e(TAG, 'The flash mode is unsupported.');
      return;
    }

    try {
      this.photoSession?.setFlashMode(newMode);
      this.setSharedFlashStatus(isOpen);
      result?.success(isOpen);
    } catch (error) {
      Log.e(TAG, 'setFlashMode failed: ' + JSON.stringify(error));
      result?.success(!isOpen);
    }
  }

  /**
   * 检查设备是否支持闪光灯
   * @returns 是否支持闪光灯
   */
  hasFlash(): boolean {
    try {
      // 检测是否有闪光灯，返回是否支持闪光灯
      return this.photoSession?.hasFlash() ?? false;
    } catch (error) {
      const err = error as BusinessError;
      Log.e(TAG, `hasFlash failed: ${err.code}`);
      return false;
    }
  }

  /**
   * 检查是否支持指定的闪光灯模式
   * @param mode - 闪光灯模式枚举值
   * @returns 是否支持该闪光灯模式
   */
  isFlashModeSupported(mode: camera.FlashMode): boolean {
    try {
      // 检测闪光灯模式是否支持
      return this.photoSession?.isFlashModeSupported(mode) ?? false;
    } catch (error) {
      const err = error as BusinessError;
      Log.e(TAG, `isFlashModeSupported failed: ${err.code}`);
      return false;
    }
  }

  /**
   * 获取缩放比率范围 [最小值, 最大值]
   * @returns 缩放比率范围数组，空数组表示不支持或不可用
   */
  getZoomRatioRange(): Array<number> {
    if (!this.photoSession) {
      return [];
    }
    try {
      // 获取支持的变焦范围
      const range = this.photoSession.getZoomRatioRange();
      if (!range || range.length < 2) {
        return [];
      }
      const min = Number(range[0]);
      const max = Number(range[1]);
      if (!Number.isFinite(min) || !Number.isFinite(max) || max < min) {
        return [];
      }
      return [min, max];
    } catch (error) {
      const err = error as BusinessError;
      Log.e(TAG, `getZoomRatioRange failed: ${err.code}`);
      return [];
    }
  }

  /**
   * 设置归一化缩放值（0~1），映射到实际缩放比率
   * @param normalized - 归一化缩放值（0~1）
   * @returns 是否设置成功
   */
  setZoomNormalized(normalized: number): boolean {
    if (!this.photoSession) {
      return false;
    }
    const range = this.getZoomRatioRange();
    if (range.length < 2) {
      return false;
    }

    const minRatio = range[0];
    const maxRatio = range[1];
    const clamped = Math.max(0, Math.min(1, normalized));
    // 对齐 iOS: zoom = 1 + value * 5，语义范围约为 1x..6x，再按设备能力夹取。
    const ohosStyleRatio = 1 + clamped * 5;
    const ratio = Math.max(minRatio, Math.min(ohosStyleRatio, maxRatio));
    // 官方说明支持到小数点后两位精度。
    const ratioRounded = Math.round(ratio * 100) / 100;

    try {
      // 设置变焦比，变焦精度最高为小数点后两位
      this.photoSession.setZoomRatio(ratioRounded);
      return true;
    } catch (error) {
      const err = error as BusinessError;
      Log.e(TAG, `setZoomNormalized failed: ${err.code}`);
      return false;
    }
  }

  /**
   * 停止相机预览，取消 imageArrival 订阅
   */
  async stopCamera(): Promise<void> {
    try {
      // 停止会话工作，通过注册回调函数获取结果
      await this.photoSession?.stop();
      this.decoder.setStop(true);
      // 显式取消 imageArrival 订阅，避免后台切换时回调在已停止状态下触发
      this.decoder.offImageArrival();
    } catch (error) {
      Log.e(TAG, 'stopCamera failed: ' + JSON.stringify(error));
    }
  }

  /**
   * 前台释放准备，停止相机并释放部分会话资源
   * @param isStop - 是否停止
   */
  async preFrontRelease(isStop: boolean): Promise<void> {
    this.decoder.setStop(isStop);
    try {
      // 释放会话资源，通过注册回调函数获取结果
      await this.releaseSessionResources();
    } catch (error) {
      Log.e(TAG, 'preFrontRelease failed: ' + JSON.stringify(error));
    }
  }

  /**
   * 释放所有相机资源：取消事件订阅、释放会话、释放 ImageReceiver、清空缓存
   */
  async releaseCamera(): Promise<void> {
    try {
      this.decoder.setStop(true);
      this.decoder.offImageArrival();
      await this.releaseSessionResources();
      await this.decoder.releaseImageReceiver();
      // 显式清理缓存数据和系统资源引用
      this.deviceManager.releaseDeviceManager();
    } catch (error) {
      Log.w(TAG, 'releaseCamera skipped: ' + JSON.stringify(error));
    }
  }

  /**
   * 断开闭包对 MLKitScannerView 的引用，提前解除循环引用链
   */
  clearSharedStateRefs(): void {
    this.getSharedFlashStatus = () => false;
    this.setSharedFlashStatus = (_: boolean) => {};
  }

  // ========== 委托方法（CameraDeviceManager） ==========

  /**
   * 通过 cameraId 查找相机设备，获取首选预览 Profile 并返回 Size
   * @param cameraId - 可选的相机设备ID，不传则使用默认相机
   * @returns 预览尺寸，未找到时返回 null
   */
  public getPreferredPreviewSize(cameraId?: string): Size | null {
    return this.deviceManager.getPreferredPreviewSize(cameraId);
  }

  /**
   * 获取可用的相机列表，包含 cameraId、position、type 信息
   * @returns 相机信息数组
   */
  public getAvailableCameras(): Array<Record<string, number | string>> {
    return this.deviceManager.getAvailableCameras();
  }

  /**
   * 根据 Dart 侧传入的 position 和 type，查找最匹配的 cameraId
   * 优先级为 position+type > position > 任意可用
   * @param positionCode - 相机位置编码
   * @param typeCode - 相机类型编码
   * @returns 匹配的 cameraId，无可用相机时返回 undefined
   */
  public findCameraIdByOhosCodes(positionCode: number, typeCode: number): string | undefined {
    return this.deviceManager.findCameraIdByOhosCodes(positionCode, typeCode);
  }

  /**
   * 创建相机设备，查询所有可用相机并缓存
   * @param cameraManager - 相机管理器实例
   */
  async createCamera(cameraManager: camera.CameraManager): Promise<void> {
    await this.deviceManager.createCamera(cameraManager);
  }

  // ========== 委托属性（ScanDecoder） ==========

  /**
   * 获取 ImageReceiver 实例（委托到 ScanDecoder）
   */
  public get imageReceiver(): image.ImageReceiver {
    return this.decoder.imageReceiver;
  }

  /**
   * 获取 ImageReceiver 是否被重建（委托到 ScanDecoder）
   */
  public get imageReceiverRecreated(): boolean {
    return this.decoder.imageReceiverRecreated;
  }

  /**
   * 注册预览帧到达的回调函数（委托到 ScanDecoder）
   * @param scanCallback - 扫码结果回调，接收 ScanResult 对象和帧高度
   */
  onImageArrival(scanCallback: (result: scanBarcode.ScanResult, frameHeight: number) => void): void {
    this.decoder.onImageArrival(scanCallback);
  }

  /**
   * 设置解码节流间隔（委托到 ScanDecoder）
   * @param ms - 节流间隔（毫秒），小于50会被自动调整为50
   */
  setDecodeThrottleMs(ms: number): void {
    this.decoder.setDecodeThrottleMs(ms);
  }
}
