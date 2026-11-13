part of 'expression_evaluator.dart';

// ---- timestamps ----

// 0001-01-01T00:00:00Z and 9999-12-31T23:59:59Z.
const int _minTimestampSeconds = -62135596800;
const int _maxTimestampSeconds = 253402300799;

final BigInt _nanosPerSecond = BigInt.from(1000000000);

/// The nanoseconds of the units `timestamp_add` and `timestamp_diff` know.
final Map<String, BigInt> _unitNanos = <String, BigInt>{
  'microsecond': BigInt.from(1000),
  'millisecond': BigInt.from(1000000),
  'second': _nanosPerSecond,
  'minute': _nanosPerSecond * BigInt.from(60),
  'hour': _nanosPerSecond * BigInt.from(3600),
  'day': _nanosPerSecond * BigInt.from(86400),
};

BigInt _toNanos(Timestamp timestamp) =>
    BigInt.from(timestamp.seconds) * _nanosPerSecond +
    BigInt.from(timestamp.nanoseconds);

/// The timestamp of [nanos] since the epoch, or an error outside the range
/// of timestamps.
EvaluateResult _fromNanos(BigInt nanos) {
  // Floor division: the nanoseconds of a timestamp count forward.
  BigInt seconds = nanos ~/ _nanosPerSecond;
  BigInt rest = nanos.remainder(_nanosPerSecond);
  if (rest.isNegative) {
    seconds -= BigInt.one;
    rest += _nanosPerSecond;
  }
  if (seconds < BigInt.from(_minTimestampSeconds) ||
      seconds > BigInt.from(_maxTimestampSeconds)) {
    return _error;
  }
  return EvaluateValue(
    TimestampValue.valueOf(Timestamp(seconds.toInt(), rest.toInt())),
  );
}

Timestamp _timestamp(FieldValue value) => (value as TimestampValue).value;

/// The backend only takes a unit (or a part of a timestamp) that is written
/// in the pipeline as a string: it rejects any other expression before it
/// runs the pipeline. Here that is an error.
_Function _literalArgument(int index, _Function function) {
  return (_Call call) => call.length > index && call.literal(index) == null
      ? _error
      : function(call);
}

/// `timestamp_add(timestamp, unit, amount)` and `timestamp_subtract`.
_Function _timestampAdd({required bool subtract}) {
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isTimestamp, _isString, _isInteger],
    (List<FieldValue> v) {
      final BigInt? unit = _unitNanos[_text(v[1])];
      if (unit == null) {
        throw const _EvaluationError();
      }
      final BigInt amount = BigInt.from(_integer(v[2])) * unit;
      return _fromNanos(
        _toNanos(_timestamp(v[0])) + (subtract ? -amount : amount),
      );
    },
  );
}

/// `timestamp_diff(end, start, unit)`: the whole units between the two.
EvaluateResult _timestampDiff(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isTimestamp, _isTimestamp, _isString],
  (List<FieldValue> v) {
    final BigInt? unit = _unitNanos[_text(v[2])];
    if (unit == null) {
      throw const _EvaluationError();
    }
    // The backend keeps microseconds: the difference is taken of the
    // truncated timestamps.
    final BigInt micro = _unitNanos['microsecond']!;
    final BigInt difference =
        (_toNanos(_timestamp(v[0])) ~/ micro -
            _toNanos(_timestamp(v[1])) ~/ micro) *
        micro;
    return _int(_checkedInt64(difference ~/ unit));
  },
);

/// Only UTC is available: the Dart SDK has no time zone database.
void _checkTimeZone(List<FieldValue> values, int index) {
  if (values.length <= index) {
    return;
  }
  final String zone = _text(values[index]);
  if (zone != 'UTC' && zone != 'Etc/UTC' && zone != 'GMT' && zone != 'Z') {
    throw UnsupportedExpression(
      'Time zones other than UTC are not evaluated locally: $zone',
    );
  }
}

DateTime _dateTime(Timestamp timestamp) => DateTime.fromMicrosecondsSinceEpoch(
  timestamp.seconds * 1000000 + timestamp.nanoseconds ~/ 1000,
  isUtc: true,
);

EvaluateResult _fromDateTime(DateTime value) {
  final int micros = value.microsecondsSinceEpoch;
  return _fromNanos(BigInt.from(micros) * BigInt.from(1000));
}

/// The Monday of the ISO week of [date].
DateTime _isoWeekStart(DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day - (date.weekday - DateTime.monday),
);

/// The year the ISO week of [date] belongs to: the year of its Thursday.
int _isoYear(DateTime date) =>
    _isoWeekStart(date).add(const Duration(days: 3)).year;

/// The Monday of the first ISO week of [year]: the week of January 4th.
DateTime _isoYearStart(int year) => _isoWeekStart(DateTime.utc(year, 1, 4));

