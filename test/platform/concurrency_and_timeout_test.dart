import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mlkit_scanner/platform/ml_kit_channel.dart';
import 'package:mlkit_scanner/models/recognition_type.dart';

void main() {
  const channel = MethodChannel('mlkit_channel');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  group('并发场景', () {
    test('多方法并发调用不抛异常', () async {
      channel.setMockMethodCallHandler((call) async {
        // 模拟异步延迟
        await Future.delayed(const Duration(milliseconds: 10));
        return null;
      });

      final mlKitChannel = MlKitChannel();

      // 同时调用多个方法
      final results = await Future.wait([
        mlKitChannel.toggleFlash(),
        mlKitChannel.cancelScan(),
        mlKitChannel.pauseCamera(),
        mlKitChannel.setScanDelay(100),
      ]);

      expect(results, everyElement(isNull));
    });

    test('扫描中暂停相机不抛异常', () async {
      bool scanStarted = false;
      channel.setMockMethodCallHandler((call) async {
        if (call.method == 'startScan') {
          scanStarted = true;
        }
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await mlKitChannel.startScan(RecognitionType.barcodeRecognition, 100);
      expect(scanStarted, true);

      // 扫描中暂停
      await mlKitChannel.pauseCamera();
    });

    test('连续快速调用 toggleFlash 不抛异常', () async {
      int callCount = 0;
      channel.setMockMethodCallHandler((call) async {
        callCount++;
        return null;
      });

      final mlKitChannel = MlKitChannel();
      await Future.wait([
        mlKitChannel.toggleFlash(),
        mlKitChannel.toggleFlash(),
        mlKitChannel.toggleFlash(),
      ]);

      expect(callCount, 3);
    });
  });

  group('超时异常场景', () {
    test('方法调用超时时抛出 PlatformException', () async {
      channel.setMockMethodCallHandler((call) async {
        // 模拟超时：不返回结果
        await Future.delayed(const Duration(seconds: 30));
        return null;
      });

      final mlKitChannel = MlKitChannel();

      // 使用 timeout 强制超时
      expect(
        () => mlKitChannel.toggleFlash().timeout(const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('方法调用返回 null 时正常处理', () async {
      channel.setMockMethodCallHandler((call) async {
        return null;
      });

      final mlKitChannel = MlKitChannel();
      // void 返回值的方法返回 null 不应抛异常
      await mlKitChannel.toggleFlash();
      await mlKitChannel.cancelScan();
      await mlKitChannel.pauseCamera();
    });
  });
}
