/// Ohos camera position.
enum OhosCameraPosition {
  unspecified,

  back,

  front,
}

extension OhosCameraPositionCode on OhosCameraPosition {
  /// 平台通道传输的位置代码
  int get code => _positionToCode[this]!;

  /// 返回与[code]对应的位置。
  static OhosCameraPosition fromCode(int code) => _codeToPosition[code]!;

  static final _positionToCode = {
    OhosCameraPosition.unspecified: 0,
    OhosCameraPosition.back: 1,
    OhosCameraPosition.front: 2,
  };

  static final _codeToPosition = {
    for (final entry in _positionToCode.entries) entry.value: entry.key,
  };
}
