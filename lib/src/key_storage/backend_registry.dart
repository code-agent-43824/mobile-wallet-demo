import 'key_storage_backend.dart';
import 'secure_key_value_store.dart';

enum WalletBackendKind { phoneSecureVault, externalDevice }

class WalletBackendDescriptor {
  const WalletBackendDescriptor({
    required this.id,
    required this.kind,
    required this.label,
    required this.description,
    this.isAvailable = true,
    this.availabilityNote,
  });

  final String id;
  final WalletBackendKind kind;
  final String label;
  final String description;
  final bool isAvailable;
  final String? availabilityNote;
}

class WalletBackendCatalogEntry {
  const WalletBackendCatalogEntry({required this.descriptor, this.backend});

  final WalletBackendDescriptor descriptor;
  final KeyStorageBackend? backend;
}

class SelectedWalletBackend {
  const SelectedWalletBackend({
    required this.backendId,
    required this.selectedAtUtc,
  });

  final String backendId;
  final DateTime selectedAtUtc;
}

class WalletBackendRegistry {
  WalletBackendRegistry({
    required SecureKeyValueStore store,
    required List<WalletBackendCatalogEntry> entries,
  }) : _store = store,
       _entriesById = {for (final entry in entries) entry.descriptor.id: entry};

  static const String selectionStorageKey =
      'wallet.backend_registry.selected_backend.v1';

  final SecureKeyValueStore _store;
  final Map<String, WalletBackendCatalogEntry> _entriesById;

  List<WalletBackendCatalogEntry> get entries => _entriesById.values.toList();

  List<WalletBackendCatalogEntry> get availableEntries => entries
      .where((entry) => entry.descriptor.isAvailable && entry.backend != null)
      .toList();

  WalletBackendDescriptor? descriptorById(String backendId) {
    return _entriesById[backendId]?.descriptor;
  }

  KeyStorageBackend? backendById(String backendId) {
    return _entriesById[backendId]?.backend;
  }

  Future<SelectedWalletBackend?> loadSelection() async {
    final raw = await _store.read(selectionStorageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final parts = raw.split('|');
    if (parts.length != 2) {
      return null;
    }

    final selectedAtUtc = DateTime.tryParse(parts[1]);
    if (selectedAtUtc == null) {
      return null;
    }

    return SelectedWalletBackend(
      backendId: parts[0],
      selectedAtUtc: selectedAtUtc,
    );
  }

  Future<String> loadSelectedBackendId() async {
    final selection = await loadSelection();
    final selectedBackendId = selection?.backendId;
    if (selectedBackendId != null && _canUseBackend(selectedBackendId)) {
      return selectedBackendId;
    }

    final fallback = defaultBackendId;
    await selectBackend(fallback);
    return fallback;
  }

  String get defaultBackendId {
    final candidates = availableEntries;
    if (candidates.isEmpty) {
      throw const VaultFailure('No available key storage backends configured.');
    }
    return candidates.first.descriptor.id;
  }

  Future<void> selectBackend(String backendId) async {
    if (!_canUseBackend(backendId)) {
      throw const VaultFailure(
        'Selected key storage backend is unavailable in this build.',
      );
    }

    final value = '$backendId|${DateTime.now().toUtc().toIso8601String()}';
    await _store.write(selectionStorageKey, value);
  }

  Future<KeyStorageBackend> loadSelectedBackend() async {
    final backendId = await loadSelectedBackendId();
    final backend = backendById(backendId);
    if (backend == null) {
      throw const VaultFailure('Selected backend is missing from registry.');
    }
    return backend;
  }

  bool _canUseBackend(String backendId) {
    final entry = _entriesById[backendId];
    if (entry == null) {
      return false;
    }
    return entry.descriptor.isAvailable && entry.backend != null;
  }
}
