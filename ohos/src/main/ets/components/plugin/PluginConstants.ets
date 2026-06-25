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
import { Permissions } from '@kit.AbilityKit';

export class PluginConstants {
  static readonly CHANNEL_NAME: string = 'mlkit_channel';
  static readonly PERMISSION_NAME: Permissions = 'ohos.permission.CAMERA';
  static readonly CAMERA_PLATFORM_VIEW_NAME: string = 'mlkit/camera_preview';
  static readonly INIT_CAMERA_METHOD: string = 'initCameraPreview';
  static readonly RESUME_CAMERA_METHOD: string = 'resumeCameraMethod';
  static readonly UPDATE_CONSTRAINTS_METHOD: string = 'updateConstraints';
  static readonly PAUSE_CAMERA_METHOD: string = 'pauseCameraMethod';
  static readonly DISPOSE_CAMERA_METHOD: string = 'dispose';
  static readonly TOGGLE_FLASH_METHOD: string = 'toggleFlash';
  static readonly START_SCAN_METHOD: string = 'startScan';
  static readonly CANCEL_SCAN_METHOD: string = 'cancelScan';
  static readonly SET_SCAN_DELAY_METHOD: string = 'setScanDelay';
  static readonly SCAN_RESULT_METHOD: string = 'onScanResult';
  static readonly CHANGE_TORCH_STATE_METHOD: string = 'changeTorchStateMethod';
  static readonly SET_ZOOM_METHOD: string = 'setZoom';
  static readonly SET_CROP_AREA_METHOD: string = 'setCropAreaMethod';
  static readonly GET_OHOS_AVAILABLE_CAMERAS_METHOD: string = 'getOhosAvailableCameras';
  static readonly SET_OHOS_CAMERA_METHOD: string = 'setOhosCamera';
  static readonly SCAN_COMPONENT_WIDTH_100: string = '100%';
  // 预览尺寸的默认比例。初始化早期在尚未拿到真实相机 profile 前，先使用该比例占位。
  static readonly PREVIEW_RATIO_W: number = 9;
  static readonly PREVIEW_RATIO_H: number = 16;
  static readonly TOUCH_TYPE_DOWN: number = 0;
  static readonly TOUCH_TYPE_UP: number = 1;
  static readonly TOUCH_TYPE_CANCEL: number = 3;
  // 长按对焦时间阈值 通常 >500ms 被认为是长按
  static readonly LONG_PRESS_THRESHOLD_MS: number = 500;
  static readonly FOCUS_RING_FADE_DURATION_MS: number = 500;
  static readonly FOCUS_RING_MAX_OPACITY: number = 1;
  static readonly LOCK_FADE_IN_DURATION_MS: number = 300;
  static readonly LOCK_MOVE_DURATION_MS: number = 500;
  static readonly LOCK_FADE_OUT_DURATION_MS: number = 200;
  // 对焦环和锁定图标的尺寸和位置参数
  static readonly FOCUS_RING_DIAMETER: number = 60;
  // 对焦环半径
  static readonly FOCUS_RING_RADIUS: number = PluginConstants.FOCUS_RING_DIAMETER / 2;
  // 对焦环边框宽度
  static readonly FOCUS_RING_STROKE: number = 1;
  // 锁定图标尺寸
  static readonly LOCK_ICON_SIZE: number = 24;
  static readonly LOCK_START_EXTRA_LEFT: number = PluginConstants.LOCK_ICON_SIZE / 2;
  // 锁定图标在预览区域内的目标位置
  static readonly LOCK_TARGET_INSET_LEFT: number = 20;
  static readonly LOCK_TARGET_INSET_TOP: number = 20;
  static readonly DEFAULT_PREVIEW_WIDTH: number = 1920;
  static readonly DEFAULT_PREVIEW_HEIGHT: number = 1080;
  static readonly DEFAULT_CAMERA_CACHE_KEY: string = '__default__';
  static readonly CAMERA_CACHE_TTL_MS: number = 3000;
}

export class PluginError {
  static readonly INIT_CAMERA_ERROR: string = '1';
  static readonly AUTHORIZATION_CAMERA_ERROR: string = '2';
  static readonly CAMERA_IS_NOT_INITIALIZED: string = '3';
  static readonly DEVICE_HAS_NOT_FLASH: string = '4';
  static readonly INVALID_ARGUMENTS: string = '5';
  static readonly DEVICE_HAS_NOT_ZOOM: string = '6';
}

export interface OhosScannerParameters {
  initialZoom?: number;
  initialCamera?: OhosInitialCamera;
  initialCropRect?: CropRect;
}

export interface OhosInitialCamera {
  position: number;
  type: number;
}

export interface CropRect {
  scaleWidth: number;
  scaleHeight: number;
  offsetX: number;
  offsetY: number;
}

// 预览状态机
export interface PreviewState {
  isRunning: boolean;
  isPausedByUser: boolean;
}

// 预览状态机
export interface Size {
  width: number;
  height: number;
}

export interface OhosCameraItem {
  cameraId: string;
  position: number;
  type: number;
}

export interface ScanRectLike {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface TouchPoint {
  x: number;
  y: number;
}

export interface TouchRecord {
  x?: Object;
  y?: Object;
}
