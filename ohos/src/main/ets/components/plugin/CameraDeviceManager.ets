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

import { camera } from '@kit.CameraKit';
import { Log } from '@ohos/flutter_ohos';
import { PluginConstants, Size } from './PluginConstants';

const TAG: string = '[CameraDeviceManager]:';

/**
 * 相机设备查询和 Profile 管理类
 * 负责相机设备发现、缓存、预览 Profile 查询与匹配
 */
export class CameraDeviceManager {
  public cameraManager: camera.CameraManager | undefined = undefined;
  private camerasLoadedAtMs: number = 0;
  private camerasDevices: Array<camera.CameraDevice> = [];
  private preferredPreviewProfileCache: Record<string, camera.Profile> = {};
  private context: Context | null = null;

  /**
   * 创建 CameraDeviceManager 实例
   * @param context - Ability 上下文
   */
  constructor(context: Context) {
    this.context = context;
  }

  /**
   * 获取预览 Profile 缓存键
   * @param cameraId - 可选的相机设备 ID
   * @returns 缓存键字符串
   */
  private getPreviewProfileCacheKey(cameraId?: string): string {
    if (cameraId && cameraId.length > 0) {
      return cameraId;
    }
    return PluginConstants.DEFAULT_CAMERA_CACHE_KEY;
  }

