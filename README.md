# FFmpegAPI - FFmpeg for Delphi (FMX) and Free Pascal

A Pascal binding of FFmpeg's shared libraries, **loaded at run time by
name**: nothing is linked in, and a program that never opens a media file
never needs FFmpeg. It reads everything FFmpeg reads - M4B / M4A
audiobooks, MP3, FLAC, Ogg, Opus, WAV, the sound track of a video - with
its streams, chapters, tags and cover art, and decodes audio to float
samples at any rate and channel count. Video streams are described
(size, frame rate, pixel format) and swscale can be loaded, but no video
decoding is done yet: it is there for completeness.

It is meant to be used as a **git submodule** (TWhisper uses it for
audiobooks), but stands on its own.

- `lib/` - framework-free units, Delphi and FPC:
  - `FFmpeg.DynLib` - loading libraries and binding symbols.
  - `FFmpeg.API` - `TFFmpegLibrary`: the functions, version, layout and
    licence checks.
  - `FFmpeg.Media` - `TFFmpegMediaFile` (streams, chapters, tags, cover
    art), `TFFmpegAudioDecoder`, the copy-protection check.
  - `FFmpeg.Components` - `TCustomFFmpegAudio`, the base of the component.
- `fmx/` - `TFFmpegAPI` for FireMonkey and its design-time registration.
- `demos/FFmpegConsole` - console demo and smoke test.
- `tools/` - the layout generator and the checks.

## Getting the libraries

FFmpeg 8 (avutil 60, swresample 6, avcodec 62, avformat 62, swscale 9) as
a **shared** build:

