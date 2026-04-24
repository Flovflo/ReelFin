# Jellyfin Original Media

Implemented:

- `OriginalMediaResolver`
- `OriginalMediaRequest`
- `OriginalMediaURLBuilder`
- `OriginalMediaAuthPolicy`
- `OriginalMediaSessionReporter`

The resolver builds:

```text
/Videos/{itemID}/stream?static=true&MediaSourceId={mediaSourceID}
```

Default auth policy appends `api_key` because the MP4 AVFoundation helper path cannot use custom request headers. Diagnostics use `redactedURLDescription` and must not log the token.

Server transcode fallback is disabled unless `allowServerTranscodeFallback` is true. The resolver does not select Jellyfin `TranscodeUrl`.