  /**
   * 解析相机设备：按 cameraId 查找，未指定时返回默认相机
   * @param cameraId - 可选的相机设备 ID
   * @returns 匹配的 CameraDevice，未找到时返回 undefined
   */
  resolveCameraDevice(cameraId?: string): camera.CameraDevice | undefined {
    try {
      if (!this.safeLoadCameras()) {
        return undefined;
      }
    } catch (error) {
      Log.e(TAG, 'resolveCameraDevice: ' + JSON.stringify(error));
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

  /**
   * 给定 CameraDevice，从 getSupportedOutputCapability 查找首选预览 Profile
   * 优先匹配默认分辨率，未匹配时选择最大分辨率作为 fallback
   * @param device - 相机设备
   * @returns 预览 Profile，未找到时返回 undefined
   */
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
          profile.size.width === PluginConstants.DEFAULT_PREVIEW_WIDTH &&
          profile.size.height === PluginConstants.DEFAULT_PREVIEW_HEIGHT
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

  /**
   * 通过 cameraId 查找相机设备，获取首选预览 Profile 并返回 Size
   * @param cameraId - 可选的相机设备ID，不传则使用默认相机
   * @returns 预览尺寸，未找到时返回 null
   */
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

  /**
   * 安全加载相机列表，带缓存和错误处理
   * @returns 是否成功加载相机列表
   * @throws 当 context 不可用或相机管理器创建失败时抛出错误
   */
  safeLoadCameras(): boolean {
    if (!this.context) {
      throw new Error('safeLoadCameras failed: context is not available');
    }

    const now = Date.now();
    const useCache =
      this.cameraManager !== undefined &&
        this.camerasDevices.length > 0 &&
        now - this.camerasLoadedAtMs < PluginConstants.CAMERA_CACHE_TTL_MS;
    if (useCache) {
      return true;
    }

    try {
      if (!this.cameraManager) {
        this.cameraManager = camera.getCameraManager(this.context);
      }
      // 使用 getCameraDevices(position, types, connectType) 按位置+类型+连接方式查询相机
      // 遍历所有 position 和 type 组合，收集所有可用相机
      this.camerasDevices = this.queryAllCameraDevices();
      this.camerasLoadedAtMs = now;
      Log.i(TAG, `safeLoadCameras: found ${this.camerasDevices.length} camera(s)`);
      return this.camerasDevices.length > 0;
    } catch (error) {
      Log.e(TAG, 'safeLoadCameras failed: ' + JSON.stringify(error));
      this.camerasLoadedAtMs = 0;
      throw new Error('safeLoadCameras failed: ' + JSON.stringify(error));
    }
  }

  /**
   * 遍历所有 position × type 组合查询相机设备，connectType 使用内置连接
   * @returns 去重后的相机设备数组
   */
  private queryAllCameraDevices(): Array<camera.CameraDevice> {
    let allDevices: Array<camera.CameraDevice> = [];
    let knownCameraIds: Set<string> = new Set();
    const positions: Array<camera.CameraPosition> = [
      camera.CameraPosition.CAMERA_POSITION_UNSPECIFIED,
      camera.CameraPosition.CAMERA_POSITION_BACK,
      camera.CameraPosition.CAMERA_POSITION_FRONT,
    ];
    const types: Array<camera.CameraType> = [
      camera.CameraType.CAMERA_TYPE_DEFAULT,
      camera.CameraType.CAMERA_TYPE_WIDE_ANGLE,
      camera.CameraType.CAMERA_TYPE_ULTRA_WIDE,
      camera.CameraType.CAMERA_TYPE_TELEPHOTO,
      camera.CameraType.CAMERA_TYPE_TRUE_DEPTH,
    ];

    for (const pos of positions) {
      for (const type of types) {
        try {
          const devices = this.cameraManager?.getCameraDevices(
            pos, [type], camera.ConnectionType.CAMERA_CONNECTION_BUILT_IN
          );
          if (devices && devices.length > 0) {
            for (const dev of devices) {
              if (!knownCameraIds.has(dev.cameraId)) {
                knownCameraIds.add(dev.cameraId);
                allDevices.push(dev);
                Log.i(TAG,
                  `queryAllCameraDevices: found cameraId=${dev.cameraId}, ` +
                  `position=${dev.cameraPosition}, type=${dev.cameraType}`);
              }
            }
          }
        } catch (error) {
          // 某些 position+type 组合可能不支持，忽略即可
        }
      }
    }

    return allDevices;
  }

  /**
   * 获取可用的相机列表，包含 cameraId、position、type 信息
   * @returns 相机信息数组
   */
  public getAvailableCameras(): Array<Record<string, number | string>> {
    try {
      if (!this.safeLoadCameras()) {
        Log.w(TAG, 'getAvailableCameras: safeLoadCameras returned false, returning empty');
        return [];
      }
    } catch (error) {
      Log.e(TAG, 'getAvailableCameras: ' + JSON.stringify(error));
      return [];
    }

    const result: Array<Record<string, number | string>> = [];
    for (const device of this.camerasDevices) {
      Log.i(TAG,
        `getAvailableCameras: cameraId=${device.cameraId}, ` +
        `position=${device.cameraPosition}, type=${device.cameraType}`);
      result.push({
        'cameraId': device.cameraId,
        'position': device.cameraPosition,
        'type': device.cameraType,
      });
    }
    Log.i(TAG, `getAvailableCameras: total ${result.length} camera(s) found`);

    return result;
  }

  /**
   * 根据 Dart 侧传入的 position 和 type，查找最匹配的 cameraId
   * 优先级为 position+type > position > 任意可用
   * @param positionCode - 相机位置编码
   * @param typeCode - 相机类型编码
   * @returns 匹配的 cameraId，无可用相机时返回 undefined
   */
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

  /**
   * 创建相机设备，查询所有可用相机并缓存
   * @param cameraManager - 相机管理器实例
   */
  async createCamera(cameraManager: camera.CameraManager): Promise<void> {
    this.cameraManager = cameraManager;
    try {
      this.camerasDevices = this.queryAllCameraDevices();
      this.camerasLoadedAtMs = Date.now();
    } catch (error) {
      Log.e(TAG, 'createCamera failed: ' + JSON.stringify(error));
      this.camerasDevices = [];
      this.camerasLoadedAtMs = 0;
    }
  }

  /**
   * 获取校验相机模式并获取预览 Profile
   * @param device - 相机设备
   * @returns 预览 Profile，不支持拍照模式或未找到 Profile 时返回 null
   */
  validateAndGetPreviewProfile(device: camera.CameraDevice): camera.Profile | null {
    const sceneModes = this.cameraManager!.getSupportedSceneModes(device);
    const supportPhoto = sceneModes.indexOf(camera.SceneMode.NORMAL_PHOTO) >= 0;
    if (!supportPhoto) {
      Log.e(TAG, 'photo mode not supported');
      return null;
    }
    const previewProfile = this.getPreferredPreviewProfile(device);
    if (!previewProfile) {
      Log.e(TAG, 'preview profile not found');
      return null;
    }
    return previewProfile;
  }

  /**
   * 释放设备管理资源，清空缓存和相机管理器引用
   */
  releaseDeviceManager(): void {
    this.preferredPreviewProfileCache = {};
    this.camerasDevices = [];
    this.cameraManager = undefined;
    this.camerasLoadedAtMs = 0;
  }
}
