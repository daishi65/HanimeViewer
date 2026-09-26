import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';

/// 登录状态。
///
/// 登录动作本身是在**后端**完成的：后端让用户自己的调试 Chrome
/// 打开 Hanime 的登录页并提交表单，所以 session cookie 保存在浏览器里，
/// 后续所有抓取请求自动带上登录态。
///
/// 客户端这边只负责：
/// - 记住上次看到的账号信息（用于启动时立刻显示头像，不用等接口）
/// - 提供 login / logout / refresh
///
/// 注意：本地**不保存密码**。
class AccountInfo {
  final bool loggedIn;
  final String userId;
  final String username;
  final String avatar;
  final String url;

  const AccountInfo({
    this.loggedIn = false,
    this.userId = '',
    this.username = '',
    this.avatar = '',
    this.url = '',
  });

  static const AccountInfo guest = AccountInfo();

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    return AccountInfo(
      loggedIn: json['logged_in'] == true,
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'logged_in': loggedIn,
        'user_id': userId,
        'username': username,
        'avatar': avatar,
        'url': url,
      };

  /// 有头像或名字才算「看起来已登录」
  bool get hasProfile => loggedIn && (avatar.isNotEmpty || username.isNotEmpty);
}

class AuthController {
  AuthController._();

  static String get _base => AppConfig.backendBase;

  /// 上次看到的账号信息（本地缓存，只为启动时立刻显示）
  static const String _cacheKey = 'account_cache';

  static final ValueNotifier<AccountInfo> account =
      ValueNotifier<AccountInfo>(AccountInfo.guest);

  static bool get isLoggedIn => account.value.loggedIn;

  /// 启动时调用：先用本地缓存显示，再异步向后端确认。
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);

      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);

        if (decoded is Map) {
          account.value = AccountInfo.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      }
    } catch (_) {
      // 缓存坏了就用默认值，不影响启动
    }

    // 后台确认真实状态（浏览器里可能已经登录/登出）
    unawaited(refresh());
  }

  /// 向后端查询真实登录状态。
  static Future<void> refresh({bool force = false}) async {
    try {
      final uri = Uri.parse(
        '$_base/api/account${force ? '?force=true' : ''}',
      );

      final response = await http.get(uri).timeout(
            const Duration(seconds: 40),
          );

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);

      if (data is! Map) return;

      final info = AccountInfo.fromJson(
        Map<String, dynamic>.from(data),
      );

      account.value = info;
      await _persist(info);
    } catch (_) {
      // 后端没起来时保持现状，不要清掉已显示的头像
    }
  }

  /// 登录。返回 (成功, 错误信息)。
  static Future<(bool, String)> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/api/login'),
            headers: const {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 90));

      final body = jsonDecode(response.body);

      if (response.statusCode != 200) {
        final detail = body is Map ? body['detail']?.toString() : null;

        return (false, detail ?? '登录失败（${response.statusCode}）');
      }

      if (body is Map && body['account'] is Map) {
        final info = AccountInfo.fromJson(
          Map<String, dynamic>.from(body['account']),
        );

        account.value = info;
        await _persist(info);
      } else {
        await refresh(force: true);
      }

      return (true, '');
    } catch (e) {
      return (false, '登录请求失败：$e');
    }
  }

  static Future<void> logout() async {
    try {
      await http
          .post(Uri.parse('$_base/api/logout'))
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      // 即使请求失败也把本地状态清掉
    }

    account.value = AccountInfo.guest;
    await _persist(AccountInfo.guest);
  }

  static Future<void> _persist(AccountInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        _cacheKey,
        jsonEncode(info.toJson()),
      );
    } catch (_) {}
  }
}
