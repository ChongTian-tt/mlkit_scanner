/*
 * Copyright (c) 2026 SwanLink (Jiangsu) Technology Development Co., LTD.
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

import { display } from '@kit.ArkUI';
import { Log } from '@ohos/flutter_ohos';
import { common, AbilityLifecycleCallback } from '@kit.AbilityKit';
import { PermissionsUtil } from './PermissionsUtil';
import { ScannerOverlay } from './ScannerOverlay';
import { getCurrentMLKitScannerView, MLKitScannerView } from './MLKitScannerView';
import { CropRect, PluginConstants, PluginError, Size, TouchPoint, TouchRecord } from './PluginConstants';

const TAG: string = '[CameraPreviewComponent:]';

let currentCameraPreview: CameraPreviewComponent | null = null;

@Component
export struct CameraPreviewComponent {
  private mXComponentController: XComponentController = new XComponentController();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private isScanKitInitialized: boolean = false;
  private lifecycleId: number = -1;
  private LONG_PRESS_THRESHOLD_MS: number = 500;
  private TOUCH_TYPE_DOWN: number = 0;
  private TOUCH_TYPE_UP: number = 1;
  private TOUCH_TYPE_CANCEL: number = 3;
  private touchDownAtMs: number = -1;
  private touchDownX: number = 0;
  private touchDownY: number = 0;
  @Prop flutterMLKitScannerView: MLKitScannerView | null = null;
  @State canRenderCamera: boolean = false;
  private hasPermission: boolean = false;
  @State surfaceId: string = '';
  // xComponent 宽度/高度——OHOS API仅接受number类型
  @State cameraWidth: number = 0;
  @State cameraHeight: number = 0;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  // 裁剪矩形状态
  @State cropRectState: CropRect | null = null;
  //  扫描仪是否处于活动状态（改变覆盖边框颜色）
  @State isActive: boolean = false;

  build() {
    Stack() {
      if (this.flutterMLKitScannerView && this.canRenderCamera) {
        XComponent({
          id: 'componentId',
          type: XComponentType.SURFACE,
          controller: this.mXComponentController,
        })
          .onLoad(() => {
            this.onLoadHandle();
          })
          .width(this.cameraWidth)
          .height(this.cameraHeight)
          .backgroundColor(Color.White)
          .position({
            x: this.offsetX,
            y: this.offsetY,
          });
        // overlay 覆盖可见区域（crop 坐标相对于可见预览区域）
        if (this.cropRectState) {
          ScannerOverlay({
            cropRect: this.cropRectState,
            isActive: this.isActive,
          })
            .width(PluginConstants.SCAN_COMPONENT_WIDTH_100)
            .height(PluginConstants.SCAN_COMPONENT_WIDTH_100)
            .position({ x: 0, y: 0 })
            .key(
              'scanner-overlay-' +
              this.cropRectState.scaleWidth + '-' +
              this.cropRectState.scaleHeight + '-' +
              this.cropRectState.offsetX + '-' +
              this.cropRectState.offsetY + '-' +
              this.isActive,
            )
        }
      }
    }
    .alignContent(Alignment.Center)
    .width(PluginConstants.SCAN_COMPONENT_WIDTH_100)
    .height(PluginConstants.SCAN_COMPONENT_WIDTH_100)
    .clip(true)
    .onTouch((event: TouchEvent) => {
      this.handleFocusTouch(event);
    })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      void oldValue;
      const dims: Size = readOnAreaChangeSize(newValue);
      if (dims.width > 0 && dims.height > 0) {
        getCurrentMLKitScannerView()?.onPreviewHostAreaChange(dims.width, dims.height);
      }
    })
  }

  private handleFocusTouch(eventObj: TouchEvent): void {
    if (!this.flutterMLKitScannerView || this.cameraWidth <= 0 || this.cameraHeight <= 0) {
      return;
    }
    const touchType = readTouchType(eventObj);
    const rawPoint = readTouchPoint(eventObj);
    const point = rawPoint ? this.toPreviewPoint(rawPoint) : null;

    // DOWN 事件时记录触点位置和时间，UP 事件时根据持续时间判断是否为长按
    if (touchType === this.TOUCH_TYPE_DOWN && point) {
      this.touchDownAtMs = Date.now();
      this.touchDownX = point.x;
      this.touchDownY = point.y;
      return;
    }

    // 仅在 UP 事件时处理对焦，长按超过阈值则锁定焦点
    if (touchType === this.TOUCH_TYPE_UP) {
      if (this.touchDownAtMs < 0) {
        return;
      }
      const duration = Date.now() - this.touchDownAtMs;
      const needLock = duration >= this.LONG_PRESS_THRESHOLD_MS;
      const focusX = this.touchDownX;
      const focusY = this.touchDownY;
      this.touchDownAtMs = -1;
      Log.w(TAG, `Focus touch at (${focusX}, ${focusY}), duration=${duration}ms, needLock=${needLock}`);
      this.flutterMLKitScannerView.handleUserFocusGesture(
        focusX,
        focusY,
        this.cameraWidth,
        this.cameraHeight,
        needLock,
      );
      return;
    }

    if (touchType === this.TOUCH_TYPE_CANCEL) {
      this.touchDownAtMs = -1;
    }
  }

  // 将触点坐标转换为预览坐标（考虑 offset 和边界）
  private toPreviewPoint(point: TouchPoint): TouchPoint | null {
    const px = point.x - this.offsetX;
    const py = point.y - this.offsetY;
    if (!Number.isFinite(px) || !Number.isFinite(py)) {
      return null;
    }

    const clampedX = Math.max(0, Math.min(this.cameraWidth, px));
    const clampedY = Math.max(0, Math.min(this.cameraHeight, py));
    const previewPoint: TouchPoint = {
      x: clampedX,
      y: clampedY,
    };
    return previewPoint;
  }

  getSurfaceId(): string {
    return this.surfaceId;
  }

  setScanActive(active: boolean): void {
    this.isActive = active;
  }

  getScanActive(): boolean {
    return this.isActive;
  }

  private async onLoadHandle(): Promise<void> {
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();
    if (this.flutterMLKitScannerView) {
      this.surfaceId = this.mXComponentController.getXComponentSurfaceId();
      this.flutterMLKitScannerView.setSurfaceId(this.surfaceId);
      await this.tryInitScanKit('onLoad');
    }
  }

  async aboutToAppear(): Promise<void> {
    currentCameraPreview = this;
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();

    this.registerLifecycle();
    await this.onInitCameraPreviewRequested();
  }

  aboutToDisappear() {
    currentCameraPreview = null;
    this.isScanKitInitialized = false;
    this.unRegisterLifecycle();
  }

  private registerLifecycle() {
    if (this.lifecycleId >= 0) {
      return;
    }
    try {
      const callbacks: AbilityLifecycleCallback = {
        onAbilityCreate: () => {
        },
        onWindowStageCreate: () => {
        },
        onWindowStageActive: () => {
        },
        onWindowStageInactive: () => {
        },
        onWindowStageDestroy: () => {
        },
        onAbilityDestroy: () => {
        },
        onAbilityContinue: () => {
        },
        onAbilityForeground: async () => {
          // 解锁或回到前台时，恢复扫描
          await this.refreshPermissionState('abilityForeground');
          if (!this.hasPermission) {
            this.canRenderCamera = false;
            this.isActive = false;
            return;
          }
          await getCurrentMLKitScannerView()?.onHostForeground();
        },
        onAbilityBackground: async () => {
          // 锁屏或退到后台时，暂停扫描
          await getCurrentMLKitScannerView()?.onHostBackground();
        },
      };
      this.lifecycleId = this.context.getApplicationContext().on('abilityLifecycle', callbacks);
    } catch (error) {
      Log.e(TAG, `Failed to register lifecycle listener: ${error}`);
    }
  }

  private unRegisterLifecycle() {
    if (this.lifecycleId < 0) {
      return;
    }
    try {
      this.context.getApplicationContext().off('abilityLifecycle', this.lifecycleId);
    } catch (error) {
      Log.e(TAG, `Failed to unregister lifecycle listener: ${error}`);
    }
    this.lifecycleId = -1;
  }

  private async refreshPermissionState(scene: string): Promise<void> {
    this.hasPermission =
      await PermissionsUtil.checkAndRequestCameraPermission(this.context, PluginConstants.permissionName);
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();
    if (this.flutterMLKitScannerView) {
      this.flutterMLKitScannerView.userGrant = this.hasPermission;
    }
    Log.i(TAG, `${scene} permission result: ${this.hasPermission}`);
  }

  async onInitCameraPreviewRequested(): Promise<void> {
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();
    if (!this.flutterMLKitScannerView || !this.flutterMLKitScannerView.methodResult) {
      return;
    }

    await this.refreshPermissionState('initCameraPreview');
    this.applyCropRect();
    if (!this.hasPermission) {
      this.canRenderCamera = false;
      this.flutterMLKitScannerView.methodResult.error(
        PluginError.AuthorizationCameraError,
        'Camera permission denied',
        null,
      );
      this.flutterMLKitScannerView.methodResult = null;
      return;
    }

    this.canRenderCamera = true;
    await this.tryInitScanKit('initCameraPreview');
  }

  private async tryInitScanKit(scene: string): Promise<void> {
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();
    if (!this.flutterMLKitScannerView || !this.surfaceId || !this.hasPermission) {
      return;
    }

    try {
      if (!this.isScanKitInitialized || !this.flutterMLKitScannerView.isCameraInitialized) {
        this.flutterMLKitScannerView.setCameraInitialized(true);
        this.isScanKitInitialized = true;
      }

      if (this.flutterMLKitScannerView.methodResult) {
        this.flutterMLKitScannerView.methodResult.success(true);
        this.flutterMLKitScannerView.methodResult = null;
      }
    } catch (error) {
      Log.e(TAG, `${scene} camera init error: ` + error);
      this.flutterMLKitScannerView.methodResult?.error(
        PluginError.InitCameraError,
        'camera init failed',
        JSON.stringify(error),
      );
      this.flutterMLKitScannerView.methodResult = null;
    }
  }

  applyCropRect() {
    try {
      if (!this.flutterMLKitScannerView) {
        return;
      }
      // 1. 设置 XComponent 尺寸：优先使用 previewSize 与 ViewControl 对齐，避免预览拉伸
      const previewSize = this.flutterMLKitScannerView.getPreviewSize();
      if (previewSize.width > 0 && previewSize.height > 0) {
        this.cameraWidth = previewSize.width;
        this.cameraHeight = previewSize.height;
      } else if (this.cameraWidth === 0 || this.cameraHeight === 0) {
        this.cameraWidth = this.getUIContext().px2vp(display.getDefaultDisplaySync().width);
        this.cameraHeight = this.getUIContext().px2vp(display.getDefaultDisplaySync().height);
      }
      // 2. XComponent 居中（Center Crop：可为负值以裁剪溢出）
      const container = this.flutterMLKitScannerView.getContainerSize();
      this.offsetX = container.width > 0 ? (container.width - this.cameraWidth) / 2 : 0;
      this.offsetY = container.height > 0 ? (container.height - this.cameraHeight) / 2 : 0;
      const initialCropRect = this.flutterMLKitScannerView.initialScannerParameters?.initialCropRect;
      if (initialCropRect) {
        this.cropRectState = {
          scaleWidth: initialCropRect.scaleWidth,
          scaleHeight: initialCropRect.scaleHeight,
          offsetX: initialCropRect.offsetX,
          offsetY: initialCropRect.offsetY,
        };
      } else {
        this.cropRectState = null;
      }
    } catch (error) {
      Log.e(TAG, 'applyCropRect error: ' + error);
    }
  }
}

export function getCurrentCameraPreviewComponent(): CameraPreviewComponent | null {
  return currentCameraPreview;
}

function parseAreaDimension(value: Length | undefined): number {
  if (value === undefined) {
    return 0;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function readOnAreaChangeSize(newValue: Area): Size {
  return {
    width: parseAreaDimension(newValue.width),
    height: parseAreaDimension(newValue.height),
  };
}

function readTouchType(eventObj: TouchEvent): number {
  const type = Number(eventObj.type);
  return Number.isFinite(type) ? Math.trunc(type) : -1;
}

function readTouchPoint(eventObj: TouchEvent): TouchPoint | null {
  if (!eventObj.touches) {
    return null;
  }

  const touches = eventObj.touches as Array<TouchRecord>;
  if (touches.length === 0) {
    return null;
  }

  const firstTouch = touches[0];
  const x = Number(firstTouch.x);
  const y = Number(firstTouch.y);
  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    return null;
  }

  const point: TouchPoint = {
    x: x,
    y: y,
  };
  return point;
}
