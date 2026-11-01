# Local patches

This directory vendors `audio_service` 0.18.19.

The upstream Android implementation publishes custom controls only through
`PlaybackStateCompat`. ColorOS builds its lock-screen controls from notification
actions instead, so those controls are omitted there.

The local patch also publishes custom controls as clickable
`NotificationCompat.Action` entries. Their broadcast is routed back through the
same audio-service custom-action callback used by the media session.
