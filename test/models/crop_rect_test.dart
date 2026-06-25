import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/models/crop_rect.dart';

void main() {
  group('CropRect', () {
    test('默认构造函数使用正确的默认值', () {
      const rect = CropRect();
      expect(rect.scaleWidth, 1);
      expect(rect.scaleHeight, 1);
      expect(rect.offsetX, 0);
      expect(rect.offsetY, 0);
    });

    test('自定义参数构造正确', () {
      const rect = CropRect(
        scaleWidth: 0.5,
        scaleHeight: 0.8,
        offsetX: 0.1,
        offsetY: -0.2,
      );
      expect(rect.scaleWidth, 0.5);
      expect(rect.scaleHeight, 0.8);
      expect(rect.offsetX, 0.1);
      expect(rect.offsetY, -0.2);
    });

    test('toJson 输出正确的映射', () {
      const rect = CropRect(
        scaleWidth: 0.6,
        scaleHeight: 0.7,
        offsetX: 0.1,
        offsetY: -0.1,
      );
      final json = rect.toJson();

      expect(json, isA<Map<String, double>>());
      expect(json['scaleWidth'], 0.6);
      expect(json['scaleHeight'], 0.7);
      expect(json['offsetX'], 0.1);
      expect(json['offsetY'], -0.1);
    });

    test('toJson 默认值序列化正确', () {
      const rect = CropRect();
      final json = rect.toJson();

      expect(json['scaleWidth'], 1);
      expect(json['scaleHeight'], 1);
      expect(json['offsetX'], 0);
      expect(json['offsetY'], 0);
    });

    test('边界值：scaleWidth 为 1（全宽）', () {
      const rect = CropRect(scaleWidth: 1, scaleHeight: 1);
      final json = rect.toJson();
      expect(json['scaleWidth'], 1);
      expect(json['scaleHeight'], 1);
    });

    test('边界值：极小正数的 scaleWidth', () {
      const rect = CropRect(scaleWidth: 0.001, scaleHeight: 0.001);
      final json = rect.toJson();
      expect(json['scaleWidth'], 0.001);
      expect(json['scaleHeight'], 0.001);
    });

    test('零偏移量居中对齐', () {
      const rect = CropRect(offsetX: 0, offsetY: 0);
      expect(rect.offsetX, 0);
      expect(rect.offsetY, 0);
    });
  });
}
