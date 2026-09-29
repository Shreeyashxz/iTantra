import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized Android runtime permission requests.
/// Manifest declares permissions; Android 12/13+ still requires runtime grant.
class AppPermissions {
  static Future<bool> ensureMicrophone() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return true;
    var status = await Permission.microphone.status;
    if (status.isGranted || status.isLimited) return true;
    status = await Permission.microphone.request();
    return status.isGranted || status.isLimited;
  }

  static Future<bool> ensureMeshPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    bool ok = true;
    // Wi-Fi Direct / BLE scan needs location on Android 10-11, BT perms on 12+.
    try {
      final loc = await Permission.location.request();
      if (loc.isPermanentlyDenied) ok = false;
    } catch (_) {}
    try {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      if (scan.isPermanentlyDenied || connect.isPermanentlyDenied) {
        debugPrint('[Permissions] BLE perms permanently denied');
      }
    } catch (_) {
      // Older Android: permission_handler may not define these; ignore.
    }
    return ok;
  }

  static Future<bool> ensureNotifications() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final s = await Permission.notification.request();
      return s.isGranted || s.isLimited || s.isProvisional;
    } catch (_) {
      return true;
    }
  }
}
