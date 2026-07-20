/// Deterministic test support used by generated Nodus graph harnesses.
library;

export 'nodus.dart';

import 'package:nodus/nodus.dart';

/// Deterministic clock intended for generated graph harnesses.
final class NodusTestClock implements Clock {
  NodusTestClock([DateTime? initial])
    : _now = (initial ?? DateTime.utc(2025)).toUtc();

  DateTime _now;

  @override
  DateTime nowUtc() => _now;

  void set(DateTime value) => _now = value.toUtc();

  void advance(Duration duration) => _now = _now.add(duration);
}
