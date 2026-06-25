import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/models/ohos_camera.dart';
import 'package:mlkit_scanner/models/ohos_camera_position.dart';
import 'package:mlkit_scanner/models/ohos_camera_type.dart';

void main() {
  group('OhosCameraPositionCode', () {
    test('各位置码与枚举值双向映射正确', () {
      expect(OhosCameraPosition.unspecified.code, 0);
      expect(OhosCameraPosition.back.code, 1);
      expect(OhosCameraPosition.front.code, 2);
    });

    test('fromCode 正确将码值转换为枚举', () {
      expect(OhosCameraPositionCode.fromCode(0), OhosCameraPosition.unspecified);
      expect(OhosCameraPositionCode.fromCode(1), OhosCameraPosition.back);
      expect(OhosCameraPositionCode.fromCode(2), OhosCameraPosition.front);
    });

    test('code 与 fromCode 互为逆操作', () {
      for (final pos in OhosCameraPosition.values) {
        expect(OhosCameraPositionCode.fromCode(pos.code), pos,
            reason: '${pos.name} 的 code=${pos.code} 反向映射应一致');
      }
    });
  });

  group('OhosCameraTypeCode', () {
    test('各类型码与枚举值双向映射正确', () {
      expect(OhosCameraType.CAMERA_TYPE_DEFAULT.code, 0);
      expect(OhosCameraType.CAMERA_TYPE_WIDE_ANGLE.code, 1);
      expect(OhosCameraType.CAMERA_TYPE_ULTRA_WIDE.code, 2);
      expect(OhosCameraType.CAMERA_TYPE_TELEPHOTO.code, 3);
      expect(OhosCameraType.CAMERA_TYPE_TRUE_DEPTH.code, 4);
    });

    test('fromCode 正确将码值转换为枚举', () {
      expect(OhosCameraTypeCode.fromCode(0), OhosCameraType.CAMERA_TYPE_DEFAULT);
      expect(OhosCameraTypeCode.fromCode(1), OhosCameraType.CAMERA_TYPE_WIDE_ANGLE);
      expect(OhosCameraTypeCode.fromCode(2), OhosCameraType.CAMERA_TYPE_ULTRA_WIDE);
      expect(OhosCameraTypeCode.fromCode(3), OhosCameraType.CAMERA_TYPE_TELEPHOTO);
      expect(OhosCameraTypeCode.fromCode(4), OhosCameraType.CAMERA_TYPE_TRUE_DEPTH);
    });

    test('code 与 fromCode 互为逆操作', () {
      for (final type in OhosCameraType.values) {
        expect(OhosCameraTypeCode.fromCode(type.code), type,
            reason: '${type.name} 的 code=${type.code} 反向映射应一致');
      }
    });
  });

  group('OhosCamera', () {
    test('fromJson 正确解析后置广角相机', () {
      final json = {
        'position': 1, // back
        'type': 1, // CAMERA_TYPE_WIDE_ANGLE
      };
      final camera = OhosCamera.fromJson(json);

      expect(camera.position, OhosCameraPosition.back);
      expect(camera.type, OhosCameraType.CAMERA_TYPE_WIDE_ANGLE);
    });

    test('fromJson 正确解析前置默认相机', () {
      final json = {
        'position': 2, // front
        'type': 0, // CAMERA_TYPE_DEFAULT
      };
      final camera = OhosCamera.fromJson(json);

      expect(camera.position, OhosCameraPosition.front);
      expect(camera.type, OhosCameraType.CAMERA_TYPE_DEFAULT);
    });

    test('fromJson 正确解析后置长焦相机', () {
      final json = {
        'position': 1, // back
        'type': 3, // CAMERA_TYPE_TELEPHOTO
      };
      final camera = OhosCamera.fromJson(json);

      expect(camera.position, OhosCameraPosition.back);
      expect(camera.type, OhosCameraType.CAMERA_TYPE_TELEPHOTO);
    });

    test('fromJson 正确解析超广角相机', () {
      final json = {
        'position': 1, // back
        'type': 2, // CAMERA_TYPE_ULTRA_WIDE
      };
      final camera = OhosCamera.fromJson(json);

      expect(camera.type, OhosCameraType.CAMERA_TYPE_ULTRA_WIDE);
    });

    test('构造函数直接创建相机对象', () {
      const camera = OhosCamera(
        position: OhosCameraPosition.back,
        type: OhosCameraType.CAMERA_TYPE_WIDE_ANGLE,
      );
      expect(camera.position, OhosCameraPosition.back);
      expect(camera.type, OhosCameraType.CAMERA_TYPE_WIDE_ANGLE);
    });
  });
}
