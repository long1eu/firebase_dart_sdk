/// Always null: a platform without `dart:io` (the web) has no environment variables. [name] is not
/// read.
String? environmentVariable(String name) => null;
