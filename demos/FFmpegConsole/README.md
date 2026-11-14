# FFmpegConsole

Console demo and smoke test of the FFmpeg binding. It uses `TFFmpegLibrary`,
`TFFmpegMediaFile` and `TFFmpegAudioDecoder` directly (no component).

Build the packages first (`FFmpegAPI.groupproj` does it in order): the demo
takes the library's DCUs from the runtime package FFmpegAPI.

## Next to the executable

FFmpeg 8's shared libraries (`avutil-60.dll`, `swresample-6.dll`,
`avcodec-62.dll`, `avformat-62.dll`, and `swscale-9.dll` for `--video`), or
pass their folder with `--ffmpeg`.

## Usage

```
FFmpegConsole --check [--ffmpeg FOLDER] [--lgpl | --redistributable] [--video]
FFmpegConsole <file> [--ffmpeg FOLDER]
FFmpegConsole <file> --wav OUT.wav [--start S] [--end S] [--chapter N] [--rate HZ] [--channels N]
FFmpegConsole <file> --cover NAME
```

- `--check` loads the libraries and prints versions, licence and the
  configure line. With `--lgpl` it fails on a GPL or non-free build, with
  `--redistributable` on a non-free one.
- `<file>` alone lists streams, chapters and tags.
- `--wav` decodes a range, or chapter N (from 1), to a 16-bit WAV;
  `--rate 16000 --channels 1` gives what whisper.cpp wants.
- `--cover NAME` writes the cover art as NAME.jpg or NAME.png.

Copy-protected files (Audible AAX, FairPlay) are refused with a message.
