/// 跟账号走的本地数据。
///
/// 背景：以前的本地存储用的是全局 key（`watch_history`、`search_history`、
/// `video_position_123`），跟登录的是哪个账号无关。
/// 结果就是「登录账号2，看到的还是账号1的数据」。
///
/// 这里统一把 key 加上账号前缀：
///
///     观看历史   ->  u_68664_watch_history
///     搜索记录   ->  u_68664_search_history
///     播放进度   ->  u_68664_video_position_123
///     未登录     ->  guest_watch_history
///
/// 未登录时用 `guest` 前缀，这样「先随便看看、之后才登录」也不会把
/// 匿名数据混进某个账号里。
///
/// 注意：主题（明暗模式）**故意不跟账号走** ——
/// 那是这台设备上的使用习惯，不该因为换账号就变。
library;

import 'auth_controller.dart';

class AccountScope {
  AccountScope._();

  /// 没有登录时用的前缀
  static const String guestPrefix = 'guest';

  /// 当前账号的作用域前缀。
  ///
  /// 登录中用 `u_<userId>`；未登录（或还没拿到 userId）用 `guest`。
  static String get prefix {
    final info = AuthController.account.value;

    if (info.loggedIn && info.userId.isNotEmpty) {
      return 'u_${info.userId}';
    }

    return guestPrefix;
  }

  /// 把一个逻辑 key 变成当前账号下的实际存储 key。
  static String key(String name) => '${prefix}_$name';

  /// 生成带参数的业务 key，例如
  /// `scopedKey('video_position', videoId)` -> `u_68664_video_position_123`
  static String scopedKey(String name, String suffix) =>
      '${prefix}_${name}_$suffix';
}
