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

import image from '@ohos.multimedia.image';
import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '@ohos/flutter_ohos';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { PluginConstants, Size } from './PluginConstants';

const TAG: string = '[ScanDecoder]:';

/**
 * 扫码解码器类
 * 负责图像接收器管理、预览帧到达回调、节流解码和 ScanKit 条码识别
 */
export class ScanDecoder {
  // 标记是否已停止，避免在停止后继续处理预览帧导致错误
  private isStop: boolean = false;
  // 解码节流，避免过于频繁地对预览帧进行解码，导致性能问题和重复结果
  private lastDecodeAtMs: number = 0;
  // 解码节流间隔（毫秒），由外部通过 setDecodeThrottleMs 注入，默认 800ms
  private decodeThrottleMs: number = 800;
  // imageArrival 事件回调引用，用于 off() 取消订阅
  private imageArrivalCallback: (() => void) | null = null;
  // 图像接收器，用于接收相机预览帧并进行扫码解码
  public imageReceiver: image.ImageReceiver;
  // 标记是否已释放 ImageReceiver，避免重复释放导致错误
  private isImageReceiverReleased: boolean = false;
  // ImageReceiver 是否在上一次 ensureImageReceiver 调用中被重建
  // 如果被重建，调用方需重置帧监听绑定标志以重新绑定回调
  public imageReceiverRecreated: boolean = false;
  // 当前预览配置的尺寸，单位是像素。初始值为默认预览尺寸，后续会根据实际相机 profile 更新。
  private previewProfileSize: Size = {
    width: PluginConstants.DEFAULT_PREVIEW_WIDTH,
    height: PluginConstants.DEFAULT_PREVIEW_HEIGHT,
  };

  /**
   * 创建 ScanDecoder 实例
   * @param previewSize - 初始预览尺寸
   * @param imgReceiver - 可选的 ImageReceiver 实例，不传则使用默认配置创建
   */
  constructor(previewSize: Size, imgReceiver?: image.ImageReceiver) {
    const receiverFormat = imgReceiver?.format ?? image.ImageFormat.JPEG;
    const receiverCapacity = imgReceiver?.capacity ?? 1;
    this.imageReceiver = this.createImageReceiver(previewSize, receiverFormat, receiverCapacity);
    this.previewProfileSize = {
      width: previewSize.width,
      height: previewSize.height,
    };
  }

  /**
   * 创建 ImageReceiver 实例
   * @param size - 预览尺寸
   * @param format - 图像格式
   * @param capacity - 缓冲区容量
   * @returns ImageReceiver 实例
   */
  private createImageReceiver(size: Size, format: number, capacity: number): image.ImageReceiver {
    const previewSize: camera.Size = {
      width: size.width,
      height: size.height,
    } as camera.Size;
    return image.createImageReceiver(previewSize, format, capacity);
  }

  /**
   * 确保ImageReceiver可用，如果尺寸变化则创建新的
   * 创建新 ImageReceiver 前会取消旧事件订阅，重建后设置 imageReceiverRecreated=true
   * @param size - 期望的预览尺寸
   */
  async ensureImageReceiver(size: Size): Promise<void> {
    if (
      !this.isImageReceiverReleased &&
      this.previewProfileSize.width === size.width &&
      this.previewProfileSize.height === size.height
    ) {
      return;
    }

    // 创建新 ImageReceiver 前，先取消旧的事件订阅，防止回调在释放后触发
    this.offImageArrival();

    try {
      if (!this.isImageReceiverReleased) {
        await this.imageReceiver.release();
        this.isImageReceiverReleased = true;
      }
    } catch (error) {
      Log.w(TAG, 'ensureImageReceiver release skipped: ' + JSON.stringify(error));
    }

    this.previewProfileSize = {
      width: size.width,
      height: size.height,
    };
    this.imageReceiver = this.createImageReceiver(this.previewProfileSize, image.ImageFormat.JPEG, 1);
    this.isImageReceiverReleased = false;
    this.imageReceiverRecreated = true;
  }

