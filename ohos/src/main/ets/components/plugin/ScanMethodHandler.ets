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

import { MethodCall, MethodResult, Log } from '@ohos/flutter_ohos';
import { ArgsParser } from './ArgsParser';
import { getCurrentCameraPreviewComponent } from './CameraPreviewComponent';
import {
  CropRect,
  OhosInitialCamera,
  PluginConstants,
  PluginError,
} from './PluginConstants';
import { MLKitScannerOptions } from './MLKitScannerOptions';
import type { MLKitScannerView } from './MLKitScannerView';

const TAG: string = '[ScanMethodHandler]:';

/**
 * 扫描方法处理器
 * 处理所有与扫描相关的 MethodChannel 调用：开始/取消扫描、扫描延迟、
 * 约束更新、裁剪区域设置、摄像头列表查询和摄像头切换
 */
export class ScanMethodHandler {
  private readonly view: MLKitScannerView;

  /**
   * 创建 ScanMethodHandler 实例
   * @param view - MLKitScannerView 实例，用于访问共享状态和相机服务
   */
  constructor(view: MLKitScannerView) {
    this.view = view;
  }

  /**
   * 开启扫描并启动预览流
   * @param call - Flutter 方法调用对象，包含扫码参数
   * @param result - 方法结果回调
   */
  async startScan(call: MethodCall, result: MethodResult): Promise<void> {
    const args = ArgsParser.normalizeArgs(call.args);
    let options: MLKitScannerOptions;
    try {
      options = MLKitScannerOptions.fromMap(args);
    } catch (error) {
      result.error(
        PluginError.INVALID_ARGUMENTS,
        'Invalid startScan arguments: ' + JSON.stringify(error),
        null,
      );
      return;
    }
    this.view.scanDelayMs = options.periodMs;
    // 同步更新 CameraService 的解码节流间隔,保持底层解码频率与上层扫描延迟一致
    this.view.getCameraService()?.setDecodeThrottleMs(this.view.scanDelayMs);
    if (!this.view.previewState.isPausedByUser) {
      this.view.flashLightStatusBeforePause = this.view.getFlashLightStatusSafely();
    }
    if (!this.view.isCameraInitialized) {
      if (this.view.previewState.isPausedByUser) {
        getCurrentCameraPreviewComponent()?.setScanActive(true);
        result.success(true);
        return;
      }
      result.error(PluginError.CAMERA_IS_NOT_INITIALIZED, 'Camera is not initialized', null);
      return;
    }
    if (!this.view.surfaceId) {
      result.error(PluginError.CAMERA_IS_NOT_INITIALIZED, 'Camera surface is not ready', null);
      return;
    }
    // 处于扫描状态 或者 用户触发了pause时不做处理 只标记开启扫描
    if (this.view.isScan || this.view.previewState.isPausedByUser) {
      this.view.beginScanSession();
      result.success(true);
      return;
    }

    // 开启扫描,开启预览流
    this.view.beginScanSession();
    this.view.startScanDelayWindow();
    if (!this.view.previewState.isRunning) {
      await this.view.startPreview();
    }
    result.success(true);
  }

  /**
   * 取消扫描，保持预览流继续运行
   * @param result - 方法结果回调
   */
  async cancelScan(result: MethodResult): Promise<void> {
    try {
      this.view.clearScanDelayTimer();
      if (!this.view.isCameraInitialized) {
        if (this.view.previewState.isPausedByUser) {
          getCurrentCameraPreviewComponent()?.setScanActive(false);
          result.success(true);
          return;
        }
        result.error(PluginError.CAMERA_IS_NOT_INITIALIZED, 'Camera is not initialized', null);
        return;
      }
      // cancel 只停止扫描,不重启预览流,避免卡顿与闪光灯状态抖动。
      if (this.view.isScan) {
        this.view.endScanSession();
      }
      result.success(true);
    } catch (error) {
      Log.e(TAG, `cancelScan error - ${error}`);
      this.view.endScanSession();
    }
  }

