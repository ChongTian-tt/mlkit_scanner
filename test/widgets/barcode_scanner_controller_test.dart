import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/mlkit_scanner.dart';
import 'package:mlkit_scanner/models/ohos_camera_position.dart';
import 'package:mlkit_scanner/models/ohos_camera_type.dart';
import 'package:mlkit_scanner/models/ios_camera_position.dart';
import 'package:mlkit_scanner/models/ios_camera_type.dart';
import 'package:mlkit_scanner/widgets/camera_preview.dart';

void main() {
  group('BarcodeScannerController', () {
    const channel = MethodChannel('mlkit_channel');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      channel.setMockMethodCallHandler((call) async => null);
      SystemChannels.platform_views.setMockMethodCallHandler((call) async => null);
    });

    tearDown(() {
      channel.setMockMethodCallHandler(null);
      SystemChannels.platform_views.setMockMethodCallHandler(null);
    });

    testWidgets('控制器在扫描器初始化后可用', (tester) async {
      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      expect(camera, findsOneWidget);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      expect(controller, isNotNull, reason: '控制器应在扫描器初始化后可用');
    });

    testWidgets('toggleFlash 调用正确的方法通道', (tester) async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      await controller?.toggleFlash();
      expect(capturedMethod, 'toggleFlash');
    });

    testWidgets('startScan 启动扫码', (tester) async {
      bool scanStarted = false;
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'startScan') {
          scanStarted = true;
        }
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      await controller?.startScan(500);
      expect(scanStarted, true);
    });

    testWidgets('cancelScan 取消扫码', (tester) async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      await controller?.cancelScan();
      expect(capturedMethod, 'cancelScan');
    });

    testWidgets('setDelay 设置扫码延迟', (tester) async {
      int? capturedDelay;
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'setScanDelay') {
          capturedDelay = call.arguments as int?;
        }
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      await controller?.setDelay(1000);
      expect(capturedDelay, 1000);
    });

    testWidgets('pauseCamera 暂停相机', (tester) async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      await controller?.pauseCamera();
      expect(capturedMethod, 'pauseCameraMethod');
    });

    testWidgets('resumeCamera 恢复相机', (tester) async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      await controller?.resumeCamera();
      expect(capturedMethod, 'resumeCameraMethod');
    });

    testWidgets('setZoom 设置缩放', (tester) async {
      double? capturedValue;
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'setZoom') {
          capturedValue = call.arguments as double?;
        }
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      await controller?.setZoom(0.5);
      expect(capturedValue, 0.5);
    });

    testWidgets('setCropArea 调用正确的方法', (tester) async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      const rect = CropRect(scaleWidth: 0.5, scaleHeight: 0.6);
      await controller?.setCropArea(rect);
      expect(capturedMethod, 'setCropAreaMethod');
    });

    testWidgets('setOhosCamera 调用正确的 OHOS 方法通道', (tester) async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      await controller?.setOhosCamera(
        position: OhosCameraPosition.back,
        type: OhosCameraType.CAMERA_TYPE_WIDE_ANGLE,
      );
      expect(capturedMethod, 'setOhosCamera',
          reason: 'OHOS 相机设置应使用 setOhosCamera 通道名');
    });

    testWidgets('setIosCamera 调用正确的 iOS 方法通道', (tester) async {
      String? capturedMethod;
      channel.setMockMethodCallHandler((call) async {
        capturedMethod = call.method;
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      await controller?.setIosCamera(
        position: IosCameraPosition.back,
        type: IosCameraType.wideAngle,
      );
      expect(capturedMethod, 'setIosCamera',
          reason: 'iOS 相机设置应使用 setIosCamera 通道名');
    });

    testWidgets('控制器在 detach 后方法不调用通道', (tester) async {
      bool methodCalled = false;
      channel.setMockMethodCallHandler((call) async {
        methodCalled = true;
        return null;
      });

      BarcodeScannerController? controller;
      await tester.pumpWidget(TestApp(
        child: BarcodeScanner(
          onScannerInitialized: (c) => controller = c,
          onScan: (value) {},
        ),
      ));

      final camera = find.byType(CameraPreview);
      final widget = tester.firstWidget(camera) as CameraPreview;
      widget.onCameraInitialized();
      await tester.pumpAndSettle();

      // 销毁 widget，控制器应 detach
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();

      methodCalled = false;
      await controller?.toggleFlash();
      expect(methodCalled, false, reason: '控制器 detach 后不应再调用方法通道');
    });
  });
}

class TestApp extends StatelessWidget {
  final Widget? child;

  const TestApp({
    this.child,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }
}
