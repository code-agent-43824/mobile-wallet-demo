import 'dart:async';

import 'package:flutter/foundation.dart';

import '../errors/app_error.dart';
import '../key_storage/phone_ton_vault.dart';
import '../key_storage/rutoken_ton_vault.dart';
import '../transactions/transaction_service.dart';
import 'ton_account.dart';
import 'ton_transfer_service.dart';

enum TonSetupMethod {
  phoneCreate,
  phoneImport,
  cardCreate,
  cardImport,
  cardGenerate,
  cardAdopt;

  bool get usesCard => this != phoneCreate && this != phoneImport;
  bool get createsPhrase => this == phoneCreate || this == cardCreate;
  bool get usesPhrase =>
      createsPhrase || this == phoneImport || this == cardImport;
}

class TonWalletSelection {
  const TonWalletSelection.phone(this.account) : card = null;
  TonWalletSelection.card(RutokenTonProfile profile)
    : card = profile,
      account = profile.key.account;

  final TonAccount account;
  final RutokenTonProfile? card;
}

class TonWalletController extends ChangeNotifier {
  TonWalletController({
    required PhoneTonVault phone,
    required RutokenTonVault? card,
    required TonTransferService transfers,
  }) : _phone = phone,
       _card = card,
       _transfers = transfers;

  final PhoneTonVault _phone;
  final RutokenTonVault? _card;
  final TonTransferService _transfers;

  TonWalletSelection? phone;
  List<TonWalletSelection> cards = const [];
  TonWalletSelection? selection;
  TonSnapshot? snapshot;
  Object? error;
  bool loading = true;
  bool refreshing = false;
  bool awaitingTransfer = false;
  bool biometricsAvailable = false;
  bool biometricsEnabled = false;
  bool _disposed = false;
  int _refreshId = 0;

  bool get cardAvailable => _card != null;

  Future<void> load() async {
    // A failure in one vault must still let the other wallet open.
    try {
      final account = await _phone.getAccount();
      if (account != null) phone = TonWalletSelection.phone(account);
    } catch (failure) {
      error = failure;
    }
    try {
      cards = (await _card?.profiles() ?? [])
          .map(TonWalletSelection.card)
          .toList();
    } catch (failure) {
      error = failure;
    }
    loading = false;
    selection = phone ?? cards.firstOrNull;
    _changed();
    await _loadBiometrics();
    await refresh();
  }

  void select(TonWalletSelection wallet) {
    if (identical(selection, wallet)) return;
    selection = wallet;
    snapshot = null;
    awaitingTransfer = false;
    _changed();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final selected = selection;
    if (_disposed || selected == null) return;
    final requestId = ++_refreshId;
    refreshing = true;
    error = null;
    _changed();
    try {
      final fresh = await _transfers.load(selected.account);
      if (requestId == _refreshId) {
        snapshot = fresh;
        awaitingTransfer = fresh.lastSubmission == TonTransferStatus.pending;
      }
    } catch (failure) {
      if (requestId == _refreshId) error = failure;
    } finally {
      if (requestId == _refreshId) {
        refreshing = false;
        _changed();
      }
    }
  }

  Future<void> setup({
    required TonSetupMethod method,
    required String phrase,
    required String pin,
    String? expectedAddress,
  }) async {
    if (method.usesCard) {
      final vault = _card!;
      final created = switch (method) {
        TonSetupMethod.cardGenerate => await vault.generateOnCard(pin: pin),
        TonSetupMethod.cardAdopt => await vault.adopt(pin: pin),
        _ => await vault.importMnemonic(
          mnemonic: phrase,
          pin: pin,
          expectedAddress: expectedAddress,
        ),
      };
      final wallet = TonWalletSelection.card(created);
      cards = [
        ...cards.where((candidate) => candidate.card!.serial != created.serial),
        wallet,
      ];
      select(wallet);
    } else {
      final account = await _phone.importMnemonic(
        mnemonic: phrase,
        pin: pin,
        expectedAddress: expectedAddress,
      );
      final wallet = TonWalletSelection.phone(account);
      phone = wallet;
      select(wallet);
      await _loadBiometrics();
    }
  }

  Future<TonTransferQuote> prepare(
    TonWalletSelection wallet,
    String recipient,
    String amount,
  ) => _transfers.prepare(
    account: wallet.account,
    recipient: recipient,
    amount: amount,
  );

  Future<bool> submit(
    TonWalletSelection wallet,
    TonTransferQuote quote, {
    String? pin,
    void Function(bool waiting)? onCardPrompt,
  }) async {
    if (!identical(wallet, selection) ||
        !identical(wallet.account, quote.account)) {
      throw const TransactionFailure.coded(AppErrorCode.txSenderMismatch);
    }
    final card = wallet.card;
    final accepted = await _transfers.submit(quote, (hash) async {
      if (card == null) {
        return _phone.sign(account: wallet.account, hash: hash, pin: pin);
      }
      if (pin == null) {
        throw const TransactionFailure.coded(AppErrorCode.cardPinEmpty);
      }
      onCardPrompt?.call(true);
      try {
        return await _card!.sign(profile: card, pin: pin, hash: hash);
      } finally {
        onCardPrompt?.call(false);
      }
    });
    awaitingTransfer = true;
    unawaited(refresh());
    return accepted;
  }

  Future<void> setBiometrics({
    required bool enabled,
    required String pin,
  }) async {
    await _phone.setBiometricUnlockEnabled(enabled: enabled, pin: pin);
    await _loadBiometrics();
  }

  Future<void> _loadBiometrics() async {
    if (phone == null) return;
    try {
      biometricsAvailable = await _phone.isBiometricUnlockAvailable();
      biometricsEnabled = await _phone.isBiometricUnlockEnabled();
      _changed();
    } catch (failure) {
      error = failure;
      _changed();
    }
  }

  Future<void> cancelCardOperation() async {
    await _card?.cancelPendingOperation();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancelCardOperation());
    super.dispose();
  }
}
