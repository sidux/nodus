import 'package:nodus/nodus.dart';
import 'package:test/test.dart';

final class Account {}

void main() {
  group('LocalId parsing', () {
    test('normalizes a valid UUID while preserving nominal type', () {
      final id = parseLocalId<Account>(
        ' 10000000-0000-4000-8000-0000000000AB ',
      );

      expect(id.value, '10000000-0000-4000-8000-0000000000ab');
    });

    test('returns null or throws for malformed external values', () {
      expect(tryParseLocalId<Account>('not-a-uuid'), isNull);
      expect(
        () => parseLocalId<Account>('not-a-uuid'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => LocalId<Account>('not-a-uuid'),
        throwsA(isA<FormatException>()),
      );
    });

    test('the conventional constructor validates and normalizes too', () {
      final id = LocalId<Account>(' 10000000-0000-4000-8000-0000000000AB ');

      expect(id.value, '10000000-0000-4000-8000-0000000000ab');
    });
  });
}
