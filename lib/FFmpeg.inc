(* FFmpeg.inc
  Shared compiler settings for every unit of the FFmpeg binding.
  Include it right after the unit line of EVERY library unit:
  @longCode(#
  unit FFmpeg.Something;
  {$I FFmpeg.inc}
  interface
  #)
  It makes the same source compile with Delphi (FMX / VCL) and Free Pascal
  (FPC 3.2.2+, {$mode delphi}), and makes record and enum layout match
  FFmpeg's headers, which use the platform's natural C layout:
  - Delphi: {$ALIGN 8} = natural alignment of every field (Int64 / Double /
    pointers on 8 bytes on 64-bit targets and on Win32 / ARM32, as MSVC and
    AAPCS do).
  - FPC: {$packrecords C}, which also covers i386 Linux, where the C ABI
    aligns Int64 on 4 bytes.
  - C enums are 32-bit ints, so Pascal enums must be at least 4 bytes.
  tools/ffmpeg_layout.py checks the records and field offsets against
  FFmpeg's headers with clang for every target and writes FFmpeg.Layout.inc;
  FFmpegCheckLayout (FFmpeg.API) compares it at run time with what the
  Pascal compiler produced.
  Defines produced here (use them instead of compiler-specific symbols):
  - FFMPEG_WINDOWS, FFMPEG_MACOS, FFMPEG_LINUX, FFMPEG_ANDROID
  - FFMPEG_CPU64, FFMPEG_CPUX64, FFMPEG_CPUARM64, FFMPEG_CPU386
  - FFMPEG_UNSUPPORTED_PLATFORM  (iOS, WebAssembly, ...)
  - FFMPEG_ANONYMOUS_METHODS     (compiler supports "reference to")
*)

{ ---------------------------------------------------------------- compiler }
{$ifdef FPC}
  {$mode delphi}
  {$H+}
  {$macro on}
  {$packrecords C}
  {$packenum 4}
  {$scopedenums off}
  // FPC 3.3.1+ (trunk) supports function references / anonymous functions.
  // PasDoc cannot evaluate FPC_FULLVERSION; no compiler defines PASDOC.
  {$ifndef PASDOC}
  {$if FPC_FULLVERSION >= 30301}
    {$modeswitch functionreferences}
    {$modeswitch anonymousfunctions}
    {$define FFMPEG_ANONYMOUS_METHODS}
  {$endif}
  {$endif}
{$else}
  {$ALIGN 8}
  {$MINENUMSIZE 4}
  {$SCOPEDENUMS OFF}
  {$define FFMPEG_ANONYMOUS_METHODS}
{$endif}

{ ---------------------------------------------------------------- platform }
{ ANDROID is tested before LINUX because FPC's Android target is Linux-based. }
{$if defined(IOS) or defined(IPHONESIM) or defined(WASI) or defined(WASM)}
  {$define FFMPEG_UNSUPPORTED_PLATFORM}
{$elseif defined(MSWINDOWS)}
  {$define FFMPEG_WINDOWS}
{$elseif defined(ANDROID)}
  {$define FFMPEG_ANDROID}
{$elseif defined(DARWIN) or defined(MACOS)}
  {$define FFMPEG_MACOS}
{$elseif defined(LINUX)}
  {$define FFMPEG_LINUX}
{$else}
  {$define FFMPEG_UNSUPPORTED_PLATFORM}
{$endif}

{ ---------------------------------------------------------------- cpu }
{$if defined(CPU64) or defined(CPU64BITS) or defined(CPUX64)}
  {$define FFMPEG_CPU64}
{$endif}
{$if defined(CPUX64) or defined(CPUX86_64) or defined(CPUAMD64)}
  {$define FFMPEG_CPUX64}
{$endif}
{$if defined(CPUARM64) or defined(CPUAARCH64)}
  {$define FFMPEG_CPUARM64}
{$endif}
{$if defined(CPU386) or defined(CPUI386) or defined(CPUX86)}
  {$define FFMPEG_CPU386}
{$endif}
