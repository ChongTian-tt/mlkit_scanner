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
import { CropRect, PluginConstants, PluginError, Size, TouchPoint, TouchRecord, LockVisualState } from './PluginConstants';

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
  // 锁定对焦动画状态：记录是否显示锁定图标、动画进度等，用于在 render 中计算锁定图标位置和透明度
  private lockTriggeredInCurrentTouch: boolean = false;
  private longPressTimerId: number = -1;
  // 对焦提示和锁定状态的定时器 ID，用于在组件卸载或状态变化时清理
  private focusHintTimerId: number = -1;
  private focusLockAnimTimerId: number = -1;
  // 锁定动画参数：定义锁定图标淡入和位移动画的时长，以及动画更新的时间间隔，确保动画平滑且性能可控
  private static readonly LOCK_FADE_IN_DURATION_MS: number = 300;
  // 锁定动画总时长包括淡入和位移，确保在动画过程中正确计算锁定图标的透明度和位置
  private static readonly LOCK_MOVE_DURATION_MS: number = 500;
  // 锁定动画总时长，确保在动画过程中正确计算锁定图标的透明度和位置
  private static readonly LOCK_ANIM_DURATION_MS: number =
    CameraPreviewComponent.LOCK_FADE_IN_DURATION_MS + CameraPreviewComponent.LOCK_MOVE_DURATION_MS;
  // 锁定动画更新间隔，通常设置为 16ms 以实现约 60fps 的动画效果，确保动画平滑且性能可控
  private static readonly LOCK_ANIM_INTERVAL_MS: number = 16;
  // 对焦环和锁定图标的尺寸和位置参数
  private static readonly FOCUS_RING_DIAMETER: number = 60;
  // 对焦环半径
  private static readonly FOCUS_RING_RADIUS: number = CameraPreviewComponent.FOCUS_RING_DIAMETER / 2;
  // 对焦环边框宽度
  private static readonly FOCUS_RING_STROKE: number = 1;
  // 锁定图标尺寸
  private static readonly LOCK_ICON_SIZE: number = 24;
  // 锁定图标在预览区域内的目标位置（相对于可见预览区域的左上角内缩）
  private static readonly LOCK_TARGET_INSET_LEFT: number = 17;
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
  // 锁定状态
  @State isFocusLockedState: boolean = false;
  // 锁定动画进度（0-1）
  @State focusLockAnimProgressState: number = 1;

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
        if (this.shouldShowFocusRing()) {
          Stack() {
          }
            .width(CameraPreviewComponent.FOCUS_RING_DIAMETER)
            .height(CameraPreviewComponent.FOCUS_RING_DIAMETER)
            .border({
              width: CameraPreviewComponent.FOCUS_RING_STROKE,
              color: Color.White,
            })
            .opacity(0.6)
            .borderRadius(CameraPreviewComponent.FOCUS_RING_RADIUS)
            .position({
              x: this.getFocusRingLeft(),
              y: this.getFocusRingTop(),
            })
        }
        // 锁定图标
        if (this.hasLockVisualState()) {
          Image($r('app.media.lock_fill'))
            .align(Alignment.TopStart)
            .width(CameraPreviewComponent.LOCK_ICON_SIZE)
            .height(CameraPreviewComponent.LOCK_ICON_SIZE)
            .opacity(this.getLockOpacity())
            .position({
              x: this.getLockLeft(),
              y: this.getLockTop(),
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

  // 计算焦点位置（相对于预览坐标系）
  private getFocusCenter(): TouchPoint | null {
    if (this.cameraWidth <= 0 || this.cameraHeight <= 0) {
      return null;
    }
    return {
      x: this.offsetX + this.cameraWidth / 2,
      y: this.offsetY + this.cameraHeight / 2,
    };
  }

  private getVisiblePreviewLeft(): number {
    return Math.max(0, this.offsetX);
  }

  private getVisiblePreviewTop(): number {
    return Math.max(0, this.offsetY);
  }

  // 计算锁定图标的视觉状态（位置和透明度）
  private getLockVisualState(): LockVisualState | null {
    if (!this.showFocusState || !this.isFocusLockedState) {
      return null;
    }
    const focusCenter = this.getFocusCenter();
    if (!focusCenter) {
      return null;
    }
    // 将动画总进度限制在 0 到 1 之间
    const progress = Math.max(0, Math.min(1, this.focusLockAnimProgressState));
    // 计算锁图标淡入阶段的透明度进度
    const fadeProgress = Math.max(
      0,
      // 将总进度映射到淡入阶段的时间轴，以淡入时长归一化得到淡入进度
      Math.min(1, progress * CameraPreviewComponent.LOCK_ANIM_DURATION_MS /
        CameraPreviewComponent.LOCK_FADE_IN_DURATION_MS),
    );
    // 计算位移动画阶段已经消耗的时间
    const movePhaseElapsed = Math.max(
      0,
      // 总耗时减去淡入阶段耗时后得到位移阶段耗时
      progress * CameraPreviewComponent.LOCK_ANIM_DURATION_MS - CameraPreviewComponent.LOCK_FADE_IN_DURATION_MS,
    );
    // 计算位移动画的归一化进度
    const moveProgress = Math.max(
      0,
      // 按位移总时长归一化并限制在 0 到 1 之间
      Math.min(1, movePhaseElapsed / CameraPreviewComponent.LOCK_MOVE_DURATION_MS),
    );
    // 使用 ease-out 曲线让移动末端更平滑
    const easedMove = 1 - Math.pow(1 - moveProgress, 3);
    // 计算锁图标一半尺寸用于垂直居中对齐
    const iconHalf = CameraPreviewComponent.LOCK_ICON_SIZE / 2;
    // 锁图标起点位于焦圈正左侧
    const startLeft = focusCenter.x - CameraPreviewComponent.FOCUS_RING_RADIUS - CameraPreviewComponent.LOCK_ICON_SIZE;
    // 锁图标起点在纵向上与焦圈中心对齐
    const startTop = focusCenter.y - iconHalf;
    // 锁图标终点横坐标位于可见预览区域左侧内缩位置
    const endLeft = this.getVisiblePreviewLeft() + CameraPreviewComponent.LOCK_TARGET_INSET_LEFT;
    // 锁图标终点纵坐标位于可见预览区域顶部内缩位置
    const endTop = this.getVisiblePreviewTop() + CameraPreviewComponent.LOCK_TARGET_INSET_TOP;

    return {
      left: startLeft + (endLeft - startLeft) * easedMove,
      top: startTop + (endTop - startTop) * easedMove,
      opacity: fadeProgress,
    };
  }

  private hasLockVisualState(): boolean {
    return this.getLockVisualState() !== null;
  }

  private getLockLeft(): number {
    const state = this.getLockVisualState();
    return state ? state.left : 0;
  }

  private getLockTop(): number {
    const state = this.getLockVisualState();
    return state ? state.top : 0;
  }

  private getLockOpacity(): number {
    const state = this.getLockVisualState();
    return state ? state.opacity : 0;
  }

  // 当锁定动画完成后，持续显示锁定图标直到下一次对焦操作触发
  private shouldHideFocusRing(): boolean {
    return this.isFocusLockedState && this.focusLockAnimProgressState >= 0.999;
  }

  // 显示对焦环的条件：必须处于对焦状态，且不满足持续显示锁定图标的条件（即未锁定或锁定动画未完成），且能够获取到焦点中心坐标
  private shouldShowFocusRing(): boolean {
    return this.showFocusState && !this.shouldHideFocusRing() && this.getFocusCenter() !== null;
  }

  private getFocusRingLeft(): number {
    const center = this.getFocusCenter();
    return center ? center.x - CameraPreviewComponent.FOCUS_RING_RADIUS : 0;
  }

  private getFocusRingTop(): number {
    const center = this.getFocusCenter();
    return center ? center.y - CameraPreviewComponent.FOCUS_RING_RADIUS : 0;
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
      const focusX = this.touchDownX;
      const focusY = this.touchDownY;
      this.touchDownAtMs = -1;

      if (this.lockTriggeredInCurrentTouch) {
        return;
      }
      // 轻触对焦：显示对焦提示但不锁定，3秒后自动隐藏；如果在提示显示期间再次轻触，则更新对焦位置和重置隐藏计时
      this.updateFocusHint(false);
      this.flutterMLKitScannerView.handleUserFocusGesture(
        focusX,
        focusY,
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
      const focusX = this.touchDownX;
      const focusY = this.touchDownY;
      this.updateFocusHint(true);
      this.flutterMLKitScannerView?.handleUserFocusGesture(
        focusX,
        focusY,
        this.cameraWidth,
        this.cameraHeight,
        true,
      );
    }, this.LONG_PRESS_THRESHOLD_MS) as number;
  }

  private clearFocusHintTimer(): void {
    if (this.focusHintTimerId >= 0) {
      clearTimeout(this.focusHintTimerId);
      this.focusHintTimerId = -1;
    }
  }

  private clearFocusLockAnimTimer(): void {
    if (this.focusLockAnimTimerId >= 0) {
      clearInterval(this.focusLockAnimTimerId);
      this.focusLockAnimTimerId = -1;
    }
  }

  // 启动锁定动画：重置动画状态并使用 setInterval 定时更新动画进度，直到动画完成后清理计时器
  private startFocusLockAnim(): void {
    this.clearFocusLockAnimTimer();
    this.focusLockAnimProgressState = 0;
    const startAt = Date.now();
    this.focusLockAnimTimerId = setInterval(() => {
      const elapsed = Date.now() - startAt;
      const raw = elapsed / CameraPreviewComponent.LOCK_ANIM_DURATION_MS;
      const clamped = Math.max(0, Math.min(1, raw));
      this.focusLockAnimProgressState = clamped;
      if (clamped >= 1) {
        this.clearFocusLockAnimTimer();
      }
    }, CameraPreviewComponent.LOCK_ANIM_INTERVAL_MS) as number;
  }

  // 更新对焦提示状态：根据是否锁定设置不同的状态，并启动或重置锁定动画
  private updateFocusHint(needLock: boolean): void {
    this.clearFocusHintTimer();
    this.showFocusState = true;
    this.isFocusLockedState = needLock;
    if (needLock) {
      this.startFocusLockAnim();
    } else {
      this.clearFocusLockAnimTimer();
      this.focusLockAnimProgressState = 1;
    }

    // 如果是轻触触发的对焦，则 900ms 后自动隐藏提示和重置锁定状态
    if (!needLock) {
      this.focusHintTimerId = setTimeout(() => {
        this.showFocusState = false;
        this.isFocusLockedState = false;
        this.focusLockAnimProgressState = 1;
        this.focusHintTimerId = -1;
      }, 900) as number;
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
    this.clearFocusHintTimer();
    this.clearFocusLockAnimTimer();
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
