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
import {
  FlutterPlugin,
  FlutterPluginBinding,
  AbilityAware,
  PlatformViewFactory,
  AbilityPluginBinding,
  Log,
} from '@ohos/flutter_ohos';
import { CameraPreviewFactory } from './CameraPreviewFactory';
import { PluginConstants } from './PluginConstants';
import { getCurrentMLKitScannerView } from './MLKitScannerView';

const TAG: string = '[MlkitScannerPlugin:]';

/**
 * MlkitScannerPlugin - Flutter插件主入口
 * 负责插件生命周期绑定、PlatformViewFactory注册与资源释放
 * @implements FlutterPlugin, AbilityAware
 */
export default class MlkitScannerPlugin implements FlutterPlugin, AbilityAware {
  private pluginBinding: FlutterPluginBinding | null = null;
  private registeredFactory: boolean = false;

  /** 获取插件唯一类名标识 */
  getUniqueClassName(): string {
    return TAG;
  }

  /**
   * 插件附加到Flutter引擎时回调，保存pluginBinding引用
   * @param binding - Flutter插件绑定对象
   */
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
  }

  /**
   * 插件从Flutter引擎分离时回调，兜底释放PlatformView资源
   * @param binding - Flutter插件绑定对象
   */
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    // 兜底保障：主动触发 PlatformView 资源释放
    try {
      const view = getCurrentMLKitScannerView();
      if (view) {
        view.dispose();
      }
    } catch (error) {
      Log.e(TAG, 'onDetachedFromEngine dispose error: ' + JSON.stringify(error));
    }
    this.pluginBinding = null;
  }

  /**
   * Ability附加时回调，注册PlatformViewFactory
   * @param binding - Ability插件绑定对象
   */
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    if (!binding || !this.pluginBinding) {
      return;
    }
    const factory: PlatformViewFactory = new CameraPreviewFactory(this.pluginBinding.getBinaryMessenger());
    this.pluginBinding.getPlatformViewRegistry().registerViewFactory(PluginConstants.CAMERA_PLATFORM_VIEW_NAME, factory);
    this.registeredFactory = true;
  }

  /** Ability分离时回调，兜底释放PlatformView资源 */
  onDetachedFromAbility(): void {
    // PlatformViewRegistry API 不提供 unregisterViewFactory，
    // 在 Ability 分离时主动释放 PlatformView 资源作为兜底
    if (this.registeredFactory) {
      try {
        const view = getCurrentMLKitScannerView();
        if (view) {
          view.dispose();
        }
      } catch (error) {
        Log.w(TAG, 'onDetachedFromAbility dispose skipped: ' + JSON.stringify(error));
      }
      this.registeredFactory = false;
    }
    this.pluginBinding = null;
  }
}