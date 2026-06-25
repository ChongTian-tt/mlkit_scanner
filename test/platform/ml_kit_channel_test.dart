import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/models/crop_rect.dart';
import 'package:mlkit_scanner/models/ohos_camera_position.dart';
import 'package:mlkit_scanner/models/ohos_camera_type.dart';
import 'package:mlkit_scanner/models/recognition_type.dart';
import 'package:mlkit_scanner/platform/ml_kit_channel.dart';

void main() {
  group('MlKitChannel 方法通道名常量', () {
    // 验证方法通道名常量与 OHOS 端 PluginConstants 一致
    test('OHOS 相机获取方法通道名应为 getOhosAvailableCameras', () async {
      const channel = MethodChannel('mlkit_channel');
      String? capturedMethod;

      TestWidgetsFlutterBinding.ensureInitialized();
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        if (call.method == 'getOhosAvailableCameras') {
          return [
            {'position': 1, 'type': 1},
          ];
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.getOhosAvailableCameras();

      expect(capturedMethod, 'getOhosAvailableCameras',
          reason: 'OHOS 相机获取方法通道名应使用 getOhosAvailableCameras 而非 getIosAvailableCameras');

      channel.setMockMethodCallHandler(null);
    });

    test('OHOS 相机设置方法通道名应为 setOhosCamera', () async {
      const channel = MethodChannel('mlkit_channel');
      String? capturedMethod;

      TestWidgetsFlutterBinding.ensureInitialized();
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.setOhosCamera(
        position: OhosCameraPosition.back,
        type: OhosCameraType.CAMERA_TYPE_WIDE_ANGLE,
      );

      expect(capturedMethod, 'setOhosCamera',
          reason: 'OHOS 相机设置方法通道名应使用 setOhosCamera 而非 setIosCamera');
    });
  });

  group('MlKitChannel 方法调用', () {
    const channel = MethodChannel('mlkit_channel');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'getOhosAvailableCameras') {
          return [
            {'position': 1, 'type': 1},
          ];
        }
        return null;
      });
    });

    tearDown(() {
      channel.setMockMethodCallHandler(null);
    });

    test('toggleFlash 调用正确的方法', () async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.toggleFlash();

      expect(capturedMethod, 'toggleFlash');
    });

    test('startScan 返回广播流', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'startScan') return null;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      final stream = await mlKitChannel.startScan(
        RecognitionType.barcodeRecognition,
        500,
      );

      expect(stream, isNotNull);
      expect(stream.isBroadcast, true);
    });

    test('cancelScan 调用正确的方法', () async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.cancelScan();

      expect(capturedMethod, 'cancelScan');
    });

    test('setScanDelay 传递正确的延迟值', () async {
      int? capturedDelay;
      channel.setMockMethodCallHandler((call) async {
        capturedDelay = call.arguments as int?;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.setScanDelay(1000);

      expect(capturedDelay, 1000);
    });

    test('pauseCamera 调用正确的方法', () async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.pauseCamera();

      expect(capturedMethod, 'pauseCameraMethod');
    });

    test('resumeCamera 调用正确的方法', () async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.resumeCamera();

      expect(capturedMethod, 'resumeCameraMethod');
    });

    test('setZoom 传递正确的缩放值', () async {
      double? capturedValue;
      channel.setMockMethodCallHandler((call) async {
        capturedValue = call.arguments as double?;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.setZoom(0.5);

      expect(capturedValue, 0.5);
    });

    test('setCropArea 调用正确的方法', () async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      const rect = CropRect(
        scaleWidth: 0.5,
        scaleHeight: 0.6,
        offsetX: 0.1,
        offsetY: -0.1,
      );
      await mlKitChannel.setCropArea(rect);

      expect(capturedMethod, 'setCropAreaMethod');
    });

    test('dispose 调用正确的方法', () async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.dispose();

      expect(capturedMethod, 'dispose');
    });
  });

  group('MlKitChannel 异常场景', () {
    const channel = MethodChannel('mlkit_channel');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    tearDown(() {
      channel.setMockMethodCallHandler(null);
    });

    test('initCameraPreview 相机初始化失败时抛出 PlatformException', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'initCameraPreview') {
          throw PlatformException(code: '1', message: 'Camera initialization failed');
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.initCameraPreview(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('toggleFlash 无闪光灯时抛出 PlatformException', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'toggleFlash') {
          throw PlatformException(code: '4', message: 'Device has no flash');
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.toggleFlash(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('resumeCamera 相机未初始化时抛出 PlatformException', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'resumeCameraMethod') {
          throw PlatformException(code: '3', message: 'Camera is not initialized');
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.resumeCamera(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('setZoom 设备不支持缩放时抛出 PlatformException', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'setZoom') {
          throw PlatformException(code: '6', message: 'Device has no zoom');
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.setZoom(0.5),
        throwsA(isA<PlatformException>()),
      );
    });

    test('startScan 相机未初始化时抛出 PlatformException', () async {
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'startScan') {
          throw PlatformException(code: '3', message: 'Camera is not initialized');
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      expect(
        () => mlKitChannel.startScan(RecognitionType.barcodeRecognition, 500),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
