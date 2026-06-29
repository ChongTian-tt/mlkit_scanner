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

import { JSON } from '@kit.ArkTS';
import { MethodChannel, Log } from '@ohos/flutter_ohos';
import { scanBarcode } from '@kit.ScanKit';
import {
  CropRect,
  OhosScannerParameters,
  PluginConstants,
  ScanRectLike,
  Size,
} from './PluginConstants';

const TAG: string = '[ScanResultProcessor]:';

/**
 * 扫码结果处理器回调接口
 * 桥接 MLKitScannerView 中的状态读写和动作触发
 */
export interface ScanResultCallbacks {
  getIsScan: () => boolean;
  getIsDelayed: () => boolean;
  getOriginalValue: () => string;
  setOriginalValue: (v: string) => void;
  getYuvFrameHeight: () => number;
  setYuvFrameHeight: (h: number) => void;
  getPreviewSize: () => Size;
  getContainerSize: () => Size;
  getInitialScannerParameters: () => OhosScannerParameters | null;
  getChannel: () => MethodChannel | null;
  startScanDelayWindow: () => void;
}

/**
 * 扫码结果处理器
 * 封装扫码结果的解析、坐标转换、扫码框命中检测和结果回传逻辑
 */
export class ScanResultProcessor {
  private readonly callbacks: ScanResultCallbacks;

  /**
   * 创建 ScanResultProcessor 实例
   * @param callbacks - 回调集合，桥接 MLKitScannerView 的状态读写
   */
  constructor(callbacks: ScanResultCallbacks) {
    this.callbacks = callbacks;
  }

  /**
   * 将 ScanResult 中需要的属性逐个提取到 Record<string, Object>。
   * ScanResult 实际运行时属性：
   * scanType, originalValue, scanCodeRect, cornerPoints, isGS1, frameHeight
   */
  scanResultToRecord(result: scanBarcode.ScanResult): Record<string, Object> {
    const record: Record<string, Object> = {};
    // 逐个提取类型声明中已暴露的属性
    record['scanType'] = result.scanType;
    record['originalValue'] = result.originalValue;
    if (result.scanCodeRect !== undefined) {
      record['scanCodeRect'] = result.scanCodeRect;
    }
    if (result.cornerPoints !== undefined) {
      record['cornerPoints'] = result.cornerPoints;
    }
    return record;
  }

  /**
   * 从 ScanResult 中提取未在类型声明中暴露的 frameHeight 属性。
   * 通过 JSON 序列化/反序列化安全获取，避免类型断言。
   */
  extractFrameHeight(result: scanBarcode.ScanResult): number {
    try {
      const jsonObj: Record<string, Object> = JSON.parse(JSON.stringify(result)) as Record<string, Object>;
      const frameHeight = Number(jsonObj['frameHeight']);
      if (Number.isFinite(frameHeight) && frameHeight > 0) {
        return Math.round(frameHeight);
      }
    } catch (error) {
      Log.w(TAG, 'extractFrameHeight skipped: ' + JSON.stringify(error));
    }
    return 0;
  }

  /**
   * 从 ScanResult 中提取扫码矩形坐标
   * @param result - 扫码结果
   * @returns 扫码矩形坐标，提取失败时返回 null
   */
  extractScanRect(result: scanBarcode.ScanResult): ScanRectLike | null {
    try {
      const rec = this.scanResultToRecord(result);
      const scanCodeRect = rec['scanCodeRect'];
      if (!scanCodeRect || typeof scanCodeRect !== 'object') {
        return null;
      }
      const rect = scanCodeRect as Record<string, Object>;
      const left = Number(rect['left']);
      const top = Number(rect['top']);
      const right = Number(rect['right']);
      const bottom = Number(rect['bottom']);
      if ([left, top, right, bottom].every((n) => Number.isFinite(n))) {
        return {
          left,
          top,
          right,
          bottom
        } as ScanRectLike;
      }
      return null;
    } catch (error) {
      Log.w(TAG, 'extractScanRect skipped: ' + JSON.stringify(error));
      return null;
    }
  }