  /**
   * 设置扫描延迟间隔
   * @param call - Flutter 方法调用对象，参数为延迟毫秒数
   * @param result - 方法结果回调
   */
  setScanDelay(call: MethodCall, result: MethodResult): void {
    // 设置扫描延迟
    const delay: Object = call.args;
    const delayNum: number = Number(delay);
    if (!Number.isFinite(delayNum)) {
      result.error(
        PluginError.INVALID_ARGUMENTS,
        'Invalid argument passed, Number type is expected',
        null,
      );
      return;
    }
    if (delayNum < 0) {
      result.error(
        PluginError.INVALID_ARGUMENTS,
        'Invalid argument passed, value must be >= 0',
        null,
      );
      return;
    }
    // 将扫描延迟设置为传入值的整数部分
    this.view.scanDelayMs = Math.trunc(delayNum);
    // 同步更新 CameraService 的解码节流间隔,保持底层解码频率与上层扫描延迟一致
    this.view.getCameraService()?.setDecodeThrottleMs(this.view.scanDelayMs);
    result.success(true);
  }

  /**
   * 更新预览约束：解析尺寸参数并重新计算预览尺寸和裁剪区域
   * @param call - Flutter 方法调用对象，包含 width/height 参数
   * @param result - 方法结果回调
   */
  updateConstraints(call: MethodCall, result: MethodResult): void {
    try {
      const args = ArgsParser.normalizeArgs(call.args);
      const rawSize = ArgsParser.parsePositiveSize(args);
      if (!rawSize) {
        result.error(
          PluginError.INVALID_ARGUMENTS,
          'Invalid constraints, positive width/height expected',
          null,
        );
        return;
      }
      const sizeChanged = this.view.applyPreviewContainerSize(rawSize.width, rawSize.height);
      if (!sizeChanged) {
        result.success(true);
        return;
      }

      const comp = getCurrentCameraPreviewComponent();
      if (comp) {
        comp.applyCropRect();
      }
      result.success(true);
    } catch (error) {
      Log.e(TAG, 'updateConstraints failed: ' + JSON.stringify(error));
      result.error(PluginError.INVALID_ARGUMENTS, 'updateConstraints failed', null);
    }
  }

  /**
   * 设置扫描区域：校验参数范围并更新裁剪矩形
   * @param call - Flutter 方法调用对象，包含 scaleWidth/scaleHeight/offsetX/offsetY 参数
   * @param result - 方法结果回调
   */
  setCropArea(call: MethodCall, result: MethodResult): void {
    const rawArgsMap: Object = call.args;
    const args = ArgsParser.normalizeArgs(rawArgsMap);
    const scaleWidth = Number(args['scaleWidth']);
    const scaleHeight = Number(args['scaleHeight']);
    const offsetX = Number(args['offsetX']);
    const offsetY = Number(args['offsetY']);

    // 参数范围校验
    if (!Number.isFinite(scaleWidth) || scaleWidth <= 0 || scaleWidth > 1 ||
        !Number.isFinite(scaleHeight) || scaleHeight <= 0 || scaleHeight > 1 ||
        !Number.isFinite(offsetX) || offsetX < 0 || offsetX >= 1 ||
        !Number.isFinite(offsetY) || offsetY < 0 || offsetY >= 1) {
      result.error(
        PluginError.INVALID_ARGUMENTS,
        'Invalid crop area arguments, scaleWidth/scaleHeight should be in (0,1], offsetX/offsetY should be in [0,1)',
        null,
      );
      Log.e(TAG, 'setCropArea invalid arguments: ' + JSON.stringify(args));
      return;
    }

    const rect: CropRect = {
      scaleWidth: scaleWidth,
      scaleHeight: scaleHeight,
      offsetX: offsetX,
      offsetY: offsetY,
    };
    this.view.initialScannerParameters = this.view.initialScannerParameters || {};
    this.view.initialScannerParameters.initialCropRect = rect;
    const comp = getCurrentCameraPreviewComponent();
    if (comp) {
      comp.applyCropRect();
    }

    result.success(true);
  }

