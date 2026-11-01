package com.ryanheise.audioservice;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;

public class MediaButtonReceiver extends androidx.media.session.MediaButtonReceiver {
    public static final String ACTION_NOTIFICATION_DELETE = "com.ryanheise.audioservice.intent.action.ACTION_NOTIFICATION_DELETE";
    public static final String ACTION_CUSTOM = "com.ryanheise.audioservice.intent.action.CUSTOM";
    public static final String EXTRA_CUSTOM_ACTION = "com.ryanheise.audioservice.extra.CUSTOM_ACTION";
    public static final String EXTRA_CUSTOM_EXTRAS = "com.ryanheise.audioservice.extra.CUSTOM_EXTRAS";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null
                && ACTION_NOTIFICATION_DELETE.equals(intent.getAction())
                && AudioService.instance != null) {
            AudioService.instance.handleDeleteNotification();
            return;
        }
        if (intent != null
                && ACTION_CUSTOM.equals(intent.getAction())
                && AudioService.instance != null) {
            String action = intent.getStringExtra(EXTRA_CUSTOM_ACTION);
            Bundle extras = intent.getBundleExtra(EXTRA_CUSTOM_EXTRAS);
            if (action != null) {
                AudioService.instance.handleCustomAction(action, extras);
            }
            return;
        }
        super.onReceive(context, intent);
    }
}
