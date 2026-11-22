/// Number rules shared by nodes, hashes, keys and query values. JS: `core/util/util.ts` (part:
/// `doubleToIEEE754String`, `tryParseInt`, `INTEGER_32_MIN/MAX`, `isInvalidJSONNumber`); Android:
/// `snapshot/LongNode.java`, `DoubleNode.java`, `core/utilities/Utilities.java` (part).
///
/// One rule on every platform: a value is an "integer" when it is integral and within the 53-bit
/// safe range, so hashes and ordering agree between the VM and the web.
library;

/// The smallest 32-bit signed integer; integer-like keys must be at least this.
const int int32Min = -2147483648;

/// The largest 32-bit signed integer; integer-like keys must be at most this.
const int int32Max = 2147483647;

/// The largest integer a double represents exactly (2^53 - 1).
const int maxSafeInteger = 9007199254740991;

/// Whether [value] counts as an integer: integral and within plus or minus [maxSafeInteger].
bool isIntegral(num value) => throw UnimplementedError();

/// Returns [value] as an `int` when [isIntegral], otherwise as a `double`, identically on the VM
/// and the web.
num normalizeNumber(num value) => throw UnimplementedError();

/// Whether [value] is NaN or infinite, which JSON cannot carry.
bool isInvalidJsonNumber(Object? value) => throw UnimplementedError();

/// The 16 hex characters of the IEEE 754 big-endian bits of [value], as the JS SDK hashes numbers.
String doubleToIeee754String(double value) => throw UnimplementedError();

/// Parses [key] as an integer-like key (`^-?(0*)\d{1,10}$` and within int32), or returns null.
int? tryParseIntKey(String key) => throw UnimplementedError();