  /**
   * 中心区域扫码框，作为扫码结果坐标缺失时的兜底方案
   * @returns 预览区域中心 30% 范围的矩形坐标
   */
  fallbackCenterRect(): ScanRectLike {
    const previewSize = this.callbacks.getPreviewSize();
    const containerSize = this.callbacks.getContainerSize();
    const w = previewSize.width > 0 ? previewSize.width : containerSize.width;
    const h = previewSize.height > 0 ? previewSize.height : containerSize.height;
    const left = Math.round(w * 0.35);
    const top = Math.round(h * 0.35);
    const right = Math.round(w * 0.65);
    const bottom = Math.round(h * 0.65);
    return {
      left,
      top,
      right,
      bottom
    } as ScanRectLike;
  }

  /**
   * 处理帧扫码结果：提取坐标、转换为屏幕坐标、判断是否在扫码框内、触发结果回调
   * @param result - ScanKit 返回的扫码结果
   */
  onFrameResult(result: scanBarcode.ScanResult): void {
    try {
      if (!this.callbacks.getIsScan() || this.callbacks.getIsDelayed()) {
        return;
      }
      if (!result.originalValue) {
        return;
      }

      this.callbacks.setOriginalValue(result.originalValue);
      const frameHeight = this.extractFrameHeight(result);

      if (frameHeight > 0) {
        this.callbacks.setYuvFrameHeight(frameHeight);
      }
      const rectLikeRaw = this.extractScanRect(result);
      const candidates: scanBarcode.ScanCodeRect[] = [];
      if (rectLikeRaw) {
        // 原始扫码结果坐标
        const scanRect: scanBarcode.ScanCodeRect = {
          left: Math.round(rectLikeRaw.left),
          top: Math.round(rectLikeRaw.top),
          right: Math.round(rectLikeRaw.right),
          bottom: Math.round(rectLikeRaw.bottom),
        };
        candidates.push(scanRect);
        // 转换为屏幕坐标
        const convertedScanRect = this.convertYuvToScreenCoords(scanRect);
        candidates.push(convertedScanRect);
      } else {
        // 没有扫码结果坐标时,使用兜底中心区域
        const fallbackRect = this.fallbackCenterRect();
        candidates.push({
          left: Math.round(fallbackRect.left),
          top: Math.round(fallbackRect.top),
          right: Math.round(fallbackRect.right),
          bottom: Math.round(fallbackRect.bottom),
        });
      }
      // 只要有一个候选区域在扫码框内就判定为命中
      const matched = candidates.some(rect => this.checkResultInScanBox(rect));
      if (matched) {
        this.emitScanResult(result);
        this.callbacks.setOriginalValue('');
        this.callbacks.startScanDelayWindow();
      }
    } catch (error) {
      Log.w(TAG, 'onFrameResult skipped: ' + JSON.stringify(error));
    }
  }

  /**
   * 获取当前活跃的裁剪矩形
   * @returns 裁剪矩形，未设置时返回 null
   */
  getActiveCropRect(): CropRect | null {
    return this.callbacks.getInitialScannerParameters()?.initialCropRect ?? null;
  }

  /**
   * 从 ScanResult 中提取扫码类型编码
   * @param result - 扫码结果
   * @returns 扫码类型编码，提取失败时返回 0
   */
  extractScanType(result: scanBarcode.ScanResult): number {
    const resultMap = this.scanResultToRecord(result);
    const scanType = Number(resultMap['scanType']);
    if (Number.isFinite(scanType)) {
      return scanType;
    }
    return 0;
  }

