import 'package:nodus/nodus.dart';
import 'package:test/test.dart';

void main() {
  test('composite scope keys preserve component order and null', () {
    expect(encodeOrderScopeKey(const ['owner', null]), '["owner",null]');
    expect(
      encodeOrderScopeKey(const ['owner', 'null']),
      isNot(encodeOrderScopeKey(const ['owner', null])),
    );
    expect(
      encodeOrderScopeKey(const ['owner', 'parent']),
      isNot(encodeOrderScopeKey(const ['parent', 'owner'])),
    );
  });

  group('OrderRank', () {
    test('normalizes and validates its canonical wire representation', () {
      final source = '${_repeat('0', 77)}1';
      final rank = OrderRank.parse('  $source  ');

      expect(rank.value, source);
      expect(OrderRank.tryParse(source), rank);
      expect(OrderRank.isValid(source), isTrue);
    });

    test('rejects malformed and reserved boundary values', () {
      final maximum = ((BigInt.one << 256) - BigInt.one).toString().padLeft(
        78,
        '0',
      );

      for (final source in [
        '',
        '1',
        '${_repeat('0', 77)}x',
        _repeat('0', 78),
        maximum,
      ]) {
        expect(OrderRank.tryParse(source), isNull, reason: source);
        expect(
          () => OrderRank.parse(source),
          throwsA(isA<FormatException>()),
          reason: source,
        );
      }
    });

    test('allocates deterministic keys whose text and value order agree', () {
      final ranks = GeneratedOrderRanks.allocate(count: 4)!;

      expect(ranks, orderedEquals([...ranks]..sort()));
      expect(
        ranks.map((rank) => rank.value),
        orderedEquals(ranks.map((rank) => rank.value).toList()..sort()),
      );
      expect(GeneratedOrderRanks.allocate(count: 4), ranks);
    });

    test('allocates strictly between either or both neighbors', () {
      final middle = GeneratedOrderRanks.between()!;
      final lower = GeneratedOrderRanks.between(before: middle)!;
      final upper = GeneratedOrderRanks.between(after: middle)!;
      final between = GeneratedOrderRanks.between(after: lower, before: upper)!;

      expect(lower.compareTo(between), lessThan(0));
      expect(between.compareTo(upper), lessThan(0));
      expect(lower.compareTo(middle), lessThan(0));
      expect(middle.compareTo(upper), lessThan(0));
    });

    test('supports repeated insertion into one gap before rebalance', () {
      var upper = GeneratedOrderRanks.between()!;
      final descending = <OrderRank>[upper];

      for (var index = 0; index < 200; index += 1) {
        upper = GeneratedOrderRanks.between(before: upper)!;
        descending.add(upper);
      }

      expect(descending.toSet(), hasLength(descending.length));
      expect([...descending]..sort(), orderedEquals(descending.reversed));
    });

    test('reports exhausted intervals and invalid neighbor order', () {
      final one = OrderRank.parse('${_repeat('0', 77)}1');
      final two = OrderRank.parse('${_repeat('0', 77)}2');

      expect(GeneratedOrderRanks.between(after: one, before: two), isNull);
      expect(
        () => GeneratedOrderRanks.between(after: two, before: one),
        throwsArgumentError,
      );
      expect(() => GeneratedOrderRanks.allocate(count: -1), throwsRangeError);
      expect(GeneratedOrderRanks.allocate(count: 0), isEmpty);
    });
  });

  group('ReorderOrderedCommand', () {
    test('round-trips exact typed membership and scope version', () {
      final command = ReorderOrderedCommand<_OrderedItem>(
        orderedIds: [
          parseLocalId('a0000000-0000-7000-8000-000000000001'),
          parseLocalId('a0000000-0000-7000-8000-000000000002'),
        ],
        scopeBaseVersion: OrderScopeVersion(3),
      );

      final decoded = ReorderOrderedCommand<_OrderedItem>.fromWire(
        command.toWire(),
        parseId: parseLocalId,
      );

      expect(decoded.orderedIds, command.orderedIds);
      expect(decoded.scopeBaseVersion, OrderScopeVersion(3));
    });

    test('rejects empty, duplicate, and malformed exact membership', () {
      const first = 'a0000000-0000-7000-8000-000000000001';
      expect(
        () => ReorderOrderedCommand<_OrderedItem>(
          orderedIds: const [],
          scopeBaseVersion: OrderScopeVersion.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => ReorderOrderedCommand<_OrderedItem>(
          orderedIds: [parseLocalId(first), parseLocalId(first)],
          scopeBaseVersion: OrderScopeVersion.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => ReorderOrderedCommand<_OrderedItem>.fromWire(const {
          'orderedIds': [first, 2],
          'scopeBaseVersion': 0,
        }, parseId: parseLocalId),
        throwsFormatException,
      );
    });
  });

  group('ReplaceActiveRelationshipCommand', () {
    test('round-trips exact base membership and typed active pairs', () {
      const source = 'a0000000-0000-7000-8000-000000000001';
      const firstLink = 'a0000000-0000-7000-8000-000000000002';
      const secondLink = 'a0000000-0000-7000-8000-000000000003';
      const firstTarget = 'a0000000-0000-7000-8000-000000000004';
      const secondTarget = 'a0000000-0000-7000-8000-000000000005';
      final command =
          ReplaceActiveRelationshipCommand<
            _RelationshipLink,
            _RelationshipSource,
            _RelationshipTarget
          >(
            sourceId: parseLocalId(source),
            baseActiveLinkIds: [parseLocalId(firstLink)],
            activeMembers: [
              ActiveRelationshipMember(
                linkId: parseLocalId(firstLink),
                targetId: parseLocalId(firstTarget),
              ),
              ActiveRelationshipMember(
                linkId: parseLocalId(secondLink),
                targetId: parseLocalId(secondTarget),
              ),
            ],
          );

      final decoded =
          ReplaceActiveRelationshipCommand<
            _RelationshipLink,
            _RelationshipSource,
            _RelationshipTarget
          >.fromWire(
            command.toWire(),
            parseLinkId: parseLocalId,
            parseSourceId: parseLocalId,
            parseTargetId: parseLocalId,
          );

      expect(decoded.sourceId, command.sourceId);
      expect(decoded.baseActiveLinkIds, command.baseActiveLinkIds);
      expect(
        decoded.activeMembers.map((member) => member.toWire()),
        command.activeMembers.map((member) => member.toWire()),
      );
    });

    test('rejects duplicate pairs and malformed payloads', () {
      const source = 'a0000000-0000-7000-8000-000000000001';
      const link = 'a0000000-0000-7000-8000-000000000002';
      const target = 'a0000000-0000-7000-8000-000000000003';
      expect(
        () =>
            ReplaceActiveRelationshipCommand<
              _RelationshipLink,
              _RelationshipSource,
              _RelationshipTarget
            >(
              sourceId: parseLocalId(source),
              baseActiveLinkIds: const [],
              activeMembers: [
                ActiveRelationshipMember(
                  linkId: parseLocalId(link),
                  targetId: parseLocalId(target),
                ),
                ActiveRelationshipMember(
                  linkId: parseLocalId(link),
                  targetId: parseLocalId(target),
                ),
              ],
            ),
        throwsArgumentError,
      );
      expect(
        () =>
            ReplaceActiveRelationshipCommand<
              _RelationshipLink,
              _RelationshipSource,
              _RelationshipTarget
            >.fromWire(
              const {
                'sourceId': source,
                'baseActiveLinkIds': [],
                'activeMembers': [
                  {'linkId': link},
                ],
              },
              parseLinkId: parseLocalId,
              parseSourceId: parseLocalId,
              parseTargetId: parseLocalId,
            ),
        throwsFormatException,
      );
    });
  });

  group('OrderedCreateIntent', () {
    test('round-trips a boundary placement and scope version', () {
      final intent = OrderedCreateIntent(
        placement: OrderedPlacement.first,
        scopeBaseVersion: OrderScopeVersion(7),
      );

      final decoded = OrderedCreateIntent.fromWire(intent.toWire());

      expect(decoded.placement, OrderedPlacement.first);
      expect(decoded.scopeBaseVersion, OrderScopeVersion(7));
      expect(decoded.toWire(), {'placement': 'first', 'scopeBaseVersion': 7});
    });

    test('rejects neighbors, missing fields, and invalid scope versions', () {
      expect(
        () => OrderedCreateIntent(
          placement: OrderedPlacement.before,
          scopeBaseVersion: OrderScopeVersion.zero,
        ),
        throwsArgumentError,
      );
      for (final payload in <JsonMap>[
        const {'placement': 'before', 'scopeBaseVersion': 0},
        const {'placement': 'first'},
        const {'placement': 'last', 'scopeBaseVersion': -1},
      ]) {
        expect(
          () => OrderedCreateIntent.fromWire(payload),
          throwsFormatException,
          reason: payload.toString(),
        );
      }
    });
  });
}

final class _OrderedItem {}

final class _RelationshipLink {}

final class _RelationshipSource {}

final class _RelationshipTarget {}

String _repeat(String value, int count) => List.filled(count, value).join();
