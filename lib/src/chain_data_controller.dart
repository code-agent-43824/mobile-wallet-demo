// widgets.dart rather than foundation.dart: this controller needs `Locale` for
// its default message bundle, and widgets re-exports foundation anyway.
import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'blockchain/blockchain_provider.dart';
import 'blockchain/network_config.dart';

/// Owns the selected network and the chain snapshot the UI renders.
///
/// Lifted out of the dashboard's `State` because the redesign splits that one
/// screen into separate **Кошелёк** and **Активность** tabs, which must show the
/// same balance, assets and history without loading them twice.
///
/// Widget-free on purpose, like [WalletFlowController]: it is a plain
/// [ChangeNotifier] so both tabs can listen and tests can drive it directly.
class ChainDataController extends ChangeNotifier {
  ChainDataController({
    required BlockchainProvider blockchainProvider,
    EvmNetwork initialNetwork = EvmNetwork.ethereumMainnet,
    AppLocalizations? messages,
  }) : _blockchainProvider = blockchainProvider,
       _selectedNetwork = initialNetwork,
       _messages = messages ?? lookupAppLocalizations(const Locale('ru'));

  final BlockchainProvider _blockchainProvider;

  /// Source of the strings this controller produces. Injected like every other
  /// collaborator because a [ChangeNotifier] has no `BuildContext`; the screen
  /// re-points it whenever the locale changes.
  AppLocalizations _messages;

  set messages(AppLocalizations value) => _messages = value;

  EvmNetwork _selectedNetwork;
  WalletChainSnapshot? _snapshot;
  String? _errorMessage;
  bool _isLoading = false;

  /// Monotonic id of the newest in-flight refresh. A response is applied only
  /// when it is still the newest **and** its network is still selected — the
  /// guard that keeps a slow reply from an earlier network from overwriting the
  /// current one (regression fixed in v1.34; do not remove).
  int _refreshId = 0;

  /// The address snapshots are loaded for. Null until the wallet is known.
  String? _address;

  EvmNetwork get selectedNetwork => _selectedNetwork;
  WalletChainSnapshot? get snapshot => _snapshot;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;

  /// The active network's static configuration.
  EvmNetworkConfig get networkConfig => evmNetworkConfigs[_selectedNetwork]!;

  /// True while the first snapshot for the current network is still loading —
  /// the redesign renders its skeleton state here rather than a spinner.
  bool get isInitialLoad => _isLoading && _snapshot == null;

  /// True when the shown data came from the local cache because every live
  /// endpoint failed; the redesign shows an offline banner for this.
  bool get isFromCache => _snapshot?.loadedFromCache ?? false;

  /// Points the controller at [address] and loads its snapshot. Safe to call
  /// repeatedly; a changed address discards the previous snapshot so one
  /// wallet's balance can never be shown under another's address.
  Future<void> setAddress(String? address) async {
    if (_address == address) {
      return;
    }
    _address = address;
    _snapshot = null;
    _errorMessage = null;
    notifyListeners();
    await refresh();
  }

  /// Switches networks and reloads. The previous network's snapshot is dropped
  /// immediately so no stale balance is shown under the new network's name.
  Future<void> selectNetwork(EvmNetwork network) async {
    if (network == _selectedNetwork) {
      return;
    }
    _selectedNetwork = network;
    _snapshot = null;
    _errorMessage = null;
    notifyListeners();
    await refresh();
  }

  /// Reloads the snapshot for the current address and network.
  Future<void> refresh() async {
    final address = _address;
    if (address == null) {
      return;
    }
    final network = _selectedNetwork;
    final refreshId = ++_refreshId;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final snapshot = await _blockchainProvider.loadSnapshot(
        network: network,
        address: address,
      );
      if (!_isCurrent(refreshId, network)) {
        return;
      }
      _snapshot = snapshot;
    } on BlockchainFailure catch (error) {
      if (!_isCurrent(refreshId, network)) {
        return;
      }
      _errorMessage = error.message;
    } catch (error) {
      // Anything the provider does not wrap — a cache read outside its retry
      // loop, a timeout, a decode failure — must still reach the UI. Swallowing
      // it here left the screen with no snapshot, no error and nothing to show.
      if (!_isCurrent(refreshId, network)) {
        return;
      }
      _errorMessage = _messages.errorChainLoadFailed('$error');
    } finally {
      if (_isCurrent(refreshId, network)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int refreshId, EvmNetwork network) =>
      refreshId == _refreshId && network == _selectedNetwork;
}
