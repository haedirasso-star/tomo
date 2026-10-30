part of '../main.dart';

/// جلسة الدخول تُحفظ في التخزين المشفّر للجهاز (Keychain في آيفون · Keystore في أندرويد)
/// بدل التخزين العادي ⇐ لا يمكن سرقتها من نسخة احتياطية أو تطبيق آخر
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage();
  static const _key = 'to_auth_session_v1';
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => (await _s.read(key: _key)) != null;
  @override
  Future<String?> accessToken() => _s.read(key: _key);
  @override
  Future<void> removePersistedSession() => _s.delete(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) => _s.write(key: _key, value: persistSessionString);
}
