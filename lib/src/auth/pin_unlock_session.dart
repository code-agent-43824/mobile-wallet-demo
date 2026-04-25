class PinUnlockSession {
  PinUnlockSession({this.ttl = const Duration(minutes: 5)});

  final Duration ttl;
  DateTime? _unlockedAtUtc;

  bool get isUnlocked {
    final unlockedAtUtc = _unlockedAtUtc;
    if (unlockedAtUtc == null) {
      return false;
    }

    return DateTime.now().toUtc().difference(unlockedAtUtc) <= ttl;
  }

  void unlock() {
    _unlockedAtUtc = DateTime.now().toUtc();
  }

  void lock() {
    _unlockedAtUtc = null;
  }
}
