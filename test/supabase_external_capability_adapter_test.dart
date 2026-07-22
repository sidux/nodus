import 'package:nodus/nodus_supabase.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

const _functionContract = ExternalCapabilityContract<int, String>(
  name: 'double-value',
  encodeRequest: _encodeValue,
  decodeResponse: _decodeValue,
);

const _rpcContract = ExternalCapabilityContract<String, int>(
  name: 'lookup-score',
  encodeRequest: _encodeId,
  decodeResponse: _decodeScore,
);

Object? _encodeValue(int value) => {'value': value};

String _decodeValue(Object? response) =>
    (response as Map<String, Object?>)['result']! as String;

Object? _encodeId(String id) => {'p_id': id};

int _decodeScore(Object? response) => response as int;

void main() {
  test('JSON contract factories validate and preserve typed codecs', () {
    final object = ExternalCapabilityContract<String, int>.jsonObject(
      name: 'object-result',
      encodeRequest: (request) => {'request': request},
      decodeResponse: (response) => response['count']! as int,
    );
    final list = ExternalCapabilityContract<void, List<String>>.jsonObjectList(
      name: 'list-result',
      encodeRequest: (_) => null,
      decodeResponse: (response) => [
        for (final item in response) item['name']! as String,
      ],
    );

    expect(object.decodeResponse(<String, dynamic>{'count': 2}), 2);
    expect(
      list.decodeResponse(<dynamic>[
        <String, dynamic>{'name': 'A'},
        <String, dynamic>{'name': 'B'},
      ]),
      ['A', 'B'],
    );
    expect(() => object.decodeResponse(const []), throwsFormatException);
    expect(
      () => list.decodeResponse(<Object?>[
        const {'name': 'A'},
        2,
      ]),
      throwsFormatException,
    );
  });

  test('function adapter encodes and decodes one typed contract', () async {
    late String name;
    late Object? body;
    final adapter = SupabaseExternalCapabilityAdapter.forTesting(
      invokeFunction: (capturedName, capturedBody) async {
        name = capturedName;
        body = capturedBody;
        return <String, Object?>{'result': 'six'};
      },
    );

    final result = await adapter.invokeFunction(_functionContract, 3);

    expect(name, 'double-value');
    expect(body, {'value': 3});
    expect(result, 'six');
  });

  test(
    'rpc adapter requires map params and returns the typed result',
    () async {
      late Map<String, Object?>? params;
      final adapter = SupabaseExternalCapabilityAdapter.forTesting(
        callRpc: (_, capturedParams) async {
          params = capturedParams;
          return 42;
        },
      );

      final result = await adapter.callRpc(_rpcContract, 'account-1');

      expect(params, {'p_id': 'account-1'});
      expect(result, 42);
    },
  );

  test(
    'decode failures become a normalized invalid-response failure',
    () async {
      final adapter = SupabaseExternalCapabilityAdapter.forTesting(
        invokeFunction: (_, _) async => const <String, Object?>{},
      );

      await expectLater(
        adapter.invokeFunction(_functionContract, 3),
        throwsA(
          isA<ExternalCapabilityException>()
              .having(
                (error) => error.kind,
                'kind',
                ExternalCapabilityFailureKind.invalidResponse,
              )
              .having(
                (error) => error.capability,
                'capability',
                'double-value',
              ),
        ),
      );
    },
  );

  test(
    'function transport errors preserve normalized auth semantics',
    () async {
      final adapter = SupabaseExternalCapabilityAdapter.forTesting(
        invokeFunction: (_, _) async => throw const FunctionException(
          status: 401,
          details: {
            'error': {'code': 'invalid_jwt', 'message': 'JWT expired'},
          },
        ),
      );

      await expectLater(
        adapter.invokeFunction(_functionContract, 3),
        throwsA(
          isA<ExternalCapabilityException>()
              .having(
                (error) => error.kind,
                'kind',
                ExternalCapabilityFailureKind.authentication,
              )
              .having((error) => error.code, 'code', 'invalid_jwt'),
        ),
      );
    },
  );

  test('unexpected transport errors become unavailable failures', () async {
    final adapter = SupabaseExternalCapabilityAdapter.forTesting(
      callRpc: (_, _) async => throw StateError('connection closed'),
    );

    await expectLater(
      adapter.callRpc(_rpcContract, 'account-1'),
      throwsA(
        isA<ExternalCapabilityException>()
            .having(
              (error) => error.kind,
              'kind',
              ExternalCapabilityFailureKind.unavailable,
            )
            .having((error) => error.code, 'code', 'transport_unavailable'),
      ),
    );
  });
}
