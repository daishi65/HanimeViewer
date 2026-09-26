/// 个人中心相关的纯逻辑。
///
/// 抽出来的原因是这些规则（哪个栏目跳到哪个 tab）容易写错，
/// 但放在页面 State 里就没法单独测。
library;

/// 个人中心的 tab 定义。
class UserTab {
  /// 内部标识，同时也是官网 URL 的最后一段
  final String key;

  /// 界面上显示的名字
  final String label;

  const UserTab(this.key, this.label);
}

/// 自己的个人中心：5 个 tab，顺序和官网一致。
///
/// 注意「主页」是个人中心首页（栏目段总览），
/// 不是 APP 首页那个首页。
const List<UserTab> selfProfileTabs = [
  UserTab('home', '主页'),
  UserTab('histories', '观看纪录'),
  UserTab('saves', '稍后观看'),
  UserTab('likes', '赞好的影片'),
  UserTab('playlists', '播放清单'),
];

/// 别人的主页：觀看紀錄 / 稍後觀看 / 讚好的影片 属于私密内容，拿不到，
/// 所以只保留主页、上传的影片和播放清单。
const List<UserTab> otherProfileTabs = [
  UserTab('home', '主页'),
  UserTab('uploaded', '上传的影片'),
  UserTab('playlists', '播放清单'),
];

/// 从栏目段的「查看更多」链接推断它对应哪个 tab。
///
/// 官网的链接形如：
///   https://hanime1.me/user/715321/histories
///   https://hanime1.me/user/715321/saves
///   https://hanime1.me/user/715321/likes
///   https://hanime1.me/user/715321/playlists
/// 最后一段正好就是 tab key；
/// 而个人中心首页的链接没有额外段（结尾就是 user id），对应 home。
///
/// 认不出来就返回 null，调用方据此不显示「查看更多」。
String? tabKeyFromUrl(String url, String userId) {
  final uri = Uri.tryParse(url);

  if (uri == null) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (segments.isEmpty) return null;

  final last = segments.last;

  // /user/715321 -> 个人中心首页
  if (last == userId) return 'home';

  const known = {
    'histories': 'histories',
    'saves': 'saves',
    'likes': 'likes',
    'playlists': 'playlists',
    'uploaded': 'uploaded',
    'uploading': 'uploading',
  };

  return known[last];
}
