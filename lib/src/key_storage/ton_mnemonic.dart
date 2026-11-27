import 'dart:isolate';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

import 'key_storage_backend.dart';

/// TON uses the English word list with its own validation and seed derivation.
abstract final class TonMnemonic {
  static const int wordCount = 24;

  static Future<String> generate() => Isolate.run(() {
    final phrase = TonMnemonicGenerator().fromWordsNumber(wordCount);
    try {
      return phrase.toStr();
    } finally {
      phrase.dispose();
    }
  });

  static String normalize(String phrase) =>
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  /// The caller owns the mutable seed and clears it after use.
  static Future<Uint8List> deriveSeed(String phrase) async {
    final normalized = normalize(phrase);
    final result = await Isolate.run(() => _deriveSeed(normalized));
    if (result == null) {
      throw const InvalidMnemonicFailure();
    }
    return result;
  }

  static Uint8List? _deriveSeed(String phrase) {
    final words = phrase.split(' ');
    final wordList = TonMnemonicLanguages.english.wordList;
    if (words.length != wordCount || !words.every(wordList.contains)) {
      return null;
    }
    final mnemonic = Mnemonic.fromList(words);
    try {
      if (!TonMnemonicValidator().isValid(mnemonic)) return null;
      final seed = TonSeedGenerator(mnemonic).generate();
      try {
        return Uint8List.fromList(seed.take(32).toList(growable: false));
      } finally {
        seed.zero();
      }
    } finally {
      mnemonic.dispose();
    }
  }
}
