import 'package:mlkit_scanner/models/crop_rect.dart';
import 'package:mlkit_scanner/models/ios_camera.dart';
import 'package:mlkit_scanner/models/ios_camera_position.dart';
import 'package:mlkit_scanner/models/ios_camera_type.dart';
import 'package:mlkit_scanner/models/scanner_parameters.dart';

/// Parameters for initializing the scanner on OHOS.
class OhosScannerParameters extends ScannerParameters {
  /// Optional initial zoom.
  final double? zoom;

  /// Optional initial camera.
  final IosCamera? camera;

  const OhosScannerParameters({this.zoom, this.camera, CropRect? cropRect})
      : super(cropRect: cropRect);

  @override
  Map<String, dynamic> toJson() {
    return {
      'initialZoom': zoom,
      'initialCamera': camera != null
          ? {
              'position': camera!.position.code,
              'type': camera!.type.code,
            }
          : null,
      ...super.toJson(),
    };
  }
}
