import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class InstallationIdentity {
  InstallationIdentity._();

  static const _storageKey = 'healing_hi_installation_id_v1';
  static const _storage = FlutterSecureStorage();

  static String? _id;
  static String? _legacyId;

  static String get id {
    final value = _id;
    if (value == null) {
      throw StateError('InstallationIdentity.initialize() must run first.');
    }
    return value;
  }

  static String? get legacyId => _legacyId;

  static Future<void> initialize() async {
    var storedId = await _storage.read(key: _storageKey);
    if (storedId == null || storedId.isEmpty) {
      storedId = const Uuid().v4();
      await _storage.write(key: _storageKey, value: storedId);
    }

    _id = storedId;
    _legacyId = await _readLegacyDeviceId();
  }

  static Future<String?> _readLegacyDeviceId() async {
    if (kIsWeb) return null;

    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) return (await deviceInfo.androidInfo).id;
    if (Platform.isIOS) {
      return (await deviceInfo.iosInfo).identifierForVendor;
    }
    if (Platform.isWindows) return (await deviceInfo.windowsInfo).deviceId;
    if (Platform.isLinux) return (await deviceInfo.linuxInfo).machineId;
    if (Platform.isMacOS) return (await deviceInfo.macOsInfo).systemGUID;
    return null;
  }
}
