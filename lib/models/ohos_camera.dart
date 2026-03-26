import 'package:mlkit_scanner/models/ohos_camera_position.dart';
import 'package:mlkit_scanner/models/ohos_camera_type.dart';

/// Ohos camera info.
class OhosCamera {
  /// Camera type.
  final OhosCameraType type;

  /// Camera position.
  final OhosCameraPosition position;

  const OhosCamera({
    required this.type,
    required this.position,
  });

  factory OhosCamera.fromJson(Map<String, dynamic> json) {
    return OhosCamera(
      type: OhosCameraTypeCode.fromCode(json['type']),
      position: OhosCameraPositionCode.fromCode(json['position']),
    );
  }
}
