import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'playlist_page.dart';
import 'widgets/windows11_loading.dart';
import 'controllers/theme_controller.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:video_player_win/video_player_win.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  await ThemeController.load();

  runApp(const HanimeViewerApp());
}

class HanimeViewerApp extends StatelessWidget {
  const HanimeViewerApp({super.key});

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
          home: const MainShell(),          
        );        
      },
    );
  }
}

enum _MainSection { home, search, history, playlist, downloads, settings }

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  _MainSection _section = _MainSection.home;

  Map<String, String>? _searchPreset;

  String get _title {
    switch (_section) {
      case _MainSection.home:
        return '首页';
      case _MainSection.search:
        return '搜索';
      case _MainSection.history:
        return '观看历史';
      case _MainSection.playlist:
        return '播放清单';
      case _MainSection.downloads:
        return '下载';
      case _MainSection.settings:
        return '设置';
    }
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
    });
  }

  Widget _buildPage() {
    switch (_section) {
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
        '观看历史'
      ),
      (
        _MainSection.playlist,
        Icons.playlist_play_outlined,
        Icons.playlist_play,
        '播放清单'
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
      );
    }

    return NavigationRail(
      selectedIndex:
          _MainSection.values.indexOf(_section),
      onDestinationSelected: (index) =>
          _select(_MainSection.values[index]),
      labelType: NavigationRailLabelType.all,
      leading: const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: Icon(
          Icons.video_library,
          size: 30,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= 800;

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
  List<Map<String, dynamic>> _sections = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
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
          'http://127.0.0.1:8000/api/home_sections',
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
                      errorBuilder: (_, __, ___) => Container(
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

  bool get _isPortraitCategory =>
      _selectedGenre == '裏番' || _selectedGenre == '泡麵番';

  static const String _historyKey = 'search_history';
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

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
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

      final uri = Uri.parse(
        'http://127.0.0.1:8000/api/filter',
      ).replace(queryParameters: params);

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          '服务器返回错误: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      if (mounted) {
        setState(() {
          _results = List<Map<String, dynamic>>.from(
            data['results'] ?? [],
          );
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

    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/tags'),
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
    await _loadTags();

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

  Widget _buildFilterBar() {
    final hasActiveFilter = _selectedGenre.isNotEmpty ||
        _selectedSort.isNotEmpty ||
        _selectedDate.isNotEmpty ||
        _selectedDuration.isNotEmpty ||
        _selectedTags.isNotEmpty;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildFilterMenu(
          label: '影片类型',
          currentValue: _selectedGenre,
          options: _genreOptions,
          onChanged: (v) {
            setState(() => _selectedGenre = v);
            _search();
          },
        ),
        _buildFilterMenu(
          label: '排序',
          currentValue: _selectedSort,
          options: _sortOptions,
          onChanged: (v) {
            setState(() => _selectedSort = v);
            _search();
          },
        ),        
        _buildFilterMenu(
          label: '日期',
          currentValue: _selectedDate,
          options: _dateOptions,
          onChanged: (v) {
            setState(() => _selectedDate = v);
            _search();
          },
        ),
        _buildFilterMenu(
          label: '時長',
          currentValue: _selectedDuration,
          options: _durationOptions,
          onChanged: (v) {
            setState(() => _selectedDuration = v);
            _search();
          },
        ),        
        _buildTagButton(),
        if (hasActiveFilter)
          TextButton.icon(
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
            icon: const Icon(Icons.close, size: 16),
            label: const Text('重置'),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              foregroundColor: Colors.grey.shade700,
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterMenu({
    required String label,
    required String currentValue,
    required List<Map<String, String>> options,
    required ValueChanged<String> onChanged,
  }) {
    final active = currentValue.isNotEmpty;
    final displayText =
        active ? '$label · $currentValue' : label;

    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onChanged,
      itemBuilder: (context) {
        return options.map((o) {
          final isCurrent = o['value'] == currentValue;

          return PopupMenuItem<String>(
            value: o['value'],
            height: 40,
            child: Row(
              children: [
                if (isCurrent)
                  const Icon(
                    Icons.check,
                    size: 16,
                    color: Colors.green,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(o['label']!),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          border: Border.all(
            color: active
                ? theme.colorScheme.primary
                : Colors.grey.shade400,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayText,
              style: TextStyle(
                fontSize: 13,
                color: active
                    ? theme.colorScheme.primary
                    : null,
                fontWeight: active
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: active
                  ? theme.colorScheme.primary
                  : Colors.grey.shade700,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagButton() {
    final active = _selectedTags.isNotEmpty;
    final displayText =
        active ? '標籤 · ${_selectedTags.length}' : '標籤';

    final theme = Theme.of(context);

    return InkWell(
      onTap: _showTagDialog,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          border: Border.all(
            color: active
                ? theme.colorScheme.primary
                : Colors.grey.shade400,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              displayText,
              style: TextStyle(
                fontSize: 13,
                color: active
                    ? theme.colorScheme.primary
                    : null,
                fontWeight: active
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: active
                  ? theme.colorScheme.primary
                  : Colors.grey.shade700,
            ),
          ],
        ),
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
                      errorBuilder: (_, __, ___) => Container(
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

            // 👇 想让搜索框行更靠右 / 更靠左，改这个数字
            // 0.0 = 居中，0.2 = 稍靠右，0.5 = 很靠右，1.0 = 靠最右
            // -0.2 = 稍靠左，-1.0 = 靠最左
            final alignmentX = 0.3;

            // 👇 搜索框行整体宽度（改这里可以调宽度）
            final contentWidth = availableWidth.clamp(0.0, 1000.0);

            // 👇 自动计算左边缘（历史面板对齐用，不用改）
            final contentLeft =
                (availableWidth - contentWidth) / 2 * (1 + alignmentX);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // ---- 主内容 ----
                Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: Align(
                        alignment: Alignment(alignmentX, 0),
                        child: SizedBox(
                          width: contentWidth,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 320,
                                child: TapRegion(
                                  groupId: 'search_history',
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _searchFocusNode,
                                    decoration: InputDecoration(
                                      labelText: '主人点击我就能色色了哦',
                                      hintText: 'Hentai杂鱼主人又在看羞羞的东西',
                                      border: const OutlineInputBorder(),
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
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildFilterBar(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

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
                    left: contentLeft,
                    width: 320,
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

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs =
          await SharedPreferences
              .getInstance();

      final raw =
          prefs.getStringList(
                'watch_history',
              ) ??
              [];

      final result =
          <Map<String, dynamic>>[];

      for (final item in raw) {
        try {
          final decoded =
              jsonDecode(item);

          if (decoded is Map) {
            result.add(
              Map<String, dynamic>.from(
                decoded,
              ),
            );
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _history = result;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _loading = false,
        );
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
    final id =
        item['video_id']?.toString();

    if (id == null || id.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoDetailPage(
          videoId: id,
        ),
      ),
    ).then(
      (_) => _loadHistory(),
    );
  }

  Future<void> _clearHistory() async {
    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.remove(
      'watch_history',
    );

    if (mounted) {
      setState(
        () => _history = [],
      );
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
          children: const [
            SizedBox(height: 180),
            Center(
              child: Text(
                '暂无观看历史',
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Align(
          alignment:
              Alignment.centerRight,
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
              24,
              12,
              24,
              0,
            ),
            child: TextButton.icon(
              onPressed:
                  _clearHistory,
              icon: const Icon(
                Icons.delete_outline,
              ),
              label:
                  const Text('清空历史'),
            ),
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

              return Card(
                margin:
                    const EdgeInsets.only(
                  bottom: 12,
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.all(
                    10,
                  ),
                  leading:
                      SizedBox(
                    width: 160,
                    height: 90,
                    child: thumbnail
                            .isNotEmpty
                        ? Image.network(
                            thumbnail,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (
                              _,
                              __,
                              ___,
                            ) =>
                                    const Icon(
                              Icons
                                  .broken_image,
                            ),
                          )
                        : const Icon(
                            Icons
                                .play_circle_outline,
                          ),
                  ),
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                  ),
                  subtitle:
                      Padding(
                    padding:
                        const EdgeInsets.only(
                      top: 8,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        if (brand.isNotEmpty)
                          Text(
                            '品牌：$brand',
                          ),
                        if (lastWatched !=
                            null)
                          Text(
                            '观看时间：${_formatTime(lastWatched)}',
                          ),
                      ],
                    ),
                  ),
                  trailing:
                      const Icon(
                    Icons.chevron_right,
                  ),
                  onTap: () =>
                      _open(item),
                ),
              );
            },
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
            ? theme.colorScheme.primary.withOpacity(0.1)
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

  VideoPlayerController?
      _videoPlayerController;

  DateTime? _lastSavedPosition;

  bool _showVideoCover = true;

  bool _autoPlayNext = true;

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
        'http://127.0.0.1:8000/api/video/${widget.videoId}',
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
              'watch_history',
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
      'watch_history',
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

    final key =
        'video_position_${widget.videoId}';

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

    final key =
        'video_position_${widget.videoId}';

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
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;

    if (hours > 0) {
      return '$hours:${minutes}:${seconds}';
    }

    return '$minutes:$seconds';
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
                          errorBuilder: (_, __, ___) => Container(
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
                                color: Colors.black.withOpacity(0.85),
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
                                          Colors.red.withOpacity(0.2),
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

    await Navigator.push(
      context,
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
                          __,
                          ___,
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

    final fileSize =
        video['file_size']
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
          label: '发行日期',
          value: releaseDate,
        ),
        _InfoRow(
          label: '文件大小',
          value: fileSize,
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
                height: 24,
              ),
              _buildInfoSection(),
            ],
          ),
        );
      },
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
                                color: Colors.black.withOpacity(0.85),
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
                                          Colors.red.withOpacity(0.2),
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