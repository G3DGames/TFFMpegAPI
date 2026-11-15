# CLAUDE.md - working rules for this repository

Read README.md first, then this file. Keep both up to date with every change.
The rules follow TWhisper's CLAUDE.md (same owner, same conventions); where
this file is silent, TWhisper's rules apply.

## Project
Pascal binding of FFmpeg 8's shared libraries (avutil 60, swresample 6,
avcodec 62, avformat 62, swscale 9), loaded DYNAMICALLY at run time: no
`external` declarations, no static linking. Split out of TWhisper
(Whisper.FFmpeg) on the owner's request (2026-11-14: "it's own repo then we
can submodule it"). TWhisper uses it as a submodule.

Owner's decisions (2026-11-14):
- "We should allow for video but not use it - completeness": video streams
  are described and swscale is bound (loaded only with AWithVideo), but
  nothing decodes video yet.
- "Also a LGPL or GPL build option as FFMpeg has a very closely guarded
  license (and is abused lots)": TFFmpegLicencePolicy (flpAny,
  flpRedistributable, flpLGPL); Licence / Configuration / Warning report
  what was loaded; a non-free build is always warned about. The README's
  licence section is guidance and says it is not legal advice.

Copy protection: protected files (Audible adrm, FairPlay drms, sinf / enca)
are REFUSED with a clear message. Never add decryption or any way around
DRM.

Target order: FMX, then VCL, then Free Pascal. Delphi 13 is the reference
compiler; lib/ must also compile with FPC (tested with 3.0; target 3.2.2).
Component platforms (FFMPEG_COMPONENT_PLATFORMS): Win64, OSX64, OSXARM64,
Linux64, Android64. lib/ also compiles for Win32 because a 32-bit IDE loads
the design-time package.

## Layout rules
- `lib/` - framework-free units only. No FMX, VCL or LCL here, ever.
- `fmx/` - FFmpeg.FMX (TFFmpegAPI) and FFmpeg.FMX.Reg (design time). They
  include `..\lib\FFmpeg.inc` by relative path.
- GENERATED, never edit by hand: `lib/FFmpeg.Layout.inc`
  (`tools/ffmpeg_layout.py <FFmpeg include folder> --write`). The OFFSETS /
  RECORDS tables of ffmpeg_layout.py, the records of FFmpeg.API and the
  Add(...) list of FFmpegCheckLayout go together: adding a field = all three
  + rerun the tool.
- `demos/<Name>/` - `<Name>.dpr` + `<Name>.dproj` + `README.md`. Demos list
  and search ONLY their own sources: the library comes from the runtime
  packages' DCUs in Delphi's Dcp folder. No demo source includes FFmpeg.inc.
- `packages/` - FFmpegAPI (runtime, rtl only), FFmpegAPIFMX (runtime),
  dclFFmpegAPIFMX (design). .dproj files and FFmpegAPI.groupproj come from
  `tools/gen_projects.py` (missing files only; `--force` rewrites); once the
  IDE has saved them, the IDE's files are authoritative.
- groupproj BUILD ORDER: runtime, FMX runtime, design, then applications.

## Code rules
- ASCII-only sources.
- PasDoc on every declaration, including private fields and both branches
  of an $ifdef.
- No `TypeOf`, `Low`, `High` or other built-in names as identifiers.
- Events of worker threads reach the main thread through
  TThread.Queue(thread, method), so queued events die with the thread.
- No absolute paths, user names or machine names in tracked files.
- Unit names never equal a package name (FFmpeg.API vs package FFmpegAPI is
  fine; a unit called FFmpeg.Library is not - `library` is a keyword).

## Deliveries
- Zips hold only the files changed since the previous zip, with paths from
  the repo root, named FFmpegAPI-NN-topic.zip; the number is never reused,
  and every delivery says what it goes on top of. Zip 01 is the whole
  initial repository.
