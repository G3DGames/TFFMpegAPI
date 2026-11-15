# FFmpegConsole

Console demo and smoke test of the FFmpeg binding. It uses `TFFmpegLibrary`,
`TFFmpegMediaFile` and `TFFmpegAudioDecoder` directly (no component).

Build the packages first (`FFmpegAPI.groupproj` does it in order): the demo
takes the library's DCUs from the runtime package FFmpegAPI.

## Next to the executable

FFmpeg 8's shared libraries (`avutil-60.dll`, `swresample-6.dll`,
`avcodec-62.dll`, `avformat-62.dll`, and `swscale-9.dll` for `--video`,
`avfilter-11.dll` for `--speed`), or pass their folder with `--ffmpeg`.

## Usage

```
FFmpegConsole --check [--ffmpeg FOLDER] [--lgpl | --redistributable] [--video]
FFmpegConsole <file> [--ffmpeg FOLDER]
FFmpegConsole <file> --wav OUT.wav [--start S] [--end S] [--chapter N] [--rate HZ] [--channels N]
FFmpegConsole <file> --cover NAME
FFmpegConsole <file> --play [--start S] [--end S] [--seconds N] [--speed X]
```

- `--check` loads the libraries and prints versions, licence and the
  configure line. With `--lgpl` it fails on a GPL or non-free build, with
  `--redistributable` on a non-free one.
- `<file>` alone lists streams, chapters and tags.
- `--wav` decodes a range, or chapter N (from 1), to a 16-bit WAV;
  `--rate 16000 --channels 1` gives what whisper.cpp wants.
- `--cover NAME` writes the cover art as NAME.jpg or NAME.png.
- `--play` plays on the sound output (WASAPI, PulseAudio, else silent with
  the clock running), printing the clock: from `--start`, for `--seconds`
  or to the end, or exactly to `--end` (`PlayRange`); `--speed 0.5 .. 2`
  plays slower / faster at the same pitch (avfilter's atempo).

Copy-protected files (Audible AAX, FairPlay) are refused with a message.
