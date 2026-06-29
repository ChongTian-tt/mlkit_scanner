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

import { BinaryMessenger, PlatformView, StandardMessageCodec, PlatformViewFactory } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import { MLKitScannerView } from './MLKitScannerView';

export class CameraPreviewFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;

  /**
   * 创建 CameraPreviewFactory 实例
   * @param messenger - Flutter 二进制消息通道，用于 MethodChannel 通信
   */
  constructor(messenger: BinaryMessenger) {
    super(StandardMessageCodec.INSTANCE);
    this.messenger = messenger;
  }

  /**
   * 创建 PlatformView 实例
   * @param context - Ability 上下文
   * @param viewId - 平台视图 ID
   * @param args - Flutter 传入的初始化参数
   * @returns MLKitScannerView 实例
   */
  create(context: common.Context, viewId: number, args: Object): PlatformView {
    return new MLKitScannerView(context, this.messenger, viewId, args);
  }
}
