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

import { PluginConstants, TouchPoint } from './PluginConstants';

/**
 * 对焦动画回调接口
 * 通过闭包桥接 @Component struct 中的 @State 属性，保持 ArkUI 响应性
 */
export interface FocusAnimationCallbacks {
  setShowFocusState: (v: boolean) => void;
  setFocusRingOpacityState: (v: number) => void;
  setShowFocusRingState: (v: boolean) => void;
  setShowLockIconState: (v: boolean) => void;
  setLockIconOpacityState: (v: number) => void;
  setLockIconLeftState: (v: number) => void;
  setLockIconTopState: (v: number) => void;
  setIsLockIconSettledState: (v: boolean) => void;
  setIsFocusLockedState: (v: boolean) => void;
  refreshFocusRingDisplayState: () => void;
  getUIContext: () => UIContext;
  getIsFocusLockedState: () => boolean;
  getShowLockIconState: () => boolean;
  getIsLockIconSettledState: () => boolean;
  getLockStartPositionCache: () => TouchPoint | null;
  getLockEndPositionCache: () => TouchPoint;
}

/**
 * 对焦动画辅助类
 * 封装对焦环和锁定图标的动画编排逻辑，包括动画序列号版本控制
 * 防止过期动画回调修改组件状态
 */
export class FocusAnimationHelper {
  // 焦圈动画版本号，每次启动或重置动画时自增，用来让旧动画的回调自动失效。
  private focusRingAnimationSeq: number = 0;
  // 锁图标动画版本号
  private lockAnimationSeq: number = 0;
  private readonly callbacks: FocusAnimationCallbacks;

  /**
   * 创建 FocusAnimationHelper 实例
   * @param callbacks - 动画回调集合，桥接 @State 属性的读写
   */
  constructor(callbacks: FocusAnimationCallbacks) {
    this.callbacks = callbacks;
  }

  /**
   * 重置对焦环动画状态，自增序列号使旧动画回调失效
   */
  resetFocusRingAnimationState(): void {
    // 每次重置都自增动画序列号，确保过期动画回调不再修改状态
    this.focusRingAnimationSeq++;
    this.callbacks.setShowFocusState(false);
    this.callbacks.setFocusRingOpacityState(0);
    this.callbacks.refreshFocusRingDisplayState();
  }

