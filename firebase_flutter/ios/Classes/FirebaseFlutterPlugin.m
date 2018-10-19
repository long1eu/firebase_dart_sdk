#import "FirebaseFlutterPlugin.h"

@implementation FirebaseFlutterPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel methodChannelWithName:@"firebase_flutter" binaryMessenger:[registrar messenger]];
    FirebaseFlutterPlugin* instance = [[FirebaseFlutterPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"googleConfig" isEqualToString:call.method]) {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* documentsDirectory = paths.firstObject;
        NSString* uid = [[[FIRAuth auth] currentUser] uid];
        NSString *plistFilePath =  [[NSBundle mainBundle] pathForResource: @"GoogleService-Info" ofType: @"plist"];
        NSDictionary *sDefaultOptionsDictionary = [NSDictionary dictionaryWithContentsOfFile:plistFilePath];
        
        NSMutableDictionary *values = [[NSMutableDictionary alloc] init];
        values[@"documents_directory"] = documentsDirectory;
        values[@"uid"] = uid;
        values[@"google_api_key"] = [sDefaultOptionsDictionary objectForKey:@"API_KEY"];
        values[@"google_app_id"] = [sDefaultOptionsDictionary objectForKey:@"GOOGLE_APP_ID"];
        values[@"firebase_database_url"] = [sDefaultOptionsDictionary objectForKey:@"DATABASE_URL"];
        values[@"ga_trackingId"] = [sDefaultOptionsDictionary objectForKey:@"TRACKING_ID"];
        values[@"gcm_defaultSenderId"] = [sDefaultOptionsDictionary objectForKey:@"GCM_SENDER_ID"];
        values[@"google_storage_bucket"] = [sDefaultOptionsDictionary objectForKey:@"STORAGE_BUCKET"];
        values[@"project_id"] = [sDefaultOptionsDictionary objectForKey:@"PROJECT_ID"];
    
        result(values);
    } else {
        result(FlutterMethodNotImplemented);
    }
}
@end
