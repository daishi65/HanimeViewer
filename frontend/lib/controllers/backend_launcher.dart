import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_config.dart';

/// 后端进程的启动与退出管理。
///
/// 目标：用户双击 App 就能用，不需要自己去开调试 Chrome、也不需要在终端起 uvicorn。
///
/// 两种情况：
/// 1. **已打包**：同目录下有 `hanime_backend.exe`（PyInstaller 产物），直接启动它。
/// 2. **开发中**：回退到用项目里的 `.venv` 跑 `python -m uvicorn`。
///
/// 后端自己负责把调试 Chrome 拉起来（见 backend/browser.py），
/// 所以这里只需要管后端进程。
class BackendLauncher {
  BackendLauncher._();

  static Process? _process;

  /// 后端是不是我们自己启动的（如果是连的别人已经开好的后端，就不该去杀它）
  static bool _startedByUs = false;

  static bool get startedByUs => _startedByUs;

  /// 项目根目录（开发模式下用）。
  ///
  /// 打包后 exe 在 `frontend/build/windows/x64/runner/Release/`，
  /// 往上四层是项目根；开发时进程在 `frontend/`，往上两层是项目根。
  static String? _findProjectRoot() {
    var dir = File(Platform.resolvedExecutable).parent;

    for (var i = 0; i < 6; i++) {
      final backendDir = Directory('${dir.path}${Platform.pathSeparator}backend');

      if (backendDir.existsSync()) {
        return dir.path;
      }

      final parent = dir.parent;

      if (parent.path == dir.path) break;

      dir = parent;
    }

    return null;
  }

  /// 打包后可执行文件的位置。
  static String? _findBundledBackend() {
    final exeDir = File(Platform.resolvedExecutable).parent;

    final candidates = [
      '${exeDir.path}${Platform.pathSeparator}hanime_backend.exe',
      '${exeDir.path}${Platform.pathSeparator}backend'
          '${Platform.pathSeparator}hanime_backend.exe',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }

    return null;
  }

  /// 后端是否已经在跑（可能是我们自己起的，也可能是外部起好的）。
  static Future<bool> isBackendAlive({Duration? timeout}) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = timeout ?? const Duration(seconds: 2);

      final request = await client.getUrl(
        Uri.parse('${AppConfig.backendBase}/'),
      );

      final response = await request.close();

      await response.drain<void>();

      client.close();

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 启动后端。返回 (成功, 错误信息)。
  ///
  /// 如果后端已经在跑，会直接复用，不会重复启动。
  static Future<(bool, String)> start() async {
    if (await isBackendAlive()) {
      _startedByUs = false;

      return (true, '');
    }

    if (!Platform.isWindows) {
      return (false, '目前只支持 Windows 自动启动后端');
    }

    final bundled = _findBundledBackend();

    try {
      if (bundled != null) {
        _process = await Process.start(
          bundled,
          [
            '--port', '${AppConfig.backendPort}',
            '--cdp-port', '${AppConfig.cdpPort}',
          ],
          workingDirectory: File(bundled).parent.path,
          // 注意：这里**不能**用 detachedWithStdio。
          // 那个模式会让后端脱离 App 独立存活，
          // 结果 App 关掉了后端还在跑、端口一直占着。
          mode: ProcessStartMode.normal,
        );
      } else {
        // 开发模式：用项目里的 venv 跑 uvicorn
        final root = _findProjectRoot();

        if (root == null) {
          return (
            false,
            '找不到后端程序。请确认 hanime_backend.exe 与 App 在同一目录。',
          );
        }

        final python = '$root${Platform.pathSeparator}.venv'
            '${Platform.pathSeparator}Scripts'
            '${Platform.pathSeparator}python.exe';

        if (!File(python).existsSync()) {
          return (
            false,
            '找不到 Python 环境：$python\n'
                '开发模式下需要项目里的 .venv。',
          );
        }

        _process = await Process.start(
          python,
          [
            '-m', 'uvicorn', 'main:app',
            '--host', '127.0.0.1',
            '--port', '${AppConfig.backendPort}',
          ],
          workingDirectory:
              '$root${Platform.pathSeparator}backend',
          environment: {
            'HANIME_CDP_PORT': '${AppConfig.cdpPort}',
          },
          mode: ProcessStartMode.normal,
        );
      }

      _startedByUs = true;

      // 必须**主动把这些管道读空**。
      //
      // 踩过的坑：之前用 debugPrint 输出后端日志，但
      //   - debugPrint 带限流（每约 12KB 就暂停一下）
      //   - 而且 release 构建下 print() 根本不输出
      // 结果管道没人读 -> 子进程写日志时阻塞 -> 后端起不来，
      // 表现就是「后端启动超时」，但手动跑 hanime_backend.exe 却正常。
      //
      // 所以这里只管把数据读走丢掉，不依赖 debugPrint。
      _drain(_process!.stdout);
      _drain(_process!.stderr);

      return (true, '');
    } catch (e) {
      return (false, '启动后端失败：$e');
    }
  }

