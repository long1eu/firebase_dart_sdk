// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

/// An enumeration of the different purposes we have for queries.
enum QueryPurpose {
  /// A regular, normal query.
  listen,

  /// The query was used to refill a query after an existence filter mismatch.
  existenceFilterMismatch,

  /// The query was used to resolve a limbo document.
  limboResolution,
}
