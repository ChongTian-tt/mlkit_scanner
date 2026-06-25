import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/models/android_scanner_parameters.dart';
import 'package:mlkit_scanner/models/crop_rect.dart';
import 'package:mlkit_scanner/models/ios_camera.dart';
import 'package:mlkit_scanner/models/ios_camera_position.dart';
import 'package:mlkit_scanner/models/ios_camera_type.dart';
import 'package:mlkit_scanner/models/ios_scanner_parameters.dart';
import 'package:mlkit_scanner/models/ohos_camera.dart';
import 'package:mlkit_scanner/models/ohos_camera_position.dart';
import 'package:mlkit_scanner/models/ohos_camera_type.dart';
import 'package:mlkit_scanner/models/ohos_scanner_parameters.dart';

void main() {
  group('AndroidScannerParameters', () {
    test('toJson 包含 zoom 和 cropRect', () {
      const params = AndroidScannerParameters(
        zoom: 0.5,
        cropRect: CropRect(scaleWidth: 0.8, scaleHeight: 0.6),
      );
      final json = params.toJson();

      expect(json['initialZoom'], 0.5);
      expect(json['initialCropRect'], isNotNull);
      expect((json['initialCropRect'] as Map)['scaleWidth'], 0.8);
    });

    test('toJson zoom 为 null 时不包含初始缩放', () {
      const params = AndroidScannerParameters();
      final json = params.toJson();

      expect(json['initialZoom'], isNull);
    });
  });

  group('IosScannerParameters', () {
    test('toJson 包含 zoom、camera 和 cropRect', () {
      const params = IosScannerParameters(
        zoom: 0.3,
        camera: IosCamera(
          position: IosCameraPosition.back,
          type: IosCameraType.builtInWideAngleCamera,
        ),
        cropRect: CropRect(scaleWidth: 0.5),
      );
      final json = params.toJson();

      expect(json['initialZoom'], 0.3);
      expect(json['initialCamera'], isNotNull);
      expect((json['initialCamera'] as Map)['position'], 1); // back
      expect((json['initialCamera'] as Map)['type'], 0); // builtInWideAngleCamera
      expect(json['initialCropRect'], isNotNull);
    });

    test('toJson camera 为 null 时 initialCamera 为 null', () {
      const params = IosScannerParameters();
      final json = params.toJson();

      expect(json['initialCamera'], isNull);
    });
  });

  group('OhosScannerParameters', () {
    test('toJson 包含 zoom、camera 和 cropRect', () {
      const params = OhosScannerParameters(
        zoom: 0.4,
        camera: OhosCamera(
          position: OhosCameraPosition.back,
          type: OhosCameraType.CAMERA_TYPE_WIDE_ANGLE,
        ),
        cropRect: CropRect(scaleWidth: 0.7),
      );
      final json = params.toJson();

      expect(json['initialZoom'], 0.4);
      expect(json['initialCamera'], isNotNull);
      // OHOS 相机码：back=1, CAMERA_TYPE_WIDE_ANGLE=1
      expect((json['initialCamera'] as Map)['position'], 1);
      expect((json['initialCamera'] as Map)['type'], 1);
      expect(json['initialCropRect'], isNotNull);
    });

    test('toJson camera 为 null 时 initialCamera 为 null', () {
      const params = OhosScannerParameters();
      final json = params.toJson();

      expect(json['initialCamera'], isNull);
    });

    test('toJson 使用 OHOS 相机码而非 iOS 码', () {
      // 验证 OHOS 前置默认相机的码值
      const params = OhosScannerParameters(
        camera: OhosCamera(
          position: OhosCameraPosition.front,
          type: OhosCameraType.CAMERA_TYPE_DEFAULT,
        ),
      );
      final json = params.toJson();
      final cameraMap = json['initialCamera'] as Map;

      // front=2, CAMERA_TYPE_DEFAULT=0
      expect(cameraMap['position'], 2);
      expect(cameraMap['type'], 0);
    });

    test('toJson 前置景深相机码值正确', () {
      const params = OhosScannerParameters(
        camera: OhosCamera(
          position: OhosCameraPosition.front,
          type: OhosCameraType.CAMERA_TYPE_TRUE_DEPTH,
        ),
      );
      final json = params.toJson();
      final cameraMap = json['initialCamera'] as Map;

      // front=2, CAMERA_TYPE_TRUE_DEPTH=4
      expect(cameraMap['position'], 2);
      expect(cameraMap['type'], 4);
    });
  });
}
