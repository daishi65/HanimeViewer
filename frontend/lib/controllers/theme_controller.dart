import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局主题控制器。
///
/// 用法：
/// - 启动时 `await ThemeController.load()` 加载保存的偏好
/// - 用 `ThemeController.mode` (ValueNotifier) 监听变化
/// - 用 `ThemeController.setMode(...)` 切换并持久化
class ThemeController {
  ThemeController._();

  static const String _storageKey = 'app_theme_mode';

  /// 当前主题模式，默认跟随系统
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// 从本地存储加载
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_storageKey) ?? 'system';
      mode.value = _fromString(value);
    } catch (_) {
      // 加载失败就用默认值
      mode.value = ThemeMode.system;
    }
  }

  /// 切换主题并持久化
  static Future<void> setMode(ThemeMode newMode) async {
    mode.value = newMode;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, _toString(newMode));
    } catch (_) {
      // 持久化失败时，只影响下次启动，不抛出
    }
  }

  static ThemeMode _fromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}