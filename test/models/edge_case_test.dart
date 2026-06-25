import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/models/barcode.dart';
import 'package:mlkit_scanner/models/barcode_format.dart';
import 'package:mlkit_scanner/models/barcode_value_type.dart';
import 'package:mlkit_scanner/models/crop_rect.dart';
import 'package:mlkit_scanner/models/ohos_camera.dart';
import 'package:mlkit_scanner/models/ohos_camera_position.dart';
import 'package:mlkit_scanner/models/ohos_camera_type.dart';

void main() {
  group('Barcode 边界场景', () {
    test('空字符串的扫码结果', () {
      final json = {
        'raw_value': '',
        'display_value': '',
        'format': 256,
        'value_type': 7,
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.rawValue, '');
      expect(barcode.displayValue, '');
      expect(barcode.format, BarcodeFormat.qrCode);
    });

    test('超长字符串的扫码结果', () {
      final longValue = 'A' * 10000;
      final json = {
        'raw_value': longValue,
        'display_value': longValue,
        'format': 256,
        'value_type': 7,
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.rawValue.length, 10000);
    });

    test('包含特殊字符的扫码结果', () {
      final specialValue = '你好世界🎉\n\t\r\\\"';
      final json = {
        'raw_value': specialValue,
        'display_value': specialValue,
        'format': 256,
        'value_type': 7,
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.rawValue, specialValue);
    });

    test('format=0 和 value_type=0 均回退到 unknown', () {
      final json = {
        'raw_value': 'test',
        'display_value': 'test',
        'format': 0,
        'value_type': 0,
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.format, BarcodeFormat.unknown);
      expect(barcode.valueType, BarcodeValueType.unknown);
    });

    test('所有 BarcodeFormat 枚举值都能正确从 json 解析', () {
      final formatCodes = {
        0: BarcodeFormat.unknown,
        1: BarcodeFormat.code128,
        2: BarcodeFormat.code39,
        4: BarcodeFormat.code93,
        8: BarcodeFormat.codabar,
        16: BarcodeFormat.dataMatrix,
        32: BarcodeFormat.ean13,
        64: BarcodeFormat.ean8,
        128: BarcodeFormat.itf,
        256: BarcodeFormat.qrCode,
        512: BarcodeFormat.upcA,
        1024: BarcodeFormat.upcE,
        2048: BarcodeFormat.pdf417,
        4096: BarcodeFormat.aztec,
      };

      for (final entry in formatCodes.entries) {
        final json = {
          'raw_value': 'test',
          'display_value': 'test',
          'format': entry.key,
          'value_type': 0,
        };
        final barcode = Barcode.fromJson(json);
        expect(barcode.format, entry.value,
            reason: 'format=${entry.key} 应解析为 ${entry.value.name}');
      }
    });

    test('所有 BarcodeValueType 枚举值都能正确从 json 解析', () {
      final valueTypeCodes = {
        0: BarcodeValueType.unknown,
        1: BarcodeValueType.contactInfo,
        2: BarcodeValueType.email,
        3: BarcodeValueType.isbn,
        4: BarcodeValueType.phone,
        5: BarcodeValueType.product,
        6: BarcodeValueType.sms,
        7: BarcodeValueType.text,
        8: BarcodeValueType.url,
        9: BarcodeValueType.wifi,
        10: BarcodeValueType.geo,
        11: BarcodeValueType.calendarEvent,
        12: BarcodeValueType.driverLicense,
      };

      for (final entry in valueTypeCodes.entries) {
        final json = {
          'raw_value': 'test',
          'display_value': 'test',
          'format': 256,
          'value_type': entry.key,
        };
        final barcode = Barcode.fromJson(json);
        expect(barcode.valueType, entry.value,
            reason: 'value_type=${entry.key} 应解析为 ${entry.value.name}');
      }
    });
  });

  group('CropRect 边界场景', () {
    test('scaleWidth 为 1 表示全宽覆盖', () {
      const rect = CropRect(scaleWidth: 1, scaleHeight: 1);
      expect(rect.scaleWidth, 1);
      expect(rect.scaleHeight, 1);
    });

    test('极小正数的裁剪区域', () {
      const rect = CropRect(scaleWidth: 0.001, scaleHeight: 0.001);
      final json = rect.toJson();
      expect(json['scaleWidth'], 0.001);
    });

    test('偏移量在合法范围外的负值（应被 OHOS 端拒绝）', () {
      // Dart 端不做验证，OHOS 端会拒绝非法值
      const rect = CropRect(offsetX: -0.5, offsetY: -0.5);
      expect(rect.offsetX, -0.5);
      expect(rect.offsetY, -0.5);
    });

    test('toJson 输出所有四个字段', () {
      const rect = CropRect();
      final json = rect.toJson();
      expect(json.length, 4);
      expect(json.containsKey('scaleWidth'), true);
      expect(json.containsKey('scaleHeight'), true);
      expect(json.containsKey('offsetX'), true);
      expect(json.containsKey('offsetY'), true);
    });
  });

  group('BarcodeFormatCode 边界场景', () {
    test('每个 BarcodeFormat 的 code 值是 2 的幂或 0', () {
      for (final format in BarcodeFormat.values) {
        if (format == BarcodeFormat.unknown) {
          expect(format.code, 0);
        } else {
          // 验证是 2 的幂
          expect((format.code & (format.code - 1)), 0,
              reason: '${format.name} 的 code=${format.code} 应是 2 的幂');
        }
      }
    });

    test('fromCode 对负数返回 unknown', () {
      expect(BarcodeFormatCode.fromCode(-1), BarcodeFormat.unknown);
      expect(BarcodeFormatCode.fromCode(-100), BarcodeFormat.unknown);
    });

    test('fromCode 对超出范围的值返回 unknown', () {
      expect(BarcodeFormatCode.fromCode(8192), BarcodeFormat.unknown);
    });
  });

  group('BarcodeValueTypeCode 边界场景', () {
    test('fromCode 对超出范围的值返回 unknown', () {
      expect(BarcodeValueTypeCode.fromCode(100), BarcodeValueType.unknown);
      expect(BarcodeValueTypeCode.fromCode(-1), BarcodeValueType.unknown);
    });

    test('所有 value type 码从 0 开始连续编码', () {
      for (int i = 0; i <= 12; i++) {
        final type = BarcodeValueTypeCode.fromCode(i);
        expect(type.code, i,
            reason: 'value_type $i 应正确映射');
      }
    });
  });

  group('OhosCamera 边界场景', () {
    test('fromJson 所有合法码值都能正确解析', () {
      // 测试所有 position 码
      for (int pos = 0; pos <= 2; pos++) {
        final json = {'position': pos, 'type': 0};
        final camera = OhosCamera.fromJson(json);
        expect(camera.position.code, pos,
            reason: 'position=$pos 应正确映射');
      }

      // 测试所有 type 码
      for (int type = 0; type <= 4; type++) {
        final json = {'position': 0, 'type': type};
        final camera = OhosCamera.fromJson(json);
        expect(camera.type.code, type,
            reason: 'type=$type 应正确映射');
      }
    });

    test('构造函数与 fromJson 结果一致', () {
      const directCamera = OhosCamera(
        position: OhosCameraPosition.back,
        type: OhosCameraType.CAMERA_TYPE_WIDE_ANGLE,
      );
      final jsonCamera = OhosCamera.fromJson({'position': 1, 'type': 1});

      expect(directCamera.position, jsonCamera.position);
      expect(directCamera.type, jsonCamera.type);
    });
  });

  group('ScanKit→MLKit 格式码映射验证', () {
    // 验证 OHOS 端的 SCAN_TYPE_TO_BARCODE_FORMAT 映射与 Dart 端一致
    test('ScanKit scanType 映射到 MLKit BarcodeFormat 后能被正确解析', () {
      // ScanKit scanType → MLKit BarcodeFormat 映射表
      // 与 MLKitScannerView.ets 中 SCAN_TYPE_TO_BARCODE_FORMAT 保持一致
      const scanTypeToBarcodeFormat = {
        0: 0,     // ALL → unknown
        1: 256,   // QR_CODE → qrCode
        2: 4096,  // AZTEC → aztec
        3: 16,    // DATA_MATRIX → dataMatrix
        4: 2048,  // PDF417 → pdf417
        5: 1,     // CODE_128 → code128
        6: 2,     // CODE_39 → code39
        7: 4,     // CODE_93 → code93
        8: 8,     // CODABAR → codabar
        9: 32,    // EAN_13 → ean13
        10: 64,   // EAN_8 → ean8
        11: 128,  // ITF → itf
        12: 512,  // UPC_A → upcA
        13: 1024, // UPC_E → upcE
      };

      // 验证映射后的 MLKit 码能被 BarcodeFormatCode.fromCode 正确解析
      for (final entry in scanTypeToBarcodeFormat.entries) {
        final format = BarcodeFormatCode.fromCode(entry.value);
        expect(format != BarcodeFormat.unknown || entry.key == 0,
            true,
            reason: 'ScanKit scanType=${entry.key} → MLKit code=${entry.value} 应能被正确解析');
      }

      // 验证关键映射正确性
      expect(BarcodeFormatCode.fromCode(scanTypeToBarcodeFormat[1]!), BarcodeFormat.qrCode,
          reason: 'ScanKit QR_CODE(1) 应映射为 MLKit qrCode(256)');
      expect(BarcodeFormatCode.fromCode(scanTypeToBarcodeFormat[2]!), BarcodeFormat.aztec,
          reason: 'ScanKit AZTEC(2) 应映射为 MLKit aztec(4096)');
      expect(BarcodeFormatCode.fromCode(scanTypeToBarcodeFormat[5]!), BarcodeFormat.code128,
          reason: 'ScanKit CODE_128(5) 应映射为 MLKit code128(1)');
      expect(BarcodeFormatCode.fromCode(scanTypeToBarcodeFormat[9]!), BarcodeFormat.ean13,
          reason: 'ScanKit EAN_13(9) 应映射为 MLKit ean13(32)');
    });

    test('value_type 基于格式推断的映射正确', () {
      // 与 MLKitScannerView.ets 中 BARCODE_FORMAT_TO_VALUE_TYPE 保持一致
      const formatToValueType = {
        0: 0,     // unknown → unknown
        1: 7,     // code128 → text
        2: 7,     // code39 → text
        4: 7,     // code93 → text
        8: 7,     // codabar → text
        16: 7,    // dataMatrix → text
        32: 5,    // ean13 → product
        64: 5,    // ean8 → product
        128: 5,   // itf → product
        256: 7,   // qrCode → text
        512: 5,   // upcA → product
        1024: 5,  // upcE → product
        2048: 7,  // pdf417 → text
        4096: 7,  // aztec → text
      };

      for (final entry in formatToValueType.entries) {
        final valueType = BarcodeValueTypeCode.fromCode(entry.value);
        expect(valueType.code, entry.value,
            reason: 'BarcodeFormat code=${entry.key} → value_type=${entry.value} 应正确映射');
      }

      // 验证商品码类型推断
      expect(BarcodeValueTypeCode.fromCode(formatToValueType[32]!), BarcodeValueType.product,
          reason: 'EAN-13 应推断为 product 类型');
      expect(BarcodeValueTypeCode.fromCode(formatToValueType[64]!), BarcodeValueType.product,
          reason: 'EAN-8 应推断为 product 类型');

      // 验证文本码类型推断
      expect(BarcodeValueTypeCode.fromCode(formatToValueType[256]!), BarcodeValueType.text,
          reason: 'QR Code 应推断为 text 类型');
      expect(BarcodeValueTypeCode.fromCode(formatToValueType[1]!), BarcodeValueType.text,
          reason: 'Code128 应推断为 text 类型');
    });
  });
}
