/** Enum describes what exactly will be recognized from the camera image. */
export enum RecognitionType {
  BarcodeRecognition = 0,
}

/** Describes image recognition configuration (OHOS equivalent of Android AnalyzeOptions). */
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