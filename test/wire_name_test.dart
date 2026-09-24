import 'package:nodus/nodus.dart';
import 'package:test/test.dart';

enum _Status { todo, inProgress, awaitingHTTPReply }

void main() {
  test('enum wire names use the persisted snake_case spelling', () {
    expect(_Status.values.map((value) => value.wireName), [
      'todo',
      'in_progress',
      'awaiting_http_reply',
    ]);
    expect(_Status.values.byWireName('in_progress'), _Status.inProgress);
    expect(_Status.values.asWireNameMap()['unknown'], isNull);
    expect(() => _Status.values.byWireName('inProgress'), throwsArgumentError);
  });
}
