import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart';

class PlaylistDetailPage extends StatefulWidget {
  final String listId;
  final String playlistName;

  const PlaylistDetailPage({
    super.key,
    required this.listId,
    required this.playlistName,
  });

  @override
  State<PlaylistDetailPage> createState() =>
      _PlaylistDetailPageState();
}

class _PlaylistDetailPageState
    extends State<PlaylistDetailPage> {
  List<Map<String, dynamic>> _videos = [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        'http://127.0.0.1:8000/api/playlist',
      ).replace(
        queryParameters: {
          'list_id': widget.listId,
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

      if (!mounted) return;

      setState(() {
        _videos = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = '播放清单加载失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.playlistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadPlaylist,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    if (_videos.isEmpty) {
      return const Center(
        child: Text('这个播放清单没有影片'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final video = _videos[index];

        final title =
            video['title']?.toString() ?? '';

        final videoId =
            video['video_id']?.toString() ?? '';

        final thumbnail =
            video['thumbnail']?.toString() ?? '';

        final duration =
            video['duration']?.toString() ?? '';

        final rating =
            video['rating']?.toString() ?? '';

        final views =
            video['views']?.toString() ?? '';

        return Padding(
          padding: const EdgeInsets.only(
            bottom: 16,
          ),
          child: Material(
            color: Theme.of(context)
                .colorScheme
                .surface,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (videoId.isEmpty) {
                  return;
                }

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) {
                      return VideoDetailPage(
                        videoId: videoId,
                      );
                    },
                  ),
                );
              },
              child: SizedBox(
                height: 180,
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: _buildThumbnail(
                        thumbnail,
                        duration,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(
                          18,
                          14,
                          18,
                          14,
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 3,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Wrap(
                              spacing: 18,
                              runSpacing: 8,
                              children: [
                                if (rating.isNotEmpty)
                                  _buildMetaItem(
                                    Icons.thumb_up_outlined,
                                    rating,
                                  ),
                                if (views.isNotEmpty)
                                  _buildMetaItem(
                                    Icons.visibility_outlined,
                                    views,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '视频 ID：$videoId',
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(
                        right: 14,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.chevron_right,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(
    String thumbnail,
    String duration,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumbnail.isEmpty)
          Container(
            color: Colors.black12,
            child: const Icon(
              Icons.image_not_supported,
              size: 48,
            ),
          )
        else
          Image.network(
            thumbnail,
            fit: BoxFit.cover,
            errorBuilder:
                (
                  context,
                  error,
                  stackTrace,
                ) {
              return Container(
                color: Colors.black12,
                child: const Icon(
                  Icons.broken_image,
                  size: 48,
                ),
              );
            },
            loadingBuilder:
                (
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
                  child:
                      CircularProgressIndicator(),
                ),
              );
            },
          ),
        if (duration.isNotEmpty)
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius:
                    BorderRadius.circular(4),
              ),
              child: Text(
                duration,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMetaItem(
    IconData icon,
    String text,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 17,
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}