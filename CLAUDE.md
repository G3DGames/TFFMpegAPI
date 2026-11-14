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
- Say "PACKAGE REBUILD NEEDED" in capitals when a package's units or
  interface changed.

Last number used: 02.

Last push: 3a9dd6e ("1st push", 2026-11-14 ~22:34; checked: all 29 files
of zip 01 identical apart from line endings). TWhisper's FFmpegAPI
submodule points at it. NOT YET PUSHED: FFmpegAPI-02-path.zip on 3a9dd6e
(the real folder of libraries found on PATH, Windows).

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
