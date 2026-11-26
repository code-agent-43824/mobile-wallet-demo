// The app's layout in every iPhone Duo pose, with the iOS pattern set.
//
// Logical sizes and safe-area insets are Somnio's measurements on the iPhone
// Duo simulator (Xcode 27.1, Flutter 3.47.5); Apple publishes no point sizes.
// See docs/JOURNAL.md, 2026-11-25. A RenderFlex overflow anywhere fails the
// test, so walking the screens is itself the check.
// Flutter 3.50 deprecates the library in favour of package:material_ui;
// see docs/PLAN.md for the migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';
import 'package:mobile_wallet_demo/src/blockchain/blockchain_provider.dart';
import 'package:mobile_wallet_demo/src/blockchain/network_config.dart';
import 'package:mobile_wallet_demo/src/key_storage/phone_secure_vault.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/qr/qr_scanner.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wallet_connect_service.dart';

class _Pose {
  const _Pose(this.name, this.size, this.padding);

  final String name;
  final Size size;
  final EdgeInsets padding;

  /// Wide enough for the side navigation (see `AppShell`).
  bool get isWide => size.width >= 600;
}

const List<_Pose> _duoPoses = <_Pose>[
  _Pose(
    'closed, portrait',
    Size(466, 678),
    EdgeInsets.only(right: 84, bottom: 34),
  ),
  _Pose(
    'closed, landscape',
    Size(678, 466),
    EdgeInsets.only(left: 84, bottom: 34),
  ),
  _Pose('open, portrait', Size(669, 951), EdgeInsets.only(top: 82, bottom: 34)),
  _Pose(
    'open, landscape',
    Size(951, 669),
    EdgeInsets.only(right: 84, bottom: 34),
  ),
  _Pose('open, Split View', Size(469, 669), EdgeInsets.only(bottom: 34)),
];

class _FakeBlockchainProvider implements BlockchainProvider {
  @override
  Future<WalletChainSnapshot> loadSnapshot({
    required EvmNetwork network,
    required String address,
  }) async {
    return WalletChainSnapshot(
      network: network,
      address: address,
      nativeBalanceWei: BigInt.parse('1230000000000000000'),
      nativeBalanceFormatted: '1.23',
      baseFeeGwei: 12.345,
      providerLabel: 'fake-rpc.local',
      fetchedAtUtc: DateTime.utc(2026, 11, 25),
      tokenBalances: <TokenBalanceSnapshot>[
        TokenBalanceSnapshot(
          symbol: 'USDC',
          name: 'USD Coin',
          balanceFormatted: '42.5',
          rawBalance: BigInt.from(42500000),
          decimals: 6,
          contractAddress: '0x6666666666666666666666666666666666666666',
        ),
      ],
      recentTransactions: const <RecentTransactionSnapshot>[],
    );
  }
}

void _setPose(WidgetTester tester, _Pose pose) {
  const ratio = 3.0;
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = pose.size * ratio;
  final insets = FakeViewPadding(
    left: pose.padding.left * ratio,
    top: pose.padding.top * ratio,
    right: pose.padding.right * ratio,
    bottom: pose.padding.bottom * ratio,
  );
  tester.view.padding = insets;
  tester.view.viewPadding = insets;
  addTearDown(tester.view.reset);
}

Future<void> _tapShown(WidgetTester tester, Finder finder) async {
  final target = finder.last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _createWallet(WidgetTester tester) async {
  await _tapShown(tester, find.text('Создать кошелёк'));
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), '1234');
  await tester.enterText(fields.at(1), '1234');
  await _tapShown(tester, find.text('Создать кошелёк'));
  await _tapShown(tester, find.text('Я сохранил seed-фразу'));
  await _tapShown(tester, find.text('Пока без биометрии'));
}

Widget _app(SecureKeyValueStore store) => MobileWalletDemoApp(
  locale: const Locale('ru'),
  store: store,
  blockchainProvider: _FakeBlockchainProvider(),
  walletConnectService: FakeWalletConnectService(),
  qrScanner: FakeQrScanner(),
);

