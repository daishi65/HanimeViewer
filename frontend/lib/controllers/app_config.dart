/// 运行期配置。
///
/// 以前后端地址写死在 11 个地方（6 个文件里都是 `http://127.0.0.1:8000`），
/// 端口一改就得全项目搜。现在统一走这里。
library;

class AppConfig {
  AppConfig._();

  /// 后端端口
  static int backendPort = 8000;

  /// 调试浏览器（Chrome）的 CDP 端口
  static int cdpPort = 9222;

  /// 后端基地址
  static String get backendBase => 'http://127.0.0.1:$backendPort';

  /// 拼接后端接口地址，例如 `api('/api/home')`
  static String api(String path) {
    if (!path.startsWith('/')) {
      path = '/$path';
    }

    return '$backendBase$path';

    // 说明：这里不用 Uri 拼接，因为路径里可能带已经编码好的查询串，
    // 交给调用方自己 Uri.parse 更可控。
  }

  /// 允许用环境变量覆盖端口，方便同时跑多个实例或排错。
  static void applyEnvironment(Map<String, String> env) {
    final backend = int.tryParse(env['HANIME_BACKEND_PORT'] ?? '');
    final cdp = int.tryParse(env['HANIME_CDP_PORT'] ?? '');

    if (backend != null && backend > 0) backendPort = backend;
    if (cdp != null && cdp > 0) cdpPort = cdp;
  }
}
