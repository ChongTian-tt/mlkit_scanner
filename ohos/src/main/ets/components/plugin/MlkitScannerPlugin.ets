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

const TAG: string = 'MlkitScannerPlugin';

/** MlkitScannerPlugin **/
export default class MlkitScannerPlugin implements FlutterPlugin, AbilityAware {
  private pluginBinding: FlutterPluginBinding | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    if (!binding || !this.pluginBinding) {
      return;
    }
    const factory: PlatformViewFactory = new CameraPreviewFactory(this.pluginBinding.getBinaryMessenger());
    this.pluginBinding.getPlatformViewRegistry().registerViewFactory(PluginConstants.cameraPlatformViewName, factory);
  }

  onDetachedFromAbility(): void {
    Log.i(TAG, 'onDetachedFromAbility');
  }
}