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
  // 用于即使外层 MLKitScannerView 仍标记为已初始化，组件被重建后也需要再次触发 setCameraInitialized(true)
  private isScanKitInitialized: boolean = false;
  private lifecycleId: number = -1;
  // 触摸时间戳和坐标，用于判断长按和对焦位置
  private touchDownAtMs: number = -1;
  // 当前触摸是否仍在按压中，以及是否已经触发过锁定（长按）逻辑，避免重复触发
  private isTouchPressed: boolean = false;
  private lockTriggeredInCurrentTouch: boolean = false;
  private longPressTimerId: number = -1;
  // 焦圈动画版本号，每次启动或重置动画时自增，用来让旧动画的回调自动失效。
  private focusRingAnimationSeq: number = 0;
  // 锁图标动画版本号
  private lockAnimationSeq: number = 0;
  private focusPointInPreviewCache: TouchPoint | null = null;
  private lockStartPositionCache: TouchPoint | null = null;
  private lockEndPositionCache: TouchPoint = { x: 0, y: 0 };
  private hasPermission: boolean = false;
  @Prop flutterMLKitScannerView: MLKitScannerView | null = null;
  @State canRenderCamera: boolean = false;
  @State surfaceId: string = '';
  // xComponent 宽度/高度——OHOS API仅接受number类型
  @State cameraWidth: number = 0;
  @State cameraHeight: number = 0;
  // XComponent 的偏移位置（相对于预览容器，用于实现居中裁剪），可能为负值以裁剪溢出部分
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  // 裁剪矩形状态
  @State cropRectState: CropRect | null = null;
  //  扫描仪是否处于活动状态（改变覆盖边框颜色）
  @State isActive: boolean = false;
  // 对焦状态
  @State showFocusState: boolean = false;
  // 是否显示对焦环
  @State showFocusRingState: boolean = false;
  // 对焦环透明度状态
  @State focusRingOpacityState: number = 0;
  // 对焦中心坐标（相对于预览容器，用于显示对焦环和计算对焦点在预览中的位置）
  @State focusCenterState: TouchPoint | null = null;
  // 对焦环位置状态（相对于预览容器，基于 focusCenterState 和固定半径计算，用于显示对焦环）
  @State focusRingLeftState: number = 0;
  @State focusRingTopState: number = 0;
  // 锁定状态，显示锁定图标并改变对焦环样式
  @State isFocusLockedState: boolean = false;
  // 是否显示锁定图标
  @State showLockIconState: boolean = false;
  // 锁定图标动画是否已完成（位置已移到目标点），用于控制动画流程和状态切换
  @State isLockIconSettledState: boolean = false;
  // 锁定图标位置状态（相对于预览容器，基于 focusCenterState 和固定偏移计算，用于显示锁定图标）
  @State lockIconLeftState: number = 0;
  @State lockIconTopState: number = 0;
  // 锁定图标透明度状态
  @State lockIconOpacityState: number = 0;

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
            .width(PluginConstants.FOCUS_RING_DIAMETER)
            .height(PluginConstants.FOCUS_RING_DIAMETER)
            .border({
              width: PluginConstants.FOCUS_RING_STROKE,
              color: Color.White,
            })
            .opacity(this.focusRingOpacityState)
            .borderRadius(PluginConstants.FOCUS_RING_RADIUS)
            .position({
              x: this.focusRingLeftState,
              y: this.focusRingTopState,
            })
        }
        // 锁定图标
        if (this.showLockIconState) {
          Image($r('app.media.lock_fill'))
            .align(Alignment.TopStart)
            .width(PluginConstants.LOCK_ICON_SIZE)
            .height(PluginConstants.LOCK_ICON_SIZE)
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

  // 获取预览容器尺寸，优先使用实际容器尺寸，回退到预设预览尺寸，如果都不可用则返回 null
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

  // 刷新对焦相关的几何状态，包括对焦中心坐标、对焦环位置、预览中的对焦点坐标，以及锁定图标的起始和结束位置
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
    this.focusRingLeftState = focusCenter.x - PluginConstants.FOCUS_RING_RADIUS;
    this.focusRingTopState = focusCenter.y - PluginConstants.FOCUS_RING_RADIUS;
    if (this.cameraWidth > 0 && this.cameraHeight > 0) {
      this.focusPointInPreviewCache = {
        x: Math.max(0, Math.min(this.cameraWidth, focusCenter.x - this.offsetX)),
        y: Math.max(0, Math.min(this.cameraHeight, focusCenter.y - this.offsetY)),
      };
    } else {
      this.focusPointInPreviewCache = null;
    }
    const iconHalf = PluginConstants.LOCK_ICON_SIZE / 2;
    this.lockStartPositionCache = {
      x: focusCenter.x - PluginConstants.FOCUS_RING_RADIUS - PluginConstants.LOCK_ICON_SIZE -
        PluginConstants.LOCK_START_EXTRA_LEFT,
      y: focusCenter.y - iconHalf,
    };
    this.lockEndPositionCache = {
      x: Math.max(0, this.offsetX) + PluginConstants.LOCK_TARGET_INSET_LEFT,
      y: Math.max(0, this.offsetY) + PluginConstants.LOCK_TARGET_INSET_TOP,
    };
    this.refreshFocusRingDisplayState();
  }

  private refreshFocusRingDisplayState(): void {
    this.showFocusRingState = this.showFocusState && this.focusCenterState !== null;
  }

  // 同步锁定图标位置
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
    if (touchType === PluginConstants.TOUCH_TYPE_DOWN && point) {
      this.touchDownAtMs = Date.now();
      this.isTouchPressed = true;
      this.lockTriggeredInCurrentTouch = false;
      this.startLongPressTimer();
      return;
    }

    // UP 如果长按已触发，则只结束本次触摸；否则按轻触对焦处理
    if (touchType === PluginConstants.TOUCH_TYPE_UP) {
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
    if (touchType === PluginConstants.TOUCH_TYPE_CANCEL) {
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
    }, PluginConstants.LONG_PRESS_THRESHOLD_MS) as number;
  }

  private resetFocusRingAnimationState(): void {
    // 每次重置都自增动画序列号，确保过期动画回调不再修改状态
    this.focusRingAnimationSeq++;
    this.showFocusState = false;
    this.focusRingOpacityState = 0;
    this.refreshFocusRingDisplayState();
  }

  /**
  * 播放焦圈提示动画：先从 0 淡入到最大透明度，再淡出到完全透明，最后隐藏焦圈。
  * 该动画同时用于轻触对焦提示，以及长按锁焦前的视觉反馈。
  */ 
  private startFocusRingAnim(): void {
    const animationSeq = ++this.focusRingAnimationSeq;
    this.showFocusState = true;
    this.refreshFocusRingDisplayState();
    // 第一步：立即将焦圈透明度设为0，为后续淡入做准备
    this.focusRingOpacityState = 0;
    // 第二步：焦圈从0淡入到最大透明度，形成“出现”动画
    this.getUIContext().animateTo({
      duration: PluginConstants.FOCUS_RING_FADE_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        // 若动画期间有新动画启动，则本次回调失效
        if (animationSeq !== this.focusRingAnimationSeq) {
          return;
        }
        // 第三步：焦圈从最大透明度淡出到0，形成“消失”动画
        this.getUIContext().animateTo({
          duration: PluginConstants.FOCUS_RING_FADE_DURATION_MS,
          curve: Curve.Linear,
          onFinish: () => {
            // 若动画期间有新动画启动，则本次回调失效
            if (animationSeq !== this.focusRingAnimationSeq) {
              return;
            }
            // 动画结束，隐藏焦圈
            this.showFocusState = false;
            this.refreshFocusRingDisplayState();
          },
        }, () => {
          // 淡出动画：透明度降为0
          this.focusRingOpacityState = 0;
          this.refreshFocusRingDisplayState();
        });
      },
    }, () => {
      // 淡入动画：透明度升至最大
      this.focusRingOpacityState = PluginConstants.FOCUS_RING_MAX_OPACITY;
      this.refreshFocusRingDisplayState();
    });
  }

  /**
  * 播放锁焦图标入场动画：图标先在焦圈左侧淡入，再移动到预览左上角的固定停靠位。
  * 只有从“未锁定”进入“锁定”时才会触发，重复长按已锁定场景不会重复播放该动画。
  */ 
  private startFocusLockAnim(): void {
    const start = this.lockStartPositionCache;
    if (!start) {
      return;
    }
    const animationSeq = ++this.lockAnimationSeq;
    this.showLockIconState = true;
    this.isLockIconSettledState = false;
    // 第一步：立即将锁图标放到起始点并设为透明，为后续动画做准备
    this.lockIconLeftState = start.x;
    this.lockIconTopState = start.y;
    this.lockIconOpacityState = 0;
    // 第二步：锁图标淡入（透明度0→1），停留在起始点
    this.getUIContext().animateTo({
      duration: PluginConstants.LOCK_FADE_IN_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        // 若动画期间有新动画启动或已解锁，则本次回调失效
        if (animationSeq !== this.lockAnimationSeq || !this.isFocusLockedState) {
          return;
        }
        // 第三步：锁图标从起始点平滑移动到左上角目标位
        this.getUIContext().animateTo({
          duration: PluginConstants.LOCK_MOVE_DURATION_MS,
          curve: Curve.EaseOut,
          onFinish: () => {
            // 若动画期间有新动画启动或已解锁，则本次回调失效
            if (animationSeq !== this.lockAnimationSeq || !this.isFocusLockedState) {
              return;
            }
            // 动画结束，标记锁图标已到达目标位
            this.isLockIconSettledState = true;
            this.refreshFocusRingDisplayState();
          },
        }, () => {
          // 移动动画：位置变为目标点
          this.lockIconLeftState = this.lockEndPositionCache.x;
          this.lockIconTopState = this.lockEndPositionCache.y;
        });
      },
    }, () => {
      // 淡入动画：透明度升至1
      this.lockIconOpacityState = 1;
    });
  }

  // 播放锁焦图标退场动画：将当前锁图标淡出并隐藏，同时把位置复位到起始点，便于下次重新播放入场动画。
  private fadeOutLockIcon(): void {
    const animationSeq = ++this.lockAnimationSeq;
    this.isLockIconSettledState = false;
    this.refreshFocusRingDisplayState();
    if (!this.showLockIconState) {
      this.lockIconOpacityState = 0;
      return;
    }
    // 锁图标淡出动画：透明度1→0，结束后隐藏并复位到起始点
    this.getUIContext().animateTo({
      duration: PluginConstants.LOCK_FADE_OUT_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        // 若动画期间有新动画启动，则本次回调失效
        if (animationSeq !== this.lockAnimationSeq) {
          return;
        }
        // 动画结束，隐藏锁图标并复位位置
        this.showLockIconState = false;
        this.lockIconOpacityState = 0;
        if (this.lockStartPositionCache) {
          this.lockIconLeftState = this.lockStartPositionCache.x;
          this.lockIconTopState = this.lockStartPositionCache.y;
        }
      },
    }, () => {
      // 淡出动画：透明度降为0
      this.lockIconOpacityState = 0;
    });
  }

  // 更新对焦提示状态，根据是否需要锁定切换对焦环和锁定图标的显示，并启动相应动画
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

  private resetLockIconAnimationState(): void {
    this.lockAnimationSeq++;
    this.showLockIconState = false;
    this.isLockIconSettledState = false;
    this.lockIconOpacityState = 0;
    if (this.lockStartPositionCache) {
      this.lockIconLeftState = this.lockStartPositionCache.x;
      this.lockIconTopState = this.lockStartPositionCache.y;
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
