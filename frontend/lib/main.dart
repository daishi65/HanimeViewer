import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'playlist_page.dart';
import 'widgets/windows11_loading.dart';
import 'controllers/theme_controller.dart';
import 'controllers/app_cache.dart';
import 'controllers/auth_controller.dart';
import 'controllers/account_scope.dart';
import 'controllers/backend_launcher.dart';
import 'login_dialog.dart';
import 'new_release_page.dart';
import 'startup_gate.dart';
import 'user_profile_page.dart';
import 'utils/format.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'controllers/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  // 允许用环境变量覆盖端口，方便排错或同时跑多个实例
  AppConfig.applyEnvironment(Platform.environment);

  await ThemeController.load();

  // 先读本地缓存的账号信息（立刻能显示头像），再异步向后端确认
  await AuthController.load();

  // 自己把后端拉起来（后端再去把调试 Chrome 拉起来）。
  // 如果后端已经在跑（比如开发时手动起的），会直接复用。
  final (backendOk, backendError) = await BackendLauncher.start();

  // 关窗口时把后端一起收掉，否则端口会一直被占着。
  // 只收我们自己启动的那个：如果后端是外部起的就不动它。
  windowManager.addListener(_LifecycleCleaner());

  runApp(
    HanimeViewerApp(
      backendStarted: backendOk,
      backendAlreadyRunning: backendOk && !BackendLauncher.startedByUs,
      backendError: backendError,
    ),
  );
}

/// 负责在 App 退出时清理我们启动的后端进程。
class _LifecycleCleaner with WindowListener {
  @override
  void onWindowClose() {
    // 先同步关掉后端，再让窗口正常关闭
    BackendLauncher.stop().whenComplete(() {
      windowManager.destroy();
    });
  }
}

class HanimeViewerApp extends StatelessWidget {
  /// 后端是否已就绪（自己起的或外部已有的）
  final bool backendStarted;

  /// 后端是否在启动前就已经在跑
  final bool backendAlreadyRunning;

  /// 启动后端失败时的原因
  final String backendError;

  const HanimeViewerApp({
    super.key,
    this.backendStarted = true,
    this.backendAlreadyRunning = false,
    this.backendError = '',
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'HanimeViewer',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: themeMode,
          home: StartupGate(
            backendAlreadyRunning: backendAlreadyRunning,
            initialError: backendError,
            child: const MainShell(),
          ),
        );        
      },
    );
  }
}

enum _MainSection {
  home,
  search,
  history,
  playlist,
  newRelease,
  downloads,
  settings,
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  _MainSection _section = _MainSection.home;

  Map<String, String>? _searchPreset;

  /// 已经创建过的页面。
  ///
  /// 以前 _buildPage() 用 switch 只返回当前页面，切走时旧页面会被销毁，
  /// 切回来重新 initState -> 重新请求接口，所以每次切换都要重新等一遍。
  /// 现在把页面放进 IndexedStack 保留 State，切回来时内容还在，
  /// 配合 AppCache 也就不会重复请求了。
  final Map<_MainSection, Widget> _pages = {};

  /// 创建这些页面时用的是哪个账号。
  ///
  /// 观看历史 / 搜索记录 / 播放清单 / 播放进度都是跟着账号走的，
  /// 所以换账号时必须把已经建好的页面丢掉重建，
  /// 否则会一直显示上一个账号的数据。
  String _pagesScope = AccountScope.prefix;

  /// 账号变了就清掉缓存页面（下次 build 会用新账号重建）。
  void _resetPagesIfAccountChanged() {
    final current = AccountScope.prefix;

    if (current == _pagesScope) return;

    _pagesScope = current;
    _pages.clear();

    // 接口结果也按账号隔离：里面可能含播放清单等私有数据
    AppCache.clear();
  }

  void _select(_MainSection section) {
    setState(() {
      _section = section;
      _searchPreset = null;
    });
    if (MediaQuery.sizeOf(context).width < 800) {
      Navigator.of(context).maybePop();
    }
  }

  void _openCategory(String title, String genre, String sort) {
    setState(() {
      _section = _MainSection.search;
      _searchPreset = {
        'genre': genre,
        'sort': sort,
        'key': DateTime.now().microsecondsSinceEpoch.toString(),
      };

      // 换了筛选条件，搜索页需要重建（key 变了）
      _pages.remove(_MainSection.search);
    });
  }

  Widget _pageFor(_MainSection section) {
    // 先查已创建的页面，存在就直接复用（IndexedStack 会保留它的 State）
    final existing = _pages[section];

    if (existing != null) {
      return existing;
    }

    final created = _createPage(section);

    _pages[section] = created;

    return created;
  }

  Widget _createPage(_MainSection section) {
    switch (section) {
      case _MainSection.home:
        return HomePage(onOpenCategory: _openCategory);
      case _MainSection.search:
        return SearchPage(
          key: ValueKey(
            _searchPreset == null
                ? 'search_default'
                : 'search_${_searchPreset!['key']}',
          ),
          initialGenre: _searchPreset?['genre'] ?? '',
          initialSort: _searchPreset?['sort'] ?? '',
        );
      case _MainSection.history:
        return const HistoryPage();
      case _MainSection.playlist:
        return const PlaylistPage();
      case _MainSection.newRelease:
        return const NewReleasePage();
      case _MainSection.downloads:
        return const _PlaceholderPage(
          icon: Icons.download,
          title: '下载',
          message: '下载功能稍后实现。',
        );
      case _MainSection.settings:
        return const SettingsPage();        
    }
  }

  /// 用 IndexedStack 承载所有「已经打开过」的页面：
  /// 只有当前页可见，其余页面保持存活但不可见，
  /// 这样切回来时滚动位置、输入内容、已加载的数据都还在。
  ///
  /// 没打开过的页面不会创建，所以不会在启动时把所有接口都请求一遍。
  Widget _buildPage() {
    // 换了账号就把旧页面丢掉，用新账号重建
    _resetPagesIfAccountChanged();

    // 确保当前页面已经创建（第一次进入某个栏目时在这里创建）
    final current = _pageFor(_section);

    final opened = [
      for (final section in _MainSection.values)
        if (_pages.containsKey(section)) section,
    ];

    if (opened.length <= 1) {
      return current;
    }

    return IndexedStack(
      index: opened.indexOf(_section),
      children: [
        for (final section in opened) _pages[section]!,
      ],
    );
  }

  Widget _buildNavigation({bool drawer = false}) {
    final items = <(
      _MainSection,
      IconData,
      IconData,
      String
    )>[
      (
        _MainSection.home,
        Icons.home_outlined,
        Icons.home,
        '首页'
      ),
      (
        _MainSection.search,
        Icons.search_outlined,
        Icons.search,
        '搜索'
      ),
      (
        _MainSection.history,
        Icons.history_outlined,
        Icons.history,
        '观看记录'
      ),
      (
        _MainSection.playlist,
        Icons.playlist_play_outlined,
        Icons.playlist_play,
        '播放清单'
      ),
      (
        _MainSection.newRelease,
        Icons.new_releases_outlined,
        Icons.new_releases,
        '新番预告'
      ),
      (
        _MainSection.downloads,
        Icons.download_outlined,
        Icons.download,
        '下载'
      ),
      (
        _MainSection.settings,
        Icons.settings_outlined,
        Icons.settings,
        '设置'
      ),
    ];

    if (drawer) {
      return SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Text(
                      'HanimeViewer',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  for (final item in items)
                    ListTile(
                      leading: Icon(
                        _section == item.$1
                            ? item.$3
                            : item.$2,
                      ),
                      title: Text(item.$4),
                      selected: _section == item.$1,
                      onTap: () => _select(item.$1),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            _AccountTile(
              onOpenProfile: _openMyProfile,
              onLogout: _logout,
            ),
          ],
        ),
      );
    }

    // 侧边栏：NavigationRail 占上方，账号入口固定在底部。
    // 外面套一个固定宽度的 SizedBox，保证 NavigationRail 拿到明确的宽度约束
    // （否则在窄窗口下它会算出非法约束导致布局断言失败）。
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          Expanded(
            child: NavigationRail(
              selectedIndex:
                  _MainSection.values.indexOf(_section),
              onDestinationSelected: (index) =>
                  _select(_MainSection.values[index]),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Icon(
                  Icons.video_library,
                  size: 28,
                ),
              ),
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Icon(item.$2),
                    selectedIcon: Icon(item.$3),
                    label: Text(item.$4),
                  ),
              ],
            ),
          ),
          // 左下角的账号头像：未登录显示登录入口，登录后点进自己的主页
          const Divider(height: 1),
          _AccountTile(
            onOpenProfile: _openMyProfile,
            onLogout: _logout,
          ),
        ],
      ),
    );
  }

  /// 退出登录。
  ///
  /// 会让浏览器登出，然后把本地数据切回「未登录」作用域 ——
  /// 这样下一个人登录时不会看到上一个账号的历史和播放清单。
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text(
          '退出后会回到未登录状态。\n'
          '各账号的观看历史、搜索记录、播放进度都是分开保存的，'
          '重新登录仍会看到自己的数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await AuthController.logout();

    if (!mounted) return;

    // 切回未登录作用域，页面按新作用域重建
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }

  /// 打开「我的主页」（点赞过的影片、储存的播放清单都在这里）
  void _openMyProfile() {
    final info = AuthController.account.value;

    if (!info.loggedIn || info.userId.isEmpty) {
      _showLogin();

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          userId: info.userId,
          initialName: info.username,
          initialTab: 'home',
        ),
      ),
    );
  }

  Future<void> _showLogin() async {
    final before = AccountScope.prefix;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const LoginDialog(),
    );

    if (!mounted) return;

    // 登录对话框内部会更新 AuthController.account。
    // 这里显式重建一次，保证：
    // - 侧边栏头像立刻更新
    // - 已经缓存的页面按新账号重建（见 _resetPagesIfAccountChanged）
    setState(() {});

    final changed = AccountScope.prefix != before;

    if (ok == true || changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok == true ? '登录成功，数据已切换到该账号' : '账号已切换',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= 800;

    // 账号（登录/登出/换号）变化时整壳重建：
    // 观看历史、搜索记录、播放清单、播放进度都跟着账号走，
    // 不重建的话会一直显示上一个账号的数据。
    return ValueListenableBuilder<AccountInfo>(
      valueListenable: AuthController.account,
      builder: (context, _, _) => _buildShell(wide),
    );
  }

  Widget _buildShell(bool wide) {
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _buildNavigation(),
            const VerticalDivider(width: 1),
            Expanded(
              child: _buildPage(),              
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        toolbarHeight: 40,
      ),
      drawer: Drawer(        
        child: _buildNavigation(drawer: true),
      ),
      body: _buildPage(),
    );    
  }
}

