import 'package:flutter/material.dart';

class ThemeStore {
  // どこからでも参照できるように static
  static final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  static bool get isDark => mode.value == ThemeMode.dark;

  static void setDark(bool on) {
    mode.value = on ? ThemeMode.dark : ThemeMode.light;
  }

  static void setSystem() {
    mode.value = ThemeMode.system;
  }
}
