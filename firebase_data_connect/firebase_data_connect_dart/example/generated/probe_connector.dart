library probe_generated;
import 'package:firebase_data_connect_dart/flutterfire.dart';
import 'package:meta/meta.dart';
import 'dart:convert';

part 'create_owner.dart';

part 'create_everything.dart';

part 'list_everything.dart';

part 'list_owners.dart';

part 'list_owners_live.dart';


String? bigIntToJson(BigInt? value) {
  return value?.toString();
}

BigInt bigIntFromJson(dynamic value) {
  return BigInt.parse(value);
}


  enum Color {
    
      RED,
    
      GREEN,
    
      BLUE,
    
  }
  
  String colorSerializer(EnumValue<Color> e) {
    return e.stringValue;
  }
  EnumValue<Color> colorDeserializer(dynamic data) {
    switch (data) {
      
      case 'RED':
        return const Known(Color.RED);
      
      case 'GREEN':
        return const Known(Color.GREEN);
      
      case 'BLUE':
        return const Known(Color.BLUE);
      
      default:
        return Unknown(data);
    }
  }
  



String enumSerializer(Enum e) {
  return e.name;
}



/// A sealed class representing either a known enum value or an unknown string value.
@immutable
sealed class EnumValue<T extends Enum> {
  const EnumValue();

  

  /// The string representation of the value.
  String get stringValue;
  @override
  String toString() {
    return "EnumValue($stringValue)";
  }
}

/// Represents a known, valid enum value.
class Known<T extends Enum> extends EnumValue<T> {
  /// The actual enum value.
  final T value;

  const Known(this.value);

  @override
  String get stringValue => value.name;

  @override
  String toString() {
    return "Known($stringValue)";
  }
}
/// Represents an unknown or unrecognized enum value.
class Unknown extends EnumValue<Never> {
  /// The raw string value that couldn't be mapped to a known enum.
  @override
  final String stringValue;

  const Unknown(this.stringValue);
  @override
  String toString() {
    return "Unknown($stringValue)";
  }
}

class ProbeConnectorConnector {
  
  
  CreateOwnerVariablesBuilder createOwner ({required String name, }) {
    return CreateOwnerVariablesBuilder(dataConnect, name: name,);
  }
  
  
  CreateEverythingVariablesBuilder createEverything ({required String s, required int i, required double f, required bool b, required BigInt i64, required DateTime d, required Timestamp ts, required String u, required Color color, required String ownerId, }) {
    return CreateEverythingVariablesBuilder(dataConnect, s: s,i: i,f: f,b: b,i64: i64,d: d,ts: ts,u: u,color: color,ownerId: ownerId,);
  }
  
  
  ListEverythingVariablesBuilder listEverything () {
    return ListEverythingVariablesBuilder(dataConnect, );
  }
  
  
  ListOwnersVariablesBuilder listOwners () {
    return ListOwnersVariablesBuilder(dataConnect, );
  }
  
  
  ListOwnersLiveVariablesBuilder listOwnersLive () {
    return ListOwnersLiveVariablesBuilder(dataConnect, );
  }
  

  static ConnectorConfig connectorConfig = ConnectorConfig(
    'us-central1',
    'probe-connector',
    'probe-service',
  );

  ProbeConnectorConnector({required this.dataConnect});
  static ProbeConnectorConnector get instance {
    
    return ProbeConnectorConnector(
        dataConnect: FirebaseDataConnect.instanceFor(
            connectorConfig: connectorConfig,
            
            sdkType: CallerSDKType.generated));
  }

  FirebaseDataConnect dataConnect;
}