| Platform | Files |
|---|---|
| Windows | `avutil-60.dll`, `swresample-6.dll`, `avcodec-62.dll`, `avformat-62.dll` (+ `swscale-9.dll` for video, `avfilter-11.dll` for the player's speed change) |
| Linux | `libavutil.so.60`, `libswresample.so.6`, `libavcodec.so.62`, `libavformat.so.62` (+ `libswscale.so.9`, `libavfilter.so.11`) |
| macOS | `libavutil.60.dylib`, ... |
| Android | `libavutil.so`, ... (an APK holds only unversioned names; the version is checked after loading) |

The usual single-file `ffmpeg.exe` downloads have no DLLs: take a
"shared" build, or build one (see the licence section for which) -
[ffmpeg-dev](https://github.com/G3DGames/ffmpeg-dev) builds FFmpeg 8.1 LGPL
with these libraries for every platform here (Windows with Visual
Studio, Linux, macOS, Android). Put the
libraries next to the executable, or pass their folder to
`TFFmpegLibrary.Create` / set `TFFmpegAPI.LibraryFolder`; otherwise the
system search path is used.

**Why the major version matters.** A few fields of FFmpeg's large structs
(the chapter list, a stream's time base, a frame's samples, ...) are read
at fixed offsets. `tools/ffmpeg_layout.py` takes them from FFmpeg's own
headers with clang for every target and writes `lib/FFmpeg.Layout.inc`;
`TFFmpegLibrary.Create` refuses other major versions and checks the
Pascal records against the C layout. A new FFmpeg major version = rerun
the tool against its headers and test.

## Using it without the component

```pascal
Lib := TFFmpegLibrary.Create('', flpLGPL);       // folder, licence policy
try
  WriteLn(Lib.Description);                       // versions, licence, folder
  Book := TFFmpegMediaFile.Create(Lib, 'book.m4b');
  try
    Dec := TFFmpegAudioDecoder.Create(Book, -1, 16000, 1);  // best stream, 16 kHz mono
    try
      for I := 0 to High(Book.Chapters) do
        Samples := Dec.Read(Book.Chapters[I].StartTime, Book.Chapters[I].EndTime);
    finally
      Dec.Free;
    end;
  finally
    Book.Free;
  end;
finally
  Lib.Free;
end;
```

- `Read(Start, End)` decodes a range (End <= 0: to the end) to
  interleaved float samples; a long book is best read a chapter at a
  time, so only one chapter is in memory.
- `Streams` gives kind, codec, language, title, duration, bit rate, and
  sample rate / channels / sample format or width / height / frame rate /
  pixel format. A cover picture is a video stream flagged `IsCoverArt`;
  `BestStream` never picks it as the video.
- `CoverArt(Data, Ext)` returns the embedded picture (`.jpg` / `.png`).
- `Tags` lists the file's metadata (title, artist, ...); `Tag(Key)` finds one.
- `TFFmpegAudioDecoder.Cancel` (from another thread) stops a `Read`.

## The component

`TFFmpegAPI` (palette page "FFmpegAPI") is a non-visual component. Set
`FileName` and `Active`; then `Streams`, `Chapters`, `Tags`, `Duration`
and `CoverArt` are there.

- `Decode(Start, End)` / `DecodeChapter(N)` decode on the calling thread.
- `DecodeAsync(Start, End)` decodes on a worker thread (with its own copy
  of the file open) and raises `OnDecoded` or `OnDecodeFailed` on the main
  thread. `CancelDecode` stops it; closing or freeing the component waits
  for the thread and drops a result not yet delivered. A handler may call
  `DecodeAsync` again (chapter after chapter), close the file or change
  it.
- `SampleRate` / `Channels` (0 = the stream's) set the output format.
- `LicencePolicy` and `LibraryFolder` choose the libraries; `Description`
  shows what was loaded.
- `OnOpen`, `OnOpenFailed` (a failure of `Active := True`; without a handler
  it is shown, never raised), `OnClose`. Exceptions raised in handlers are
  shown with `Application.ShowException`.

A console program that uses `TCustomFFmpegAudio` with `DecodeAsync` must
call `CheckSynchronize` to receive the events.

## Playing sound (`TFFmpegAudioPlayer`)

`FFmpeg.Player` plays any file FFmpeg reads on the platform's sound output,
**streamed**: `TFFmpegAudioStream` decodes frame by frame from the playing
position, resamples to the output's rate and channels and writes into the
output's ring buffer, on a thread of its own - a whole audiobook in one M4B
plays without being decoded into memory. `Position` is the output's
**clock**: the time of the sound being heard now (what has really reached
the device, less what still waits in it), so pictures or highlighted words
timed by it stay in step.

```pascal
Player := TFFmpegAudioPlayer.Create(Lib);   // the platform's output
Player.Open('book.m4b');
Player.Play(125.0);                          // from 2:05 (a seek drops the buffer)
... a timer: Caption := FormatFloat('0.00', Player.Position) ...
Player.Pause;  Player.Resume;  Player.Stop;  Player.Ended;
Player.PlayRange(130.20, 130.55);            // one word, then silence (Ended)
Player.Speed := 0.8;                         // slower, the pitch unchanged
```

- **`PlayRange(From, To)`** stops exactly at `To`: the stream stops feeding
  the output there (sample-exact at speed 1), so nothing of what follows is
  heard, and `Ended` turns True when it has played out. For a reader that
  says one word or one sentence at a time.
- **`Speed`** (0.5 .. 2) plays slower or faster at the same pitch, through
  FFmpeg's `atempo` filter (`TFFmpegTempo`). Set while playing, it plays on
  from the same place. `Position` stays the time in the file at any speed.
  It needs **avfilter** (`avfilter-11.dll`, `libavfilter.so.11`, ...), loaded
  on first use by `TFFmpegLibrary.LoadFilters` from the same folder; without
  it the speed cannot change (`FiltersNote` says why) and playing is as
  before. Through atempo a range's length is within ~10-20 ms of
  (To - From) / Speed.

`FFmpeg.AudioOut` - the outputs, one thread each:

| Output | Platform | |
|---|---|---|
| `TFFmpegWasapiOutput` | Windows (Delphi) | WASAPI shared mode, 32-bit float at the device's rate, event driven (from SRDelphiFMX's MoviePlayerFMX) |
| `TFFmpegPulseOutput` | Linux, SteamOS | PulseAudio's simple API (PipeWire's pulse server too), `libpulse-simple.so.0` loaded at run time |
| `TFFmpegNullOutput` | all | silent; the clock runs on a timer |

`TFFmpegAudioOutput.CreateDefault` picks the platform's output and falls
back to the silent one, saying why (`TFFmpegAudioPlayer.OutputNote`): a
reader still follows the text with no sound device. macOS (AudioQueue) and
Android come later. `FFmpegConsole <file> --play [--start S] [--end S]
[--speed X]` tries it.

An output whose device goes away while it plays (headphones unplugged,
another output chosen in Windows, the sound server gone) stops and says
so in `LastError`; `TFFmpegAudioPlayer` then opens the default device
afresh at its next `Play` / `PlayRange` (its own output only - one you
passed in is yours to replace), and `Output` is then a new object.

A Free Pascal program on Linux / macOS must list `cthreads` first in its
uses clause (threads).

## Copy-protected files

Protected files are not read. `FFmpegMp4Protection` looks at an MPEG-4
file's header (Audible's `adrm`, FairPlay's `drms`, `sinf` / `enca`) and
`TFFmpegMediaFile.Create` refuses such a file with a clear message
instead of decoding noise. The binding never decrypts anything. The
extension does not matter: an `.aax` that has already been made DRM-free
reads like any M4B.

## FFmpeg's licence (read this before shipping)

*This is guidance, not legal advice.* FFmpeg's own page, "FFmpeg License
and Legal Considerations" (ffmpeg.org/legal.html), is the reference and
has a compliance checklist.

FFmpeg is LGPL 2.1 or later, but the licence of a **build** depends on how
it was configured:

| Configure option | Licence of the build | Shipping it with a closed-source program |
|---|---|---|
| (default) | LGPL 2.1+ | Possible, if you meet the LGPL (below) |
| `--enable-version3` | LGPL 3+ | As LGPL, version 3 terms |
| `--enable-gpl` (x264, x265, ... ) | GPL 2+ (3+ with version3) | Your program must then be GPL too |
| `--enable-nonfree` (fdk-aac, ...) | not redistributable | Not at all |

FFmpeg is not available under any other licence, paid or not.

The binding helps you know what you are shipping:

- `TFFmpegLibrary.Licence` is the licence the libraries report
  (`avformat_license()`, corrected to GPL / non-free when the build
  options say so), `Configuration` is the exact configure line, and
  `Description` puts versions, licence and folder in one line for a log or
  an About box.
- `TFFmpegLicencePolicy` (`TFFmpegAPI.LicencePolicy`) refuses builds at
  load time:
  - `flpAny` - load anything (default). A non-free build still sets
    `Warning`.
  - `flpRedistributable` - refuse non-free builds.
  - `flpLGPL` - accept LGPL builds only (the right setting for a
    closed-source program).
- `FFmpegConsole --check --lgpl` shows what a set of libraries is.

The usual LGPL points when you ship FFmpeg with your program (see
FFmpeg's checklist for all of them):

- Use an LGPL build (no `--enable-gpl`, no `--enable-nonfree`) unless
  your program is GPL.
- Link dynamically - this binding always does - and ship the libraries
  as separate files the user can replace.
- Ship, or offer, the exact FFmpeg source you built from, including any
  changes, and say so in your documentation.
- Credit FFmpeg ("uses FFmpeg under the LGPL v2.1", with a link) in the
  About box or documentation, and include the licence text.
- Don't forbid reverse engineering of your program in its licence
  terms, as far as that is needed to debug changes to the libraries.
- Don't rename the libraries or claim FFmpeg as your own.

Patents are a separate question from the licence: some codecs are
patent-encumbered in some countries. A build with only the decoders you
need (`--disable-everything` plus a list) is smaller and easier to reason
about.

## Packages and demos

`FFmpegAPI.groupproj` builds, in order:

1. `packages/FFmpegAPI` - runtime, rtl only: all of `lib/`.
2. `packages/FFmpegAPIFMX` - runtime: `TFFmpegAPI`.
3. `packages/dclFFmpegAPIFMX` - design time (Win32 / Win64): registers it.
4. `demos/FFmpegConsole` - uses the runtime package's DCUs from Delphi's
   Dcp folder, as any user project would, so build the packages first.

Install `dclFFmpegAPIFMX` in the IDE to get the component.

Platforms of the component: Win64, macOS (x64, ARM), Linux64, Android64.
`lib/` also compiles for Win32 (the IDE is 32-bit) and with FPC.

As a submodule in another repository, add `<submodule>\lib` (and
`<submodule>\fmx` for FMX) to that project's search path, or put
`packages\FFmpegAPI.dproj` (and FFmpegAPIFMX) at the start of its group.

## Layout

- `lib/FFmpeg.inc` - compiler and platform defines (FFMPEG_WINDOWS,
  FFMPEG_MACOS, FFMPEG_LINUX, FFMPEG_ANDROID, FFMPEG_CPU64, ...).
- `lib/FFmpeg.Layout.inc` - GENERATED by
  `python3 tools/ffmpeg_layout.py <FFmpeg include folder> --write`; never
  edit it by hand.
- `tools/gen_projects.py` - generates the .dproj files and the
  groupproj (missing files only; `--force` rewrites them).

## Checks before delivery

```
python3 tools/pasdoc_check.py      # every declaration documented, ASCII, hygiene
python3 tools/project_check.py     # projects, packages and build order agree
python3 tools/ffmpeg_layout.py <FFmpeg include folder>   # 0 error(s)
```

## Not covered (yet)

- Sound output on macOS (AudioQueue) and Android.
- Video decoding (frames to RGB through swscale) - the streams are
  described and swscale is bound, nothing decodes them yet.
- Encoding and muxing.
- VCL and LCL components (the base class is framework-free; a VCL unit
  only has to publish the properties as `FFmpeg.FMX` does).
