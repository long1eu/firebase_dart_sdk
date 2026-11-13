part of 'expression_evaluator.dart';

// ---- vectors ----

_Function _vectorDistance(double Function(List<double> a, List<double> b) f) {
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isVector, _isVector],
    (List<FieldValue> v) {
      final List<double> a = (v[0] as VectorFieldValue).internalValue;
      final List<double> b = (v[1] as VectorFieldValue).internalValue;
      if (a.length != b.length) {
        throw const _EvaluationError();
      }
      final double result = f(a, b);
      if (result.isNaN) {
        throw const _EvaluationError();
      }
      return _double(result);
    },
  );
}

double _dot(List<double> a, List<double> b) {
  double sum = 0;
  for (int i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// One minus the cosine of the angle between the vectors. Not defined (NaN,
/// an error) for a vector without length.
double _cosineDistance(List<double> a, List<double> b) =>
    1.0 - _dot(a, b) / math.sqrt(_dot(a, a) * _dot(b, b));

double _euclideanDistance(List<double> a, List<double> b) {
  double sum = 0;
  for (int i = 0; i < a.length; i++) {
    final double difference = a[i] - b[i];
    sum += difference * difference;
  }
  return math.sqrt(sum);
}

EvaluateResult _vectorLength(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isVector],
  (List<FieldValue> v) => _int((v[0] as VectorFieldValue).internalValue.length),
);

final Map<String, _Function> _vectorFunctions = <String, _Function>{
  'cosine_distance': _vectorDistance(_cosineDistance),
  'dot_product': _vectorDistance(_dot),
  'euclidean_distance': _vectorDistance(_euclideanDistance),
  'vector_length': _vectorLength,
};