  /**
   * 基于条码格式和原始内容推断 value_type
   * ScanKit 不提供值类型分类，对 QR Code 尝试前缀匹配提升准确性
   * value_type 编码参考 MLKit BarcodeValueType: 0=unknown, 2=email, 4=phone, 7=text, 8=url, 9=wifi
   */
  inferValueType(rawValue: string, format: number): number {
    // 仅对 QR Code 进行内容推断，其他格式走静态映射表
    if (format === 256) { // QR_CODE
      const lower = rawValue.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        return 8; // url
      }
      if (lower.startsWith('wifi:')) {
        return 9; // wifi
      }
      if (lower.startsWith('tel:')) {
        return 4; // phone
      }
      if (lower.startsWith('mailto:')) {
        return 2; // email
      }
    }
    return PluginConstants.BARCODE_FORMAT_TO_VALUE_TYPE[format] ?? 0;
  }

  /**
   * 将扫码结果通过 MethodChannel 回传给 Flutter
   * @param result - ScanKit 返回的扫码结果
   */
  emitScanResult(result: scanBarcode.ScanResult): void {
    const scanType = this.extractScanType(result);
    // 将 ScanKit scanType 转换为 MLKit BarcodeFormat 码
    const mappedFormat = PluginConstants.SCAN_TYPE_TO_BARCODE_FORMAT[scanType] ?? 0;
    // 基于条码格式和内容推断 value_type(ScanKit 不提供值类型分类)
    const valueType = this.inferValueType(result.originalValue, mappedFormat);
    // 将扫码解析后的结果回传flutter
    // 注意：ScanKit 不提供独立的 displayValue，display_value 与 raw_value 相同，
    // 这是 ScanKit API 限制，与 Android/iOS MLKit 的 displayValue 行为不同
    this.callbacks.getChannel()?.invokeMethod(PluginConstants.SCAN_RESULT_METHOD, {
      raw_value: result.originalValue,
      display_value: result.originalValue,
      format: mappedFormat,
      value_type: valueType,
    });
  }

  /**
   * 检查二维码是否在扫码框内(crop 相对于可见区域)
   */
  checkResultInScanBox(scanCodeRect: scanBarcode.ScanCodeRect): boolean {
    const cropRect = this.getActiveCropRect();
    // 未设置裁剪框时默认全屏可识别
    if (!cropRect) {
      return true;
    }

    const containerSize = this.callbacks.getContainerSize();
    const previewSize = this.callbacks.getPreviewSize();
    const baseWidth = containerSize.width;
    const baseHeight = containerSize.height;
    if (baseWidth <= 0 || baseHeight <= 0) {
      return false;
    }

    const cropWidth = baseWidth * cropRect.scaleWidth;
    const cropHeight = baseHeight * cropRect.scaleHeight;
    const cropLeft = (baseWidth / 2) * (1 + cropRect.offsetX) - cropWidth / 2;
    const cropTop = (baseHeight / 2) * (1 + cropRect.offsetY) - cropHeight / 2;
    const cropRight = cropLeft + cropWidth;
    const cropBottom = cropTop + cropHeight;

    let codeLeft = Math.min(scanCodeRect.left, scanCodeRect.right);
    let codeRight = Math.max(scanCodeRect.left, scanCodeRect.right);
    let codeTop = Math.min(scanCodeRect.top, scanCodeRect.bottom);
    let codeBottom = Math.max(scanCodeRect.top, scanCodeRect.bottom);
    if (previewSize.width <= containerSize.width) {
      const padX = (containerSize.width - previewSize.width) / 2;
      codeLeft += padX;
      codeRight += padX;
    } else {
      const cropX = (previewSize.width - containerSize.width) / 2;
      codeLeft -= cropX;
      codeRight -= cropX;
    }
    if (previewSize.height <= containerSize.height) {
      const padY = (containerSize.height - previewSize.height) / 2;
      codeTop += padY;
      codeBottom += padY;
    } else {
      const cropY = (previewSize.height - containerSize.height) / 2;
      codeTop -= cropY;
      codeBottom -= cropY;
    }
    const inScanBox =
      codeLeft >= cropLeft &&
        codeRight <= cropRight &&
        codeTop >= cropTop &&
        codeBottom <= cropBottom;

    return inScanBox;
  }

  /**
   * 将YUV帧坐标转换为屏幕坐标
   */
  convertYuvToScreenCoords(yuvRect: scanBarcode.ScanCodeRect): scanBarcode.ScanCodeRect {
    const yuvFrameHeight = this.callbacks.getYuvFrameHeight();
    if (!yuvFrameHeight) {
      return yuvRect;
    }
    const previewSize = this.callbacks.getPreviewSize();
    const ratio = previewSize.width / yuvFrameHeight;
    const convertedLeft = (yuvFrameHeight - yuvRect.bottom) * ratio;
    const convertedTop = yuvRect.left * ratio;
    const convertedRight = (yuvFrameHeight - yuvRect.top) * ratio;
    const convertedBottom = yuvRect.right * ratio;
    return {
      left: Math.round(convertedLeft),
      top: Math.round(convertedTop),
      right: Math.round(convertedRight),
      bottom: Math.round(convertedBottom)
    };
  }
}
