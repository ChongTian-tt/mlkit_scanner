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

const TAG = '[CameraService]:';

export class CameraService {
  public cameraManager: camera.CameraManager | undefined = undefined;
  // 相机缓存，避免频繁调用 getSupportedCameras 导致性能问题
  private static readonly CAMERA_CACHE_TTL_MS: number = 3000;
  private camerasLoadedAtMs: number = 0;
  private camerasDevices: Array<camera.CameraDevice> = [];
  // 当前使用的相机设备
  private curcamerasDevice: camera.CameraDevice | undefined = undefined;
  // 相机设备输入对象
  private cameraInput: camera.CameraInput | undefined = undefined;
  // 拍照会话中使用的输出信息 目前似乎未赋值
  private photoOutput: camera.PhotoOutput | undefined = undefined;
  // 预览输出类
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  // 普通拍照模式会话类
  private photoSession: camera.PhotoSession | null = null;
  private context: Context | null = null;
  // 标记是否已停止，避免在停止后继续处理预览帧导致错误
  private isStop: boolean = false;
  // 解码节流，避免过于频繁地对预览帧进行解码，导致性能问题和重复结果
  private lastDecodeAtMs: number = 0;
  // TODO: 解码尝试计数，仅用于日志记录，帮助分析解码频率和成功率
  private decodeAttemptCount: number = 0;
  // 图像接收器，用于接收相机预览帧并进行扫码解码
  public imageReceiver: image.ImageReceiver;