- Never commit or push, and don't offer to; the owner does.
- On "sync + check": clone into a scratch folder and compare every
  delivered file, ignoring CRLF.
- Before delivery: `python3 tools/pasdoc_check.py`,
  `python3 tools/project_check.py`, `python3 tools/ffmpeg_layout.py
  <FFmpeg include folder>` (0 errors), and an FPC compile of lib/ and the
  console demo with a run against a test file.
- PACKAGE REBUILDS (owner, 2026-11-15: "Add rule"). Every delivery says
  one or the other. When a package must be rebuilt, the message carries,
  exactly, a blank line, the banner, a blank line, then the details:

      =====> PACKAGE REBUILD NEEDED <=====

  Details of the package rebuilds: which packages, in build order, why
  (which unit changed), and what to rebuild after them (programs, other
  repos' packages). Otherwise say "NO PACKAGE REBUILD", in capitals.

Last number used: 11.

Last push: 0761ff2 ("latest for Claude", checked): zips 04 and 05 match,
but dclFFmpegAPIFMX.dproj was back on Win64 (zip 03's Win32 line lost) -
set to Win32 again in zip 06. Before it 05532ee (IDE re-save of the four
.dproj files) and 54f7ab2 = zip 02.

THE OWNER BUILDS IN THE 32-BIT IDE (2026-11-14: "I always build on 32 bit cos
64 doesn't have Mac etc" - Delphi 13's 64-bit IDE has no macOS / Linux /
Android targets). The design package must open on Win32: the default-platform
line of dclFFmpegAPIFMX.dproj is Win32; a save from the 64-bit IDE flips it to
Win64 - set it back. Runtime packages are built for Win32 too.

## Sound output and player (zip 04, owner 2026-11-15)
The WhisperBooks reader plays a book's audio through FFmpeg, not FMX's
TMediaPlayer (owner: "That's how MoviePlayerFMX does it",
github.com/peardox/SRDelphiFMX; "the player in FFMPegAPI"; "it definitely
needs to stream"). FFmpeg.AudioOut: ring buffer + clock in the base class
(from Lenticular.AudioOutput), one thread per output owning the device;
WASAPI (Delphi, Windows; adapted, plus Reset on a flush), PulseAudio simple
API (Linux; libpulse-simple loaded at run time; 48 kHz stereo float, 100 ms
buffer), Null (silent, timer clock; the fallback). FFmpeg.Player:
TFFmpegAudioStream (a TFFmpegDecoder that hands every resampled frame to a
sink; drops the frames before the start after a seek) and
TFFmpegAudioPlayer (feed thread writing into the output; Position = clock).
FFmpeg's licence: either GPL or LGPL is fine for the reader (owner) - no
policy is forced; flpLGPL / flpRedistributable stay for distributors.
Tested here (FPC 3.0, Linux, n8.1): stream == range decode (3,264,914
samples, 0 difference); clock vs wall time within ~5 ms; pause holds; seek;
end at 39.010 s of 39.003; PulseAudio: no server here -> fallback to silent
with a note. NOT RUN here: WASAPI (Windows only), PulseAudio playing (no
server).
Owner (2026-11-15, Delphi 13, Windows, EpubReader with Moby-Dick): "All tests
ran perfectly" - WASAPI sound, highlight in sync, pause / resume, seeks.
Zip 06: an underrun is counted only once sound has started, so the wait for
the first sound after Open or a seek no longer shows as 1 underrun.

## Review fixes (zip 08, on top of 87cfd0b "Claude push")
From a code review by reading (owner, 2026-11-15: "Code review", then "y" to
patching the three main bugs). NOT COMPILED OR RUN here (no FPC, no FFmpeg
libraries in that session): the owner's Delphi build and an FPC run are
their test.
- FFmpeg.Components, DecodeDone: samples, error and range are taken out of
  the thread BEFORE the handler runs, and nothing is touched after it. A
  handler that calls DecodeAsync / Close / sets FileName frees the thread;
  before, the handler's const ASamples then dangled and the thread was
  written to after it was freed.
- FFmpeg.AudioOut, WASAPI: after MarkEnd only real frames are released to
  the device (ReleaseBuffer(Real), also 0), no silence. Silence kept the
  padding near the buffer size for ever, so SetDrained (Padding = 0) never
  ran: Ended stayed False and the clock stopped ~100 ms short. TO TEST on
  Windows: FFmpegConsole <file> --play to the end must stop by itself.
- FFmpeg.Media: FUsed moved from TFFmpegDecoder to TFFmpegMediaFile (the
  position is the demuxer's). Before, a second decoder on a file already
  read (the component after SampleRate / Channels changed) did not seek for
  a read from 0 and returned nothing. TO TEST: Decode(0, 10), SampleRate :=
  16000, Decode(0, 10) - same length of sound both times.
Found in the same review and NOT fixed yet: WASAPI device loss is silent
(GetCurrentPadding fails for ever, no LastError); a Cancel just before Run
is lost (Run resets FCancelled) and Cancel reads FDecoder while the worker
frees it; any av_read_frame error counts as the end of the file;
TFFmpegAudioDecoder.Create indexes Streams[AStream] before the range check;
every Play reopens the file (moov scan + find_stream_info); Active := True
fails silently without OnOpenFailed; the bare-name load uses the OS search
path (current directory on Windows); the repository has no LICENSE of its
own.

## Play range and speed (zip 09, on top of cb56479 "Claude review push")
Owner, 2026-11-15: the reader's "learn to read" idea (EpubUnum CLAUDE.md,
"Shall we do this") needs a word played alone; slower speech "is
something I already had thought of"; "once we've got the reader at a
satisfactory pausing point we can improve the other contributing
components" -> "OK, sync+check then Mpeg".
- TFFmpegAudioPlayer.PlayRange(From, To): the stream counts the frames
  left to To and hands out nothing after it (TFFmpegAudioStream.FLeft,
  FRangeDone; decoding stops), then MarkEnd -> Ended. Play = no end.
- Speed (0.5 .. 2): TFFmpegTempo (in FFmpeg.Player - no new unit, so no
  package file changed) = avfilter graph abuffer -> atempo -> aformat
  (flt, the output's rate / layout) -> abuffersink, fed our resampled
  float frames (AVFrame fields written at the generated offsets,
  av_frame_get_buffer). Position = FBase + (clock - FBase) * Speed (the
  output's clock counts sound played). Speed set while playing restarts
  the feed at Position (a range keeps its end).
- avfilter is OPTIONAL: TFFmpegLibrary.LoadFilters loads avfilter-11 from
  the same folder on first use (Speed <> 1), checks its major
  (FFMPEG_AVFILTER_MAJOR, now generated by ffmpeg_layout.py from
  libavfilter/version_major.h) and its licence against the policy; on
  failure FiltersNote, nothing half-bound stays, Speed raises and stays.
  New flat functions: av_frame_unref, av_frame_get_buffer (avutil), and
  the avfilter set.
- FFmpegConsole --play: --end S (PlayRange), --speed X; prints the wall
  time and Ended at the end.
TESTED here (FPC 3.0, Linux x64, BtbN's FFmpeg n8.1 LGPL shared build,
silent output - no sound server): ranges sample-exact at speed 1 (4.768 s
asked 4.768 s given; one word 0.173 s = 8304 frames); through atempo
within ~10-20 ms (0.75: 6.347 s for 6.357; a 0.173 s word at 0.5: 0.328 s
for 0.346); the voice's peak in 80-400 Hz stays at 140.6 Hz at 0.75 and
1.5 (resampling would move it to ~105 / ~211 Hz); the player: a range at
1x ends at its end after 5.0 s wall time (Ended), at 0.75 after 6.5 s,
a word alone after 0.25 s, at 1.5 four seconds of wall time = six of the
file. ffmpeg_layout.py: 0 errors (only the avfilter major added).
NOT RUN: WASAPI / PulseAudio playing (owner), Delphi build (owner). TO
TEST: FFmpegConsole <file> --play --start S --end E --speed 0.75 on
Windows - the sound stops at E and is slower at the same pitch; the
avfilter-11.dll must be next to the others (a "shared" build has it).

## avfilter's dependency, ffmpeg-dev (zip 10, on top of zip 09)
- LoadFilters loads swscale first (FLibs[4], not bound - HasVideo stays
  False): avfilter NEEDS libswscale, and neither Windows' LoadLibrary nor
  dlopen looks for a library's dependencies in its own folder - only among
  the libraries already loaded (and the usual search path). Found here:
  with the libraries in a folder passed by --ffmpeg (no LD_LIBRARY_PATH),
  zip 09's LoadFilters failed ("libswscale.so.9: cannot open"); zip 09's
  tests had LD_LIBRARY_PATH set. Tested after the fix: 0.75 from that
  folder works.
- The owner's FFmpeg builds: github.com/G3DGames/ffmpeg-dev (owner,
  2026-11-15: "Similar to whisper-dev a super make would fit this"), FFmpeg
  n8.1 as a submodule, build.sh for every system, build.bat (Visual Studio
  + MSYS2) on Windows; targets windows-x64, linux-x64, macos-arm64 /
  macos-x64, android-arm64 ("This will be all supported OSes"); LGPL only,
  --disable-autodetect, dlls/<target>/ with the licence texts and
  BUILD-INFO.txt. README "Getting the libraries" points there. Its
  linux-x64 build was made and tested here with this binding (--check
  --lgpl, --play --end --speed 0.75).

## Owner's Windows test of zips 09 + 10 (2026-11-15)
Delphi 13, Win64, FFmpeg 8.1.3 LGPL built by ffmpeg-dev's build.bat
(MSVC, -MT), DLLs on PATH: --check --lgpl passes (avutil 60.26.103 ...
"from C:\...\redistributable_bin\Win64\"). LibriVox Moby Dick Part 1
m4b (5:12:22, 11 chapters, AAC 32 kHz mono): --play --start 24.5 --end
29.268 on WASAPI - clock stops at 29.268, Ended True, 0 underruns, 5.28 s
wall time; --speed 0.75 - avfilter 11.14.103 loaded from that folder
(zip 10's swscale-first works on Windows), clock 197 ms per 263 ms tick,
stops at 29.261, Ended True, 6.86 s; owner: "slower but not lower"; the
cut lands mid-word there (times from another file - expected). Owner:
timing details to be judged with real TWhisper word times, not now.
Deployment (owner): FFmpeg's DLLs next to the exe (searched first).

## Test notes
- Test files are made locally: an M4B with 3 chapters and AAC audio, the
  same with a JPEG cover (attached picture), and a fake .aax with an adrm
  box. Copyrighted books are never committed or quoted.
- Tested (FPC 3.0, Linux x64, FFmpeg n8.1 LGPL build): --check with and
  without --video, stream / chapter / tag listing, cover art extraction,
  chapter decode to 16 kHz mono WAV, DRM refusal, and the component:
  Decode, DecodeChapter, DecodeAsync with CheckSynchronize, freeing while a
  decode runs, OnOpenFailed.
- Owner (2026-11-14, Delphi 13, Win64): packages built and installed,
  TFFmpegAPI dropped on an FMX form; FFmpegConsole --check --lgpl with a
  GPL v3 build on PATH refused it as it should - but the message said
  "libraries in  are": a library found on PATH had no folder. Fixed in
  zip 02 (TFFmpegDynLib.LoadedFileName: GetModuleFileName on Windows;
  Linux / macOS still say "the system search path" for a bare-name load).
- Not yet tested: a non-free build against flpRedistributable, macOS,
  Android; the Windows branch of LoadedFileName is not compiled here (no
  Windows units for FPC): owner's Delphi build is its test.