  /**
   * 取消 imageArrival 事件订阅，防止回调在释放后触发和循环引用
   */
  offImageArrival(): void {
    if (this.imageArrivalCallback) {
      try {
        this.imageReceiver.off('imageArrival', this.imageArrivalCallback);
      } catch (error) {
        Log.w(TAG, 'offImageArrival skipped: ' + JSON.stringify(error));
      }
      this.imageArrivalCallback = null;
    }
  }

  /**
   * 注册预览帧到达的回调函数，在回调中读取预览帧图像并进行扫码解码
   * @param scanCallback - 扫码结果回调，接收 ScanResult 对象和帧高度
   */
  onImageArrival(scanCallback: (result: scanBarcode.ScanResult, frameHeight: number) => void): void {
    // 先取消旧监听器
    this.offImageArrival();

    this.imageArrivalCallback = () => {
      if (this.isStop) {
        return;
      }
      try {
        // 从ImageReceiver读取下一张图片
        this.imageReceiver.readNextImage((err: BusinessError, nextImage: image.Image) => {
          if (err || nextImage === undefined) {
            Log.e(TAG, 'onImageArrival readNextImage failed');
            return;
          }
          // 根据图像的组件类型从图像中获取组件缓存
          nextImage.getComponent(image.ComponentType.JPEG,
            async (compErr: BusinessError, imgComponent: image.Component) => {
            if (compErr || imgComponent === undefined) {
              Log.e(TAG, 'onImageArrival getComponent(JPEG) failed: ' + JSON.stringify(compErr));
              await nextImage.release();
              return;
            }
            if (imgComponent.byteBuffer as ArrayBuffer) {
              // 对图片进行解码
              await this.decodeImageBuffer(
                imgComponent, nextImage.size.width, nextImage.size.height,
                scanCallback, nextImage
              );
            } else {
              await nextImage.release();
            }
          });
        });
      } catch (error) {
        Log.e(TAG, 'imageArrivalCallback unhandled: ' + JSON.stringify(error));
      }
    };
    this.imageReceiver.on('imageArrival', this.imageArrivalCallback);
  }

  /**
   * 使用ScanKit解码图像缓冲区中的条码
   * @param imgComponent - 图像组件数据
   * @param width - 图像宽度
   * @param height - 图像高度
   * @param scanCallback - 扫码结果回调
   * @param nextImage - 待释放的Image对象
   */
  async decodeImageBuffer(
    imgComponent: image.Component,
    width: number,
    height: number,
    scanCallback: (result: scanBarcode.ScanResult, frameHeight: number) => void,
    nextImage: image.Image
  ): Promise<void> {
    const now = Date.now();
    if (now - this.lastDecodeAtMs < this.decodeThrottleMs) {
      await nextImage.release();
      return;
    }
    this.lastDecodeAtMs = now;

    // 构造扫码解码需要的 ByteImage 对象，包含图像数据的字节缓冲区、图像宽高和格式等信息
    const byteImg: detectBarcode.ByteImage = {
      byteBuffer: imgComponent.byteBuffer,
      width: width,
      height: height,
      format: detectBarcode.ImageFormat.NV21,
    };
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: true,
      enableAlbum: false,
    };

    detectBarcode.decodeImage(byteImg, options).then((detectResult: detectBarcode.DetectResult) => {
      if (detectResult.scanResults.length > 0) {
        const res: scanBarcode.ScanResult = detectResult.scanResults[0];
        if (res && res.originalValue) {
          scanCallback(res, height);
        }
      }
    }).catch((error: BusinessError) => {
      Log.e(TAG, 'decodeImageBuffer failed: ' + error.message);
    }).finally(async () => {
      await nextImage.release();
    });
  }

  /**
   * 设置解码节流间隔，与上层 scanDelayMs 对齐，最低 50ms 防止过于频繁解码
   * @param ms - 节流间隔（毫秒），小于50会被自动调整为50
   */
  setDecodeThrottleMs(ms: number): void {
    this.decodeThrottleMs = Math.max(ms, 50);
  }

  /**
   * 标记解码器已停止
   * @param stop - 是否停止
   */
  setStop(stop: boolean): void {
    this.isStop = stop;
  }

  /**
   * 释放 ImageReceiver 资源
   */
  async releaseImageReceiver(): Promise<void> {
    if (!this.isImageReceiverReleased) {
      this.isImageReceiverReleased = true;
      await this.imageReceiver.release();
    }
  }
}
