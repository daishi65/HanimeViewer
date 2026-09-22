import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'playlist_page.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:video_player_win/video_player_win.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  runApp(const HanimeViewerApp());
}

class HanimeViewerApp extends StatelessWidget {
  const HanimeViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HanimeViewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainShell(),
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
    setState(() => _section = section);
    if (MediaQuery.sizeOf(context).width < 800) {
      Navigator.of(context).maybePop();
    }
  }

  Widget _buildPage() {
    switch (_section) {
      case _MainSection.home:
        return const HomePage();
      case _MainSection.search:
        return const SearchPage();
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
        return const _PlaceholderPage(
          icon: Icons.settings,
          title: '设置',
          message: '设置功能稍后实现。',
        );
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
              child: Column(
                children: [
                  AppBar(
                    title: Text(_title),
                  ),
                  Expanded(
                    child: _buildPage(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
      ),
      drawer: Drawer(
        child: _buildNavigation(drawer: true),
      ),
      body: _buildPage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _videos = [];
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
          'http://127.0.0.1:8000/api/home',
        ),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '服务器返回错误: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      final videos =
          List<Map<String, dynamic>>.from(
        data['results'] ?? [],
      );

      if (mounted) {
        setState(() => _videos = videos);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = '首页加载失败：$e',
        );
      }
    } finally {
      if (mounted) {
        setState(
          () => _loading = false,
        );
      }
    }
  }

  String? _extractVideoId(String url) {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['v'];
  }

  void _openVideo(
    Map<String, dynamic> video,
  ) {
    final id = _extractVideoId(
      video['url']?.toString() ?? '',
    );

    if (id == null || id.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoDetailPage(videoId: id),
      ),
    );
  }

  Widget _buildCard(
    Map<String, dynamic> video,
  ) {
    final thumbnail =
        video['thumbnail']?.toString() ?? '';

    final title =
        video['title']?.toString() ?? '';

    final duration =
        video['duration']?.toString() ?? '';

    final rating =
        video['rating']?.toString() ?? '';

    final views =
        video['views']?.toString() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openVideo(video),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: thumbnail.isNotEmpty
                  ? Image.network(
                      thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (
                        _,
                        __,
                        ___,
                      ) =>
                          Container(
                        color: Colors.black12,
                        alignment:
                            Alignment.center,
                        child: const Icon(
                          Icons.broken_image,
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported,
                      ),
                    ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                12,
                10,
                12,
                4,
              ),
              child: Text(
                title,
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                12,
                0,
                12,
                12,
              ),
              child: Text(
                [
                  duration,
                  rating,
                  views,
                ]
                    .where(
                      (v) => v.isNotEmpty,
                    )
                    .join(' · '),
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadHomeVideos,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHomeVideos,
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          int columns;

          if (constraints.maxWidth >= 1200) {
            columns = 4;
          } else if (
              constraints.maxWidth >= 850) {
            columns = 3;
          } else if (
              constraints.maxWidth >= 550) {
            columns = 2;
          } else {
            columns = 1;
          }

          return GridView.builder(
            padding:
                const EdgeInsets.all(24),
            gridDelegate:
                SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              mainAxisExtent: 310,
            ),
            itemCount: _videos.length,
            itemBuilder: (_, index) =>
                _buildCard(
              _videos[index],
            ),
          );
        },
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() =>
      _SearchPageState();
}

