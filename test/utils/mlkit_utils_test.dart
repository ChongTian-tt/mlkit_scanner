import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/models/ios_camera.dart';
import 'package:mlkit_scanner/models/ios_camera_position.dart';
import 'package:mlkit_scanner/models/ios_camera_type.dart';
import 'package:mlkit_scanner/models/ohos_camera.dart';
import 'package:mlkit_scanner/models/ohos_camera_position.dart';
import 'package:mlkit_scanner/models/ohos_camera_type.dart';
import 'package:mlkit_scanner/utils/mlkit_utils.dart';

void main() {
  const channel = MethodChannel('mlkit_channel');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  group('MLKitUtils', () {
    test('构造函数正常创建实例', () {
      final utils = MLKitUtils();
      expect(utils, isNotNull);
    });

    test('getIosAvailableCameras 调用正确的方法并解析返回值', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'getIosAvailableCameras') {
          return [
            {'position': 1, 'type': 0},
            {'position': 0, 'type': 2},
          ];
        }
        return null;
      });

      final utils = MLKitUtils();
      final cameras = await utils.getIosAvailableCameras();

      expect(cameras, isA<List<IosCamera>>());
      expect(cameras.length, 2);
      expect(cameras[0].position, IosCameraPosition.back);
      expect(cameras[0].type, IosCameraType.builtInWideAngleCamera);
      expect(cameras[1].position, IosCameraPosition.unspecified);
    });

    test('getOhosAvailableCameras 调用正确的方法并解析返回值', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'getOhosAvailableCameras') {
          return [
            {'position': 1, 'type': 1},
            {'position': 1, 'type': 2},
          ];
        }
        return null;
      });

      final utils = MLKitUtils();
      final cameras = await utils.getOhosAvailableCameras();

      expect(cameras, isA<List<OhosCamera>>());
      expect(cameras.length, 2);
      expect(cameras[0].position, OhosCameraPosition.back);
      expect(cameras[0].type, OhosCameraType.CAMERA_TYPE_WIDE_ANGLE);
      expect(cameras[1].type, OhosCameraType.CAMERA_TYPE_ULTRA_WIDE);
    });

    test('getIosAvailableCameras 返回空列表时正常处理', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'getIosAvailableCameras') {
          return <Map>[];
        }
        return null;
      });

      final utils = MLKitUtils();
      final cameras = await utils.getIosAvailableCameras();
      expect(cameras, isEmpty);
    });

    test('getOhosAvailableCameras 返回空列表时正常处理', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'getOhosAvailableCameras') {
          return <Map>[];
        }
        return null;
      });

      final utils = MLKitUtils();
      final cameras = await utils.getOhosAvailableCameras();
      expect(cameras, isEmpty);
    });

    test('getIosAvailableCameras 平台异常时抛出 PlatformException', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'getIosAvailableCameras') {
          throw PlatformException(code: '1', message: 'Camera service unavailable');
        }
        return null;
      });

      final utils = MLKitUtils();
      expect(
        () => utils.getIosAvailableCameras(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('getOhosAvailableCameras 平台异常时抛出 PlatformException', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'getOhosAvailableCameras') {
          throw PlatformException(code: '1', message: 'Camera service unavailable');
        }
        return null;
      });

      final utils = MLKitUtils();
      expect(
        () => utils.getOhosAvailableCameras(),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
