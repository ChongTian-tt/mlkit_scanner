/// Ohos camera type.
enum OhosCameraType {
  /// 默认相机类型
  CAMERA_TYPE_DEFAULT,

  /// 广角相机
  CAMERA_TYPE_WIDE_ANGLE,

  /// 超广角相机
  CAMERA_TYPE_ULTRA_WIDE,

  /// 长焦相机
  CAMERA_TYPE_TELEPHOTO,

  /// 带景深信息的相机
  CAMERA_TYPE_TRUE_DEPTH
  }

extension OhosCameraTypeCode on OhosCameraType {
  /// Code of type for transmission over the platform channel.
  int get code => _typeToCode[this]!;

  /// Returns the type corresponding to the [code].
  static OhosCameraType fromCode(int code) => _codeToType[code]!;

  static final _typeToCode = {
    OhosCameraType.CAMERA_TYPE_DEFAULT: 0,
    OhosCameraType.CAMERA_TYPE_WIDE_ANGLE: 1,
    OhosCameraType.CAMERA_TYPE_ULTRA_WIDE: 2,
    OhosCameraType.CAMERA_TYPE_TELEPHOTO: 3,
    OhosCameraType.CAMERA_TYPE_TRUE_DEPTH: 4,
  };

  static final _codeToType = {
    for (final entry in _typeToCode.entries) entry.value: entry.key,
  };
}
