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