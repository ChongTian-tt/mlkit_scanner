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
import { Permissions } from "@kit.AbilityKit";

export class PluginConstants {
  static readonly channelName: string = 'mlkit_channel';
  static readonly permissionName: Permissions = 'ohos.permission.CAMERA';
  static readonly cameraPlatformViewName: string = 'mlkit/camera_preview';
  static readonly initCameraMethod: string = 'initCameraPreview';
  static readonly resumeCameraMethod: string = 'resumeCameraMethod';
  static readonly updateConstraintsMethod: string = 'updateConstraints';
  static readonly pauseCameraMethod: string = 'pauseCameraMethod';
  static readonly disposeCameraMethod: string = 'dispose';
  static readonly toggleFlashMethod: string = 'toggleFlash';
  static readonly startScanMethod: string = 'startScan';
  static readonly cancelScanMethod: string = 'cancelScan';
  static readonly setScanDelayMethod: string = 'setScanDelay';
  static readonly scanResultMethod: string = 'onScanResult';
  static readonly setZoomMethod: string = 'setZoom';
  static readonly setCropAreaMethod: string = 'setCropAreaMethod';
  static readonly getIosAvailableCamerasMethod: string = 'getIosAvailableCameras';
  static readonly setIosCameraMethod: string = 'setIosCamera';
  static readonly SCAN_COMPONENT_WIDTH_100 = '100%';
}

export class PluginError {
  static readonly InitCameraError: string = '1';
  static readonly AuthorizationCameraError: string = '2';
  static readonly CameraIsNotInitialized: string = '3';
  static readonly DeviceHasNotFlash: string = '4';
  static readonly InvalidArguments: string = '5';
  static readonly DeviceHasNotZoom: string = '6';
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

export interface DecodeState {
  inFlight: boolean;
  lastAttemptAtMs: number;
  scanSessionStartedAtMs: number;
  lastEmittedRawValue: string;
  lastEmittedAtMs: number;
  lastDecodedRawValue: string;
}