/// Turns on «Запрашивать PIN при открытии» and starts the app again on the
/// same storage, which opens on the lock screen.
Future<void> _restartLocked(
  WidgetTester tester,
  SecureKeyValueStore store,
) async {
  await tester.tap(find.text('Настройки').last);
  await tester.pumpAndSettle();
  await _tapShown(tester, find.text('Запрашивать PIN при открытии'));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(_app(store));
  await tester.pumpAndSettle();
  expect(find.text('Кошелёк заблокирован'), findsOneWidget);
}

void main() {
  setUp(() => PhoneSecureVault.debugIterationsOverride = 2);
  tearDown(() => PhoneSecureVault.debugIterationsOverride = null);

  // 1.0 is the default text size; 2.0 is between iOS's AX2 and AX3 Dynamic
  // Type sizes, where every screen must still fit (scrolling where needed).
  for (final textScale in <double>[1, 2]) {
    for (final pose in _duoPoses) {
      testWidgets(
        'iPhone Duo ${pose.name}, text ×$textScale: every screen fits',
        (tester) async {
          _setPose(tester, pose);
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(_app(InMemorySecureKeyValueStore()));
          await tester.pumpAndSettle();
          await _createWallet(tester);

          // No tab label is cut short, at any text size.
          for (final label in <String>[
            'Кошелёк',
            'Активность',
            'Связи',
            'Настройки',
          ]) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(label).last,
            );
            expect(paragraph.didExceedMaxLines, isFalse, reason: label);
          }

          // The tabs sit on the side of a wide window and along the bottom of a
          // narrow one.
          final tab = tester.getCenter(find.text('Связи'));
          if (pose.isWide) {
            expect(tab.dx, lessThan(pose.padding.left + 120));
          } else {
            expect(tab.dy, greaterThan(pose.size.height - 120));
          }

          for (final name in <String>['Активность', 'Связи', 'Настройки']) {
            await tester.tap(find.text(name).last);
            await tester.pumpAndSettle();
          }

          // The PIN sheet a private-key operation opens.
          await tester.tap(find.text('Связи').last);
          await tester.pumpAndSettle();
          await _tapShown(tester, find.text('Показать QR аккаунта'));
          expect(find.text('Отмена'), findsWidgets);
          await _tapShown(tester, find.text('Отмена'));

          await tester.tap(find.text('Кошелёк').last);
          await tester.pumpAndSettle();
          await _tapShown(tester, find.text('Получить'));
          await _tapShown(tester, find.text('Закрыть'));

          // The send sheet and the network picker.
          await _tapShown(tester, find.text('Отправить'));
          await _tapShown(tester, find.byTooltip('Закрыть'));
          await _tapShown(tester, find.text('Ethereum Mainnet'));
          await _tapShown(tester, find.text('Ethereum Mainnet'));
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );

      testWidgets('iPhone Duo ${pose.name}, text ×$textScale: the lock screen '
          '${textScale == 1 ? 'fits without scrolling' : 'fits'}', (
        tester,
      ) async {
        _setPose(tester, pose);
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = InMemorySecureKeyValueStore();
        await tester.pumpWidget(_app(store));
        await tester.pumpAndSettle();
        await _createWallet(tester);
        await _restartLocked(tester, store);

        if (textScale == 1) {
          // Everything is on screen at once: the wallet, the bottom row of
          // keys and the button, inside the window's safe area.
          final top = pose.padding.top;
          final bottom = pose.size.height - pose.padding.bottom;
          for (final finder in <Finder>[
            find.byIcon(Icons.account_balance_wallet_outlined),
            find.byKey(const ValueKey<String>('pin-key-0')),
            find.text('Разблокировать'),
          ]) {
            final rect = tester.getRect(finder);
            expect(rect.top, greaterThanOrEqualTo(top), reason: '$finder');
            expect(rect.bottom, lessThanOrEqualTo(bottom), reason: '$finder');
          }
          // Keys keep a key's proportions, not a bar's.
          expect(
            tester
                .getSize(find.byKey(const ValueKey<String>('pin-key-5')))
                .width,
            lessThan(140),
          );
        }

        for (final digit in <String>['1', '2', '3', '4']) {
          await _tapShown(
            tester,
            find.byKey(ValueKey<String>('pin-key-$digit')),
          );
        }
        await _tapShown(tester, find.text('Разблокировать'));
        expect(find.text('Кошелёк заблокирован'), findsNothing);
        expect(find.text('Отправить'), findsOneWidget);
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }
  }
}
