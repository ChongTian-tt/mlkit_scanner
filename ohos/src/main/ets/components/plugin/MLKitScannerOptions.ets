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
// 枚举描述了将从摄像头图像中准确识别出的内容
export enum RecognitionType {
  BarcodeRecognition = 0,
}

// 描述图像识别配置
export class MLKitScannerOptions {
  recognizeType: RecognitionType;
  periodMs: number;

  constructor(recognizeType: RecognitionType, periodMs: number) {
    this.recognizeType = recognizeType;
    this.periodMs = periodMs;
  }

  static fromMap(map: Record<string, Object>): MLKitScannerOptions {
    const typeCode = MLKitScannerOptions.requireInt(map, 'type');
    const delayCode = MLKitScannerOptions.requireInt(map, 'delay');
    if (delayCode < 0) {
      throw new Error('Invalid delay: must be >= 0');
    }
    return new MLKitScannerOptions(
      MLKitScannerOptions.recognitionTypeFromValue(typeCode),
      delayCode,
    );
  }

  private static recognitionTypeFromValue(code: number): RecognitionType {
    if (code === RecognitionType.BarcodeRecognition) {
      return RecognitionType.BarcodeRecognition;
    }
    throw new Error('Unsupported recognition type: ' + code);
  }

  private static requireInt(map: Record<string, Object>, fieldName: string): number {
    const raw = map[fieldName];
    if (typeof raw !== 'number' || !Number.isFinite(raw)) {
      throw new Error('Invalid argument: ' + fieldName + ' must be Number');
    }
    return Math.trunc(raw);
  }
}