import 'package:drift/drift.dart';

Future<QueryExecutor> openApplicationSupportNodusStore({
  required String packageName,
  required String accountId,
}) => throw UnsupportedError(
  'The default Nodus local store is not available on this platform. '
  'Provide a platform-specific NodusLocalStore.',
);

QueryExecutor openNodusInMemoryExecutor() => throw UnsupportedError(
  'The default in-memory Nodus executor is not available on this platform.',
);