class _SearchPageState
    extends State<SearchPage> {
  final TextEditingController _controller =
      TextEditingController();

  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;

  String? _extractVideoId(String url) {
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['v'];
  }

  Future<void> _search() async {
    final query =
        _controller.text.trim();

    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
      final uri =
          Uri.parse(
            'http://127.0.0.1:8000/api/search',
          ).replace(
        queryParameters: {
          'query': query,
        },
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

      if (mounted) {
        setState(() {
          _results =
              List<Map<String, dynamic>>.from(
            data['results'] ?? [],
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = '搜索失败：$e',
        );
      }
    } finally {
      if (mounted) {
        setState(
          () => _loading = false,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration:
                      const InputDecoration(
                    labelText: '搜索',
                    hintText:
                        '输入关键词，例如 nmf',
                    border:
                        OutlineInputBorder(),
                  ),
                  onSubmitted: (_) =>
                      _search(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed:
                    _loading ? null : _search,
                child:
                    const Text('搜索'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding:
                  const EdgeInsets.all(12),
              child: Text(
                _error!,
                style:
                    const TextStyle(
                  color: Colors.red,
                ),
              ),
            ),
          Expanded(
            child:
                _results.isEmpty &&
                        !_loading
                    ? const Center(
                        child: Text(
                          '请输入关键词开始搜索',
                        ),
                      )
                    : ListView.builder(
                        itemCount:
                            _results.length,
                        itemBuilder: (
                          _,
                          index,
                        ) {
                          final video =
                              _results[index];

                          final thumbnail =
                              video['thumbnail']
                                      ?.toString() ??
                                  '';

                          return Card(
                            margin:
                                const EdgeInsets
                                    .only(
                              bottom: 12,
                            ),
                            child: ListTile(
                              leading:
                                  SizedBox(
                                width: 140,
                                height: 80,
                                child: thumbnail
                                        .isNotEmpty
                                    ? Image.network(
                                        thumbnail,
                                        fit: BoxFit
                                            .cover,
                                      )
                                    : const Icon(
                                        Icons
                                            .image,
                                      ),
                              ),
                              title: Text(
                                video['title']
                                        ?.toString() ??
                                    '',
                                maxLines: 2,
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                              ),
                              subtitle:
                                  Text([
                                video['duration'] ??
                                    '',
                                video['rating'] ??
                                    '',
                                video['views'] ??
                                    '',
                              ]
                                      .where(
                                        (v) =>
                                            v
                                                .toString()
                                                .isNotEmpty,
                                      )
                                      .join(
                                        ' · ',
                                      )),
                              trailing:
                                  const Icon(
                                Icons
                                    .chevron_right,
                              ),
                              onTap: () {
                                final id =
                                    _extractVideoId(
                                  video['url']
                                          ?.toString() ??
                                      '',
                                );

                                if (id == null) {
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
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
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
        child: CircularProgressIndicator(),
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

class FullscreenPlayerPage extends StatefulWidget {
  final VideoPlayerController controller;

  const FullscreenPlayerPage({
    super.key,
    required this.controller,
  });

  @override
  State<FullscreenPlayerPage> createState() =>
      _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState
    extends State<FullscreenPlayerPage> {

  bool _showControls = true;
  Timer? _timer;

  void _show() {
    setState(() {
      _showControls = true;
    });

    _timer?.cancel();

    _timer = Timer(
      const Duration(seconds: 3),
      () {
        if(mounted){
          setState(() {
            _showControls=false;
          });
        }
      },
    );
  }


  @override
  void dispose(){
    _timer?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context){

    final controller =
        widget.controller;


    return Scaffold(
      backgroundColor: Colors.black,

      body: Listener(
        onPointerHover: (_) => _show(),
        onPointerMove: (_) => _show(),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,

          children:[
            
            Center(
              child: AspectRatio(
                aspectRatio:
                    controller.value.aspectRatio,

                child:
                    VideoPlayer(controller),
              ),
            ),


            if(_showControls)

              Positioned(
                left:0,
                right:0,
                bottom:0,

                child:
                    Container(
                      height:60,
                      color:
                          Colors.black87,

                      child:
                          const Center(
                            child:
                            Text(
                              '全屏控制栏',
                              style:
                              TextStyle(
                                color:
                                Colors.white,
                              ),
                            ),
                          ),
                    ),
              ),
          ],
        ),
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

  bool _showControls = true;
  Timer? _controlsTimer;

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

    await Navigator.push(
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
    final controller =
        _videoPlayerController;

    if (controller == null ||
        !controller
            .value
            .isInitialized) {
      return Container(
        width:
            double.infinity,
        height: 420,
        color: Colors.black,
        alignment:
            Alignment.center,
        child:
            const CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }

    final thumbnail =
        _video?['thumbnail']
                ?.toString() ??
            '';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: AspectRatio(
      aspectRatio:
          controller.value
              .aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MouseRegion(
            onHover: (_) => _showPlayerControls(),
            child: VideoPlayer(controller),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (
              context,
              value,
              child,
            ) {
              if (!value.isInitialized ||
                  value.duration.inMilliseconds <= 0) {
                return const SizedBox();
              }

              final progress =
                  value.position.inMilliseconds /
                      value.duration.inMilliseconds;

              return Positioned(
                left: 0,
                right: 0,
                bottom: _showControls ? 48 : 0,
                child: IgnorePointer(
                  child: LinearProgressIndicator(
                    value:
                        progress.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor:
                        Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(
                      Colors.red,
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
                        errorBuilder: (
                          _,
                          __,
                          ___,
                        ) =>
                            Container(
                          color: Colors.black,
                        ),
                      )
                    else
                      Container(
                        color: Colors.black,
                      ),

                    Container(
                      color:
                          Colors.black26,
                    ),

                    const Center(
                      child: DecoratedBox(
                        decoration:
                            BoxDecoration(
                          color:
                              Colors.black54,
                          shape:
                              BoxShape.circle,
                        ),
                        child: Padding(
                          padding:
                              EdgeInsets.all(
                            16,
                          ),
                          child: Icon(
                            Icons
                                .play_arrow,
                            color:
                                Colors.white,
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

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(vertical: 6),
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
              Text(
                '${_formatDuration(position)} / ${_formatDuration(duration)}',
                style: const TextStyle(color: Colors.white),
              ),
              const Spacer(),
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
              SizedBox(
                width: 100,
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
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.fullscreen),
                onPressed: _showFullscreenPlayer,
              ),
            ],
          ),
        ],
      ),
    );
  }

Future<void> _showFullscreenPlayer() async {
  final controller =
      _videoPlayerController;

  if (controller == null ||
      !controller.value.isInitialized) {
    return;
  }

  await windowManager.setFullScreen(true);

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) {
        return StatefulBuilder(
          builder: (
            context,
            setFullState,
          ) {
            bool showControls = false;
            Timer? timer;


            void show() {

              setFullState(() {
                showControls = true;
              });


              timer?.cancel();


              timer = Timer(
                const Duration(seconds: 3),
                () {

                  setFullState(() {
                    showControls = false;
                  });

                },
              );

            }

            return Scaffold(
              backgroundColor:
                  Colors.black,

              body: Listener(
                behavior:
                    HitTestBehavior.translucent,

                onPointerHover: (_) {
                  show();
                },

                child: Stack(
                  fit: StackFit.expand,
                  children: [

                    Center(
                      child: AspectRatio(
                        aspectRatio:
                            controller.value.aspectRatio,
                        child:
                            VideoPlayer(
                          controller,
                        ),
                      ),
                    ),


                    // 底部常驻细进度条
                    if (!showControls)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child:
                            VideoProgressIndicator(
                        controller,
                        allowScrubbing:
                            false,
                        colors:
                            const VideoProgressColors(
                          playedColor:
                              Colors.red,
                          bufferedColor:
                              Colors.white38,
                          backgroundColor:
                              Colors.white24,
                        ),
                        padding:
                            EdgeInsets.zero,
                      ),
                    ),


                    if (showControls)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color:
                              Colors.black87,
                          padding:
                              const EdgeInsets.all(8),
                          child: Row(
                            children: [

                              IconButton(
                                color:
                                    Colors.white,
                                icon: Icon(
                                  controller
                                          .value
                                          .isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                                onPressed: () {
                                  setFullState(() {
                                    if (controller
                                        .value
                                        .isPlaying) {
                                      controller.pause();
                                    } else {
                                      controller.play();
                                    }
                                  });
                                },
                              ),


                              Expanded(
                                child:
                                    VideoProgressIndicator(
                                  controller,
                                  allowScrubbing:
                                      true,
                                ),
                              ),


                              IconButton(
                                color:
                                    Colors.white,
                                icon:
                                    const Icon(
                                  Icons.fullscreen_exit,
                                ),
                                onPressed:
                                    () async {
                                  await windowManager
                                      .setFullScreen(
                                          false);

                                  Navigator.pop(
                                      context);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),


                    Positioned(
                      top: 20,
                      left: 20,
                      child:
                          IconButton(
                        color:
                            Colors.white,
                        icon:
                            const Icon(
                          Icons.arrow_back,
                          size: 32,
                        ),
                        onPressed:
                            () async {
                          await windowManager
                              .setFullScreen(
                                  false);

                          Navigator.pop(
                              context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
        title:
            const Text('视频详情'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child:
            CircularProgressIndicator(),
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