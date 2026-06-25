import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/models/barcode.dart';
import 'package:mlkit_scanner/models/barcode_format.dart';
import 'package:mlkit_scanner/models/barcode_value_type.dart';

void main() {
  group('BarcodeFormatCode', () {
    test('各格式码与枚举值双向映射正确', () {
      // 验证所有 BarcodeFormat 枚举值的 code 属性
      expect(BarcodeFormat.unknown.code, 0);
      expect(BarcodeFormat.code128.code, 1);
      expect(BarcodeFormat.code39.code, 2);
      expect(BarcodeFormat.code93.code, 4);
      expect(BarcodeFormat.codabar.code, 8);
      expect(BarcodeFormat.dataMatrix.code, 16);
      expect(BarcodeFormat.ean13.code, 32);
      expect(BarcodeFormat.ean8.code, 64);
      expect(BarcodeFormat.itf.code, 128);
      expect(BarcodeFormat.qrCode.code, 256);
      expect(BarcodeFormat.upcA.code, 512);
      expect(BarcodeFormat.upcE.code, 1024);
      expect(BarcodeFormat.pdf417.code, 2048);
      expect(BarcodeFormat.aztec.code, 4096);
    });

    test('fromCode 正确将码值转换为枚举', () {
      expect(BarcodeFormatCode.fromCode(0), BarcodeFormat.unknown);
      expect(BarcodeFormatCode.fromCode(1), BarcodeFormat.code128);
      expect(BarcodeFormatCode.fromCode(256), BarcodeFormat.qrCode);
      expect(BarcodeFormatCode.fromCode(4096), BarcodeFormat.aztec);
      expect(BarcodeFormatCode.fromCode(2048), BarcodeFormat.pdf417);
    });

    test('fromCode 对未知码值返回 unknown', () {
      expect(BarcodeFormatCode.fromCode(9999), BarcodeFormat.unknown);
      expect(BarcodeFormatCode.fromCode(-1), BarcodeFormat.unknown);
    });

    test('code 与 fromCode 互为逆操作', () {
      for (final format in BarcodeFormat.values) {
        expect(BarcodeFormatCode.fromCode(format.code), format,
            reason: '${format.name} 的 code=${format.code} 反向映射应一致');
      }
    });
  });

  group('BarcodeValueTypeCode', () {
    test('各值类型码与枚举值双向映射正确', () {
      expect(BarcodeValueType.unknown.code, 0);
      expect(BarcodeValueType.contactInfo.code, 1);
      expect(BarcodeValueType.email.code, 2);
      expect(BarcodeValueType.isbn.code, 3);
      expect(BarcodeValueType.phone.code, 4);
      expect(BarcodeValueType.product.code, 5);
      expect(BarcodeValueType.sms.code, 6);
      expect(BarcodeValueType.text.code, 7);
      expect(BarcodeValueType.url.code, 8);
      expect(BarcodeValueType.wifi.code, 9);
      expect(BarcodeValueType.geo.code, 10);
      expect(BarcodeValueType.calendarEvent.code, 11);
      expect(BarcodeValueType.driverLicense.code, 12);
    });

    test('fromCode 正确将码值转换为枚举', () {
      expect(BarcodeValueTypeCode.fromCode(0), BarcodeValueType.unknown);
      expect(BarcodeValueTypeCode.fromCode(7), BarcodeValueType.text);
      expect(BarcodeValueTypeCode.fromCode(8), BarcodeValueType.url);
      expect(BarcodeValueTypeCode.fromCode(5), BarcodeValueType.product);
    });

    test('fromCode 对未知码值返回 unknown', () {
      expect(BarcodeValueTypeCode.fromCode(999), BarcodeValueType.unknown);
      expect(BarcodeValueTypeCode.fromCode(-1), BarcodeValueType.unknown);
    });

    test('code 与 fromCode 互为逆操作', () {
      for (final vtype in BarcodeValueType.values) {
        expect(BarcodeValueTypeCode.fromCode(vtype.code), vtype,
            reason: '${vtype.name} 的 code=${vtype.code} 反向映射应一致');
      }
    });
  });

  group('Barcode.fromJson', () {
    test('正确解析包含所有字段的扫码结果', () {
      final json = {
        'raw_value': 'https://example.com',
        'display_value': 'https://example.com',
        'format': 256, // qrCode
        'value_type': 8, // url
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.rawValue, 'https://example.com');
      expect(barcode.displayValue, 'https://example.com');
      expect(barcode.format, BarcodeFormat.qrCode);
      expect(barcode.valueType, BarcodeValueType.url);
    });

    test('正确解析 EAN-13 商品码结果', () {
      final json = {
        'raw_value': '5901234123457',
        'display_value': '5901234123457',
        'format': 32, // ean13
        'value_type': 5, // product
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.rawValue, '5901234123457');
      expect(barcode.format, BarcodeFormat.ean13);
      expect(barcode.valueType, BarcodeValueType.product);
    });

    test('正确解析未知格式码（回退为 unknown）', () {
      final json = {
        'raw_value': 'some_value',
        'display_value': 'some_value',
        'format': 9999, // 不存在的码
        'value_type': 0,
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.format, BarcodeFormat.unknown);
      expect(barcode.valueType, BarcodeValueType.unknown);
    });

    test('正确解析 display_value 为 null 的情况', () {
      final json = {
        'raw_value': 'test',
        'display_value': null,
        'format': 256,
        'value_type': 7,
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.rawValue, 'test');
      expect(barcode.displayValue, isNull);
      expect(barcode.format, BarcodeFormat.qrCode);
    });

    test('正确解析 Code128 格式', () {
      final json = {
        'raw_value': 'ABC-123',
        'display_value': 'ABC-123',
        'format': 1, // code128
        'value_type': 7, // text
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.format, BarcodeFormat.code128);
      expect(barcode.valueType, BarcodeValueType.text);
    });

    test('正确解析 PDF417 格式', () {
      final json = {
        'raw_value': 'pdf_data',
        'display_value': 'pdf_data',
        'format': 2048, // pdf417
        'value_type': 7,
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.format, BarcodeFormat.pdf417);
    });

    test('正确解析 Aztec 格式', () {
      final json = {
        'raw_value': 'aztec_data',
        'display_value': 'aztec_data',
        'format': 4096, // aztec
        'value_type': 7,
      };
      final barcode = Barcode.fromJson(json);

      expect(barcode.format, BarcodeFormat.aztec);
    });
  });
}