/// `timestamp_trunc(timestamp, granularity, [timezone])`.
EvaluateResult _timestampTrunc(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isTimestamp, _isString, _isString],
  min: 2,
  max: 3,
  (List<FieldValue> v) {
    _checkTimeZone(v, 2);
    final Timestamp timestamp = _timestamp(v[0]);
    final DateTime t = _dateTime(timestamp);
    final String granularity = _text(v[1]);
    switch (granularity) {
      case 'microsecond':
        return _fromDateTime(t);
      case 'millisecond':
        return _fromDateTime(
          DateTime.utc(
            t.year,
            t.month,
            t.day,
            t.hour,
            t.minute,
            t.second,
            t.millisecond,
          ),
        );
      case 'second':
        return _fromDateTime(
          DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second),
        );
      case 'minute':
        return _fromDateTime(
          DateTime.utc(t.year, t.month, t.day, t.hour, t.minute),
        );
      case 'hour':
        return _fromDateTime(DateTime.utc(t.year, t.month, t.day, t.hour));
      case 'day':
        return _fromDateTime(DateTime.utc(t.year, t.month, t.day));
      case 'week':
      case 'week(sunday)':
        // Weeks begin on Sunday.
        return _fromDateTime(
          DateTime.utc(t.year, t.month, t.day - t.weekday % 7),
        );
      case 'isoweek':
      case 'week(monday)':
        return _fromDateTime(_isoWeekStart(t));
      case 'month':
        return _fromDateTime(DateTime.utc(t.year, t.month));
      case 'quarter':
        return _fromDateTime(DateTime.utc(t.year, t.month - (t.month - 1) % 3));
      case 'year':
        return _fromDateTime(DateTime.utc(t.year));
      case 'isoyear':
        return _fromDateTime(_isoYearStart(_isoYear(t)));
    }
    final int? weekday = _weekdays[granularity];
    if (weekday != null) {
      return _fromDateTime(
        DateTime.utc(t.year, t.month, t.day - (t.weekday - weekday) % 7),
      );
    }
    throw const _EvaluationError();
  },
);

const Map<String, int> _weekdays = <String, int>{
  'week(tuesday)': DateTime.tuesday,
  'week(wednesday)': DateTime.wednesday,
  'week(thursday)': DateTime.thursday,
  'week(friday)': DateTime.friday,
  'week(saturday)': DateTime.saturday,
};

/// `timestamp_extract(timestamp, part, [timezone])`.
EvaluateResult _timestampExtract(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isTimestamp, _isString, _isString],
  min: 2,
  max: 3,
  (List<FieldValue> v) {
    _checkTimeZone(v, 2);
    final DateTime t = _dateTime(_timestamp(v[0]));
    final DateTime startOfYear = DateTime.utc(t.year);
    final int dayOfYear =
        DateTime.utc(t.year, t.month, t.day).difference(startOfYear).inDays + 1;
    switch (_text(v[1])) {
      case 'microsecond':
        return _int(t.millisecond * 1000 + t.microsecond);
      case 'millisecond':
        return _int(t.millisecond);
      case 'second':
        return _int(t.second);
      case 'minute':
        return _int(t.minute);
      case 'hour':
        return _int(t.hour);
      case 'day':
        return _int(t.day);
      case 'dayofweek':
        // Sunday is 1.
        return _int(t.weekday % 7 + 1);
      case 'dayofyear':
        return _int(dayOfYear);
      case 'week':
        // Weeks begin on Sunday; the days before the first Sunday of the
        // year are week 0.
        final int firstSunday = (7 - startOfYear.weekday % 7) % 7 + 1;
        return _int(
          dayOfYear < firstSunday ? 0 : (dayOfYear - firstSunday) ~/ 7 + 1,
        );
      case 'isoweek':
        return _int(
          _isoWeekStart(t).difference(_isoYearStart(_isoYear(t))).inDays ~/ 7 +
              1,
        );
      case 'month':
        return _int(t.month);
      case 'quarter':
        return _int((t.month - 1) ~/ 3 + 1);
      case 'year':
        return _int(t.year);
      case 'isoyear':
        return _int(_isoYear(t));
    }
    throw const _EvaluationError();
  },
);

/// `timestamp_to_unix_micros`, `..._millis` and `..._seconds`: the whole
/// units since the epoch, rounded toward the past.
_Function _timestampToUnix(BigInt unitNanos) {
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isTimestamp],
    (List<FieldValue> v) {
      final BigInt nanos = _toNanos(_timestamp(v[0]));
      BigInt units = nanos ~/ unitNanos;
      if (nanos.isNegative && nanos.remainder(unitNanos) != BigInt.zero) {
        units -= BigInt.one;
      }
      return _int(_checkedInt64(units));
    },
  );
}

/// `unix_micros_to_timestamp`, `..._millis_...` and `..._seconds_...`.
_Function _unixToTimestamp(BigInt unitNanos) {
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isInteger],
    (List<FieldValue> v) => _fromNanos(BigInt.from(_integer(v[0])) * unitNanos),
  );
}

final Map<String, _Function> _timestampFunctions = <String, _Function>{
  'timestamp_add': _literalArgument(1, _timestampAdd(subtract: false)),
  'timestamp_subtract': _literalArgument(1, _timestampAdd(subtract: true)),
  'timestamp_diff': _literalArgument(2, _timestampDiff),
  'timestamp_trunc': _literalArgument(1, _timestampTrunc),
  'timestamp_extract': _literalArgument(1, _timestampExtract),
  'timestamp_to_unix_micros': _timestampToUnix(BigInt.from(1000)),
  'timestamp_to_unix_millis': _timestampToUnix(BigInt.from(1000000)),
  'timestamp_to_unix_seconds': _timestampToUnix(_nanosPerSecond),
  'unix_micros_to_timestamp': _unixToTimestamp(BigInt.from(1000)),
  'unix_millis_to_timestamp': _unixToTimestamp(BigInt.from(1000000)),
  'unix_seconds_to_timestamp': _unixToTimestamp(_nanosPerSecond),
};
