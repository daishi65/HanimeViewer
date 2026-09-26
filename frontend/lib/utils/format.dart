/// 播放器用的小工具函数。
///
/// 之前这些逻辑藏在页面的私有方法里，没法单独写测试。
/// 抽出来之后可以直接验证（见 test/widget_test.dart）。
library;

/// 把播放进度格式化成 `分:秒` 或 `时:分:秒`。
///
/// 例如：
/// - 5 秒        -> `00:05`
/// - 1 分 5 秒   -> `01:05`
/// - 1 时 5 分 3 秒 -> `1:05:03`
String formatPlaybackDuration(Duration duration) {
  final minutes =
      duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds =
      duration.inSeconds.remainder(60).toString().padLeft(2, '0');

  final hours = duration.inHours;

  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }

  return '$minutes:$seconds';
}