  /// 把管道读空（内容丢弃，只为了防止子进程写阻塞）。
  static void _drain(Stream<List<int>> stream) {
    final lastLines = <String>[];

    stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
      (line) {
        // 只留最后几行，出错时能拿出来给用户看
        lastLines.add(line);

        if (lastLines.length > _recentOutputLimit) {
          lastLines.removeAt(0);
        }

        _recentOutput = List<String>.unmodifiable(lastLines);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  static const int _recentOutputLimit = 30;

  static List<String> _recentOutput = const [];

  /// 后端最近的输出（用来在启动失败时给出真实原因，而不是一句「超时」）。
  static List<String> get recentOutput => _recentOutput;

  /// 等后端就绪。
  static Future<bool> waitUntilReady({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (await isBackendAlive()) return true;

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    return false;
  }

  /// 退出时收尾：只结束我们自己启动的后端。
  ///
  /// 顺序很重要：
  /// 1. 先请求后端 /api/shutdown —— 让它把关掉的「隐藏调试浏览器」也收掉
  ///    （那个浏览器窗口是隐藏的，用户看不到也没法自己关）
  /// 2. 再结束后端进程树
  static Future<void> stop() async {
    if (!_startedByUs) return;

    final process = _process;

    _process = null;
    _startedByUs = false;

    if (process == null) return;

    // 1. 让后端顺便收掉隐藏的浏览器
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);

      final request = await client.postUrl(
        Uri.parse('${AppConfig.backendBase}/api/shutdown'),
      );

      final response = await request.close();

      await response.drain<void>();

      // 等后端把浏览器收干净。
      //
      // 后端内部是「轮询等 chrome 进程真正消失」，可能要好几秒。
      // 之前这里只等 1.2 秒就把后端进程树杀了，
      // 结果收尾被打断，留下 13 个隐藏的 chrome.exe。
      //
      // 所以这里改成轮询后端状态：等 cdp_alive 变成 false 再走，
      // 最多等 20 秒，避免固定 sleep 要么太短要么白等。
      final deadline = DateTime.now().add(const Duration(seconds: 20));

      while (DateTime.now().isBefore(deadline)) {
        try {
          final statusRequest = await client.getUrl(
            Uri.parse('${AppConfig.backendBase}/api/status'),
          );

          final statusResponse = await statusRequest.close();

          final body =
              await statusResponse.transform(utf8.decoder).join();

          final data = jsonDecode(body);

          if (data is Map && data['cdp_alive'] != true) {
            // 浏览器已经没了
            break;
          }
        } catch (_) {
          // 后端可能已经自己退出了（说明收尾完成），也可以走了
          break;
        }

        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      client.close();
    } catch (_) {
      // 后端可能已经没了，继续走结束进程
    }

    // 2. 结束后端进程树
    //    只杀外层是不够的：PyInstaller onefile 是「引导进程 + 应用进程」两层。
    try {
      if (Platform.isWindows) {
        await Process.run(
          'taskkill',
          ['/PID', '${process.pid}', '/T', '/F'],
        );
      } else {
        process.kill();
      }
    } catch (_) {
      try {
        process.kill();
      } catch (_) {}
    }
  }
}
