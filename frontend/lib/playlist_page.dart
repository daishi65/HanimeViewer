import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'playlist_detail_page.dart';
import 'widgets/windows11_loading.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  List<Map<String, dynamic>> _playlists = [];

  int _page = 1;
  int _totalPages = 8;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists({int? page}) async {
    final targetPage = page ?? _page;

    if (targetPage < 1 || targetPage > _totalPages) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        'http://127.0.0.1:8000/api/playlists',
      ).replace(
        queryParameters: {
          'page': targetPage.toString(),
        },
      );

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

      final currentPage =
          int.tryParse(
                data['page']?.toString() ?? '',
              ) ??
              targetPage;

      final serverTotalPages =
          int.tryParse(
                data['total_pages']?.toString() ?? '',
              ) ??
              1;

      if (!mounted) return;

      setState(() {
        _playlists = results;
        _page = currentPage;
        _totalPages =
            serverTotalPages < 8
                ? 8
                : serverTotalPages;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = '播放清单加载失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _previousPage() {
    if (_page <= 1 || _loading) {
      return;
    }

    _loadPlaylists(
      page: _page - 1,
    );
  }

  void _nextPage() {
    if (_page >= _totalPages || _loading) {
      return;
    }

    _loadPlaylists(
      page: _page + 1,
    );
  }

  Future<void> _showPageJumpDialog() async {
    final page = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return _PageJumpDialog(
          currentPage: _page,
          totalPages: _totalPages,
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (page == null || page == _page) {
      return;
    }

    await _loadPlaylists(
      page: page,
    );
  }

  void _openPlaylist(
    Map<String, dynamic> playlist,
  ) {
    final name =
        playlist['name']?.toString() ?? '';

    final url =
        playlist['url']?.toString() ?? '';

    if (url.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(url);

    if (uri == null) {
      return;
    }

    final listId =
        uri.queryParameters['list'] ?? '';

    if (listId.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          return PlaylistDetailPage(
            listId: listId,
            playlistName: name,
          );
        },
      ),
    );
  }

  int _getCrossAxisCount(double width) {
    if (width >= 1400) {
      return 5;
    }

    if (width >= 1100) {
      return 4;
    }

    if (width >= 800) {
      return 3;
    }

    if (width >= 560) {
      return 2;
    }

    return 1;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _playlists.isEmpty) {
      return const Center(
        child: Windows11Loading(size: 48),
      );
    }
    
    if (_error != null && _playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadPlaylists,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_loading)
          const LinearProgressIndicator(),

        Expanded(
          child: RefreshIndicator(
            onRefresh: () {
              return _loadPlaylists(
                page: _page,
              );
            },
            child: LayoutBuilder(
              builder: (
                context,
                constraints,
              ) {
                final crossAxisCount =
                    _getCrossAxisCount(
                  constraints.maxWidth,
                );

                return GridView.builder(
                  padding: const EdgeInsets.all(18),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.35,
                  ),
                  itemCount: _playlists.length,
                  itemBuilder: (
                    context,
                    index,
                  ) {
                    final playlist =
                        _playlists[index];

                    final name =
                        playlist['name']
                                ?.toString() ??
                            '';

                    final videoCount =
                        playlist['video_count']
                                ?.toString() ??
                            '';

                    final thumbnail =
                        playlist['thumbnail']
                                ?.toString() ??
                            '';

                    return _PlaylistCard(
                      name: name,
                      videoCount: videoCount,
                      thumbnail: thumbnail,
                      onTap: () {
                        _openPlaylist(
                          playlist,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            18,
            6,
            18,
            14,
          ),
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _page > 1 && !_loading
                        ? _previousPage
                        : null,
                icon: const Icon(
                  Icons.chevron_left,
                ),
                label: const Text('上一页'),
              ),

              const SizedBox(width: 16),

              InkWell(
                borderRadius:
                    BorderRadius.circular(8),
                onTap:
                    _loading
                        ? null
                        : _showPageJumpDialog,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Text(
                    '第 $_page / $_totalPages 页',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.w600,
                      color:
                          _loading
                              ? Colors.grey
                              : Theme.of(context)
                                  .colorScheme
                                  .primary,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              OutlinedButton.icon(
                onPressed:
                    _page < _totalPages &&
                            !_loading
                        ? _nextPage
                        : null,
                icon: const Icon(
                  Icons.chevron_right,
                ),
                label: const Text('下一页'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final String name;
  final String videoCount;
  final String thumbnail;
  final VoidCallback onTap;

  const _PlaylistCard({
    required this.name,
    required this.videoCount,
    required this.thumbnail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 6,
              child: _buildThumbnail(),
            ),

            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  10,
                  7,
                  8,
                  7,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    if (videoCount.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.video_library_outlined,
                            size: 15,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              videoCount,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.1,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
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

  Widget _buildThumbnail() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumbnail.isEmpty)
          Container(
            color: Colors.black12,
            child: const Icon(
              Icons.image_not_supported,
              size: 36,
            ),
          )
        else
          Image.network(
            thumbnail,
            fit: BoxFit.cover,
            errorBuilder: (
              context,
              error,
              stackTrace,
            ) {
              return Container(
                color: Colors.black12,
                child: const Icon(
                  Icons.broken_image,
                  size: 36,
                ),
              );
            },
            loadingBuilder: (
              context,
              child,
              loadingProgress,
            ) {
              if (loadingProgress == null) {
                return child;
              }

              return Container(
                color: Colors.black12,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              );
            },
          ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 5,
            ),
            color: Colors.black54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(
                  Icons.playlist_play,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    videoCount.isEmpty
                        ? '影片数量未知'
                        : videoCount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PageJumpDialog extends StatefulWidget {
  final int currentPage;
  final int totalPages;

  const _PageJumpDialog({
    required this.currentPage,
    required this.totalPages,
  });

  @override
  State<_PageJumpDialog> createState() =>
      _PageJumpDialogState();
}

class _PageJumpDialogState
    extends State<_PageJumpDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(
      text: widget.currentPage.toString(),
    );
  }

  void _submit() {
    final page = int.tryParse(
      _controller.text.trim(),
    );

    if (page == null ||
        page < 1 ||
        page > widget.totalPages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '请输入 1~${widget.totalPages} 之间的页码',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('跳转到页码'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '页码',
          hintText: '请输入 1~${widget.totalPages}',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('跳转'),
        ),
      ],
    );
  }
}