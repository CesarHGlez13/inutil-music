package com.ryanheise.just_audio;

import android.content.Context;

/** Public media-device bridge without exposing Media3 types to the host app. */
public final class InutilAudioOutput {
    private InutilAudioOutput() {}

    public static Integer getPreferredDeviceId() {
        return AudioPlayer.getInutilPreferredAudioDeviceId();
    }

    public static boolean setPreferredDevice(Context context, Integer deviceId) {
        return AudioPlayer.setInutilPreferredAudioDevice(context, deviceId);
    }
}