  /**
   * 获取可用的鸿蒙摄像头列表
   * @param result - 方法结果回调，返回包含 position 和 type 的数组
   */
  getOhosAvailableCameras(result: MethodResult): void {
    if (!this.view.context) {
      result.error(PluginError.INIT_CAMERA_ERROR, 'context is undefined!', null);
      return;
    }

    try {
      const service = this.view.getCameraService();
      if (!service) {
        result.error(PluginError.INIT_CAMERA_ERROR, 'camera service is unavailable', null);
        return;
      }

      const devices = service.getAvailableCameras();
      const available: Array<Record<string, number>> = [];
      for (const device of devices) {
        const position = Number(device['position']);
        const type = Number(device['type']);
        available.push({
          'position': position,
          'type': type,
        });
      }
      result.success(available);
    } catch (error) {
      result.error(PluginError.INIT_CAMERA_ERROR, 'Failed to get camera list: ' + JSON.stringify(error), null);
    }
  }

  /**
   * 校验 setOhosCamera 的参数，无效时返回 null 并通过 result 报错
   * @param args - 包含 position 和 type 的键值对
   * @param result - 方法结果回调
   * @returns 校验通过的 OhosInitialCamera，无效时返回 null
   */
  private validateSetOhosCameraArgs(args: Record<string, Object>, result: MethodResult): OhosInitialCamera | null {
    const position = Number(args['position']);
    const type = Number(args['type']);
    if (!Number.isFinite(position) || !Number.isFinite(type)) {
      Log.e(TAG, `setOhosCamera invalid arguments: position=${position}, type=${type}`);
      result.error(PluginError.INVALID_ARGUMENTS, 'Invalid camera arguments, position/type required', null);
      return null;
    }
    if (!this.view.context) {
      Log.e(TAG, 'setOhosCamera failed: context is undefined');
      result.error(PluginError.INIT_CAMERA_ERROR, 'context is undefined!', null);
      return null;
    }
    return { position: Math.trunc(position), type: Math.trunc(type) } as OhosInitialCamera;
  }

  /**
   * 通过 CameraService 查找目标 cameraId，找不到时返回空串
   * @param reqPosition - 请求的摄像头位置编码
   * @param reqType - 请求的摄像头类型编码
   * @param result - 方法结果回调
   * @returns 匹配的 cameraId，未找到时返回空串
   */
  private queryCameraIdForSwitch(reqPosition: number, reqType: number, result: MethodResult): string {
    try {
      const service = this.view.getCameraService();
      if (!service) {
        Log.e(TAG, 'setOhosCamera failed: camera service is unavailable');
        result.error(PluginError.INIT_CAMERA_ERROR, 'camera service is unavailable', null);
        return '';
      }
      const cameraId = service.findCameraIdByOhosCodes(reqPosition, reqType);
      if (!cameraId) {
        Log.e(TAG, `setOhosCamera no camera matches: position=${reqPosition}, type=${reqType}`);
        result.error(
          PluginError.INVALID_ARGUMENTS,
          `No camera matches position=${reqPosition}, type=${reqType}`,
          null,
        );
        return '';
      }
      return cameraId;
    } catch (error) {
      Log.e(TAG, 'setOhosCamera query camera list failed: ' + JSON.stringify(error));
      result.error(PluginError.INIT_CAMERA_ERROR, 'Failed to query camera list: ' + JSON.stringify(error), null);
      return '';
    }
  }

  /**
   * 切换鸿蒙摄像头：校验参数、查找目标摄像头、必要时重启预览
   * @param call - Flutter 方法调用对象，包含 position 和 type 参数
   * @param result - 方法结果回调
   */
  setOhosCamera(call: MethodCall, result: MethodResult): void {
    const args = ArgsParser.normalizeArgs(call.args);
    const validated = this.validateSetOhosCameraArgs(args, result);
    if (!validated) {
      return;
    }

    const cameraId = this.queryCameraIdForSwitch(validated.position, validated.type, result);
    if (!cameraId) {
      return;
    }
    this.view.selectedCameraId = cameraId;
    this.view.selectedCameraPositionCode = validated.position;
    this.view.selectedCameraTypeCode = validated.type;

    getCurrentCameraPreviewComponent()?.applyCropRect();

    if (this.view.isCameraInitialized && this.view.surfaceId && !this.view.previewState.isPausedByUser) {
      Log.i(TAG, 'setOhosCamera restarting preview after camera switch');
      void this.view.restartPreviewAfterLayoutChange();
    }

    result.success(true);
  }
}
