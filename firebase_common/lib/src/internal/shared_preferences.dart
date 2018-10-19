// File created by
// Lung Razvan <long1eu>
// on 18/10/2018

// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:async';
import 'dart:io';

import 'package:firebase_common/src/internal/shared_preferences_impl.dart';

/// Interface for accessing and modifying preference data returned by {@link
/// Context#getSharedPreferences}.  For any particular set of preferences,
/// there is a single instance of this class that all clients share.
/// Modifications to the preferences must go through an [Editor] object to
/// ensure the preference values remain in a consistent state and control when
/// they are committed to storage. Objects that are returned from the various
/// <b>get</b> methods must be treated as immutable by the application.
abstract class SharedPreferences {
  static Future<SharedPreferences> getInstance([String path]) {
    return SharedPreferencesImpl.init(File(path));
  }

  static SharedPreferences get instance {
    if (SharedPreferencesImpl.instance == null) {
      throw StateError('You need to call SharedPreferences.getInstance() at '
          'least once');
    }
    return SharedPreferencesImpl.instance;
  }

  /// Retrieve all values from the preferences.
  ///
  /// * Note that you <em>must not</em> modify the collection returned by this
  /// method, or alter any of its contents. The consistency of your stored data
  /// is not guaranteed if you do.
  ///
  /// Returns a map containing a list of pairs key/value representing the
  /// preferences.
  Map<String, dynamic> get all;

  /// Retrieve a value from the preferences.
  ///
  /// [key] is the name of the preference to retrieve.
  ///
  /// Returns the preference value if it exists, or null.
  dynamic operator [](String key);

  /// Retrieve a String value from the preferences.
  ///
  /// [key] is the name of the preference to retrieve. [defValue] is the value
  /// to return if this preference does not exist.
  ///
  /// Returns the preference value if it exists, or defValue. Throws [CastError]
  /// if there is a preference with this name that is not a String.
  String getString(String key, {String defValue});

  /// Retrieve a list of String values from the preferences.
  ///
  /// * Note that you <em>must not</em> modify the set instance returned by this
  /// call. The consistency of the stored data is not guaranteed if you do, nor
  /// is your ability to modify the instance at all.
  ///
  /// [key] is the name of the preference to retrieve. [defValues] is the value
  /// to return if this preference does not exist.
  ///
  /// Returns the preference value if it exists, or defValue. Throws [CastError]
  /// if there is a preference with this name that is not a Set<String>.
  List<String> getStringList(String key, {List<String> defValues});

  /// Retrieve an int value from the preferences.
  ///
  /// [key] is the name of the preference to retrieve. [defValue] is the value
  /// to return if this preference does not exist.
  ///
  /// Returns the preference value if it exists, or defValue. Throws [CastError]
  /// if there is a preference with this name that is not a int.
  int getInt(String key, {int defValue});

  /// Retrieve an double value from the preferences.
  ///
  /// [key] is the name of the preference to retrieve. [defValue] is the value
  /// to return if this preference does not exist.
  ///
  /// Returns the preference value if it exists, or defValue. Throws [CastError]
  /// if there is a preference with this name that is not a double.
  double getDouble(String key, {double defValue});

  /// Retrieve a boolean value from the preferences.
  ///
  /// [key] is the name of the preference to retrieve. [defValue] is the value
  /// to return if this preference does not exist.
  ///
  /// Returns the preference value if it exists, or defValue. Throws [CastError]
  /// if there is a preference with this name that is not a bool.
  bool getBool(String key, {bool defValue});

  /// Checks whether the preferences contains a preference.
  ///
  /// [key] is the name of the preference to check.
  /// Returns true if the preference exists in the preferences, otherwise false.
  bool contains(String key);

  /// Create a new [Editor] for these preferences, through which you can make
  /// modifications to the data in the preferences and atomically commit those
  /// changes back to the [SharedPreferences] object.
  ///
  /// * Note that you <em>must</em> call [Editor.commit] to have any changes you
  /// perform in the Editor actually show up in the [SharedPreferences].
  ///
  /// Returns a new instance of the [Editor] abstract class, allowing you to
  /// modify the values in this [SharedPreferences] object.
  Editor edit();

