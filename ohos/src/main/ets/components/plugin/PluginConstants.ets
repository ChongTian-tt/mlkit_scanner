/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");

 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

export class PluginConstants {
  static readonly channelName: string = "mlkit_channel";
  static readonly cameraPlatformViewName: string = "mlkit/camera_preview";
  static readonly initCameraMethod: string = "initCameraPreview";
  static readonly resumeCameraMethod: string = "resumeCameraMethod";
  static readonly updateConstraintsMethod: string = "updateConstraints";
  static readonly pauseCameraMethod: string = "pauseCameraMethod";
  static readonly disposeCameraMethod: string = "dispose";
  static readonly toggleFlashMethod: string = "toggleFlash";
  static readonly startScanMethod: string = "startScan";
  static readonly cancelScanMethod: string = "cancelScan";
  static readonly setScanDelayMethod: string = "setScanDelay";
  static readonly scanResultMethod: string = "onScanResult";
  static readonly setZoomMethod: string = "setZoom";
  static readonly setCropAreaMethod: string = "setCropAreaMethod";
  static readonly SCAN_TO_TOP_HEIGHT = 120;
  /**
   * 相机闪光灯按钮尺寸
   */
  static readonly SCAN_FLASH_BUTTON_SIZE = 40;
  /**
   * 相机返回按钮尺寸
   */
  static readonly SCAN_CANCEL_BUTTON_SIZE = 40;
  /**
   * 相机扫描框尺寸
   */
  static readonly SCAN_BORDER_SIZE = 280;
  /**
   * 扫描动画组件线宽
   */
  static readonly SCAN_DIVIDER_STROKE_WIDTH = 1;
  /**
   * 扫描动画组件高度
   */
  static readonly SCAN_DIVIDER_HEIGHT = 4;
  /**
   * 扫描动画组件起点偏移量
   */
  static readonly SCAN_DIVIDER_OFFSET_BEGIN = 0;
  /**
   * 扫描动画组件终点偏移量
   */
  static readonly SCAN_DIVIDER_OFFSET_END = 390;
  /**
   * 组件安全边距
   */
  static readonly SCAN_SAFE_MARGINS = 24;
  /**
   * 组件宽度100%
   */
  static readonly SCAN_COMPONENT_WIDTH_100 = '100%';
  /**
   * 组件宽度50%
   */
  static readonly SCAN_COMPONENT_WIDTH_50 = '50%';
  /**
   * 组件位置X坐标
   */
  static readonly SCAN_COMPONENT_POSITION_X = 0;
  /**
   * 组件位置Y坐标
   */
  static readonly SCAN_COMPONENT_POSITION_Y = 0;
  /**
   * 组件translate X坐标
   */
  static readonly SCAN_COMPONENT_TRANSLATE_X = 0;
  /**
   * 按钮文字大小
   */
  static readonly SCAN_BUTTON_FONT_SIZE = 18;
  /**
   * 按钮和文字间距
   */
  static readonly SCAN_BUTTON_TEXT_SAFE_MARGINS = 4;
  /**
   * 多按钮之间安全间距
   */
  static readonly SCAN_BUTTON_SAFE_MARGINS = 50;
  /**
   * 按钮距离顶部距离
   */
  static readonly SCAN_BUTTON_TOP_MARGINS = 190;
}

/**
 * Plugin error codes aligned with Android PluginError enum.
 */
export class PluginError {
  static readonly InitCameraError: string = "1";
  static readonly AuthorizationCameraError: string = "2";
  static readonly CameraIsNotInitialized: string = "3";
  static readonly DeviceHasNotFlash: string = "4";
  static readonly InvalidArguments: string = "5";
  static readonly DeviceHasNotZoom: string = "6";
}

export interface OhosScannerParameters {
  initialZoom?: number;
  initialCropRect?: CropRect;
}

export interface CropRect {
  scaleWidth: number;
  scaleHeight: number;
  offsetX: number;
  offsetY: number;
}

export interface CropPosition {
  left: number;
  top: number;
  width: number;
  height: number;
}