class HomePage extends StatefulWidget {
  final void Function(String title, String genre, String sort)?
      onOpenCategory;

  const HomePage({
    super.key,
    this.onOpenCategory,
  });

  @override
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _cacheKey = 'home_sections';

  List<Map<String, dynamic>> _sections = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    // 先看缓存：有就直接显示，避免启动时白屏等网络
    final cached = AppCache.get(_cacheKey);

    if (cached is List) {
      _sections = List<Map<String, dynamic>>.from(cached);
      _loading = false;

      return;
    }

    _loadHomeVideos();
  }

  Future<void> _loadHomeVideos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.get(
        Uri.parse(
          '${AppConfig.backendBase}/api/home_sections',
        ),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '服务器返回错误: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      final sections = List<Map<String, dynamic>>.from(
        data['sections'] ?? [],
      );

      if (sections.isNotEmpty) {
        AppCache.set(_cacheKey, sections, ttl: AppCache.homeTtl);
      }

      if (mounted) {
        setState(() => _sections = sections);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = '首页加载失败：$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String? _extractVideoId(String url) {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['v'];
  }

  void _openVideo(Map<String, dynamic> video) {
    final id = _extractVideoId(
      video['url']?.toString() ?? '',
    );

    if (id == null || id.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(videoId: id),
      ),
    );
  }

  int _columnsFor(double width) {
    if (width >= 1600) return 6;
    if (width >= 1300) return 5;
    if (width >= 1000) return 4;
    if (width >= 750) return 3;
    if (width >= 500) return 2;
    return 1;
  }

  void _openCategory(String name, String url) {
    final uri = Uri.tryParse(url);

    if (uri == null) return;

    final genre = uri.queryParameters['genre'] ?? '';
    String sort = uri.queryParameters['sort'] ?? '';

    // 有 genre 时忽略 sort，避免官网 URL 自带的 sort 干扰
    if (genre.isNotEmpty) {
      sort = '';
    }

    if (widget.onOpenCategory != null) {
      widget.onOpenCategory!(name, genre, sort);
    }
  }

  Widget _buildCard(Map<String, dynamic> video) {
    final thumbnail =
        video['thumbnail']?.toString() ?? '';
    final title = video['title']?.toString() ?? '';
    final duration =
        video['duration']?.toString() ?? '';
    final rating = video['rating']?.toString() ?? '';
    final views = video['views']?.toString() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openVideo(video),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: thumbnail.isNotEmpty
                  ? Image.network(
                      thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image),
                      ),
                    )
                  : Container(
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                [duration, rating, views]
                    .where((v) => v.isNotEmpty)
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    Map<String, dynamic> section,
    double maxWidth,
  ) {
    final name = section['name']?.toString() ?? '';
    final url = section['url']?.toString() ?? '';
    final videos = List<Map<String, dynamic>>.from(
      section['videos'] ?? [],
    );

    if (videos.isEmpty) {
      return const SizedBox.shrink();
    }

    final columns = _columnsFor(maxWidth);

    const horizontalPadding = 48.0;
    const crossAxisSpacing = 16.0;

    final availableWidth = maxWidth -
        horizontalPadding -
        crossAxisSpacing * (columns - 1);
    final itemWidth = availableWidth / columns;
    final thumbnailHeight = itemWidth * 9 / 16;
    final itemHeight = thumbnailHeight + 92;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (url.isNotEmpty)
                TextButton(
                  onPressed: () {
                    _openCategory(name, url);
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('查看更多'),
                      Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
            ],
          ),
        ),        
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: 16,
            mainAxisExtent: itemHeight,
          ),
          itemCount: videos.length,
          itemBuilder: (_, index) => _buildCard(videos[index]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Windows11Loading(size: 48),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadHomeVideos,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    if (_sections.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadHomeVideos,
        child: ListView(
          children: const [
            SizedBox(height: 180),
            Center(child: Text('暂无内容')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHomeVideos,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: _sections.length,
            itemBuilder: (_, index) => _buildSection(
              _sections[index],
              constraints.maxWidth,
            ),
          );
        },
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  final String initialGenre;
  final String initialSort;

  const SearchPage({
    super.key,
    this.initialGenre = '',
    this.initialSort = '',
  });

  @override
  State<SearchPage> createState() =>
      _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller =
      TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;

  String _selectedGenre = '';
  String _selectedSort = '';
  String _selectedDate = '';
  String _selectedDuration = '';
  List<String> _selectedTags = [];
  bool _broadMatch = false;

  List<Map<String, dynamic>> _tagGroups = [];
  bool _tagsLoaded = false;
  bool _tagsLoading = false;

  /// 标签分组的缓存 key（后端把标签随搜索结果一起返回，这里缓存下来复用）
  static const String _tagCacheKey = 'search_tag_groups';

  bool get _isPortraitCategory =>
      _selectedGenre == '裏番' || _selectedGenre == '泡麵番';

  /// 搜索历史跟着账号走（见 account_scope.dart）
  String get _historyKey => AccountScope.key('search_history');

  static const int _maxHistoryCount = 20;
  List<String> _searchHistory = [];
  bool _showHistoryPanel = false;
  
  @override
  void initState() {
    super.initState();
    _selectedGenre = widget.initialGenre;
    _selectedSort = widget.initialSort;
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _loadSearchHistory();

    // 进入搜索页：无条件加载一次（显示默认搜索结果）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search();
    });
  }

  void _onSearchFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  static const List<Map<String, String>> _genreOptions = [
    {'label': '全部', 'value': ''},
    {'label': '裏番', 'value': '裏番'},
    {'label': '泡麵番', 'value': '泡麵番'},
    {'label': 'Motion Anime', 'value': 'Motion Anime'},
    {'label': '3DCG', 'value': '3DCG'},
    {'label': '2.5D動畫', 'value': '2.5D'},
    {'label': '2D動畫', 'value': '2D動畫'},
    {'label': 'AI生成', 'value': 'AI生成'},
    {'label': 'MMD', 'value': 'MMD'},
    {'label': 'Cosplay', 'value': 'Cosplay'},
  ];

  static const List<Map<String, String>> _sortOptions = [

    {'label': '默认排序', 'value': ''},
    {'label': '最新上市', 'value': '最新上市'},
    {'label': '最新上傳', 'value': '最新上傳'},
    {'label': '本日排行', 'value': '本日排行'},
    {'label': '本週排行', 'value': '本週排行'},
    {'label': '本月排行', 'value': '本月排行'},
    {'label': '觀看次數', 'value': '觀看次數'},
    {'label': '讚好比例', 'value': '讚好比例'},
    {'label': '時長最長', 'value': '時長最長'},
    {'label': '他們在看', 'value': '他們在看'},
  ];

  static const List<Map<String, String>> _dateOptions = [
    {'label': '全部', 'value': ''},
    {'label': '過去 24 小時', 'value': '過去 24 小時'},
    {'label': '過去 2 天', 'value': '過去 2 天'},
    {'label': '過去 1 週', 'value': '過去 1 週'},
    {'label': '過去 1 個月', 'value': '過去 1 個月'},
    {'label': '過去 3 個月', 'value': '過去 3 個月'},
    {'label': '過去 1 年', 'value': '過去 1 年'},
  ];

  static const List<Map<String, String>> _durationOptions = [
    {'label': '全部', 'value': ''},
    {'label': '1 分鐘 +', 'value': '1 分鐘 +'},
    {'label': '5 分鐘 +', 'value': '5 分鐘 +'},
    {'label': '10 分鐘 +', 'value': '10 分鐘 +'},
    {'label': '20 分鐘 +', 'value': '20 分鐘 +'},
    {'label': '30 分鐘 +', 'value': '30 分鐘 +'},
    {'label': '60 分鐘 +', 'value': '60 分鐘 +'},
    {'label': '0 - 10 分鐘', 'value': '0 - 10 分鐘'},
    {'label': '0 - 20 分鐘', 'value': '0 - 20 分鐘'},
  ];

  String? _extractVideoId(String url) {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['v'];
  }

  Future<void> _search() async {
    final query = _controller.text.trim();

    // 无条件执行搜索：即使没有任何筛选，也加载默认结果

    final params = <String, String>{};

    if (query.isNotEmpty) {
      params['query'] = query;
    }

    if (_selectedGenre.isNotEmpty) {
      params['genre'] = _selectedGenre;
    }

    if (_selectedSort.isNotEmpty) {
      params['sort'] = _selectedSort;
    }

    if (_selectedDate.isNotEmpty) {
      params['date'] = _selectedDate;
    }

    if (_selectedDuration.isNotEmpty) {
      params['duration'] = _selectedDuration;
    }

    if (_selectedTags.isNotEmpty) {
      params['tags'] = _selectedTags.join('|');
    }

    if (_broadMatch && _selectedTags.isNotEmpty) {
      params['broad'] = 'on';
    }

    // 后端要求 query/genre/sort 至少有一个
    if (!params.containsKey('query') &&
        !params.containsKey('sort') &&
        !params.containsKey('genre')) {
      params['query'] = '';
    }

    // 同一组筛选条件在短时间内重复请求时，直接用上次的结果，
    // 不用再等一次「CDP -> 解析」的往返
    final cacheKey = AppCache.buildKey('/api/filter', params);

    final cached = AppCache.get(cacheKey);

    if (cached is Map && cached['results'] is List) {
      setState(() {
        _results = List<Map<String, dynamic>>.from(
          cached['results'],
        );
        _loading = false;
        _error = null;
      });

      if (query.isNotEmpty) {
        _saveSearchHistory(query);
      }

      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
      final uri = Uri.parse(
        '${AppConfig.backendBase}/api/filter',
      ).replace(queryParameters: params);

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          '服务器返回错误: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      final results = List<Map<String, dynamic>>.from(
        data['results'] ?? [],
      );

      // 标签分组是搜索响应的附赠品（后端从同一个页面里解析出来的），
      // 这里顺手存下来，点「標籤」时就不用再单独请求一次了。
      final tagGroups = data['tag_groups'];

      if (tagGroups is List && tagGroups.isNotEmpty) {
        AppCache.set(
          _tagCacheKey,
          tagGroups,
          ttl: AppCache.tagsTtl,
        );

        if (mounted) {
          setState(() {
            _tagGroups = List<Map<String, dynamic>>.from(tagGroups);
            _tagsLoaded = true;
          });
        }
      }

      if (results.isNotEmpty) {
        AppCache.set(
          cacheKey,
          {
            'results': results,
            'total_pages': data['total_pages'],
          },
          ttl: AppCache.searchTtl,
        );
      }

      if (mounted) {
        setState(() {
          _results = results;
        });

        if (query.isNotEmpty) {
          _saveSearchHistory(query);
        }
      }      
    } catch (e) {
      if (mounted) {
        setState(() => _error = '搜索失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_historyKey) ?? [];

      if (mounted) {
        setState(() => _searchHistory = history);
      }
    } catch (_) {
      // 加载失败就用空列表
    }
  }

  Future<void> _saveSearchHistory(String keyword) async {
    final trimmed = keyword.trim();

    if (trimmed.isEmpty) return;

    // 去重 + 最新排前
    final updated = [
      trimmed,
      ..._searchHistory.where((k) => k != trimmed),
    ];

    if (updated.length > _maxHistoryCount) {
      updated.removeRange(_maxHistoryCount, updated.length);
    }

    setState(() => _searchHistory = updated);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_historyKey, updated);
    } catch (_) {
      // 持久化失败只影响下次启动
    }
  }

  Future<void> _removeSearchHistory(String keyword) async {
    final updated =
        _searchHistory.where((k) => k != keyword).toList();

    setState(() => _searchHistory = updated);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_historyKey, updated);
    } catch (_) {}
  }

  Future<void> _clearSearchHistory() async {
    setState(() => _searchHistory = []);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (_) {}
  }

  Future<void> _loadTags() async {
    if (_tagsLoaded) return;

    // 先看缓存（第一次搜索时已经顺手存下来了，正常情况都走这里，瞬间打开）
    final cached = AppCache.get(_tagCacheKey);

    if (cached is List && cached.isNotEmpty) {
      setState(() {
        _tagGroups = List<Map<String, dynamic>>.from(cached);
        _tagsLoaded = true;
      });

      return;
    }

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBase}/api/tags'),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '服务器返回错误: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      final groups = List<Map<String, dynamic>>.from(
        data['groups'] ?? [],
      );

      if (groups.isNotEmpty) {
        AppCache.set(
          _tagCacheKey,
          groups,
          ttl: AppCache.tagsTtl,
        );
      }

      if (!mounted) return;

      setState(() {
        _tagGroups = groups;
        _tagsLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标签加载失败：$e')),
      );
    }
  }

  Future<void> _showTagDialog() async {
    // 正常情况下标签已经在第一次搜索时随结果一起拿到了，
    // _loadTags() 会立刻返回，弹窗秒开。
    // 只有「搜索还没回来就先点标签」这种情况才会真的等待。
    final firstLoad = !_tagsLoaded;

    if (firstLoad) {
      // 先给个反馈，避免用户以为没点到
      setState(() => _tagsLoading = true);
    }

    await _loadTags();

    if (mounted) {
      setState(() => _tagsLoading = false);
    }

    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return SearchTagDialog(
          groups: _tagGroups,
          initialTags: _selectedTags,
          initialBroad: _broadMatch,
        );
      },
    );

    if (result == null) return;

    setState(() {
      _selectedTags =
          List<String>.from(result['tags'] ?? []);
      _broadMatch = result['broad'] == true;
    });

    if (_controller.text.trim().isNotEmpty) {
      _search();
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 筛选栏：始终靠左排列，视觉上统一成一组胶囊按钮。
  Widget _buildFilterBar() {
    final hasActiveFilter = _selectedGenre.isNotEmpty ||
        _selectedSort.isNotEmpty ||
        _selectedDate.isNotEmpty ||
        _selectedDuration.isNotEmpty ||
        _selectedTags.isNotEmpty;

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildDropdownFilter(
            label: '影片类型',
            currentValue: _selectedGenre,
            options: _genreOptions,
            onChanged: (v) {
              setState(() => _selectedGenre = v);
              _search();
            },
          ),
          _buildDropdownFilter(
            label: '排序',
            currentValue: _selectedSort,
            options: _sortOptions,
            onChanged: (v) {
              setState(() => _selectedSort = v);
              _search();
            },
          ),
          _buildDropdownFilter(
            label: '日期',
            currentValue: _selectedDate,
            options: _dateOptions,
            onChanged: (v) {
              setState(() => _selectedDate = v);
              _search();
            },
          ),
          _buildDropdownFilter(
            label: '時長',
            currentValue: _selectedDuration,
            options: _durationOptions,
            onChanged: (v) {
              setState(() => _selectedDuration = v);
              _search();
            },
          ),
          _buildTagButton(),
          if (hasActiveFilter) ...[
            // 和筛选按钮之间加一条细分隔线，把「重置」区分开
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            _buildResetButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    final theme = Theme.of(context);

    return TextButton.icon(
      onPressed: () {
        setState(() {
          _selectedGenre = '';
          _selectedSort = '';
          _selectedDate = '';
          _selectedDuration = '';
          _selectedTags = [];
          _broadMatch = false;
        });
        _search();
      },
      icon: const Icon(Icons.refresh, size: 15),
      label: const Text('重置'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, _FilterChipStyle.height),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: theme.colorScheme.error,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_FilterChipStyle.radius),
        ),
      ),
    );
  }

  /// 统一下拉筛选按钮：和「標籤」按钮共用同一套外观。
  Widget _buildDropdownFilter({
    required String label,
    required String currentValue,
    required List<Map<String, String>> options,
    required ValueChanged<String> onChanged,
  }) {
    final active = currentValue.isNotEmpty;

    return PopupMenuButton<String>(
      tooltip: label,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      onSelected: onChanged,
      itemBuilder: (context) {
        return _buildMenuItems(
          options: options,
          currentValue: currentValue,
        );
      },
      child: _FilterChip(
        labelPrefix: label,
        text: active ? currentValue : '',
        active: active,
        trailing: Icons.keyboard_arrow_down_rounded,
      ),
    );
  }

  /// 下拉菜单项：统一的圆角、选中高亮和图标。
  List<PopupMenuEntry<String>> _buildMenuItems({
    required List<Map<String, String>> options,
    required String currentValue,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return options.map((o) {
      final value = o['value']!;
      final isCurrent = value == currentValue;

      return PopupMenuItem<String>(
        value: value,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(
                isCurrent
                    ? Icons.check_rounded
                    : Icons.circle_outlined,
                size: 16,
                color: isCurrent
                    ? theme.colorScheme.primary
                    : (isDark
                        ? Colors.white24
                        : Colors.black26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  o['label']!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isCurrent
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildTagButton() {
    final active = _selectedTags.isNotEmpty;

    return InkWell(
      onTap: _tagsLoading ? null : _showTagDialog,
      borderRadius: BorderRadius.circular(_FilterChipStyle.radius),
      child: _FilterChip(
        labelPrefix: '標籤',
        text: active ? '已选 ${_selectedTags.length} 个' : '',
        active: active,
        trailing: Icons.keyboard_arrow_down_rounded,
        loading: _tagsLoading,
      ),
    );
  }

  int _columnsFor(double width) {
    if (_isPortraitCategory) {
      if (width >= 1600) return 8;
      if (width >= 1300) return 7;
      if (width >= 1000) return 5;
      if (width >= 750) return 4;
      if (width >= 500) return 2;
      return 1;
    }

    if (width >= 1600) return 6;
    if (width >= 1300) return 5;
    if (width >= 1000) return 4;
    if (width >= 750) return 3;
    if (width >= 500) return 2;
    return 1;
  }

  Widget _buildResultCard(Map<String, dynamic> video) {
    final thumbnail =
        video['thumbnail']?.toString() ?? '';
    final title = video['title']?.toString() ?? '';
    final duration =
        video['duration']?.toString() ?? '';
    final rating = video['rating']?.toString() ?? '';
    final views = video['views']?.toString() ?? '';

    final meta = [duration, rating, views]
        .where((v) => v.isNotEmpty)
        .join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final id = _extractVideoId(
            video['url']?.toString() ?? '',
          );

          if (id == null) return;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoDetailPage(videoId: id),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio:
                  _isPortraitCategory ? 268 / 394 : 16 / 9,
              child: thumbnail.isNotEmpty
                  ? Image.network(
                      thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image),
                      ),
                    )
                  : Container(
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (meta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryPanel() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),      
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              const Text(
                '搜索历史',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearSearchHistory,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _searchHistory.map((keyword) {
              return InputChip(
                label: Text(keyword),
                mouseCursor: SystemMouseCursors.click,
                deleteButtonTooltipMessage: '',
                onPressed: () {
                  _controller.text = keyword;
                  _searchFocusNode.unfocus();
                  setState(
                    () => _showHistoryPanel = false,
                  );
                  _search();
                },
                onDeleted: () => _removeSearchHistory(keyword),
                deleteIcon: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: const Icon(Icons.close, size: 16),
                ),
              );
            }).toList(),
          ),                   
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text('没有找到视频'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;

            // 搜索框宽度：窗口越宽越长，但不会无限拉长
            final searchBoxWidth =
                (availableWidth * 0.40).clamp(260.0, 520.0);

            // 搜索框永远居中，所以它的左边缘就是这个位置。
            // 历史浮层也按这个位置对齐。
            final searchBoxLeft =
                ((availableWidth - searchBoxWidth) / 2)
                    .clamp(0.0, availableWidth);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // ---- 主内容 ----
                Column(
                  children: [
                    // 搜索框单独占一行并居中：
                    // 这样无论窗口多宽多窄，左右留白都是相等的。
                    // （之前搜索框和筛选栏挤在同一行，宽度一变就偏了）
                    Center(
                      child: SizedBox(
                        height: 56,
                        width: searchBoxWidth,
                        child: TapRegion(
                          groupId: 'search_history',
                          child: TextField(
                            controller: _controller,
                            focusNode: _searchFocusNode,
                            textAlignVertical:
                                TextAlignVertical.center,
                            decoration: InputDecoration(
                              labelText: '主人点击我就能色色了哦',
                              hintText: 'Hentai杂鱼主人又在看羞羞的东西',
                              border: const OutlineInputBorder(),
                              // 给右侧的搜索/清空按钮留出位置，
                              // 否则输入的文字会被按钮压住
                              contentPadding: const EdgeInsets.only(
                                left: 12,
                                right: 88,
                                top: 16,
                                bottom: 16,
                              ),
                              suffixIconConstraints:
                                  const BoxConstraints(
                                minWidth: 0,
                                minHeight: 0,
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_controller.text.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        size: 20,
                                      ),
                                      tooltip: '清空',
                                      onPressed: () {
                                        setState(() {
                                          _controller.clear();
                                        });
                                      },
                                    ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.search,
                                      size: 20,
                                    ),
                                    tooltip: '搜索',
                                    onPressed:
                                        _loading ? null : _search,
                                  ),
                                ],
                              ),
                            ),
                            onChanged: (_) {
                              setState(() {});
                            },
                            onTap: () {
                              setState(
                                () => _showHistoryPanel = true,
                              );
                            },
                            onSubmitted: (_) => _search(),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 筛选栏占满整行并靠左排列：
                    // 不再跟着搜索框一起居中，这样窗口怎么变都是贴左边对齐的。
                    _buildFilterBar(),

                    const SizedBox(height: 20),

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),

                    // ---- 结果区 ----
                    Expanded(
                      child: _loading
                          ? const Align(
                              alignment: Alignment(0, -0.2),
                              child: Windows11Loading(size: 56),
                            )
                          : _results.isEmpty
                              ? _buildEmptyState()
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    final columns = _columnsFor(
                                        constraints.maxWidth);

                                    const crossAxisSpacing = 12.0;

                                    final availableWidth =
                                        constraints.maxWidth -
                                            crossAxisSpacing *
                                                (columns - 1);
                                    final itemWidth =
                                        availableWidth / columns;
                                    final thumbnailHeight =
                                        _isPortraitCategory
                                            ? itemWidth * 394 / 268
                                            : itemWidth * 9 / 16;
                                    final itemHeight =
                                        thumbnailHeight + 92;

                                    return GridView.builder(
                                      padding: EdgeInsets.zero,
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        crossAxisSpacing: crossAxisSpacing,
                                        mainAxisSpacing: 12,
                                        mainAxisExtent: itemHeight,
                                      ),
                                      itemCount: _results.length,
                                      itemBuilder: (_, index) =>
                                          _buildResultCard(
                                              _results[index]),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),

                // ---- 搜索历史浮层（Stack 最上层） ----
                if (_showHistoryPanel && _searchHistory.isNotEmpty)
                  Positioned(
                    top: 64,
                    left: searchBoxLeft,
                    width: searchBoxWidth,
                    child: TapRegion(
                      groupId: 'search_history',
                      onTapOutside: (_) {
                        if (mounted) {
                          setState(
                            () => _showHistoryPanel = false,
                          );
                        }
                      },
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context).brightness ==
                                Brightness.dark
                            ? const Color(0xFF2A2A2A)
                            : Colors.white,
                        clipBehavior: Clip.antiAlias,
                        child: _buildHistoryPanel(),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SearchTagDialog extends StatefulWidget {
  final List<Map<String, dynamic>> groups;
  final List<String> initialTags;
  final bool initialBroad;

  const SearchTagDialog({
    super.key,
    required this.groups,
    required this.initialTags,
    required this.initialBroad,
  });

  @override
  State<SearchTagDialog> createState() =>
      _SearchTagDialogState();
}

class _SearchTagDialogState
    extends State<SearchTagDialog> {
  late Set<String> _selected;
  late bool _broad;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialTags);
    _broad = widget.initialBroad;
  }

  void _toggle(String tag) {
    setState(() {
      if (_selected.contains(tag)) {
        _selected.remove(tag);
      } else {
        _selected.add(tag);
      }
    });
  }

  void _clear() {
    setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择标签'),
      content: SizedBox(
        width: 700,
        height: 600,
        child: Column(
          children: [
            Row(
              children: [
                Switch(
                  value: _broad,
                  onChanged: (v) {
                    setState(() => _broad = v);
                  },
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '廣泛配對（符合任一標籤即可，預設需全部符合）',
                  ),
                ),
                TextButton.icon(
                  onPressed: _selected.isEmpty ? null : _clear,
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('清空'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: widget.groups.length,
                itemBuilder: (_, index) {
                  final group = widget.groups[index];
                  final name =
                      group['name']?.toString() ?? '';
                  final tags = List<String>.from(
                    group['tags'] ?? [],
                  );

                  return Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          0,
                          12,
                          0,
                          8,
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tags.map((tag) {
                          final checked =
                              _selected.contains(tag);

                          return FilterChip(
                            label: Text(tag),
                            selected: checked,
                            onSelected: (_) => _toggle(tag),
                          );
                        }).toList(),
                      ),
                      const Divider(height: 24),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop({
              'tags': _selected.toList(),
              'broad': _broad,
            });
          },
          child: const Text('確定'),
        ),
      ],
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() =>
      _HistoryPageState();
}

class _HistoryPageState
    extends State<HistoryPage> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  /// 数据来自哪里。
  ///
  /// - `online`：登录后直接读官网的「觀看紀錄」，和「个人主页 → 观看记录」
  ///   是同一份数据（同一个接口）。
  /// - `local`：未登录时用本地记录兜底
  ///   （本地只记自己看过的，没有账号也就没有官网记录）。
  String _source = 'local';

  int _page = 1;
  int _totalPages = 1;

  bool get _isOnline => _source == 'online';

  @override
  void initState() {
    super.initState();

    // 账号切换后要重新取（这个页面会被重建，但保险起见仍然监听）
    AuthController.account.addListener(_onAccountChanged);

    _loadHistory();
  }

  @override
  void dispose() {
    AuthController.account.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) _loadHistory();
  }

  Future<void> _loadHistory({int page = 1}) async {
    final info = AuthController.account.value;

    if (info.loggedIn && info.userId.isNotEmpty) {
      await _loadOnline(info.userId, page: page);
    } else {
      await _loadLocal();
    }
  }

  /// 读官网的观看记录（和个人主页「观看记录」同一个接口、同一份数据）。
  Future<void> _loadOnline(String userId, {int page = 1}) async {
    final target = page < 1 ? 1 : page;

    setState(() {
      _loading = true;
    });

    try {
      final uri = Uri.parse('${AppConfig.backendBase}/api/user/$userId')
          .replace(
        queryParameters: {
          'tab': 'histories',
          'page': '$target',
        },
      );

      final response = await http.get(uri).timeout(
            const Duration(seconds: 90),
          );

      if (response.statusCode != 200) {
        throw Exception('服务器返回错误: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      if (data is! Map) {
        throw Exception('返回数据格式不正确');
      }

      final videos = List<Map<String, dynamic>>.from(
        data['videos'] ?? [],
      );

      final totalPages =
          int.tryParse('${data['total_pages']}') ?? 1;

      if (!mounted) return;

      setState(() {
        _history = videos;
        _source = 'online';
        _page = target;
        _totalPages = totalPages < 1 ? 1 : totalPages;
        _loading = false;
      });
    } catch (_) {
      // 网络失败时退回本地，至少还能看到自己看过的
      await _loadLocal();
    }
  }

  /// 未登录时的本地记录。
  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final raw = prefs.getStringList(
            AccountScope.key('watch_history'),
          ) ??
          [];

      final result = <Map<String, dynamic>>[];

      for (final item in raw) {
        try {
          final decoded = jsonDecode(item);

          if (decoded is Map) {
            result.add(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _history = result;
        _source = 'local';
        _page = 1;
        _totalPages = 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatTime(
    String? value,
  ) {
    if (value == null ||
        value.isEmpty) {
      return '';
    }

    final time =
        DateTime.tryParse(value);

    if (time == null) {
      return value;
    }

    final local =
        time.toLocal();

    String two(int n) =>
        n.toString().padLeft(
          2,
          '0',
        );

    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  void _open(
    Map<String, dynamic> item,
  ) {
    // 本地记录存的是 video_id；官网记录给的是 url，这里两种都支持
    var id = item['video_id']?.toString() ?? '';

    if (id.isEmpty) {
      final url = item['url']?.toString() ?? '';

      if (url.isNotEmpty) {
        id = Uri.tryParse(url)?.queryParameters['v'] ?? '';
      }
    }

    if (id.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(videoId: id),
      ),
    ).then((_) => _loadHistory());
  }

  Future<void> _clearHistory() async {
    // 官网的观看记录只能到官网上清，本地没有权限改，
    // 所以登录状态下不发这个按钮（见 build）。
    if (_isOnline) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(
      AccountScope.key('watch_history'),
    );

    if (mounted) {
      setState(() => _history = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Windows11Loading(size: 48),
      );
    }

    if (_history.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView(
          children: [
            const SizedBox(height: 180),
            Center(
              child: Text(
                _isOnline ? '这个账号还没有观看记录' : '暂无观看记录',
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 「清空」只对本地记录有意义；官网记录要在官网上清
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Row(
            children: [
              Text(
                _isOnline ? '观看记录（与个人主页一致）' : '观看记录（本地）',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              if (!_isOnline)
                TextButton.icon(
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清空历史'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding:
                const EdgeInsets.all(24),
            itemCount:
                _history.length,
            itemBuilder: (_, index) {
              final item =
                  _history[index];

              final title =
                  item['title']
                          ?.toString() ??
                      '';

              final thumbnail =
                  item['thumbnail']
                          ?.toString() ??
                      '';

              final brand =
                  item['brand']
                          ?.toString() ??
                      '';

              final lastWatched =
                  item['last_watched']
                      ?.toString();

              // 官网记录带的是时长/播放量，本地记录带的是品牌/观看时间
              final duration =
                  item['duration']?.toString() ?? '';

              final views =
                  item['views']?.toString() ?? '';

              // 用 Row 手写而不是 ListTile：
              // ListTile 会对 leading 施加自己的尺寸约束，
              // 我们想要的 16:9 缩略图有可能被压/被裁。
              // 手写 Row 能保证缩略图就是固定 160x90（16:9）。
              final meta = [
                if (brand.isNotEmpty) '品牌：$brand',
                if (lastWatched != null)
                  '观看时间：${_formatTime(lastWatched)}',
                if (_isOnline) ...[
                  if (duration.isNotEmpty) duration,
                  if (views.isNotEmpty) views,
                ],
              ];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _open(item),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 缩略图固定 16:9，和首页/个人中心保持一致
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 160,
                            height: 90,
                            child: thumbnail.isNotEmpty
                                ? Image.network(
                                    thumbnail,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: Colors.black12,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.broken_image,
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: Colors.black12,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.play_circle_outline,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (meta.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  meta.join('\n'),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.62),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // 官网观看记录每页 60 条，页数多，必须能翻页
        if (_isOnline && _totalPages > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '上一页',
                  onPressed: (_page > 1 && !_loading)
                      ? () => _loadHistory(page: _page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                const SizedBox(width: 8),
                Text('第 $_page / $_totalPages 页'),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '下一页',
                  onPressed: (_page < _totalPages && !_loading)
                      ? () => _loadHistory(page: _page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '外观',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '选择应用的配色方案',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.mode,
          builder: (context, mode, _) {
            return Column(
              children: [
                _ThemeOptionTile(
                  icon: Icons.brightness_auto,
                  title: '跟随系统',
                  subtitle: '根据系统设置自动切换',
                  selected: mode == ThemeMode.system,
                  onTap: () => ThemeController.setMode(
                    ThemeMode.system,
                  ),
                ),
                _ThemeOptionTile(
                  icon: Icons.light_mode_outlined,
                  title: '浅色',
                  subtitle: '始终使用浅色主题',
                  selected: mode == ThemeMode.light,
                  onTap: () => ThemeController.setMode(
                    ThemeMode.light,
                  ),
                ),
                _ThemeOptionTile(
                  icon: Icons.dark_mode_outlined,
                  title: '深色',
                  subtitle: '始终使用深色主题',
                  selected: mode == ThemeMode.dark,
                  onTap: () => ThemeController.setMode(
                    ThemeMode.dark,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: selected
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderPage
    extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _PlaceholderPage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(message),
        ],
      ),
    );
  }
}

class VideoDetailPage
    extends StatefulWidget {
  final String videoId;

  const VideoDetailPage({
    super.key,
    required this.videoId,
  });

  @override
  State<VideoDetailPage>
      createState() =>
          _VideoDetailPageState();
}

class _VideoDetailPageState
    extends State<VideoDetailPage> {
  Map<String, dynamic>? _video;

  List<Map<String, dynamic>> _playlist = [];

  bool _loading = true;
  String? _error;

  /// 点赞 / 储存请求进行中
  bool _acting = false;

  /// 本影片详情在 AppCache 里的 key
  String get _detailCacheKey => 'video_detail_${widget.videoId}';

  VideoPlayerController?
      _videoPlayerController;

  DateTime? _lastSavedPosition;

  bool _showVideoCover = true;

  /// 播完当前影片是否自动播下一集（目前固定开启，暂无设置项）
  final bool _autoPlayNext = true;

  final ScrollController _playlistScrollController =
      ScrollController();

  final Map<String, GlobalKey> _playlistKeys = {};

  double _volume = 1.0;

  bool _showVolumeSlider = false;
  Timer? _volumeHideTimer;
  bool _showControls = true;
  Timer? _controlsTimer;

  List<Map<String, dynamic>> _availableSources = [];
  String _currentQuality = '';
  bool _switchingQuality = false;
  bool _progressHovering = false;
  double _progressHoverRatio = 0.0;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendBase}/api/video/${widget.videoId}',
      );

      final response =
          await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          '服务器返回错误: ${response.statusCode}',
        );
      }

      final data =
          jsonDecode(response.body);

      final playlist =
          List<Map<String, dynamic>>.from(
        data['playlist'] ?? [],
      );

      if (!mounted) return;

      setState(() {
        _video =
            Map<String, dynamic>.from(
          data,
        );

        _playlist = playlist;

        _availableSources =
            List<Map<String, dynamic>>.from(
          data['sources'] ?? [],
        );

        if (_availableSources.isNotEmpty) {
          _currentQuality =
              _availableSources.first['quality']
                      ?.toString() ??
                  '';
        }
      });

      _scrollToCurrentVideo();

      final videoSource =
          data['video_source']
                  ?.toString() ??
              '';

      if (videoSource.isEmpty) {
        throw Exception(
          '没有获取到视频地址',
        );
      }

      await _saveToWatchHistory(
        data,
      );

      await _initializePlayer(
        videoSource,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error =
            '加载视频详情失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveToWatchHistory(
    Map<String, dynamic> data,
  ) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    final history =
        prefs.getStringList(
              AccountScope.key('watch_history'),
            ) ??
            [];

    final title =
        data['title']
                ?.toString() ??
            '';

    final thumbnail =
        data['thumbnail']
                ?.toString() ??
            '';

    final brand =
        data['brand']
                ?.toString() ??
            '';

    final item = jsonEncode({
      'video_id':
          widget.videoId,
      'title': title,
      'thumbnail':
          thumbnail,
      'brand': brand,
      'last_watched':
          DateTime.now()
              .toIso8601String(),
    });

    history.removeWhere((value) {
      try {
        final oldItem =
            jsonDecode(value);

        return oldItem[
                    'video_id']
                ?.toString() ==
            widget.videoId;
      } catch (_) {
        return false;
      }
    });

    history.insert(
      0,
      item,
    );

    if (history.length > 100) {
      history.removeRange(
        100,
        history.length,
      );
    }

    await prefs.setStringList(
      AccountScope.key('watch_history'),
      history,
    );
  }

  Future<void> _initializePlayer(
    String videoSource,
  ) async {
    final uri =
        Uri.tryParse(videoSource);

    if (uri == null) {
      throw Exception(
        '视频地址无效',
      );
    }

    final controller =
        VideoPlayerController
            .networkUrl(uri);

    _videoPlayerController =
        controller;

    await controller.initialize();

    await _restorePlaybackPosition();

    controller.addListener(
      _onVideoPositionChanged,
    );

    controller.addListener(
      _onVideoCompleted,
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _changeQuality(String newQuality) async {
    if (_switchingQuality) {
      return;
    }

    final source = _availableSources.firstWhere(
      (s) => s['quality'] == newQuality,
      orElse: () => <String, dynamic>{},
    );

    final newUrl = source['url']?.toString();

    if (newUrl == null || newUrl.isEmpty) {
      return;
    }

    final oldController = _videoPlayerController;

    if (oldController == null) {
      return;
    }

    final wasPlaying = oldController.value.isPlaying;
    final position = oldController.value.position;

    setState(() {
      _currentQuality = newQuality;
      _switchingQuality = true;
    });

    // 移除旧监听，避免 dispose 后仍被回调
    oldController.removeListener(_onVideoPositionChanged);
    oldController.removeListener(_onVideoCompleted);

    // 先准备好新控制器（此时 UI 显示中转画面，不再引用旧控制器）
    final newController = VideoPlayerController.networkUrl(
      Uri.parse(newUrl),
    );

    await newController.initialize();
    await newController.seekTo(position);
    newController.setVolume(_volume);

    newController.addListener(_onVideoPositionChanged);
    newController.addListener(_onVideoCompleted);

    _videoPlayerController = newController;

    if (wasPlaying) {
      await newController.play();
    }

    // 新控制器就绪后，才销毁旧的
    await oldController.pause();
    await oldController.dispose();

    if (mounted) {
      setState(() {
        _switchingQuality = false;
      });
    }
  }
  
  Future<void>
      _restorePlaybackPosition() async {
    final controller =
        _videoPlayerController;

    if (controller == null ||
        !controller
            .value
            .isInitialized) {
      return;
    }

    final prefs =
        await SharedPreferences
            .getInstance();

    // 播放进度也要跟着账号走：
    // 同一个影片，账号 A 看到 12:30，账号 B 不该被带过去
    final key = AccountScope.scopedKey(
      'video_position',
      widget.videoId,
    );

    final savedSeconds =
        prefs.getInt(key);

    if (savedSeconds == null ||
        savedSeconds <= 0) {
      return;
    }

    final duration =
        controller.value.duration;

    if (duration ==
        Duration.zero) {
      return;
    }

    final savedPosition =
        Duration(
      seconds: savedSeconds,
    );

    if (savedPosition < duration) {
      await controller.seekTo(
        savedPosition,
      );
    }
  }

  void _onVideoPositionChanged() {
    final controller = _videoPlayerController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    final position = controller.value.position;

    if (position <= Duration.zero) {
      return;
    }

    final now = DateTime.now();

    if (_lastSavedPosition != null &&
        now.difference(_lastSavedPosition!).inSeconds < 2) {
      return;
    }

    _lastSavedPosition = now;

    _savePlaybackPosition();

    if (controller.value.position >= controller.value.duration) {
      _onVideoCompleted();
    }
  }

  void _onVideoCompleted() {
    final controller = _videoPlayerController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    if (!_autoPlayNext) {
      return;
    }

    if (controller.value.position >=
        controller.value.duration) {
      _playNextVideo();
    }
  }

  Future<void> _playNextVideo() async {
    final currentIndex =
        _playlist.indexWhere(
      (item) =>
          item['video_id']?.toString() ==
          widget.videoId,
    );

    if (currentIndex == -1) {
      return;
    }

    final nextIndex = currentIndex - 1;

    if (nextIndex < 0) {
      return;
    }

    final nextVideoId =
        _playlist[nextIndex]['video_id']
            ?.toString();

    if (nextVideoId == null ||
        nextVideoId.isEmpty) {
      return;
    }

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoDetailPage(
          videoId: nextVideoId,
        ),
      ),
    );
  }

  Future<void>
      _savePlaybackPosition() async {
    final controller =
        _videoPlayerController;

    if (controller == null ||
        !controller
            .value
            .isInitialized) {
      return;
    }

    final position =
        controller.value.position;

    if (position <=
        Duration.zero) {
      return;
    }

    final prefs =
        await SharedPreferences
            .getInstance();

    // 播放进度也要跟着账号走：
    // 同一个影片，账号 A 看到 12:30，账号 B 不该被带过去
    final key = AccountScope.scopedKey(
      'video_position',
      widget.videoId,
    );

    await prefs.setInt(
      key,
      position.inSeconds,
    );
  }

  Future<void> _startVideo() async {
    final controller =
        _videoPlayerController;

    if (controller == null ||
        !controller
            .value
            .isInitialized) {
      return;
    }

    setState(() {
      _showVideoCover = false;
    });

    await controller.play();
  }

  Future<void> _openPlaylistVideo(
    String videoId,
  ) async {
    if (videoId.isEmpty ||
        videoId == widget.videoId) {
      return;
    }

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoDetailPage(
          videoId: videoId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _savePlaybackPosition();

    _controlsTimer?.cancel();
    _volumeHideTimer?.cancel();

    _videoPlayerController
        ?.removeListener(
      _onVideoPositionChanged,
    );

    _videoPlayerController
        ?.dispose();

    _playlistScrollController.dispose();

    super.dispose();
  }

  String _formatDuration(Duration duration) {
    return formatPlaybackDuration(duration);
  }

  void _showPlayerControls() {
    setState(() {
      _showControls = true;
    });

    _controlsTimer?.cancel();
    _controlsTimer = Timer(
      const Duration(seconds: 3),
      () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      },
    );
  }

  Widget _buildVideoPlayer() {
    if (_switchingQuality) {
      return Container(
        width: double.infinity,
        height: 420,
        color: Colors.black,
        alignment: Alignment.center,
        child: const Windows11Loading(
          size: 48,
          color: Colors.white,
        ),
      );
    }

    final controller = _videoPlayerController;

    if (controller == null || !controller.value.isInitialized) {
      return Container(
        width: double.infinity,
        height: 420,
        color: Colors.black,
        alignment: Alignment.center,
        child: const Windows11Loading(
          size: 48,
          color: Colors.white,
        ),
      );
    }

    final thumbnail =
        _video?['thumbnail']?.toString() ?? '';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            MouseRegion(
              onHover: (_) => _showPlayerControls(),
              child: Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, child) {
                if (!value.isInitialized ||
                    value.duration.inMilliseconds <= 0) {
                  return const SizedBox();
                }

                final progress = value.position.inMilliseconds /
                    value.duration.inMilliseconds;

                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _showControls ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(
                          Colors.red,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildPlayerControls(),
              ),
            if (_showVideoCover)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _startVideo,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumbnail.isNotEmpty)
                        Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.black,
                          ),
                        )
                      else
                        Container(color: Colors.black),
                      Container(color: Colors.black26),
                      const Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 42,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerControls() {
    final controller = _videoPlayerController;

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final position = controller.value.position;
    final duration = controller.value.duration;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnorePointer(
          child: Container(
            height: 16,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black54,
                ],
              ),
            ),
          ),
        ),
        Container(
          color: Colors.black54,
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;

                  return MouseRegion(
                    onHover: (event) {
                      final dx = event.localPosition.dx;
                      final ratio = (dx / trackWidth).clamp(0.0, 1.0);

                      if (!_progressHovering ||
                          (_progressHoverRatio - ratio).abs() > 0.002) {
                        setState(() {
                          _progressHovering = true;
                          _progressHoverRatio = ratio;
                        });
                      }
                    },
                    onExit: (_) {
                      if (_progressHovering) {
                        setState(() {
                          _progressHovering = false;
                        });
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                        ),
                        if (_progressHovering)
                          Positioned(
                            left: (trackWidth * _progressHoverRatio - 30)
                                .clamp(0.0, trackWidth - 60),
                            top: -26,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                _formatDuration(
                                  Duration(
                                    milliseconds: (duration.inMilliseconds *
                                            _progressHoverRatio)
                                        .round(),
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    onPressed: () {
                      setState(() {
                        if (controller.value.isPlaying) {
                          controller.pause();
                        } else {
                          controller.play();
                          _showVideoCover = false;
                        }
                      });
                    },
                  ),
                  MouseRegion(
                    onEnter: (_) {
                      _volumeHideTimer?.cancel();
                      if (!_showVolumeSlider) {
                        setState(() => _showVolumeSlider = true);
                      }
                    },
                    onExit: (_) {
                      _volumeHideTimer?.cancel();
                      _volumeHideTimer = Timer(
                        const Duration(milliseconds: 150),
                        () {
                          if (mounted && _showVolumeSlider) {
                            setState(() => _showVolumeSlider = false);
                          }
                        },
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          color: Colors.white,
                          icon: Icon(
                            _volume == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                          ),
                          onPressed: () {
                            setState(() {
                              _volume = _volume == 0 ? 1 : 0;
                              controller.setVolume(_volume);
                            });
                          },
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          alignment: Alignment.centerLeft,
                          child: _showVolumeSlider
                              ? SizedBox(
                                  width: 80,
                                  height: 40,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.0,
                                      activeTrackColor: Colors.red,
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: Colors.red,
                                      overlayColor:
                                          Colors.red.withValues(alpha: 0.2),
                                      thumbShape:
                                          const RoundSliderThumbShape(
                                        enabledThumbRadius: 6.0,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                        overlayRadius: 12.0,
                                      ),
                                    ),
                                    child: Slider(
                                      value: _volume,
                                      min: 0,
                                      max: 1,
                                      onChanged: (value) {
                                        setState(() {
                                          _volume = value;
                                          controller.setVolume(value);
                                        });
                                      },
                                    ),
                                  ),
                                )
                              : const SizedBox(width: 0, height: 40),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  if (_availableSources.isNotEmpty)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.high_quality,
                        color: Colors.white,
                      ),
                      tooltip: '选择画质',
                      onSelected: _changeQuality,
                      itemBuilder: (context) {
                        return _availableSources.map((source) {
                          final quality =
                              source['quality']?.toString() ?? '';

                          return PopupMenuItem<String>(
                            value: quality,
                            child: Row(
                              children: [
                                if (quality == _currentQuality)
                                  const Icon(
                                    Icons.check,
                                    size: 18,
                                    color: Colors.green,
                                  )
                                else
                                  const SizedBox(width: 18),
                                const SizedBox(width: 8),
                                Text(quality),
                              ],
                            ),
                          );
                        }).toList();
                      },
                    ),
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.fullscreen),
                    onPressed: _showFullscreenPlayer,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showFullscreenPlayer() async {
    final controller = _videoPlayerController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    await windowManager.setFullScreen(true);

    // setFullScreen 是异步的，这期间页面可能已经被关掉，
    // 所以用 context 之前必须确认还挂着。
    if (!mounted) return;

    final navigator = Navigator.of(context);

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => _FullscreenPlayerPage(
          controller: controller,
          availableSources: _availableSources,
          currentQuality: _currentQuality,
          volume: _volume,
          onControllerChanged: (newController, newQuality) {
            if (!mounted) return;

            setState(() {
              _videoPlayerController = newController;
              _currentQuality = newQuality;
            });

            newController.addListener(_onVideoPositionChanged);
            newController.addListener(_onVideoCompleted);
          },
          onVolumeChanged: (newVolume) {
            if (!mounted) return;

            setState(() {
              _volume = newVolume;
            });
          },
        ),
      ),
    );

    await windowManager.setFullScreen(false);
  }
  void _scrollToCurrentVideo() {
    final key =
        _playlistKeys[widget.videoId];

    if (key == null) {
      return;
    }

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      final context = key.currentContext;

      if (context == null) {
        return;
      }

      Scrollable.ensureVisible(
        context,
        duration:
            const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    });
  }

  Widget _buildPlaylistPanel() {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.fromLTRB(
              14,
              12,
              14,
              12,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.playlist_play,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '播放清单',
                    style:
                        const TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${_playlist.length} 集',
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
          ),
          if (_playlist.isEmpty)
            const Padding(
              padding:
                  EdgeInsets.all(20),
              child: Text(
                '没有获取到播放清单',
                textAlign:
                    TextAlign.center,
              ),
            )
          else
            ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxHeight: 520,
              ),
              child: ListView.builder(
                controller: _playlistScrollController,
                shrinkWrap: true,
                itemCount:
                    _playlist.length,
                itemBuilder: (
                  context,
                  index,
                ) {
                  return _buildPlaylistItem(
                    _playlist[index],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaylistItem(
    Map<String, dynamic> item,
  ) {
    final videoId =
        item['video_id']
                ?.toString() ??
            '';

    final title =
        item['title']
                ?.toString() ??
            '';

    final thumbnail =
        item['thumbnail']
                ?.toString() ??
            '';

    final duration =
        item['duration']
                ?.toString() ??
            '';

    final rating =
        item['rating']
                ?.toString() ??
            '';

    final views =
        item['views']
                ?.toString() ??
            '';

    final current =
        videoId == widget.videoId;

    final itemKey =
        _playlistKeys.putIfAbsent(
          videoId,
          () => GlobalKey(),
        );

    return Material(
      key: itemKey,
      color: current
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: current
            ? null
            : () => _openPlaylistVideo(
                  videoId,
                ),
        child: Padding(
          padding:
              const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                height: 70,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumbnail.isNotEmpty)
                      Image.network(
                        thumbnail,
                        fit: BoxFit.cover,
                        errorBuilder: (
                          _,
                          _,
                          _,
                        ) =>
                            Container(
                          color:
                              Colors.black12,
                          alignment:
                              Alignment.center,
                          child: const Icon(
                            Icons
                                .broken_image,
                          ),
                        ),
                      )
                    else
                      Container(
                        color:
                            Colors.black12,
                        alignment:
                            Alignment.center,
                        child: const Icon(
                          Icons.image,
                        ),
                      ),
                    if (duration.isNotEmpty)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          color:
                              Colors.black87,
                          child: Text(
                            duration,
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    if (current)
                      Positioned.fill(
                        child: Container(
                          color:
                              Colors.black38,
                          alignment:
                              Alignment.center,
                          child:
                              const Icon(
                            Icons
                                .play_arrow,
                            color:
                                Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          TextStyle(
                        fontSize: 13,
                        fontWeight: current
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(
                      height: 6,
                    ),
                    if (rating.isNotEmpty)
                      Text(
                        rating,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors
                              .grey.shade700,
                        ),
                      ),
                    if (views.isNotEmpty)
                      Text(
                        views,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors
                              .grey.shade700,
                        ),
                      ),
                    if (current)
                      Padding(
                        padding:
                            const EdgeInsets
                                .only(
                          top: 4,
                        ),
                        child: Text(
                          '正在播放',
                          style:
                              TextStyle(
                            fontSize: 11,
                            fontWeight:
                                FontWeight.bold,
                            color: Theme.of(
                                    context)
                                .colorScheme
                                .primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    final video = _video!;

    final brand =
        video['brand']
                ?.toString() ??
            '';

    final releaseDate =
        video['release_date']
                ?.toString() ??
            '';

    final uploader =
        video['uploader']
                ?.toString() ??
            '';

    final views =
        video['views']
                ?.toString() ??
            '';

    final tags =
        List<String>.from(
      video['tags'] ?? [],
    );

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        _InfoRow(
          label: '品牌',
          value: brand,
        ),
        _InfoRow(
          label: '上传者',
          value: uploader,
        ),
        _InfoRow(
          label: '观看次数',
          value: views,
        ),
        _InfoRow(
          label: '发行日期',
          value: releaseDate,
        ),
        const SizedBox(
          height: 16,
        ),
        const Text(
          '标签',
          style: TextStyle(
            fontSize: 18,
            fontWeight:
                FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags
              .map(
                (tag) => Chip(
                  label: Text(tag),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
      ),      
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Windows11Loading(size: 48),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.all(24),
          child: Text(
            _error!,
            style:
                const TextStyle(
              color: Colors.red,
            ),
          ),
        ),
      );
    }

    if (_video == null) {
      return const Center(
        child: Text(
          '没有获取到视频信息',
        ),
      );
    }

    final title =
        _video!['title']
                ?.toString() ??
            '';

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final wide =
            constraints.maxWidth >= 1000;

        return SingleChildScrollView(
          padding:
              const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                        context)
                    .textTheme
                    .headlineMedium,
              ),
              const SizedBox(
                height: 20,
              ),
              if (wide)
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          _buildVideoPlayer(),
                        ],
                      ),
                    ),
                    const SizedBox(
                      width: 16,
                    ),
                    SizedBox(
                      width: 340,
                      child:
                          _buildPlaylistPanel(),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _buildVideoPlayer(),
                    const SizedBox(
                      height: 16,
                    ),
                    _buildPlaylistPanel(),
                  ],
                ),
              const SizedBox(
                height: 16,
              ),

              // 播放器下方的操作条：发行商头像 + 点赞/储存/下载
              // 对应官网播放器下面那一排按钮
              _buildActionBar(),

              const SizedBox(
                height: 24,
              ),
              _buildInfoSection(),

              const SizedBox(
                height: 32,
              ),

              // 相关影片（和官网一样放在详情下方）
              _buildRelatedSection(),
            ],
          ),
        );
      },
    );
  }

  /// 播放器下方操作条：左边是发行商头像（可点击进入主页），
  /// 右边是点赞比例、储存、下载。
  Widget _buildActionBar() {
    final video = _video!;

    final artistName = video['brand']?.toString() ?? '';
    final artistUrl = video['artist_url']?.toString() ?? '';
    final artistAvatar = video['artist_avatar']?.toString() ?? '';

    final likeRatio = video['like_ratio']?.toString() ?? '';
    final likeCount = video['like_count']?.toString() ?? '';

    final downloadUrl = video['download_url']?.toString() ?? '';

    final hasArtist = artistName.isNotEmpty;
    final hasLike = likeCount.isNotEmpty || likeRatio.isNotEmpty;

    if (!hasArtist && !hasLike && downloadUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasArtist) _buildArtistChip(artistName, artistAvatar, artistUrl),

        // 点赞 / 储存：登录后可以真正生效
        if (hasLike)
          _ActionChip(
            icon: Icons.thumb_up_outlined,
            label: '点赞',
            trailing: likeRatio.isNotEmpty
                ? '$likeRatio${likeCount.isNotEmpty ? ' · $likeCount' : ''}'
                : likeCount,
            color: theme.colorScheme.primary,
            busy: _acting,
            onTap: _acting ? null : () => _doVideoAction('like'),
          ),

        _ActionChip(
          icon: Icons.playlist_add,
          label: '储存',
          tooltip: '把影片存进你的播放清单',
          busy: _acting,
          onTap: _acting ? null : () => _doVideoAction('save'),
        ),

        if (downloadUrl.isNotEmpty)
          _ActionChip(
            icon: Icons.download_outlined,
            label: '下载',
            tooltip: downloadUrl,
          ),
      ],
    );
  }

  /// 执行点赞 / 储存。
  ///
  /// 没登录就先引导登录——不假装成功。
  Future<void> _doVideoAction(String action) async {
    if (!AuthController.isLoggedIn) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => const LoginDialog(),
      );

      if (ok != true || !mounted) return;
    }

    setState(() => _acting = true);

    try {
      final response = await http
          .post(
            Uri.parse(
              '${AppConfig.backendBase}/api/video/${widget.videoId}/action',
            ),
            headers: const {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'action': action}),
          )
          .timeout(const Duration(seconds: 120));

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        final detail =
            data is Map ? data['detail']?.toString() : null;

        throw Exception(detail ?? '操作失败（${response.statusCode}）');
      }

      if (!mounted) return;

      final message =
          (data is Map ? data['message']?.toString() : null) ?? '完成';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      // 播放清单会变，清掉详情与用户主页缓存后重新加载
      AppCache.removeWherePrefix('/api/user/');
      AppCache.remove(_detailCacheKey);

      await _loadVideo();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  /// 发行商/品牌：头像 + 名称，点击在 APP 内打开发行商主页。
  Widget _buildArtistChip(
    String name,
    String avatar,
    String url,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final artistId = _video!['artist_id']?.toString() ?? '';

    return Tooltip(
      message: artistId.isEmpty ? name : '查看 $name 的主页',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: artistId.isEmpty
            ? null
            : () {
                // 在 APP 内打开，不再跳到外部浏览器
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfilePage(
                      userId: artistId,
                      initialName: name,
                    ),
                  ),
                );
              },
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? Colors.white12 : const Color(0xFFE2E4E8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: avatar.isEmpty
                      ? Container(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.15),
                          child: Icon(
                            Icons.storefront_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Image.network(
                          avatar,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.15),
                            child: Icon(
                              Icons.storefront_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '发行商',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 相关影片：官网从同一个页面里就能解析出来，不需要额外请求。
  Widget _buildRelatedSection() {
    final related = List<Map<String, dynamic>>.from(
      _video!['related'] ?? [],
    );

    if (related.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text(
              '相关影片',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${related.length}',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // 卡片宽度固定，列数随可用宽度变化
            const cardWidth = 200.0;
            const spacing = 12.0;

            final columns = ((constraints.maxWidth + spacing) /
                    (cardWidth + spacing))
                .floor()
                .clamp(1, 8);

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: 0.72,
              ),
              itemCount: related.length,
              itemBuilder: (context, index) {
                return _RelatedVideoCard(
                  video: related[index],
                  onTap: () {
                    final id = related[index]['video_id']
                        ?.toString();

                    if (id == null || id.isEmpty) return;

                    // 用 push 打开新页面，返回时回到当前视频
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoDetailPage(videoId: id),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

}

class _InfoRow
    extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    // 值为空时整行不显示，避免出现「品牌 / 发行日期」后面空一片
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty
                  ? '-'
                  : value,
            ),
          ),
        ],
      ),
    );
  }
}


class _FullscreenPlayerPage extends StatefulWidget {
  final VideoPlayerController controller;
  final List<Map<String, dynamic>> availableSources;
  final String currentQuality;
  final double volume;
  final void Function(VideoPlayerController, String) onControllerChanged;
  final ValueChanged<double> onVolumeChanged;

  const _FullscreenPlayerPage({
    required this.controller,
    required this.availableSources,
    required this.currentQuality,
    required this.volume,
    required this.onControllerChanged,
    required this.onVolumeChanged,
  });

  @override
  State<_FullscreenPlayerPage> createState() =>
      _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState
    extends State<_FullscreenPlayerPage> {
  late VideoPlayerController _controller;
  late List<Map<String, dynamic>> _availableSources;
  late String _currentQuality;
  late double _volume;

  bool _showControls = true;
  bool _showVolumeSlider = false;
  bool _switchingQuality = false;
  bool _progressHovering = false;
  double _progressHoverRatio = 0.0;
  Timer? _controlsTimer;
  Timer? _volumeHideTimer;

  @override
  void initState() {
    super.initState();

    _controller = widget.controller;
    _availableSources = widget.availableSources;
    _currentQuality = widget.currentQuality;
    _volume = widget.volume;

    _controller.addListener(_onControllerTick);

    _restartHideTimer();
  }

  void _onControllerTick() {
    if (mounted) {
      setState(() {});
    }
  }

  void _restartHideTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onMouseMove() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _restartHideTimer();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _volumeHideTimer?.cancel();
    _controller.removeListener(_onControllerTick);
    super.dispose();
  }

  Future<void> _exitFullscreen() async {
    await windowManager.setFullScreen(false);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  String _formatDuration(Duration duration) {
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

  Future<void> _changeQuality(String newQuality) async {
    if (_switchingQuality || newQuality == _currentQuality) {
      return;
    }

    final source = _availableSources.firstWhere(
      (s) => s['quality'] == newQuality,
      orElse: () => <String, dynamic>{},
    );

    final newUrl = source['url']?.toString();

    if (newUrl == null || newUrl.isEmpty) {
      return;
    }

    final oldController = _controller;
    final wasPlaying = oldController.value.isPlaying;
    final position = oldController.value.position;

    setState(() {
      _currentQuality = newQuality;
      _switchingQuality = true;
    });

    oldController.removeListener(_onControllerTick);

    final newController = VideoPlayerController.networkUrl(
      Uri.parse(newUrl),
    );

    await newController.initialize();
    await newController.seekTo(position);
    newController.setVolume(_volume);

    _controller = newController;
    newController.addListener(_onControllerTick);

    widget.onControllerChanged(newController, newQuality);

    if (wasPlaying) {
      await newController.play();
    }

    await oldController.pause();
    await oldController.dispose();

    if (mounted) {
      setState(() {
        _switchingQuality = false;
      });
    }
  }


  Widget _buildControls() {
    final position = _controller.value.position;
    final duration = _controller.value.duration;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 视频到控制栏的渐变过渡层
        IgnorePointer(
          child: Container(
            height: 16,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black54,
                ],
              ),
            ),
          ),
        ),
        // 控制栏本体
        Container(
          color: Colors.black54,
          padding: const EdgeInsets.only(left: 4, right: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;

                  return MouseRegion(
                    onHover: (event) {
                      final dx = event.localPosition.dx;
                      final ratio = (dx / trackWidth).clamp(0.0, 1.0);

                      if (!_progressHovering ||
                          (_progressHoverRatio - ratio).abs() > 0.002) {
                        setState(() {
                          _progressHovering = true;
                          _progressHoverRatio = ratio;
                        });
                      }
                    },
                    onExit: (_) {
                      if (_progressHovering) {
                        setState(() {
                          _progressHovering = false;
                        });
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                        ),
                        if (_progressHovering)
                          Positioned(
                            left: (trackWidth * _progressHoverRatio - 30)
                                .clamp(0.0, trackWidth - 60),
                            top: -26,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                _formatDuration(
                                  Duration(
                                    milliseconds: (duration.inMilliseconds *
                                            _progressHoverRatio)
                                        .round(),
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    icon: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_controller.value.isPlaying) {
                          _controller.pause();
                        } else {
                          _controller.play();
                        }
                      });
                      _restartHideTimer();
                    },
                  ),
                  MouseRegion(
                    onEnter: (_) {
                      _volumeHideTimer?.cancel();
                      if (!_showVolumeSlider) {
                        setState(() => _showVolumeSlider = true);
                      }
                    },
                    onExit: (_) {
                      _volumeHideTimer?.cancel();
                      _volumeHideTimer = Timer(
                        const Duration(milliseconds: 150),
                        () {
                          if (mounted && _showVolumeSlider) {
                            setState(() => _showVolumeSlider = false);
                          }
                        },
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          color: Colors.white,
                          icon: Icon(
                            _volume == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                          ),
                          onPressed: () {
                            setState(() {
                              _volume = _volume == 0 ? 1 : 0;
                              _controller.setVolume(_volume);
                              widget.onVolumeChanged(_volume);
                            });
                          },
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          alignment: Alignment.centerLeft,
                          child: _showVolumeSlider
                              ? SizedBox(
                                  width: 80,
                                  height: 40,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.0,
                                      activeTrackColor: Colors.red,
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: Colors.red,
                                      overlayColor:
                                          Colors.red.withValues(alpha: 0.2),
                                      thumbShape:
                                          const RoundSliderThumbShape(
                                        enabledThumbRadius: 6.0,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                        overlayRadius: 12.0,
                                      ),
                                    ),
                                    child: Slider(
                                      value: _volume,
                                      min: 0,
                                      max: 1,
                                      onChanged: (value) {
                                        setState(() {
                                          _volume = value;
                                          _controller.setVolume(value);
                                          widget.onVolumeChanged(value);
                                        });
                                      },
                                    ),
                                  ),
                                )
                              : const SizedBox(width: 0, height: 40),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  if (_availableSources.isNotEmpty)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.high_quality,
                        color: Colors.white,
                      ),
                      tooltip: '选择画质',
                      onSelected: _changeQuality,
                      itemBuilder: (context) {
                        return _availableSources.map((source) {
                          final quality =
                              source['quality']?.toString() ?? '';

                          return PopupMenuItem<String>(
                            value: quality,
                            child: Row(
                              children: [
                                if (quality == _currentQuality)
                                  const Icon(
                                    Icons.check,
                                    size: 18,
                                    color: Colors.green,
                                  )
                                else
                                  const SizedBox(width: 18),
                                const SizedBox(width: 8),
                                Text(quality),
                              ],
                            ),
                          );
                        }).toList();
                      },
                    ),
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.fullscreen_exit),
                    onPressed: _exitFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) => _onMouseMove(),
        onEnter: (_) => _onMouseMove(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: _switchingQuality
                    ? Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: const Windows11Loading(
                          size: 48,
                          color: Colors.white,
                        ),
                      )
                    : VideoPlayer(_controller),
              ),              
            ),

            // 底部常驻细进度条（控制栏出现时淡出）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showControls ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: VideoProgressIndicator(
                    _controller,
                    allowScrubbing: false,
                    colors: const VideoProgressColors(
                      playedColor: Colors.red,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white24,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),

            // 底部控制栏（淡入淡出）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildControls(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// 筛选按钮的统一外观
// ==========================================================
//
// 五个筛选项（影片类型 / 排序 / 日期 / 時長 / 標籤）共用这一套尺寸和配色，
// 保证美术风格一致。要整体调整筛选栏的样子，改这里就够了。
// ==========================================================
// 侧边栏底部的账号入口
// ==========================================================

/// 未登录：一个「登录」按钮。
/// 已登录：显示头像 + 名字，点击进入自己的主页，右键可退出登录。
class _AccountTile extends StatelessWidget {
  final VoidCallback onOpenProfile;
  final Future<void> Function() onLogout;

  const _AccountTile({
    required this.onOpenProfile,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 跟着登录状态自动重建
    return ValueListenableBuilder<AccountInfo>(
      valueListenable: AuthController.account,
      builder: (context, info, _) {
        if (!info.loggedIn) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Tooltip(
              message: '登录后可以点赞、储存、查看自己的收藏',
              child: TextButton.icon(
                onPressed: onOpenProfile,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('登录'),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ),
          );
        }

        // 昵称不显示在头像下面（只保留头像，更干净）
        return PopupMenuButton<String>(
          tooltip: '打开我的主页（右键可登出）',
          position: PopupMenuPosition.over,
          onSelected: (value) {
            if (value == 'logout') {
              onLogout();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'profile',
              height: 40,
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 18),
                  SizedBox(width: 10),
                  Text('我的主页'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'logout',
              height: 40,
              child: Row(
                children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 10),
                  Text('退出登录'),
                ],
              ),
            ),
          ],
          child: InkWell(
            onTap: onOpenProfile,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
              // 只显示头像，不显示昵称
              child: CircleAvatar(
                radius: 20,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                backgroundImage:
                    info.avatar.isEmpty ? null : NetworkImage(info.avatar),
                child: info.avatar.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 22,
                        color: theme.colorScheme.primary,
                      )
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ==========================================================
// 详情页操作条 / 相关影片
// ==========================================================

/// 详情页操作条上的一个只读按钮（点赞 / 储存 / 下载）。
///
/// 官网的点赞和储存需要登录账号才能生效，所以这里做成展示型按钮，
/// 不假装能点，但把真实的点赞比例和数量显示出来。
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String trailing;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;
  final bool busy;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.trailing = '',
    this.tooltip = '',
    this.color,
    this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tint = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.7);

    Widget chip = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E4E8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tint,
              ),
            )
          else
            Icon(icon, size: 18, color: tint),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              trailing,
              style: TextStyle(
                fontSize: 12,
                color: tint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );

    // 可点击时才包 InkWell（下载那种纯展示的就不包）
    if (onTap != null) {
      chip = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: chip,
      );
    }

    if (tooltip.isEmpty) return chip;

    return Tooltip(message: tooltip, child: chip);
  }
}

/// 相关影片卡片：封面 + 标题。
class _RelatedVideoCard extends StatefulWidget {
  final Map<String, dynamic> video;
  final VoidCallback onTap;

  const _RelatedVideoCard({
    required this.video,
    required this.onTap,
  });

  @override
  State<_RelatedVideoCard> createState() => _RelatedVideoCardState();
}

class _RelatedVideoCardState extends State<_RelatedVideoCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final title = widget.video['title']?.toString() ?? '';
    final thumbnail = widget.video['thumbnail']?.toString() ?? '';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _hovering
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: thumbnail.isEmpty
                      ? Container(
                          color: isDark
                              ? Colors.white10
                              : Colors.black12,
                          child: const Center(
                            child: Icon(
                              Icons.movie_outlined,
                              color: Colors.white38,
                            ),
                          ),
                        )
                      : Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, _, _) => Container(
                            color: isDark
                                ? Colors.white10
                                : Colors.black12,
                            child: const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChipStyle {
  _FilterChipStyle._();

  static const double height = 34;
  static const double radius = 17;
  static const EdgeInsets padding =
      EdgeInsets.symmetric(horizontal: 12);
}

/// 筛选栏上的胶囊按钮。
///
/// - 未选中：中性描边，低调
/// - 已选中：主色描边 + 浅主色底，并把选中的值显示出来
class _FilterChip extends StatelessWidget {
  /// 前缀文字，例如「排序」
  final String labelPrefix;

  /// 选中的值，空字符串表示未选中
  final String text;

  final bool active;
  final IconData trailing;
  final bool loading;

  const _FilterChip({
    required this.labelPrefix,
    this.text = '',
    this.active = false,
    this.trailing = Icons.keyboard_arrow_down_rounded,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primary = theme.colorScheme.primary;

    final borderColor = active
        ? primary.withValues(alpha: 0.75)
        : (isDark ? Colors.white24 : const Color(0xFFD5D7DB));

    final fillColor = active
        ? primary.withValues(alpha: isDark ? 0.20 : 0.10)
        : (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white);

    final textColor = active
        ? primary
        : (isDark
            ? Colors.white.withValues(alpha: 0.82)
            : const Color(0xFF44464B));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: _FilterChipStyle.height,
      padding: _FilterChipStyle.padding,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(_FilterChipStyle.radius),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            labelPrefix,
            style: TextStyle(
              fontSize: 13,
              color: textColor,
              fontWeight:
                  active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(width: 6),
            // 选中的值单独用一个小色块强调
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: isDark ? 0.28 : 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          if (loading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: primary,
              ),
            )
          else
            Icon(
              trailing,
              size: 18,
              color: active
                  ? primary
                  : (isDark ? Colors.white54 : Colors.black45),
            ),
        ],
      ),
    );
  }
}