  /// The Stream emits the key of a shared preference that was changed, added,
  /// or removed.
  ///
  /// This may be called even if a preference is set to its existing value.
  Stream<String> get onChange;
}

/// Interface used for modifying values in a [SharedPreferences] object. All
/// changes you make in an editor are batched, and not copied back to the
/// original [SharedPreferences] until you call [commit] or [apply]
abstract class Editor {
  /// Set a value in the preferences editor, to be written back once [commit] or
  /// [apply] are called.
  ///
  /// [key] the name of the preference to modify and [value] is the new value
  /// for the preference. Passing null for this argument is equivalent to
  /// calling [remove] with this key.
  void operator []=(String key, dynamic value);

  /// Set a String value in the preferences editor, to be written back once
  /// [commit] or [apply] are called.
  ///
  /// [key] the name of the preference to modify and [value] is the new value
  /// for the preference. Passing null for this argument is equivalent to
  /// calling [remove] with this key.
  void putString(String key, String value);

  /// Set a List of String values in the preferences editor, to be written back
  /// once [commit] or [apply] is called.
  ///
  /// [key] the name of the preference to modify and [values] is the new value
  /// for the preference. Passing null for this argument is equivalent to
  /// calling [remove] with this key.
  void putStringList(String key, List<String> values);

  /// Set an int value in the preferences editor, to be written back once
  /// [commit] or [apply] are called.
  ///
  /// [key] the name of the preference to modify and [value] is the new value
  /// for the preference. Passing null for this argument is equivalent to
  /// calling [remove] with this key.
  void putInt(String key, int value);

  /// Set an double value in the preferences editor, to be written back once
  /// [commit] or [apply] are called.
  ///
  /// [key] the name of the preference to modify and [value] is the new value
  /// for the preference. Passing null for this argument is equivalent to
  /// calling [remove] with this key.
  void putDouble(String key, double value);

  /// Set a boolean value in the preferences editor, to be written back once
  /// [commit] or [apply] are called.
  ///
  /// [key] the name of the preference to modify and [value] is the new value
  /// for the preference. Passing null for this argument is equivalent to
  /// calling [remove] with this key.
  void putBool(String key, bool value);

  /// Mark in the editor that a preference value should be removed, which will
  /// be done in the actual preferences once [commit] is called.
  ///
  /// * Note that when committing back to the preferences, all removals are done
  /// first, regardless of whether you called remove before or after put methods
  /// on this editor.
  ///
  /// [key] is the name of the preference to remove.
  void remove(String key);

  /// Mark in the editor to remove <em>all</em> values from the preferences.
  /// Once commit is called, the only remaining preferences will be any that you
  /// have defined in this editor.
  ///
  /// * Note that when committing back to the preferences, the clear is done
  /// first, regardless of whether you called clear before or after put methods
  /// on this editor.
  void clear();

  /// Commit your preferences changes back from this Editor to the
  /// [SharedPreferences] object it is editing.  This atomically performs the
  /// requested modifications, replacing whatever is currently in the
  /// [SharedPreferences].
  ///
  /// * Note that when two editors are modifying preferences at the same time,
  /// the last one to call commit wins.
  ///
  /// * If you don't care about the return value consider using [apply] instead.
  ///
  /// Returns true if the new values were successfully written
  /// to persistent storage.
  Future<bool> commit();

  /// Commit your preferences changes back from this Editor to the
  /// [SharedPreferences] object it is editing. This atomically performs the
  /// requested modifications, replacing whatever is currently in the
  /// [SharedPreferences].
  ///
  /// * Note that when two editors are modifying preferences at the same time,
  /// the last one to call apply wins.
  ///
  /// * Unlike [commit], which writes its preferences out to persistent storage
  /// synchronously, [apply] commits its changes to the in-memory
  /// [SharedPreferences] immediately but starts an asynchronous commit to disk
  /// and you won't be notified of any failures.  If another editor on this
  /// [SharedPreferences] does a regular [commit] while a [apply] is still
  /// outstanding, the [commit] will block until all async commits are completed
  /// as well as the commit itself.
  void apply();
}
