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
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { Size } from './PluginConstants';

const TAG = '[CameraService]:';

export class CameraService {
  private static readonly DEFAULT_PREVIEW_WIDTH: number = 1920;
  private static readonly DEFAULT_PREVIEW_HEIGHT: number = 1080;
  private static readonly DEFAULT_CAMERA_CACHE_KEY: string = '__default__';
  public cameraManager: camera.CameraManager | undefined = undefined;
  // 相机缓存，避免频繁调用 getSupportedCameras 导致性能问题
  private static readonly CAMERA_CACHE_TTL_MS: number = 3000;
  private camerasLoadedAtMs: number = 0;
  private camerasDevices: Array<camera.CameraDevice> = [];
  // 当前使用的相机设备
  private curcamerasDevice: camera.CameraDevice | undefined = undefined;
  // 相机设备输入对象
  private cameraInput: camera.CameraInput | undefined = undefined;
  // 预览输出类
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  // 普通拍照模式会话类
  private photoSession: camera.PhotoSession | null = null;
  private context: Context | null = null;
  // 标记是否已停止，避免在停止后继续处理预览帧导致错误
  private isStop: boolean = false;
  // 解码节流，避免过于频繁地对预览帧进行解码，导致性能问题和重复结果
  private lastDecodeAtMs: number = 0;
  // 由外部注入的闪光灯状态读写器（共享 MLKitScannerView 中的状态）
  private readonly getSharedFlashStatus: () => boolean;
  private readonly setSharedFlashStatus: (status: boolean) => void;
  // 图像接收器，用于接收相机预览帧并进行扫码解码
  public imageReceiver: image.ImageReceiver;
  // 标记是否已释放 ImageReceiver，避免重复释放导致错误
  private isImageReceiverReleased: boolean = false;
  // 当前预览配置的尺寸，单位是像素。初始值为默认预览尺寸，后续会根据实际相机 profile 更新。
  private previewProfileSize: Size = {
    width: CameraService.DEFAULT_PREVIEW_WIDTH,
    height: CameraService.DEFAULT_PREVIEW_HEIGHT,
  };
  private preferredPreviewProfileCache: Record<string, camera.Profile> = {};

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
    const receiverFormat = imgReceiver?.format ?? image.ImageFormat.JPEG;
    const receiverCapacity = imgReceiver?.capacity ?? 1;
    this.imageReceiver = this.createImageReceiver(this.previewProfileSize, receiverFormat, receiverCapacity);
  }

  private createImageReceiver(size: Size, format: number, capacity: number): image.ImageReceiver {
    const previewSize: camera.Size = {
      width: size.width,
      height: size.height,
    } as camera.Size;
    return image.createImageReceiver(previewSize, format, capacity);
  }

  // 外部调用以更新预览配置时，确保 ImageReceiver 的尺寸和格式与预览输出匹配，否则可能导致无法正确接收预览帧。
  private async ensureImageReceiver(size: Size): Promise<void> {
    if (
      !this.isImageReceiverReleased &&
      this.previewProfileSize.width === size.width &&
      this.previewProfileSize.height === size.height
    ) {
      return;
    }

    try {
      if (!this.isImageReceiverReleased) {
        await this.imageReceiver.release();
      }
    } catch (error) {
      Log.w(TAG, 'ensureImageReceiver release skipped: ' + JSON.stringify(error));
    }

    this.previewProfileSize = {
      width: size.width,
      height: size.height,
    };
    this.imageReceiver = this.createImageReceiver(this.previewProfileSize, image.ImageFormat.JPEG, 1);
    this.isImageReceiverReleased = false;
  }

  private getPreviewProfileCacheKey(cameraId?: string): string {
    if (cameraId && cameraId.length > 0) {
      return cameraId;
    }
    return CameraService.DEFAULT_CAMERA_CACHE_KEY;
  }

  private resolveCameraDevice(cameraId?: string): camera.CameraDevice | undefined {
    if (!this.safeLoadCameras()) {
      return undefined;
    }
    if (cameraId) {
      const matched = this.camerasDevices.find((dev) => dev.cameraId === cameraId);
      if (matched) {
        return matched;
      }
    }
    return this.camerasDevices[0];
  }

  // 给定 CameraDevice，从 getSupportedOutputCapability 查找首选预览 Profile
  private getPreferredPreviewProfile(device: camera.CameraDevice): camera.Profile | undefined {
    const cachedProfile = this.preferredPreviewProfileCache[device.cameraId];
    if (cachedProfile) {
      return cachedProfile;
    }
    if (!this.cameraManager) {
      return undefined;
    }
    try {
      const profiles = this.cameraManager.getSupportedOutputCapability(
        device,
        camera.SceneMode.NORMAL_PHOTO,
      );
      const previewProfiles = profiles.previewProfiles;
      if (!previewProfiles || previewProfiles.length === 0) {
        Log.e(TAG, 'getPreferredPreviewProfile no preview profiles');
        return undefined;
      }

      const preferred = previewProfiles.find((profile: camera.Profile) => {
        return (
          profile.size.width === CameraService.DEFAULT_PREVIEW_WIDTH &&
          profile.size.height === CameraService.DEFAULT_PREVIEW_HEIGHT
        );
      });
      if (preferred) {
        this.preferredPreviewProfileCache[device.cameraId] = preferred;
        return preferred;
      }
      // 没有找到完全匹配的预览配置，按尺寸从大到小排序，选择最大的那个作为 fallback
      const sorted = [...previewProfiles].sort((a: camera.Profile, b: camera.Profile) => {
        return (b.size.width * b.size.height) - (a.size.width * a.size.height);
      });
      const fallback = sorted[0];
      this.preferredPreviewProfileCache[device.cameraId] = fallback;
      return fallback;
    } catch (error) {
      Log.e(TAG, 'getPreferredPreviewProfile failed: ' + JSON.stringify(error));
      return undefined;
    }
  }

  // 外部入口，通过 cameraId 查找相机设备 → 获取 Profile → 返回 Size
  public getPreferredPreviewSize(cameraId?: string): Size | null {
    const cacheKey = this.getPreviewProfileCacheKey(cameraId);
    const cachedProfile = this.preferredPreviewProfileCache[cacheKey];
    if (cachedProfile) {
      return {
        width: cachedProfile.size.width,
        height: cachedProfile.size.height,
      };
    }
    const device = this.resolveCameraDevice(cameraId);
    if (!device) {
      return null;
    }
    const profile = this.getPreferredPreviewProfile(device);
    if (!profile) {
      return null;
    }
    const resolvedSize: Size = {
      width: profile.size.width,
      height: profile.size.height,
    };

    return resolvedSize;
  }

  private safeLoadCameras(): boolean {
    if (!this.context) {
      return false;
    }

    const now = Date.now();
    const useCache =
      this.cameraManager !== undefined &&
        this.camerasDevices.length > 0 &&
        now - this.camerasLoadedAtMs < CameraService.CAMERA_CACHE_TTL_MS;
    if (useCache) {
      return true;
    }

    try {
      if (!this.cameraManager) {
        this.cameraManager = camera.getCameraManager(this.context);
      }
      // 获取设备支持的相机列表
      this.camerasDevices = this.cameraManager.getSupportedCameras() ?? [];
      this.camerasLoadedAtMs = now;
      return this.camerasDevices.length > 0;
    } catch (error) {
      Log.e(TAG, 'safeLoadCameras failed: ' + JSON.stringify(error));
      this.camerasLoadedAtMs = 0;
      return false;
    }
  }

  // 获取可用的相机列表
  public getAvailableCameras(): Array<Record<string, number | string>> {
    if (!this.safeLoadCameras()) {
      return [];
    }

    const result: Array<Record<string, number | string>> = [];
    for (const device of this.camerasDevices) {
      result.push({
        'cameraId': device.cameraId,
        'position': device.cameraPosition,
        'type': device.cameraType,
      });
    }

    return result;
  }

  // 根据 dart侧传入的 position 和 type，查找最匹配的 cameraId，优先级为 position+type > position > 任意可用
  public findCameraIdByOhosCodes(positionCode: number, typeCode: number): string | undefined {
    const cameras = this.getAvailableCameras();
    if (cameras.length === 0) {
      return undefined;
    }

    const strict = cameras.find((c) => c['position'] === positionCode && c['type'] === typeCode);
    if (strict) {
      return strict['cameraId'] as string;
    }

    const positionOnly = cameras.find((c) => c['position'] === positionCode);
    if (positionOnly) {
      return positionOnly['cameraId'] as string;
    }

    return cameras[0]['cameraId'] as string;
  }

  async createCamera(cameraManager: camera.CameraManager): Promise<void> {
    this.cameraManager = cameraManager;
    try {
      this.camerasDevices = this.cameraManager.getSupportedCameras() ?? [];
      this.camerasLoadedAtMs = Date.now();
    } catch (error) {
      Log.e(TAG, 'createCamera failed: ' + JSON.stringify(error));
      this.camerasDevices = [];
      this.camerasLoadedAtMs = 0;
    }
  }

  async initCamera(XComponentSurfaceId: string, cameraId?: string): Promise<boolean> {
    if (!this.safeLoadCameras() || !this.cameraManager) {
      Log.e(TAG, 'initCamera failed: camera manager unavailable');
      return false;
    }

    this.curcamerasDevice = this.resolveCameraDevice(cameraId);
    if (!this.curcamerasDevice) {
      Log.e(TAG, 'initCamera failed: camera device unavailable');
      return false;
    }

    try {
      // 获取指定的相机设备对象支持的模式
      const sceneModes = this.cameraManager.getSupportedSceneModes(this.curcamerasDevice);
      const supportPhoto = sceneModes.indexOf(camera.SceneMode.NORMAL_PHOTO) >= 0;
      if (!supportPhoto) {
        Log.e(TAG, 'photo mode not supported');
        return false;
      }

      const previewProfile = this.getPreferredPreviewProfile(this.curcamerasDevice);
      if (!previewProfile) {
        Log.e(TAG, 'preview profile not found');
        return false;
      }

      await this.ensureImageReceiver({
        width: previewProfile.size.width,
        height: previewProfile.size.height,
      });

      // 创建一个预览输出对象，输出到 XComponentSurfaceId 以显示预览画面
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, XComponentSurfaceId);
      // 用于获取一个surface id供Camera或其他组件使用
      const imageSurfaceId = await this.imageReceiver.getReceivingSurfaceId();
      // 创建第二个预览输出对象，输出到 imageReceiver 以获取预览帧进行扫码解码
      const previewOutput2 = this.cameraManager.createPreviewOutput(previewProfile, imageSurfaceId);
      // 使用CameraDevice对象创建CameraInput实例
      this.cameraInput = this.cameraManager.createCameraInput(this.curcamerasDevice);
      // 打开相机
      await this.cameraInput.open();

      this.photoSession = this.cameraManager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
      // 开始配置会话
      this.photoSession.beginConfig();
      // 把CameraInput加入到会话
      this.photoSession.addInput(this.cameraInput);
      // 把PreviewOutput加入到会话
      this.photoSession.addOutput(this.previewOutput);
      this.photoSession.addOutput(previewOutput2);
      // 提交配置信息
      await this.photoSession.commitConfig();
      // 开始会话工作
      await this.photoSession.start();
      // 设置连续自动对焦模式
      this.setFocusMode(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO);
      this.isStop = false;
      return true;
    } catch (error) {
      Log.e(TAG, 'initCamera failed: ' + JSON.stringify(error));
      return false;
    }
  }

  private clearSessionRefs(): void {
    this.photoSession = null;
    this.cameraInput = undefined;
    this.previewOutput = undefined;
    this.curcamerasDevice = undefined;
  }

  private async releaseSessionResources(): Promise<void> {
    const session = this.photoSession;
    const input = this.cameraInput;
    const preview = this.previewOutput;
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
  }

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
   * HarmonyOS 对焦点坐标系定义：以“充电口在右侧”的横屏方向为基准。
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
   * needLock=true：切到自动对焦模式，模拟“锁定当前对焦点”。
   * needLock=false：切回连续自动对焦。
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
    const OhosStyleRatio = 1 + clamped * 5;
    const ratio = Math.max(minRatio, Math.min(OhosStyleRatio, maxRatio));
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

  async stopCamera(): Promise<void> {
    try {
      // 停止会话工作，通过注册回调函数获取结果
      await this.photoSession?.stop();
      this.isStop = true;
    } catch (error) {
      Log.e(TAG, 'stopCamera failed: ' + JSON.stringify(error));
    }
  }

  async preFrontRelease(isStop: boolean): Promise<void> {
    this.isStop = isStop;
    try {
      // 释放会话资源，通过注册回调函数获取结果
      await this.releaseSessionResources();
    } catch (error) {
      Log.e(TAG, 'preFrontRelease failed: ' + JSON.stringify(error));
    }
  }

  async releaseCamera(): Promise<void> {
    try {
      this.isStop = true;
      await this.releaseSessionResources();
      if (!this.isImageReceiverReleased) {
        this.isImageReceiverReleased = true;
        await this.imageReceiver.release();
      }
    } catch (error) {
      Log.w(TAG, 'releaseCamera skipped: ' + JSON.stringify(error));
    }
  }

  // 注册预览帧到达的回调函数，在回调中读取预览帧图像并进行扫码解码
  onImageArrival(scanCallback: (result: scanBarcode.ScanResult) => void): void {
    this.imageReceiver.on('imageArrival', () => {
      if (this.isStop) {
        return;
      }
      // 从ImageReceiver读取下一张图片
      this.imageReceiver.readNextImage((err: BusinessError, nextImage: image.Image) => {
        if (err || nextImage === undefined) {
          Log.e(TAG, 'onImageArrival readNextImage failed');
          return;
        }
        // 根据图像的组件类型从图像中获取组件缓存
        nextImage.getComponent(image.ComponentType.JPEG, async (compErr: BusinessError, imgComponent: image.Component) => {
          if (compErr || imgComponent === undefined) {
            Log.e(TAG, 'onImageArrival getComponent(JPEG) failed: ' + JSON.stringify(compErr));
            await nextImage.release();
            return;
          }
          if (imgComponent.byteBuffer as ArrayBuffer) {
            // 对图片进行解码
            await this.decodeImageBuffer(imgComponent, nextImage.size.width, nextImage.size.height, scanCallback, nextImage);
          } else {
            await nextImage.release();
          }
        });
      });
    });
  }

  async decodeImageBuffer(
    imgComponent: image.Component,
    width: number,
    height: number,
    scanCallback: (result: scanBarcode.ScanResult) => void,
    nextImage: image.Image
  ): Promise<void> {
    const now = Date.now();
    if (now - this.lastDecodeAtMs < 800) {
      await nextImage.release();
      return;
    }
    this.lastDecodeAtMs = now;

    // 构造扫码解码需要的 ByteImage 对象，包含图像数据的字节缓冲区、图像宽高和格式等信息
    const byteImg: detectBarcode.ByteImage = {
      byteBuffer: imgComponent.byteBuffer,
      width: width,
      height: height,
      format: detectBarcode.ImageFormat.NV21,
    };
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: true,
      enableAlbum: false,
    };

    detectBarcode.decodeImage(byteImg, options).then((detectResult: detectBarcode.DetectResult) => {
      if (detectResult.scanResults.length > 0) {
        const res: scanBarcode.ScanResult = detectResult.scanResults[0];
        if (res && res.originalValue) {
          const resultMap = res;
          resultMap['frameHeight'] = height;
          scanCallback(res);
        }
      }
    }).catch((error: BusinessError) => {
      Log.e(TAG, 'decodeImageBuffer failed: ' + error.message);
    }).finally(async () => {
      await nextImage.release();
    });
  }
}
