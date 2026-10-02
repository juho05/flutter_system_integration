/// Persistent storage used to remember version checking and AppImage state.
///
/// [store] receives [String], [bool], [DateTime] and objects with a `toJson`
/// method. Loading must return values of the same type that were stored.
abstract interface class KeyValueStore {
  Future<void> store<T>(String key, T value);

  Future<void> remove(String key);

  Future<String?> loadString(String key);

  Future<bool?> loadBool(String key);

  Future<DateTime?> loadDateTime(String key);

  Future<T?> loadObject<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  );
}
