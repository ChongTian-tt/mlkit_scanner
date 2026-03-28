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
  // 长按对焦时间阈值 通常 >500ms 被认为是长按
  private LONG_PRESS_THRESHOLD_MS: number = 500;
  private TOUCH_TYPE_DOWN: number = 0;
  private TOUCH_TYPE_UP: number = 1;
  private TOUCH_TYPE_CANCEL: number = 3;
  // 触摸时间戳和坐标，用于判断长按和对焦位置
  private touchDownAtMs: number = -1;
  private touchDownX: number = 0;
  private touchDownY: number = 0;
  // 当前触摸是否仍在按压中，以及是否已经触发过锁定（长按）逻辑，避免重复触发
  private isTouchPressed: boolean = false;
  private lockTriggeredInCurrentTouch: boolean = false;
  private longPressTimerId: number = -1;
  private focusRingAnimationSeq: number = 0;
  private lockAnimationSeq: number = 0;
  private static readonly FOCUS_RING_FADE_DURATION_MS: number = 500;
  private static readonly FOCUS_RING_MAX_OPACITY: number = 1;
  private static readonly LOCK_FADE_IN_DURATION_MS: number = 300;
  private static readonly LOCK_MOVE_DURATION_MS: number = 500;
  private static readonly LOCK_FADE_OUT_DURATION_MS: number = 200;
  // 对焦环和锁定图标的尺寸和位置参数
  private static readonly FOCUS_RING_DIAMETER: number = 60;
  // 对焦环半径
  private static readonly FOCUS_RING_RADIUS: number = CameraPreviewComponent.FOCUS_RING_DIAMETER / 2;
  // 对焦环边框宽度
  private static readonly FOCUS_RING_STROKE: number = 1;
  // 锁定图标尺寸
  private static readonly LOCK_ICON_SIZE: number = 24;
  private static readonly LOCK_START_EXTRA_LEFT: number = CameraPreviewComponent.LOCK_ICON_SIZE / 2;
  // 锁定图标在预览区域内的目标位置
  private static readonly LOCK_TARGET_INSET_LEFT: number = 20;
  private static readonly LOCK_TARGET_INSET_TOP: number = 20;
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
  // 对焦状态
  @State showFocusState: boolean = false;
  @State showFocusRingState: boolean = false;
  @State focusRingOpacityState: number = 0;
  @State focusCenterState: TouchPoint | null = null;
  @State focusRingLeftState: number = 0;
  @State focusRingTopState: number = 0;
  // 锁定状态
  @State isFocusLockedState: boolean = false;
  @State showLockIconState: boolean = false;
  @State isLockIconSettledState: boolean = false;
  @State lockIconLeftState: number = 0;
  @State lockIconTopState: number = 0;
  @State lockIconOpacityState: number = 0;
  private focusPointInPreviewCache: TouchPoint | null = null;
  private lockStartPositionCache: TouchPoint | null = null;
  private lockEndPositionCache: TouchPoint = { x: 0, y: 0 };

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
        // 对焦环
        if (this.showFocusRingState) {
          Stack() {
          }
            .width(CameraPreviewComponent.FOCUS_RING_DIAMETER)
            .height(CameraPreviewComponent.FOCUS_RING_DIAMETER)
            .border({
              width: CameraPreviewComponent.FOCUS_RING_STROKE,
              color: Color.White,
            })
            .opacity(this.focusRingOpacityState)
            .borderRadius(CameraPreviewComponent.FOCUS_RING_RADIUS)
            .position({
              x: this.focusRingLeftState,
              y: this.focusRingTopState,
            })
        }
        if (this.showLockIconState) {
          Image($r('app.media.lock_fill'))
            .align(Alignment.TopStart)
            .width(CameraPreviewComponent.LOCK_ICON_SIZE)
            .height(CameraPreviewComponent.LOCK_ICON_SIZE)
            .opacity(this.lockIconOpacityState)
            .position({
              x: this.lockIconLeftState,
              y: this.lockIconTopState,
            })
            .draggable(false)
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

  private getViewportSize(): Size | null {
    const container = this.flutterMLKitScannerView?.getContainerSize();
    if (container && container.width > 0 && container.height > 0) {
      return container;
    }
    if (this.cameraWidth > 0 && this.cameraHeight > 0) {
      return {
        width: this.cameraWidth,
        height: this.cameraHeight,
      };
    }
    return null;
  }

  private refreshFocusGeometry(): void {
    const viewport = this.getViewportSize();
    if (!viewport) {
      this.focusCenterState = null;
      this.focusRingLeftState = 0;
      this.focusRingTopState = 0;
      this.focusPointInPreviewCache = null;
      this.lockStartPositionCache = null;
      this.lockEndPositionCache = { x: 0, y: 0 };
      this.refreshFocusRingDisplayState();
      return;
    }
    let focusCenter: TouchPoint;
    if (this.cropRectState) {
      focusCenter = {
        x: viewport.width / 2 * (1 + this.cropRectState.offsetX),
        y: viewport.height / 2 * (1 + this.cropRectState.offsetY),
      };
    } else {
      focusCenter = {
        x: viewport.width / 2,
        y: viewport.height / 2,
      };
    }
    this.focusCenterState = focusCenter;
    this.focusRingLeftState = focusCenter.x - CameraPreviewComponent.FOCUS_RING_RADIUS;
    this.focusRingTopState = focusCenter.y - CameraPreviewComponent.FOCUS_RING_RADIUS;
    if (this.cameraWidth > 0 && this.cameraHeight > 0) {
      this.focusPointInPreviewCache = {
        x: Math.max(0, Math.min(this.cameraWidth, focusCenter.x - this.offsetX)),
        y: Math.max(0, Math.min(this.cameraHeight, focusCenter.y - this.offsetY)),
      };
    } else {
      this.focusPointInPreviewCache = null;
    }
    const iconHalf = CameraPreviewComponent.LOCK_ICON_SIZE / 2;
    this.lockStartPositionCache = {
      x: focusCenter.x - CameraPreviewComponent.FOCUS_RING_RADIUS - CameraPreviewComponent.LOCK_ICON_SIZE -
        CameraPreviewComponent.LOCK_START_EXTRA_LEFT,
      y: focusCenter.y - iconHalf,
    };
    this.lockEndPositionCache = {
      x: Math.max(0, this.offsetX) + CameraPreviewComponent.LOCK_TARGET_INSET_LEFT,
      y: Math.max(0, this.offsetY) + CameraPreviewComponent.LOCK_TARGET_INSET_TOP,
    };
    this.refreshFocusRingDisplayState();
  }

  private refreshFocusRingDisplayState(): void {
    this.showFocusRingState = this.showFocusState && this.focusCenterState !== null;
  }

  private syncLockIconGeometry(): void {
    if (!this.showLockIconState) {
      return;
    }
    const target = this.isLockIconSettledState ? this.lockEndPositionCache : this.lockStartPositionCache;
    if (!target) {
      return;
    }
    this.lockIconLeftState = target.x;
    this.lockIconTopState = target.y;
  }

  // 处理对焦触摸事件
  private handleFocusTouch(eventObj: TouchEvent): void {
    if (!this.flutterMLKitScannerView || this.cameraWidth <= 0 || this.cameraHeight <= 0) {
      return;
    }
    const touchType = readTouchType(eventObj);
    const rawPoint = readTouchPoint(eventObj);
    const point = rawPoint ? this.toPreviewPoint(rawPoint) : null;

    // DOWN 事件时启动长按计时，满 500ms 立即触发锁定对焦（不再等待 UP）
    if (touchType === this.TOUCH_TYPE_DOWN && point) {
      this.touchDownAtMs = Date.now();
      this.touchDownX = point.x;
      this.touchDownY = point.y;
      this.isTouchPressed = true;
      this.lockTriggeredInCurrentTouch = false;
      this.startLongPressTimer();
      return;
    }

    // UP 如果长按已触发，则只结束本次触摸；否则按轻触对焦处理
    if (touchType === this.TOUCH_TYPE_UP) {
      if (!this.isTouchPressed || this.touchDownAtMs < 0) {
        return;
      }
      this.clearLongPressTimer();
      this.isTouchPressed = false;
      this.touchDownAtMs = -1;

      if (this.lockTriggeredInCurrentTouch) {
        return;
      }
      const focusPoint = this.focusPointInPreviewCache;
      if (!focusPoint) {
        return;
      }
      // 轻触对焦：显示一次淡入淡出焦圈，不显示锁定图标，并以裁剪框中心作为统一焦点
      this.updateFocusHint(false);
      this.flutterMLKitScannerView.handleUserFocusGesture(
        focusPoint.x,
        focusPoint.y,
        this.cameraWidth,
        this.cameraHeight,
        false,
      );
      return;
    }

    // CANCEL 事件时清理状态和计时，避免残留状态影响下一次触摸
    if (touchType === this.TOUCH_TYPE_CANCEL) {
      this.clearLongPressTimer();
      this.isTouchPressed = false;
      this.lockTriggeredInCurrentTouch = false;
      this.touchDownAtMs = -1;
    }
  }

  private clearLongPressTimer(): void {
    if (this.longPressTimerId >= 0) {
      clearTimeout(this.longPressTimerId);
      this.longPressTimerId = -1;
    }
  }

  // 启动长按计时器，在达到长按阈值后触发锁定对焦逻辑，并更新状态以显示锁定动画
  private startLongPressTimer(): void {
    this.clearLongPressTimer();
    this.longPressTimerId = setTimeout(() => {
      this.longPressTimerId = -1;
      if (!this.isTouchPressed || this.lockTriggeredInCurrentTouch || this.touchDownAtMs < 0) {
        return;
      }

      this.lockTriggeredInCurrentTouch = true;
      const focusPoint = this.focusPointInPreviewCache;
      if (!focusPoint) {
        return;
      }
      this.updateFocusHint(true);
      this.flutterMLKitScannerView?.handleUserFocusGesture(
        focusPoint.x,
        focusPoint.y,
        this.cameraWidth,
        this.cameraHeight,
        true,
      );
    }, this.LONG_PRESS_THRESHOLD_MS) as number;
  }

  private resetFocusRingAnimationState(): void {
    this.focusRingAnimationSeq++;
    this.showFocusState = false;
    this.focusRingOpacityState = 0;
    this.refreshFocusRingDisplayState();
  }

  private startFocusRingAnim(): void {
    const animationSeq = ++this.focusRingAnimationSeq;
    this.showFocusState = true;
    this.refreshFocusRingDisplayState();
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.focusRingOpacityState = 0;
    });
    this.getUIContext().animateTo({
      duration: CameraPreviewComponent.FOCUS_RING_FADE_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        if (animationSeq !== this.focusRingAnimationSeq) {
          return;
        }
        this.getUIContext().animateTo({
          duration: CameraPreviewComponent.FOCUS_RING_FADE_DURATION_MS,
          curve: Curve.Linear,
          onFinish: () => {
            if (animationSeq !== this.focusRingAnimationSeq) {
              return;
            }
            this.showFocusState = false;
            this.refreshFocusRingDisplayState();
          },
        }, () => {
          this.focusRingOpacityState = 0;
          this.refreshFocusRingDisplayState();
        });
      },
    }, () => {
      this.focusRingOpacityState = CameraPreviewComponent.FOCUS_RING_MAX_OPACITY;
      this.refreshFocusRingDisplayState();
    });
  }

  private resetLockIconAnimationState(): void {
    this.lockAnimationSeq++;
    this.showLockIconState = false;
    this.isLockIconSettledState = false;
    this.lockIconOpacityState = 0;
    const start = this.lockStartPositionCache;
    if (start) {
      this.lockIconLeftState = start.x;
      this.lockIconTopState = start.y;
    }
  }

  private startFocusLockAnim(): void {
    const start = this.lockStartPositionCache;
    if (!start) {
      return;
    }
    const end = this.lockEndPositionCache;
    const animationSeq = ++this.lockAnimationSeq;
    this.showLockIconState = true;
    this.isLockIconSettledState = false;
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.lockIconLeftState = start.x;
      this.lockIconTopState = start.y;
      this.lockIconOpacityState = 0;
    });
    this.getUIContext().animateTo({
      duration: CameraPreviewComponent.LOCK_FADE_IN_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        if (animationSeq !== this.lockAnimationSeq || !this.isFocusLockedState) {
          return;
        }
        this.getUIContext().animateTo({
          duration: CameraPreviewComponent.LOCK_MOVE_DURATION_MS,
          curve: Curve.EaseOut,
          onFinish: () => {
            if (animationSeq !== this.lockAnimationSeq || !this.isFocusLockedState) {
              return;
            }
            this.isLockIconSettledState = true;
            this.refreshFocusRingDisplayState();
          },
        }, () => {
          this.lockIconLeftState = end.x;
          this.lockIconTopState = end.y;
        });
      },
    }, () => {
      this.lockIconOpacityState = 1;
    });
  }

  private fadeOutLockIcon(): void {
    const animationSeq = ++this.lockAnimationSeq;
    this.isLockIconSettledState = false;
    this.refreshFocusRingDisplayState();
    if (!this.showLockIconState) {
      this.lockIconOpacityState = 0;
      return;
    }
    this.getUIContext().animateTo({
      duration: CameraPreviewComponent.LOCK_FADE_OUT_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        if (animationSeq !== this.lockAnimationSeq) {
          return;
        }
        this.showLockIconState = false;
        this.lockIconOpacityState = 0;
        const start = this.lockStartPositionCache;
        if (start) {
          this.lockIconLeftState = start.x;
          this.lockIconTopState = start.y;
        }
      },
    }, () => {
      this.lockIconOpacityState = 0;
    });
  }

  // 更新对焦提示状态：根据是否锁定设置不同的状态，并启动或重置锁定动画
  private updateFocusHint(needLock: boolean): void {
    this.startFocusRingAnim();
    const isAlreadyLocked = needLock && this.isFocusLockedState && this.showLockIconState && this.isLockIconSettledState;
    this.isFocusLockedState = needLock;
    this.refreshFocusRingDisplayState();
    if (needLock) {
      if (!isAlreadyLocked) {
        this.startFocusLockAnim();
      }
    } else {
      this.fadeOutLockIcon();
      this.isFocusLockedState = false;
      this.refreshFocusRingDisplayState();
      this.resetLockIconAnimationState();
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
    this.clearLongPressTimer();
    this.resetFocusRingAnimationState();
    this.resetLockIconAnimationState();
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
      this.refreshFocusGeometry();
      this.syncLockIconGeometry();
    } catch (error) {
      Log.e(TAG, 'applyCropRect error: ' + error);
    }
  }
}

export function getCurrentCameraPreviewComponent(): CameraPreviewComponent | null {
  return currentCameraPreview;
}

// 解析 Area 维度，支持 number 或字符串形式的数字，返回有效的数值或 0
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

// 从 Area 变化事件中提取新的宽高，返回 Size 对象
function readOnAreaChangeSize(newValue: Area): Size {
  return {
    width: parseAreaDimension(newValue.width),
    height: parseAreaDimension(newValue.height),
  };
}

// 解析触摸事件类型，返回标准化的触摸类型常量，未识别时返回 -1
function readTouchType(eventObj: TouchEvent): number {
  const type = Number(eventObj.type);
  return Number.isFinite(type) ? Math.trunc(type) : -1;
}

// 解析触摸事件中的第一个触点坐标，返回 TouchPoint 对象或 null
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
