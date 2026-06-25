import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/models/barcode.dart';
import 'package:mlkit_scanner/models/barcode_format.dart';
import 'package:mlkit_scanner/models/barcode_value_type.dart';
import 'package:mlkit_scanner/models/crop_rect.dart';
import 'package:mlkit_scanner/models/ios_camera.dart';
import 'package:mlkit_scanner/models/ios_camera_position.dart';
import 'package:mlkit_scanner/models/ios_camera_type.dart';
import 'package:mlkit_scanner/models/ohos_camera_position.dart';
import 'package:mlkit_scanner/models/ohos_camera_type.dart';
import 'package:mlkit_scanner/platform/ml_kit_channel.dart';

void main() {
  group('IosCameraPositionCode fromCode 完整覆盖', () {
    test('fromCode 对所有合法码值正确映射', () {
      expect(IosCameraPositionCode.fromCode(0), IosCameraPosition.unspecified);
      expect(IosCameraPositionCode.fromCode(1), IosCameraPosition.back);
      expect(IosCameraPositionCode.fromCode(2), IosCameraPosition.front);
    });
  });

  group('IosCameraTypeCode fromCode 完整覆盖', () {
    test('fromCode 对所有合法码值正确映射', () {
      expect(IosCameraTypeCode.fromCode(0), IosCameraType.builtInWideAngleCamera);
      expect(IosCameraTypeCode.fromCode(1), IosCameraType.builtInTelephotoCamera);
      expect(IosCameraTypeCode.fromCode(2), IosCameraType.builtInDualCamera);
      expect(IosCameraTypeCode.fromCode(3), IosCameraType.builtInUltraWideCamera);
      expect(IosCameraTypeCode.fromCode(4), IosCameraType.builtInDualWideCamera);
      expect(IosCameraTypeCode.fromCode(5), IosCameraType.builtInTripleCamera);
    });
  });

  group('IosCamera.fromJson 完整覆盖', () {
    test('fromJson 正确解析后置广角相机', () {
      final json = {'position': 1, 'type': 0};
      final camera = IosCamera.fromJson(json);
      expect(camera.position, IosCameraPosition.back);
      expect(camera.type, IosCameraType.builtInWideAngleCamera);
    });

    test('fromJson 正确解析前置长焦相机', () {
      final json = {'position': 2, 'type': 1};
      final camera = IosCamera.fromJson(json);
      expect(camera.position, IosCameraPosition.front);
      expect(camera.type, IosCameraType.builtInTelephotoCamera);
    });
  });

  group('Barcode 直接构造函数测试', () {
    test('使用构造函数创建 Barcode 实例', () {
      const barcode = Barcode(
        rawValue: 'test_value',
        valueType: BarcodeValueType.text,
        format: BarcodeFormat.qrCode,
        displayValue: 'Test Value',
      );
      expect(barcode.rawValue, 'test_value');
      expect(barcode.displayValue, 'Test Value');
      expect(barcode.valueType, BarcodeValueType.text);
      expect(barcode.format, BarcodeFormat.qrCode);
    });

    test('构造函数 displayValue 为 null', () {
      const barcode = Barcode(
        rawValue: 'raw',
        valueType: BarcodeValueType.unknown,
        format: BarcodeFormat.unknown,
      );
      expect(barcode.displayValue, isNull);
    });
  });

  group('MlKitChannel 参数异常场景', () {
    const channel = MethodChannel('mlkit_channel');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    tearDown(() {
      channel.setMockMethodCallHandler(null);
    });

    test('setScanDelay 传入负数延迟值', () async {
      int? capturedDelay;
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'setScanDelay') {
          capturedDelay = call.arguments as int?;
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      // Dart端不做验证，OHOS端会拒绝非法值
      await mlKitChannel.setScanDelay(-1);
      expect(capturedDelay, -1);
    });

    test('setZoom 传入超范围值', () async {
      double? capturedValue;
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'setZoom') {
          capturedValue = call.arguments as double?;
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      // Dart端assert只在debug生效，这里测试通道传递
      await mlKitChannel.setZoom(1.5);
      expect(capturedValue, 1.5);
    });
  });

  group('MlKitChannel 权限异常场景', () {
    const channel = MethodChannel('mlkit_channel');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    tearDown(() {
      channel.setMockMethodCallHandler(null);
    });

    test('initCameraPreview 权限被拒绝时抛出 PlatformException', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'initCameraPreview') {
          throw PlatformException(code: '2', message: 'Camera permission denied');
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.initCameraPreview(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('cancelScan 通道异常', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'cancelScan') {
          throw PlatformException(code: '3', message: 'Camera not initialized');
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.cancelScan(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('setCropArea 相机未初始化时抛出异常', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'setCropAreaMethod') {
          throw PlatformException(code: '3', message: 'Camera not initialized');
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.setCropArea(const CropRect(scaleWidth: 0.5)),
        throwsA(isA<PlatformException>()),
      );
    });

    test('getOhosAvailableCameras 通道异常', () async {
      channel.setMockMethodCallHandler((call) async {
        throw PlatformException(code: '1', message: 'Camera initialization failed');
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.getOhosAvailableCameras(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('setOhosCamera 通道异常', () async {
      channel.setMockMethodCallHandler((call) async {
        throw PlatformException(code: '3', message: 'Camera not initialized');
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.setOhosCamera(
          position: OhosCameraPosition.back,
          type: OhosCameraType.CAMERA_TYPE_WIDE_ANGLE,
        ),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('Barcode.fromJson 异常数据场景', () {
    test('缺少 format 字段时抛出异常（需确保数据完整）', () {
      final json = {
        'raw_value': 'test',
        'display_value': 'test',
        'value_type': 0,
      };
      // Barcode.fromJson 不会自动回退，缺少 format 字段时
      // json['format'] 为 null，BarcodeFormatCode.fromCode(null) 会报错
      // 这是预期行为：调用方应确保数据完整
      expect(() => Barcode.fromJson(json), throwsA(anything));
    });

    test('缺少 value_type 字段时抛出异常（需确保数据完整）', () {
      final json = {
        'raw_value': 'test',
        'display_value': 'test',
        'format': 256,
      };
      expect(() => Barcode.fromJson(json), throwsA(anything));
    });

    test('format 为 0 时回退为 unknown', () {
      final json = {
        'raw_value': 'test',
        'display_value': 'test',
        'format': 0,
        'value_type': 0,
      };
      final barcode = Barcode.fromJson(json);
      expect(barcode.format, BarcodeFormat.unknown);
    });

    test('raw_value 为空字符串', () {
      final json = {
        'raw_value': '',
        'display_value': '',
        'format': 1,
        'value_type': 7,
      };
      final barcode = Barcode.fromJson(json);
      expect(barcode.rawValue, '');
      expect(barcode.format, BarcodeFormat.code128);
    });
  });
}
