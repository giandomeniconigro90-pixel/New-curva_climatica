// lib/utils/app_toast.dart

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

enum ToastLevel { info, success, warning, error }

class AppToast {
  /// Mostra un toast su mobile (Fluttertoast) o uno SnackBar su desktop.
  /// [context] è necessario solo su desktop; su mobile viene ignorato.
  static void show(
    String message, {
    BuildContext? context,
    ToastLevel level = ToastLevel.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (_isDesktop) {
      assert(context != null,
          'AppToast.show: context è obbligatorio su desktop');
      if (context == null) return;
      final color = _snackColor(level);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: color,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } else {
      Fluttertoast.showToast(
        msg: message,
        backgroundColor: _toastColor(level),
        textColor: Colors.white,
        fontSize: 14,
        toastLength: duration.inSeconds > 3 ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT,
      );
    }
  }

  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  static Color _toastColor(ToastLevel level) {
    switch (level) {
      case ToastLevel.success: return const Color(0xFF43A047);
      case ToastLevel.warning: return const Color(0xFFF57C00);
      case ToastLevel.error:   return const Color(0xFFD32F2F);
      case ToastLevel.info:    return const Color(0xFF1565C0);
    }
  }

  static Color _snackColor(ToastLevel level) {
    switch (level) {
      case ToastLevel.success: return const Color(0xFF2E7D32);
      case ToastLevel.warning: return const Color(0xFFE65100);
      case ToastLevel.error:   return const Color(0xFFB71C1C);
      case ToastLevel.info:    return const Color(0xFF0D47A1);
    }
  }
}
