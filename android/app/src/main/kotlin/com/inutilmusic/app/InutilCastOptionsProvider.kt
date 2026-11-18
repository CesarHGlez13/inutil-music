package com.inutilmusic.app

import android.content.Context
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions

class InutilCastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions = CastOptions.Builder()
        .setReceiverApplicationId(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID)
        // audio_service owns the app's single media session/notification.
        .setCastMediaOptions(CastMediaOptions.Builder()
            .setMediaSessionEnabled(false)
            .setNotificationOptions(null)
            .build())
        .build()

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}
