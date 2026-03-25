import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mlkit_scanner/mlkit_scanner.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var _barcode = 'Please, scan';
  final _zoomValues = [0.0, 0.33, 0.66];
  var _actualZoomIndex = 0;

  static const _delayOptions = {
    "0 milliseconds": 0,
    "100 milliseconds": 100,
    "500 milliseconds": 500,
    "2000 milliseconds": 2000,
  };
  BarcodeScannerController? _controller;

  List<IosCamera> _iosCameras = [];

  var _cameraIndex = -1;
  var _cameraType = '';
  var _cameraPosition = '';
  
  // 扫描区域设置选项
  final _cropAreaOptions = [
    const CropRect(scaleHeight: 0.7, scaleWidth: 0.7), // 默认设置
    const CropRect(scaleHeight: 0.5, scaleWidth: 0.5), // 小区域
    const CropRect(scaleHeight: 0.9, scaleWidth: 0.9), // 大区域
    const CropRect(scaleHeight: 0.7, scaleWidth: 0.3, offsetX: 0, offsetY: 0), // 窄区域
  ];
  var _currentCropAreaIndex = 0;

  void _setNextIosCamera() {
    if (_iosCameras.isEmpty) {
      return;
    }
    _cameraIndex = (_cameraIndex + 1) % _iosCameras.length;
    _controller!.setIosCamera(position: _iosCameras[_cameraIndex].position, type: _iosCameras[_cameraIndex].type);
    _resetZoom();
    setState(() {
      _cameraType = _iosCameras[_cameraIndex].type.name;
      _cameraPosition = _iosCameras[_cameraIndex].position.name;
    });
  }

  void _setNextRearCameraType() {
    if (_iosCameras.isEmpty) {
      return;
    }
    final rearIndexes = <int>[];
    for (var i = 0; i < _iosCameras.length; i++) {
      if (_iosCameras[i].position == IosCameraPosition.back) {
        rearIndexes.add(i);
      }
    }
    if (rearIndexes.isEmpty) {
      return;
    }
    final currentRearPos = rearIndexes.indexOf(_cameraIndex);
    final nextRearPos = currentRearPos >= 0
        ? (currentRearPos + 1) % rearIndexes.length
        : 0;
    _cameraIndex = rearIndexes[nextRearPos];
    _controller!.setIosCamera(position: _iosCameras[_cameraIndex].position, type: _iosCameras[_cameraIndex].type);
    _resetZoom();
    setState(() {
      _cameraType = _iosCameras[_cameraIndex].type.name;
      _cameraPosition = _iosCameras[_cameraIndex].position.name;
    });
  }

  String _getCameraListDescription() {
    if (_iosCameras.isEmpty) {
      return 'no cameras';
    }
    return _iosCameras
        .asMap()
        .entries
        .map((entry) => '${entry.key}:${entry.value.position.name}/${entry.value.type.name}')
        .join(' | ');
  }

  // 切换扫描区域
  void _setNextCropArea() {
    _currentCropAreaIndex = (_currentCropAreaIndex + 1) % _cropAreaOptions.length;
    _controller?.setCropArea(_cropAreaOptions[_currentCropAreaIndex]);
    setState(() {});
  }

  String _getCropAreaDescription() {
    final cropRect = _cropAreaOptions[_currentCropAreaIndex];
    return '${(cropRect.scaleWidth * 100).toInt()}%x${(cropRect.scaleHeight * 100).toInt()}%';
  }

  void _resetZoom() {
    _actualZoomIndex = 0;
    _controller?.setZoom(_zoomValues[_actualZoomIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Mlkit Scanner example app',
          ),
        ),
        body: Column(
          children: [
            Stack(
              children: [
                Container(
                  height: 200,
                  child: BarcodeScanner(
                    initialArguments: (defaultTargetPlatform == TargetPlatform.iOS)
                        ? const IosScannerParameters(
                            cropRect: CropRect(scaleHeight: 0.7, scaleWidth: 0.7),
                          )
                        : (defaultTargetPlatform == TargetPlatform.ohos)
                        ? const OhosScannerParameters(
                            cropRect: CropRect(scaleHeight: 0.7, scaleWidth: 0.7),
                          )
                        : const AndroidScannerParameters(
                            cropRect: CropRect(scaleHeight: 0.7, scaleWidth: 0.7),
                          ),
                    onScan: (code) {
                      setState(() {
                        _barcode = code.rawValue;
                      });
                    },
                    onScannerInitialized: (controller) async {
                      _controller = controller;
                      if (defaultTargetPlatform == TargetPlatform.iOS || 
                      defaultTargetPlatform == TargetPlatform.ohos) {
                        _iosCameras = await MLKitUtils().getIosAvailableCameras();
                        _setNextIosCamera();
                      }
                    },
                  ),
                ),
                const Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      "Tap to focus on Center / LongTap to lock focus",
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _barcode,
                style: const TextStyle(fontSize: 18),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  child: const SizedBox(
                    width: 88,
                    child: Text(
                      'Start scan',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  onPressed: () => _controller?.startScan(100),
                ),
                const SizedBox(width: 8),
                TextButton(
                  child: const SizedBox(
                    width: 88,
                    child: Text(
                      'Cancel scan',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  onPressed: () => _controller?.cancelScan(),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  child: const SizedBox(
                    width: 88,
                    child: Text(
                      'Pause camera',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  onPressed: () => _controller?.pauseCamera(),
                ),
                const SizedBox(width: 8),
                TextButton(
                  child: const SizedBox(
                    width: 88,
                    child: Text(
                      'Resume camera',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  onPressed: () => _controller?.resumeCamera(),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  child: const SizedBox(
                    width: 88,
                    child: Text(
                      'Toggle flash',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  onPressed: () => _controller?.toggleFlash(),
                ),
                const SizedBox(width: 8),
                _buildDelayButton(),
              ],
            ),
            TextButton(
              child: const SizedBox(
                width: 88,
                child: Text(
                  'Zoom',
                  textAlign: TextAlign.center,
                ),
              ),
              onPressed: () {
                _actualZoomIndex = _actualZoomIndex + 1 < _zoomValues.length ? _actualZoomIndex + 1 : 0;
                _controller?.setZoom(_zoomValues[_actualZoomIndex]);
              },
            ),
            TextButton(
              child: Text(
                'Crop: ${_getCropAreaDescription()}',
                textAlign: TextAlign.center,
              ),
              onPressed: _setNextCropArea,
            ),
            if (defaultTargetPlatform == TargetPlatform.iOS ||
             defaultTargetPlatform == TargetPlatform.ohos)
              Column(
                children: [
                  TextButton(
                    child: Text(
                      '$_cameraIndex: $_cameraPosition, $_cameraType',
                      textAlign: TextAlign.center,
                    ),
                    onPressed: _setNextIosCamera,
                  ),
                  TextButton(
                    child: const Text(
                      'Next rear camera type',
                      textAlign: TextAlign.center,
                    ),
                    onPressed: _setNextRearCameraType,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _getCameraListDescription(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDelayButton() {
    return TextButton(
      child: SizedBox(
        width: 88,
        child: PopupMenuButton<int>(
          onSelected: (delay) => _controller?.setDelay(delay),
          child: const Text(
            'Set Delay',
            textAlign: TextAlign.center,
          ),
          itemBuilder: (context) {
            return _delayOptions.entries
                .map(
                  (entry) => PopupMenuItem(
                    value: entry.value,
                    child: Text(entry.key),
                  ),
                )
                .toList();
          },
        ),
      ),
      onPressed: () {},
    );
  }
}