  /**
  * 播放焦圈提示动画：先从 0 淡入到最大透明度，再淡出到完全透明，最后隐藏焦圈。
  * 该动画同时用于轻触对焦提示，以及长按锁焦前的视觉反馈。
  */
  startFocusRingAnim(): void {
    const animationSeq = ++this.focusRingAnimationSeq;
    this.callbacks.setShowFocusState(true);
    this.callbacks.refreshFocusRingDisplayState();
    // 第一步：立即将焦圈透明度设为0，为后续淡入做准备
    this.callbacks.setFocusRingOpacityState(0);
    // 第二步：焦圈从0淡入到最大透明度，形成"出现"动画
    this.callbacks.getUIContext().animateTo({
      duration: PluginConstants.FOCUS_RING_FADE_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        // 若动画期间有新动画启动，则本次回调失效
        if (animationSeq !== this.focusRingAnimationSeq) {
          return;
        }
        // 第三步：焦圈从最大透明度淡出到0，形成"消失"动画
        this.callbacks.getUIContext().animateTo({
          duration: PluginConstants.FOCUS_RING_FADE_DURATION_MS,
          curve: Curve.Linear,
          onFinish: () => {
            // 若动画期间有新动画启动，则本次回调失效
            if (animationSeq !== this.focusRingAnimationSeq) {
              return;
            }
            // 动画结束，隐藏焦圈
            this.callbacks.setShowFocusState(false);
            this.callbacks.refreshFocusRingDisplayState();
          },
        }, () => {
          // 淡出动画：透明度降为0
          this.callbacks.setFocusRingOpacityState(0);
          this.callbacks.refreshFocusRingDisplayState();
        });
      },
    }, () => {
      // 淡入动画：透明度升至最大
      this.callbacks.setFocusRingOpacityState(PluginConstants.FOCUS_RING_MAX_OPACITY);
      this.callbacks.refreshFocusRingDisplayState();
    });
  }

  /**
  * 播放锁焦图标入场动画：图标先在焦圈左侧淡入，再移动到预览左上角的固定停靠位。
  * 只有从"未锁定"进入"锁定"时才会触发，重复长按已锁定场景不会重复播放该动画。
  */
  startFocusLockAnim(): void {
    const start = this.callbacks.getLockStartPositionCache();
    if (!start) {
      return;
    }
    const animationSeq = ++this.lockAnimationSeq;
    this.callbacks.setShowLockIconState(true);
    this.callbacks.setIsLockIconSettledState(false);
    // 第一步：立即将锁图标放到起始点并设为透明，为后续动画做准备
    this.callbacks.setLockIconLeftState(start.x);
    this.callbacks.setLockIconTopState(start.y);
    this.callbacks.setLockIconOpacityState(0);
    // 第二步：锁图标淡入（透明度0→1），停留在起始点
    this.callbacks.getUIContext().animateTo({
      duration: PluginConstants.LOCK_FADE_IN_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        // 若动画期间有新动画启动或已解锁，则本次回调失效
        if (animationSeq !== this.lockAnimationSeq || !this.callbacks.getIsFocusLockedState()) {
          return;
        }
        // 第三步：锁图标从起始点平滑移动到左上角目标位
        const endPos = this.callbacks.getLockEndPositionCache();
        this.callbacks.getUIContext().animateTo({
          duration: PluginConstants.LOCK_MOVE_DURATION_MS,
          curve: Curve.EaseOut,
          onFinish: () => {
            // 若动画期间有新动画启动或已解锁，则本次回调失效
            if (animationSeq !== this.lockAnimationSeq || !this.callbacks.getIsFocusLockedState()) {
              return;
            }
            // 动画结束，标记锁图标已到达目标位
            this.callbacks.setIsLockIconSettledState(true);
            this.callbacks.refreshFocusRingDisplayState();
          },
        }, () => {
          // 移动动画：位置变为目标点
          this.callbacks.setLockIconLeftState(endPos.x);
          this.callbacks.setLockIconTopState(endPos.y);
        });
      },
    }, () => {
      // 淡入动画：透明度升至1
      this.callbacks.setLockIconOpacityState(1);
    });
  }

  /**
   * 播放锁焦图标退场动画：淡出并隐藏，同时把位置复位到起始点
   */
  fadeOutLockIcon(): void {
    const animationSeq = ++this.lockAnimationSeq;
    this.callbacks.setIsLockIconSettledState(false);
    this.callbacks.refreshFocusRingDisplayState();
    if (!this.callbacks.getShowLockIconState()) {
      this.callbacks.setLockIconOpacityState(0);
      return;
    }
    // 锁图标淡出动画：透明度1→0，结束后隐藏并复位到起始点
    this.callbacks.getUIContext().animateTo({
      duration: PluginConstants.LOCK_FADE_OUT_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        // 若动画期间有新动画启动，则本次回调失效
        if (animationSeq !== this.lockAnimationSeq) {
          return;
        }
        // 动画结束，隐藏锁图标并复位位置
        this.callbacks.setShowLockIconState(false);
        this.callbacks.setLockIconOpacityState(0);
        const startPos = this.callbacks.getLockStartPositionCache();
        if (startPos) {
          this.callbacks.setLockIconLeftState(startPos.x);
          this.callbacks.setLockIconTopState(startPos.y);
        }
      },
    }, () => {
      // 淡出动画：透明度降为0
      this.callbacks.setLockIconOpacityState(0);
    });
  }

  /**
   * 更新对焦提示状态：根据是否需要锁定切换对焦环和锁定图标的显示，并启动相应动画
   * @param needLock - 是否需要锁定焦点（长按为 true，轻触为 false）
   */
  updateFocusHint(needLock: boolean): void {
    this.startFocusRingAnim();
    const isAlreadyLocked =
      needLock && this.callbacks.getIsFocusLockedState() &&
      this.callbacks.getShowLockIconState() && this.callbacks.getIsLockIconSettledState();
    this.callbacks.setIsFocusLockedState(needLock);
    this.callbacks.refreshFocusRingDisplayState();
    if (needLock) {
      if (!isAlreadyLocked) {
        this.startFocusLockAnim();
      }
    } else {
      this.fadeOutLockIcon();
      this.callbacks.setIsFocusLockedState(false);
      this.callbacks.refreshFocusRingDisplayState();
      this.resetLockIconAnimationState();
    }
  }

  /**
   * 重置锁定图标动画状态，自增序列号使旧动画回调失效
   */
  resetLockIconAnimationState(): void {
    this.lockAnimationSeq++;
    this.callbacks.setShowLockIconState(false);
    this.callbacks.setIsLockIconSettledState(false);
    this.callbacks.setLockIconOpacityState(0);
    const startPos = this.callbacks.getLockStartPositionCache();
    if (startPos) {
      this.callbacks.setLockIconLeftState(startPos.x);
      this.callbacks.setLockIconTopState(startPos.y);
    }
  }
}