  constructor(context: Context, imgReceiver?: image.ImageReceiver) {
    this.context = context;
    // TODO: 固定使用 1920x1080 的预览分辨率，兼容性较好且性能可控。实际使用中会根据设备支持情况进行回退选择。
    const previewSize: camera.Size = { width: 1920, height: 1080 } as camera.Size;
    if (imgReceiver === undefined) {
      // 通过图片大小、图片格式、容量创建ImageReceiver实例
      this.imageReceiver = image.createImageReceiver(previewSize, image.ImageFormat.JPEG, 1);
    } else {
      this.imageReceiver = image.createImageReceiver(previewSize, imgReceiver.format, imgReceiver.capacity);
    }
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
      Log.i(TAG, `this.camerasDevices length= ${this.camerasDevices.length}`);
      return this.camerasDevices.length > 0;
    } catch (error) {
      Log.e(TAG, 'safeLoadCameras failed: ' + JSON.stringify(error));
      this.camerasLoadedAtMs = 0;
      return false;
    }
  }

  // 映射 dart侧传入的 position
  private mapPositionToIosCode(position: camera.CameraPosition): number {
    if (position === camera.CameraPosition.CAMERA_POSITION_BACK) {
      return 1;
    }
    if (position === camera.CameraPosition.CAMERA_POSITION_FRONT) {
      return 2;
    }
    // 相对于设备屏幕没有固定的朝向的相机
    return 0;
  }

  // 映射 dart侧传入的 type
  private mapTypeToIosCode(type: camera.CameraType): number {
    const typeName = this.getCameraTypeName(type).toUpperCase();
    // 长焦
    if (typeName.indexOf('TELE') >= 0) {
      return 1;
    }
    // 超广角
    if (typeName.indexOf('ULTRA') >= 0 && typeName.indexOf('WIDE') >= 0) {
      return 3;
    }
    // 默认相机类型
    return 0;
  }

  // 获取 camera type 的字符串名称
  private getCameraTypeName(type: camera.CameraType): string {
    const typeRecord = camera.CameraType as ESObject as Record<string, number>;
    const rawType = Number(type);
    const keys = Object.keys(typeRecord);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      if (typeRecord[key] === rawType) {
        return key;
      }
    }
    return `UNKNOWN_${rawType}`;
  }

  // 获取可用的相机列表
  public getAvailableCameras(): Array<Record<string, number | string>> {
    if (!this.safeLoadCameras()) {
      return [];
    }

    const result: Array<Record<string, number | string>> = [];
    for (const device of this.camerasDevices) {
      const mappedPosition = this.mapPositionToIosCode(device.cameraPosition);
      const mappedType = this.mapTypeToIosCode(device.cameraType);
      // TODO: 日志记录原始和映射后的信息，便于分析设备差异和调试。
      const typeName = this.getCameraTypeName(device.cameraType);

      result.push({
        'cameraId': device.cameraId,
        'position': mappedPosition,
        'type': mappedType,
      });
    }

    Log.i(TAG, `getAvailableCameras total=${result.length}`);
    return result;
  }

  // 根据 dart侧传入的 position 和 type，查找最匹配的 cameraId，优先级为 position+type > position > 任意可用
  public findCameraIdByIosCodes(positionCode: number, typeCode: number): string | undefined {
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

  // 获取预览配置
  getPreviewProfilesObj(): camera.Profile | undefined {
    if (!this.cameraManager || !this.curcamerasDevice) {
      return undefined;
    }
    try {
      // 查询相机设备在指定模式下支持的输出能力，同步返回结果
      const profiles = this.cameraManager.getSupportedOutputCapability(
        this.curcamerasDevice,
        camera.SceneMode.NORMAL_PHOTO,
      );
      // 支持的预览配置信息集合
      const previewProfiles = profiles.previewProfiles;
      if (!previewProfiles || previewProfiles.length === 0) {
        Log.e(TAG, 'getPreviewProfilesObj no preview profiles');
        return undefined;
      }
      // TODO: 优先选择 1920x1080 的预览分辨率，兼容性较好且性能可控。实际使用中会根据设备支持情况进行回退选择。
      const preferred = previewProfiles.find((profile: camera.Profile) => {
        Log.i(TAG, `getPreviewProfilesObj supported profile: ${profile.size.width}x${profile.size.height}`);
        return profile.size.width === 1920 && profile.size.height === 1080;
      });
      if (preferred) {
        return preferred;
      }

      // 回退到分辨率最高的可用 profile，避免设备不支持固定 1920x1080 时无预览。
      const sorted = [...previewProfiles].sort((a: camera.Profile, b: camera.Profile) => {
        return (b.size.width * b.size.height) - (a.size.width * a.size.height);
      });
      const fallback = sorted[0];
      Log.w(TAG, `getPreviewProfilesObj fallback profile: ${fallback.size.width}x${fallback.size.height}`);
      return fallback;
    } catch (error) {
      Log.e(TAG, 'getPreviewProfilesObj failed: ' + JSON.stringify(error));
      return undefined;
    }
  }

  async initCamera(XComponentSurfaceId: string, cameraId?: string): Promise<boolean> {
    if (!this.safeLoadCameras() || !this.cameraManager) {
      Log.e(TAG, 'initCamera failed: camera manager unavailable');
      return false;
    }

    if (cameraId) {
      this.curcamerasDevice = this.camerasDevices.find((dev) => dev.cameraId === cameraId);
    }
    if (!this.curcamerasDevice) {
      this.curcamerasDevice = this.camerasDevices[0];
    }

    try {
      // 获取指定的相机设备对象支持的模式
      const sceneModes = this.cameraManager.getSupportedSceneModes(this.curcamerasDevice);
      const supportPhoto = sceneModes.indexOf(camera.SceneMode.NORMAL_PHOTO) >= 0;
      if (!supportPhoto) {
        Log.e(TAG, 'photo mode not supported');
        return false;
      }

      const previewProfile = this.getPreviewProfilesObj();
      if (!previewProfile) {
        Log.e(TAG, 'preview profile not found');
        return false;
      }
      Log.i(
        TAG,
        `initCamera using profile=${previewProfile.size.width}x${previewProfile.size.height}, cameraId=${this.curcamerasDevice.cameraId}`,
      );

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

  getFlashStatus(): boolean {
    if (!this.photoSession) {
      return false;
    }
    try {
      // 获取当前设备的闪光灯模式
      const flashMode = this.photoSession.getFlashMode();
      return flashMode === camera.FlashMode.FLASH_MODE_ALWAYS_OPEN;
    } catch (error) {
      Log.e(TAG, 'getFlashStatus failed: ' + JSON.stringify(error));
      return false;
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
    const iosStyleRatio = 1 + clamped * 5;
    const ratio = Math.max(minRatio, Math.min(iosStyleRatio, maxRatio));
    // 官方说明支持到小数点后两位精度。
    const ratioRounded = Math.round(ratio * 100) / 100;

    try {
      // 设置变焦比，变焦精度最高为小数点后两位
      this.photoSession.setZoomRatio(ratioRounded);
      Log.i(
        TAG,
        `setZoomNormalized success: normalized=${clamped}, ` +
          `ratio=${ratioRounded}, range=[${minRatio}, ${maxRatio}], iosStyleRatio=${iosStyleRatio}`,
      );
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
      if (!this.isStop) {
        await this.photoSession?.stop();
        this.isStop = true;
      }
      // 释放会话资源，通过注册回调函数获取结果
      await this.photoSession?.release();
      await this.cameraInput?.close();
      await this.photoOutput?.release();
      await this.previewOutput?.release();
    } catch (error) {
      Log.e(TAG, 'preFrontRelease failed: ' + JSON.stringify(error));
    }
  }

  async releaseCamera(): Promise<void> {
    try {
      if (!this.isStop) {
        await this.photoSession?.stop();
        this.isStop = true;
      }
      await this.cameraInput?.close();
      await this.previewOutput?.release();
      await this.photoSession?.release();
      await this.photoOutput?.release();
      await this.imageReceiver.release();
    } catch (error) {
      Log.e(TAG, 'releaseCamera failed: ' + JSON.stringify(error));
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
        nextImage.getComponent(image.ComponentType.JPEG, (compErr: BusinessError, imgComponent: image.Component) => {
          if (compErr || imgComponent === undefined) {
            Log.e(TAG, 'onImageArrival getComponent(JPEG) failed: ' + JSON.stringify(compErr));
            nextImage.release();
            return;
          }
          if (imgComponent.byteBuffer as ArrayBuffer) {
            // 对图片进行解码
            this.decodeImageBuffer(imgComponent, nextImage.size.width, nextImage.size.height, scanCallback);
          } else {
            Log.w(TAG, 'onImageArrival component has empty byteBuffer');
          }
          nextImage.release();
        });
      });
    });
  }

  decodeImageBuffer(
    imgComponent: image.Component,
    width: number,
    height: number,
    scanCallback: (result: scanBarcode.ScanResult) => void,
  ): void {
    const now = Date.now();
    if (now - this.lastDecodeAtMs < 800) {
      return;
    }
    this.lastDecodeAtMs = now;
    this.decodeAttemptCount += 1;

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
      if (this.decodeAttemptCount % 10 === 0) {
        Log.i(TAG, `decodeImageBuffer attempt=${this.decodeAttemptCount}, results=${detectResult.scanResults.length}`);
      }
      if (detectResult.scanResults.length > 0) {
        const res = detectResult.scanResults[0];
        if (res && res.originalValue) {
          const resultMap = res as ESObject as Record<string, Object>;
          resultMap['frameHeight'] = height;
          Log.i(TAG, `decodeImageBuffer success value=${res.originalValue}`);
          scanCallback(res);
        }
      }
    }).catch((error: BusinessError) => {
      Log.e(TAG, 'decodeImageBuffer failed: ' + error.message);
    });
  }
}
