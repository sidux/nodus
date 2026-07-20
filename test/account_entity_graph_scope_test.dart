@Tags(['flutter'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodus/nodus_flutter.dart';

void main() {
  testWidgets('optional ready lookup returns null without a scope', (
    tester,
  ) async {
    AccountEntityGraphReady<_TestEntityGraph, _TestAccount>? observed;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          observed =
              AccountEntityGraphScope.maybeReadyOf<
                _TestEntityGraph,
                _TestAccount
              >(context);
          return const SizedBox();
        },
      ),
    );

    expect(observed, isNull);
  });

  testWidgets(
    'scope rebuilds for session transitions and exposes ready entity graph',
    (tester) async {
      final session = AccountEntityGraphSession<_TestEntityGraph, _TestAccount>(
        open: (accountId) async => _TestEntityGraph(accountId.value),
        close: (_) async {},
      );
      AccountEntityGraphSessionState<_TestEntityGraph, _TestAccount>? observed;
      AccountEntityGraphSession<_TestEntityGraph, _TestAccount>?
      observedSession;

      await tester.pumpWidget(
        AccountEntityGraphScope<_TestEntityGraph, _TestAccount>(
          session: session,
          child: Builder(
            builder: (context) {
              observed =
                  AccountEntityGraphScope.stateOf<
                    _TestEntityGraph,
                    _TestAccount
                  >(context);
              observedSession =
                  AccountEntityGraphScope.sessionOf<
                    _TestEntityGraph,
                    _TestAccount
                  >(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        observed,
        isA<AccountEntityGraphSignedOut<_TestEntityGraph, _TestAccount>>(),
      );
      expect(observedSession, same(session));

      const id = '00000000-0000-4000-8000-000000000001';
      await session.switchAccount(parseLocalId<_TestAccount>(id));
      await tester.pump();

      final ready =
          observed as AccountEntityGraphReady<_TestEntityGraph, _TestAccount>;
      expect(ready.accountId.value, id);
      expect(ready.entityGraph.accountId, id);

      final accountId = await observedSession!.withReadyEntityGraph(
        (accountId, entityGraph) =>
            '${accountId.value}:${entityGraph.accountId}',
      );
      expect(accountId, '$id:$id');

      await tester.pumpWidget(const SizedBox());
      await session.dispose();
    },
  );
}

final class _TestEntityGraph {
  const _TestEntityGraph(this.accountId);

  final String accountId;
}

final class _TestAccount {}
