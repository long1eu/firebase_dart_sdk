package com.google.firebase.firebaseflutter;

import android.content.Context;
import android.text.TextUtils;

import com.google.android.gms.common.internal.StringResourceValueReader;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.util.PathUtils;


/**
 * FirebaseFlutterPlugin
 */
public class FirebaseFlutterPlugin implements MethodCallHandler {
    private static final String DOCUMENTS_DIRECTORY = "documents_directory";
    private static final String UID = "uid";
    private static final String API_KEY_RESOURCE_NAME = "google_api_key";
    private static final String APP_ID_RESOURCE_NAME = "google_app_id";
    private static final String DATABASE_URL_RESOURCE_NAME = "firebase_database_url";
    private static final String GA_TRACKING_ID_RESOURCE_NAME = "ga_trackingId";
    private static final String GCM_SENDER_ID_RESOURCE_NAME = "gcm_defaultSenderId";
    private static final String STORAGE_BUCKET_RESOURCE_NAME = "google_storage_bucket";
    private static final String PROJECT_ID_RESOURCE_NAME = "project_id";

    private final Context context;

    private FirebaseFlutterPlugin(Context context) {
        this.context = context;
    }

    /**
     * Plugin registration.
     */
    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "firebase_flutter");
        channel.setMethodCallHandler(new FirebaseFlutterPlugin(registrar.context()));
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        if (call.method.equals("googleConfig")) {
            final String documentsDirectory = PathUtils.getDataDirectory(context);
            final FirebaseUser user = FirebaseAuth.getInstance().getCurrentUser();
            final String uid = user != null ? user.getUid() : null;

            final StringResourceValueReader reader = new StringResourceValueReader(context);
            final String applicationId = reader.getString(APP_ID_RESOURCE_NAME);
            if (TextUtils.isEmpty(applicationId)) {
                result.error("The application id is null.", "", null);
            }


            final Map<String, String> values = new HashMap<>();
            values.put(DOCUMENTS_DIRECTORY, documentsDirectory);
            values.put(UID, uid);

            values.put(APP_ID_RESOURCE_NAME, applicationId);
            values.put(API_KEY_RESOURCE_NAME, reader.getString(API_KEY_RESOURCE_NAME));
            values.put(DATABASE_URL_RESOURCE_NAME, reader.getString(DATABASE_URL_RESOURCE_NAME));
            values.put(GA_TRACKING_ID_RESOURCE_NAME, reader.getString(GA_TRACKING_ID_RESOURCE_NAME));
            values.put(GCM_SENDER_ID_RESOURCE_NAME, reader.getString(GCM_SENDER_ID_RESOURCE_NAME));
            values.put(STORAGE_BUCKET_RESOURCE_NAME, reader.getString(STORAGE_BUCKET_RESOURCE_NAME));
            values.put(PROJECT_ID_RESOURCE_NAME, reader.getString(PROJECT_ID_RESOURCE_NAME));

            result.success(values);
        } else {
            result.notImplemented();
        }
    }
}
