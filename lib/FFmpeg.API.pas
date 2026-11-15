(* @abstract(FFmpeg's shared libraries, loaded at run time by name: the
  functions this binding uses, the version and layout checks, and the
  licence the libraries were built under.)

  Nothing is linked in. @link(TFFmpegLibrary.Create) loads avutil,
  swresample, avcodec and avformat (and swscale, for video, only when asked)
  from a folder, or from the executable's folder and then the system search
  path:
  @unorderedList(
    @item(Windows: avutil-60.dll, swresample-6.dll, avcodec-62.dll,
      avformat-62.dll, swscale-9.dll - a "shared" FFmpeg 8 build.)
    @item(Linux: libavutil.so.60, ...; macOS: libavutil.60.dylib, ...;
      Android: libavutil.so, ... (the version is checked after loading).)
  )
  avfilter (FFmpeg's filters - the player's speed change uses atempo) is
  loaded only when asked for, by @link(TFFmpegLibrary.LoadFilters): a
  folder without it still plays, at the normal speed.

  The major versions must be the ones FFmpeg.Layout.inc was generated for
  (tools/ffmpeg_layout.py), because a few fields of FFmpeg's structs are
  read at fixed offsets; the constructor checks them, and checks the Pascal
  records against the C layout.

  @bold(Licence.) FFmpeg's licence is that of the build: LGPL by default,
  GPL with --enable-gpl, not redistributable at all with --enable-nonfree.
  The libraries report it; @link(TFFmpegLibrary.Licence),
  @link(TFFmpegLibrary.Configuration) and @link(TFFmpegLibrary.Description)
  show it, and a @link(TFFmpegLicencePolicy) refuses builds a program may
  not ship (see the README's licence section; it is guidance, not legal
  advice).

  Framework-free; compiles with Delphi and FPC. *)
unit FFmpeg.API;

{$I FFmpeg.inc}

interface

uses
  SysUtils, Classes,
  FFmpeg.DynLib;

const
  {$I FFmpeg.Layout.inc}

  { AVMEDIA_TYPE_UNKNOWN. }
  AVMEDIA_TYPE_UNKNOWN = -1;
  { AVMEDIA_TYPE_VIDEO. }
  AVMEDIA_TYPE_VIDEO = 0;
  { AVMEDIA_TYPE_AUDIO. }
  AVMEDIA_TYPE_AUDIO = 1;
  { AVMEDIA_TYPE_DATA. }
  AVMEDIA_TYPE_DATA = 2;
  { AVMEDIA_TYPE_SUBTITLE. }
  AVMEDIA_TYPE_SUBTITLE = 3;
  { AVMEDIA_TYPE_ATTACHMENT. }
  AVMEDIA_TYPE_ATTACHMENT = 4;
  { AV_SAMPLE_FMT_FLT: packed (interleaved) 32-bit float. }
  AV_SAMPLE_FMT_FLT = 3;
  { AVSEEK_FLAG_BACKWARD. }
  AVSEEK_FLAG_BACKWARD = 1;
  { AV_LOG_QUIET. }
  AV_LOG_QUIET = -8;
  { AV_LOG_ERROR. }
  AV_LOG_ERROR = 16;
  { AV_LOG_WARNING. }
  AV_LOG_WARNING = 24;
  { AV_NOPTS_VALUE: no time stamp. }
  AV_NOPTS_VALUE = Low(Int64);
  { AV_TIME_BASE: format-level times are in microseconds. }
  AV_TIME_BASE = 1000000;
  { AV_DISPOSITION_ATTACHED_PIC: the stream is a picture (cover art). }
  AV_DISPOSITION_ATTACHED_PIC = $0400;
  { AV_DISPOSITION_DEFAULT. }
  AV_DISPOSITION_DEFAULT = $0001;
  { AV_DICT_IGNORE_SUFFIX: with key '' and this flag, av_dict_get walks
    every entry. }
  AV_DICT_IGNORE_SUFFIX = 2;
  { AVERROR_EOF = -MKTAG('E','O','F',' '). }
  AVERROR_EOF = -541478725;
  {$ifdef FFMPEG_MACOS}
  { AVERROR(EAGAIN): EAGAIN is 35 on macOS. }
  AVERROR_EAGAIN = -35;
  {$else}
  { AVERROR(EAGAIN): EAGAIN is 11 on Windows, Linux and Android. }
  AVERROR_EAGAIN = -11;
  {$endif}

type
  { FFmpeg's AVRational: a fraction (time bases, frame rates). }
  TAVRational = record
    { Numerator. }
    num: Int32;
    { Denominator. }
    den: Int32;
  end;
  { Pointer to a @link(TAVRational). }
  PAVRational = ^TAVRational;

  { FFmpeg's AVChannelLayout. }
  TAVChannelLayout = record
    { enum AVChannelOrder. }
    order: Int32;
    { Number of channels. }
    nb_channels: Int32;
    { Union: channel mask (native order) or a map pointer. }
    u: UInt64;
    { User data. }
    opaque: Pointer;
  end;
  { Pointer to a @link(TAVChannelLayout). }
  PAVChannelLayout = ^TAVChannelLayout;

  { FFmpeg's AVChapter. }
  TAVChapter = record
    { Unique id. }
    id: Int64;
    { Time base of start and end_. }
    time_base: TAVRational;
    { Start, in time_base units. }
    start: Int64;
    { End, in time_base units (C name "end"). }
    end_: Int64;
    { AVDictionary of the chapter's metadata (title). }
    metadata: Pointer;
  end;
  { Pointer to a @link(TAVChapter). }
  PAVChapter = ^TAVChapter;

  { FFmpeg's AVDictionaryEntry. }
  TAVDictionaryEntry = record
    { Key (UTF-8). }
    key: PAnsiChar;
    { Value (UTF-8). }
    value: PAnsiChar;
  end;
  { Pointer to a @link(TAVDictionaryEntry). }
  PAVDictionaryEntry = ^TAVDictionaryEntry;

  { The FFmpeg functions this binding uses, bound by name. Opaque structs
    are plain pointers. The swscale functions are nil unless the library
    was loaded with video. }
  TFFmpegFlat = record
    { avutil: packed version (major shl 16). }
    avutil_version: function: UInt32; cdecl;
    { avutil: licence text. }
    avutil_license: function: PAnsiChar; cdecl;
    { avutil: build options. }
    avutil_configuration: function: PAnsiChar; cdecl;
    { avutil: sets the log level. }
    av_log_set_level: procedure(level: Int32); cdecl;
    { avutil: allocates a frame. }
    av_frame_alloc: function: Pointer; cdecl;
    { avutil: frees a frame and clears the pointer. }
    av_frame_free: procedure(var frame: Pointer); cdecl;
    { avutil: releases a frame's data (the frame stays). }
    av_frame_unref: procedure(frame: Pointer); cdecl;
    { avutil: allocates a frame's buffers for its format, nb_samples and
      ch_layout (align 0 = the default). }
    av_frame_get_buffer: function(frame: Pointer; align: Int32): Int32; cdecl;
    { avutil: dictionary lookup (key '' with AV_DICT_IGNORE_SUFFIX walks
      all entries). }
    av_dict_get: function(m: Pointer; key: PAnsiChar; prev: PAVDictionaryEntry;
      flags: Int32): PAVDictionaryEntry; cdecl;
    { avutil: error code to text. }
    av_strerror: function(errnum: Int32; errbuf: PAnsiChar; errbuf_size: NativeUInt): Int32; cdecl;
    { avutil: default layout for a channel count. }
    av_channel_layout_default: procedure(ch_layout: PAVChannelLayout; nb_channels: Int32); cdecl;
    { avutil: frees what a layout owns. }
    av_channel_layout_uninit: procedure(channel_layout: PAVChannelLayout); cdecl;
    { avutil: name of a media type ('audio', 'video', ...). }
    av_get_media_type_string: function(media_type: Int32): PAnsiChar; cdecl;
    { avutil: name of a sample format. }
    av_get_sample_fmt_name: function(sample_fmt: Int32): PAnsiChar; cdecl;
    { avutil: name of a pixel format. }
    av_get_pix_fmt_name: function(pix_fmt: Int32): PAnsiChar; cdecl;
    { swresample: packed version. }
    swresample_version: function: UInt32; cdecl;
    { swresample: licence text. }
    swresample_license: function: PAnsiChar; cdecl;
    { swresample: allocates and sets a resampler. }
    swr_alloc_set_opts2: function(var ps: Pointer; out_ch_layout: PAVChannelLayout;
      out_sample_fmt, out_sample_rate: Int32; in_ch_layout: PAVChannelLayout;
      in_sample_fmt, in_sample_rate, log_offset: Int32; log_ctx: Pointer): Int32; cdecl;
    { swresample: initialises a resampler. }
    swr_init: function(s: Pointer): Int32; cdecl;
    { swresample: frees a resampler and clears the pointer. }
    swr_free: procedure(var s: Pointer); cdecl;
    { swresample: converts; in_ nil = flush. Returns samples out. }
    swr_convert: function(s: Pointer; out_: Pointer; out_count: Int32; in_: Pointer;
      in_count: Int32): Int32; cdecl;
    { swresample: upper bound of samples out for in_samples in. }
    swr_get_out_samples: function(s: Pointer; in_samples: Int32): Int32; cdecl;
    { avcodec: packed version. }
    avcodec_version: function: UInt32; cdecl;
    { avcodec: licence text. }
    avcodec_license: function: PAnsiChar; cdecl;
    { avcodec: decoder of a codec id. }
    avcodec_find_decoder: function(id: Int32): Pointer; cdecl;
    { avcodec: name of a codec id. }
    avcodec_get_name: function(id: Int32): PAnsiChar; cdecl;
    { avcodec: allocates a codec context. }
    avcodec_alloc_context3: function(codec: Pointer): Pointer; cdecl;
    { avcodec: frees a codec context and clears the pointer. }
    avcodec_free_context: procedure(var avctx: Pointer); cdecl;
    { avcodec: copies stream parameters into a context. }
    avcodec_parameters_to_context: function(codec: Pointer; par: Pointer): Int32; cdecl;
    { avcodec: opens a codec context. }
    avcodec_open2: function(avctx: Pointer; codec: Pointer; options: Pointer): Int32; cdecl;
    { avcodec: gives the decoder a packet (nil = end). }
    avcodec_send_packet: function(avctx: Pointer; avpkt: Pointer): Int32; cdecl;
    { avcodec: takes a decoded frame. }
    avcodec_receive_frame: function(avctx: Pointer; frame: Pointer): Int32; cdecl;
    { avcodec: drops buffered data (after a seek). }
    avcodec_flush_buffers: procedure(avctx: Pointer); cdecl;
    { avcodec: allocates a packet. }
    av_packet_alloc: function: Pointer; cdecl;
    { avcodec: frees a packet and clears the pointer. }
    av_packet_free: procedure(var pkt: Pointer); cdecl;
    { avcodec: releases a packet's data. }
    av_packet_unref: procedure(pkt: Pointer); cdecl;
    { avformat: packed version. }
    avformat_version: function: UInt32; cdecl;
    { avformat: licence text. }
    avformat_license: function: PAnsiChar; cdecl;
    { avformat: build options. }
    avformat_configuration: function: PAnsiChar; cdecl;
    { avformat: opens a file (url in UTF-8). }
    avformat_open_input: function(var ps: Pointer; url: PAnsiChar; fmt: Pointer;
      options: Pointer): Int32; cdecl;
    { avformat: reads stream information. }
    avformat_find_stream_info: function(ic: Pointer; options: Pointer): Int32; cdecl;
    { avformat: closes a file and clears the pointer. }
    avformat_close_input: procedure(var s: Pointer); cdecl;
    { avformat: the best stream of a media type. }
    av_find_best_stream: function(ic: Pointer; type_, wanted_stream_nb, related_stream: Int32;
      decoder_ret: Pointer; flags: Int32): Int32; cdecl;
    { avformat: reads the next packet. }
    av_read_frame: function(s: Pointer; pkt: Pointer): Int32; cdecl;
    { avformat: seeks a stream to a time stamp. }
    av_seek_frame: function(s: Pointer; stream_index: Int32; timestamp: Int64;
      flags: Int32): Int32; cdecl;
    { swscale (video only): packed version. }
    swscale_version: function: UInt32; cdecl;
    { swscale (video only): licence text. }
    swscale_license: function: PAnsiChar; cdecl;
    { swscale (video only): a scaling / pixel conversion context. }
    sws_getContext: function(srcW, srcH, srcFormat, dstW, dstH, dstFormat, flags: Int32;
      srcFilter, dstFilter: Pointer; param: PDouble): Pointer; cdecl;
    { swscale (video only): scales one picture. }
    sws_scale: function(c: Pointer; srcSlice: Pointer; srcStride: PInteger; srcSliceY, srcSliceH: Int32;
      dst: Pointer; dstStride: PInteger): Int32; cdecl;
    { swscale (video only): frees a context. }
    sws_freeContext: procedure(c: Pointer); cdecl;
    { avfilter (after LoadFilters): packed version. }
    avfilter_version: function: UInt32; cdecl;
    { avfilter (after LoadFilters): licence text. }
    avfilter_license: function: PAnsiChar; cdecl;
    { avfilter (after LoadFilters): a filter by name ('atempo'). }
    avfilter_get_by_name: function(name: PAnsiChar): Pointer; cdecl;
    { avfilter (after LoadFilters): allocates a filter graph. }
    avfilter_graph_alloc: function: Pointer; cdecl;
    { avfilter (after LoadFilters): frees a graph and its filters, clears
      the pointer. }
    avfilter_graph_free: procedure(var graph: Pointer); cdecl;
    { avfilter (after LoadFilters): creates a filter instance in a graph
      with its options ('tempo=0.75'). }
    avfilter_graph_create_filter: function(var filt_ctx: Pointer; filt: Pointer; name, args: PAnsiChar;
      opaque, graph_ctx: Pointer): Int32; cdecl;
    { avfilter (after LoadFilters): links an output pad to an input pad. }
    avfilter_link: function(src: Pointer; srcpad: UInt32; dst: Pointer; dstpad: UInt32): Int32; cdecl;
    { avfilter (after LoadFilters): checks and configures a graph. }
    avfilter_graph_config: function(graphctx: Pointer; log_ctx: Pointer): Int32; cdecl;
    { avfilter (after LoadFilters): gives a buffer source a frame (nil =
      the end); flags 0 takes the frame's data and resets it. }
    av_buffersrc_add_frame_flags: function(buffer_src: Pointer; frame: Pointer; flags: Int32): Int32; cdecl;
    { avfilter (after LoadFilters): takes a filtered frame from a buffer
      sink (AVERROR(EAGAIN): needs more input; AVERROR_EOF: the end). }
    av_buffersink_get_frame: function(ctx: Pointer; frame: Pointer): Int32; cdecl;
  end;

  { Which FFmpeg builds a program accepts. }
  TFFmpegLicencePolicy = (
    { Any build (a non-free one is still reported in
      @link(TFFmpegLibrary.Warning)). }
    flpAny,
    { Builds that may be redistributed: LGPL or GPL, not --enable-nonfree. }
    flpRedistributable,
    { LGPL builds only: no --enable-gpl, no --enable-nonfree. }
    flpLGPL
  );

  { The loaded FFmpeg libraries. One object serves any number of files (not
    the same file from several threads at once). }
  TFFmpegLibrary = class
  private
    { The libraries, in load order (avutil, swresample, avcodec, avformat,
      swscale - nil without video - and avfilter - nil until
      LoadFilters). }
    FLibs: array[0..5] of TFFmpegDynLib;
    { The policy the libraries were loaded under (avfilter is checked by
      it too). }
    FPolicy: TFFmpegLicencePolicy;
    { Backing field of @link(HasFilters). }
    FHasFilters: Boolean;
    { Backing field of @link(FiltersNote). }
    FFiltersNote: string;
    { Backing field of @link(Flat). }
    FFlat: TFFmpegFlat;
    { Backing field of @link(Description). }
    FDescription: string;
    { Backing field of @link(Folder). }
    FFolder: string;
    { Backing field of @link(Licence). }
    FLicence: string;
    { Backing field of @link(Configuration). }
    FConfiguration: string;
    { Backing field of @link(Warning). }
    FWarning: string;
    { Backing field of @link(HasVideo). }
    FHasVideo: Boolean;
    { Loads library AIndex from AFolder ('' = the executable's folder, then
      the system search). }
    procedure LoadLib(AIndex: Integer; const AFolder: string);
    { Binds every function of @link(Flat) (swscale's only with video). }
    procedure BindAll;
    { Checks the major versions against the layout include. }
    procedure CheckVersions;
    { Reads the licence and build options and applies APolicy. }
    procedure CheckLicence(APolicy: TFFmpegLicencePolicy);
    { Folder of the libraries for messages: @link(Folder), or 'the system
      search path' when it is not known. }
    function FolderText: string;
  public
    { Loads FFmpeg from AFolder, or ('') the executable's folder and then
      the system search path. AWithVideo also loads swscale.
      @raises(EFFmpegError when a library or function is missing, the major
        versions differ from the ones the offsets were generated for, the
        record layout differs, or the build's licence is one APolicy
        refuses.) }
    constructor Create(const AFolder: string = ''; APolicy: TFFmpegLicencePolicy = flpAny;
      AWithVideo: Boolean = False);
    { Unloads the libraries. }
    destructor Destroy; override;
    { FFmpeg's text for an error code. }
    function ErrorText(ACode: Integer): string;
    { Loads avfilter (from the folder the others came from) for filters -
      the player's speed change. True when it is (or already was) loaded;
      False, with the reason in @link(FiltersNote), when it is missing, of
      another major version or of a licence the policy refuses. Call it
      from one thread, before the filters are used. }
    function LoadFilters: Boolean;
    { File name of library AStem ('avutil', ...) with major version AMajor
      on this platform: avutil-60.dll, libavutil.so.60, libavutil.60.dylib,
      and on Android libavutil.so (an APK holds no versioned names). }
    class function LibraryFileName(const AStem: string; AMajor: Integer): string;
    { The bound functions. }
    property Flat: TFFmpegFlat read FFlat;
    { "FFmpeg avutil 60.26.100, ... (licence) from folder", for logs. }
    property Description: string read FDescription;
    { Folder the libraries were loaded from. On Windows always known (also
      for libraries found on PATH); elsewhere '' when they were found by
      name on the system search path. }
    property Folder: string read FFolder;
    { The build's licence as FFmpeg reports it, e.g. 'LGPL version 2.1 or
      later', 'GPL version 3 or later', 'nonfree and unredistributable'. }
    property Licence: string read FLicence;
    { The build's configure options (--enable-gpl, --enable-nonfree, ...). }
    property Configuration: string read FConfiguration;
    { '' or a warning about the licence (a non-free build). }
    property Warning: string read FWarning;
    { swscale was loaded (video). }
    property HasVideo: Boolean read FHasVideo;
    { avfilter was loaded (@link(LoadFilters)). }
    property HasFilters: Boolean read FHasFilters;
    { Why LoadFilters failed ('' when it did not). }
    property FiltersNote: string read FFiltersNote;
  end;

  { Raised for FFmpeg errors. }
  EFFmpegError = class(Exception);

{ Compares the Pascal records above with the C layout from
  FFmpeg.Layout.inc; '' when they agree, else what differs. }
function FFmpegCheckLayout: string;

{ Pointer AOffset bytes into AP. }
function FFmpegAt(AP: Pointer; AOffset: Integer): Pointer;
{ Int32 at AOffset in AP. }
function FFmpegI32(AP: Pointer; AOffset: Integer): Int32;
{ Int64 at AOffset in AP. }
function FFmpegI64(AP: Pointer; AOffset: Integer): Int64;
{ Pointer at AOffset in AP. }
function FFmpegPtr(AP: Pointer; AOffset: Integer): Pointer;
{ A C string (UTF-8) as a string ('' for nil). }
function FFmpegText(AP: PAnsiChar): string;
{ "major.minor.micro" of a packed version. }
function FFmpegVersionText(V: UInt32): string;

implementation

const
  { Library stems in load order (each needs the ones before it). }
  STEMS: array[0..5] of string = ('avutil', 'swresample', 'avcodec', 'avformat', 'swscale', 'avfilter');

function FFmpegAt(AP: Pointer; AOffset: Integer): Pointer;
begin
  Result := Pointer(NativeUInt(AP) + NativeUInt(AOffset));
end;

function FFmpegI32(AP: Pointer; AOffset: Integer): Int32;
begin
  Result := PInteger(FFmpegAt(AP, AOffset))^;
end;

function FFmpegI64(AP: Pointer; AOffset: Integer): Int64;
begin
  Result := PInt64(FFmpegAt(AP, AOffset))^;
end;

function FFmpegPtr(AP: Pointer; AOffset: Integer): Pointer;
begin
  Result := PPointer(FFmpegAt(AP, AOffset))^;
end;

function FFmpegText(AP: PAnsiChar): string;
begin
  if AP = nil then
    Result := ''
  else
    Result := string(UTF8String(AP));
end;

function FFmpegVersionText(V: UInt32): string;
begin
  Result := Format('%d.%d.%d', [V shr 16, (V shr 8) and $FF, V and $FF]);
end;

{ Major version library AIndex must have. }
function ExpectedMajor(AIndex: Integer): Integer;
begin
  case AIndex of
    0: Result := FFMPEG_AVUTIL_MAJOR;
    1: Result := FFMPEG_SWRESAMPLE_MAJOR;
    2: Result := FFMPEG_AVCODEC_MAJOR;
    3: Result := FFMPEG_AVFORMAT_MAJOR;
    4: Result := FFMPEG_SWSCALE_MAJOR;
  else
    Result := FFMPEG_AVFILTER_MAJOR;
  end;
end;

function FFmpegCheckLayout: string;
{$ifndef FFMPEG_NO_LAYOUT}
var
  Got: array of Integer;
  I: Integer;
  R: TAVRational;
  L: TAVChannelLayout;
  C: TAVChapter;
  E: TAVDictionaryEntry;

  procedure Add(AValue: NativeUInt);
  begin
    SetLength(Got, Length(Got) + 1);
    Got[High(Got)] := Integer(AValue);
  end;

{$endif}
begin
  Result := '';
  {$ifndef FFMPEG_NO_LAYOUT}
  Got := nil;
  Add(SizeOf(TAVRational)); Add(FFMPEG_C_LAYOUT[1]);
  Add(NativeUInt(@R.num) - NativeUInt(@R)); Add(NativeUInt(@R.den) - NativeUInt(@R));
  Add(SizeOf(TAVChannelLayout)); Add(FFMPEG_C_LAYOUT[5]);
  Add(NativeUInt(@L.order) - NativeUInt(@L)); Add(NativeUInt(@L.nb_channels) - NativeUInt(@L));
  Add(NativeUInt(@L.u) - NativeUInt(@L)); Add(NativeUInt(@L.opaque) - NativeUInt(@L));
  Add(SizeOf(TAVChapter)); Add(FFMPEG_C_LAYOUT[11]);
  Add(NativeUInt(@C.id) - NativeUInt(@C)); Add(NativeUInt(@C.time_base) - NativeUInt(@C));
  Add(NativeUInt(@C.start) - NativeUInt(@C)); Add(NativeUInt(@C.end_) - NativeUInt(@C));
  Add(NativeUInt(@C.metadata) - NativeUInt(@C));
  Add(SizeOf(TAVDictionaryEntry)); Add(FFMPEG_C_LAYOUT[18]);
  Add(NativeUInt(@E.key) - NativeUInt(@E)); Add(NativeUInt(@E.value) - NativeUInt(@E));
  // Alignments (indexes 1, 5, 11, 18) are copied from the table: Pascal has
  // no portable way to ask for them; sizes and offsets cover the layout.
  if Length(Got) <> Length(FFMPEG_C_LAYOUT) then
    Result := Format(' %d values, C table %d;', [Length(Got), Length(FFMPEG_C_LAYOUT)])
  else
    for I := 0 to High(FFMPEG_C_LAYOUT) do
      if Got[I] <> FFMPEG_C_LAYOUT[I] then
        Result := Result + Format(' [%d] C %d, Pascal %d;', [I, FFMPEG_C_LAYOUT[I], Got[I]]);
  if Result <> '' then
    Result := 'FFmpeg record layout differs from C:' + Result;
  {$endif}
end;

{ TFFmpegLibrary }

class function TFFmpegLibrary.LibraryFileName(const AStem: string; AMajor: Integer): string;
begin
  {$if defined(FFMPEG_WINDOWS)}
  Result := Format('%s-%d.dll', [AStem, AMajor]);
  {$elseif defined(FFMPEG_MACOS)}
  Result := Format('lib%s.%d.dylib', [AStem, AMajor]);
  {$elseif defined(FFMPEG_ANDROID)}
  // an APK carries only lib*.so names; the version is checked after loading
  Result := Format('lib%s.so', [AStem]);
  {$else}
  Result := Format('lib%s.so.%d', [AStem, AMajor]);
  {$endif}
end;

constructor TFFmpegLibrary.Create(const AFolder: string; APolicy: TFFmpegLicencePolicy;
  AWithVideo: Boolean);
var
  I, Last: Integer;
  Layout, Video: string;
begin
  inherited Create;
  FPolicy := APolicy;
  Layout := FFmpegCheckLayout;
  if Layout <> '' then
    raise EFFmpegError.Create(Layout);
  FHasVideo := AWithVideo;
  if AWithVideo then
    Last := 4
  else
    Last := 3;
  for I := 0 to Last do
    LoadLib(I, AFolder);
  FFolder := ExtractFilePath(FLibs[3].FileName);
  BindAll;
  CheckVersions;
  CheckLicence(APolicy);
  FFlat.av_log_set_level(AV_LOG_ERROR);
  if AWithVideo then
    Video := ', swscale ' + FFmpegVersionText(FFlat.swscale_version)
  else
    Video := '';
  FDescription := Format('FFmpeg avutil %s, swresample %s, avcodec %s, avformat %s%s (%s) from %s',
    [FFmpegVersionText(FFlat.avutil_version), FFmpegVersionText(FFlat.swresample_version),
     FFmpegVersionText(FFlat.avcodec_version), FFmpegVersionText(FFlat.avformat_version), Video,
     FLicence, FolderText]);
end;

destructor TFFmpegLibrary.Destroy;
var
  I: Integer;
begin
  FillChar(FFlat, SizeOf(FFlat), 0);
  for I := High(FLibs) downto 0 do
    FreeAndNil(FLibs[I]);
  inherited;
end;

procedure TFFmpegLibrary.LoadLib(AIndex: Integer; const AFolder: string);
var
  Name: string;
begin
  Name := LibraryFileName(STEMS[AIndex], ExpectedMajor(AIndex));
  if AFolder <> '' then
    Name := IncludeTrailingPathDelimiter(AFolder) + Name;
  try
    FLibs[AIndex] := TFFmpegDynLib.Load(Name, True);
  except
    on E: EFFmpegDynLibError do
      raise EFFmpegError.CreateFmt('FFmpeg''s shared libraries (%s, %s, %s, %s) are needed: %s',
        [LibraryFileName(STEMS[0], ExpectedMajor(0)), LibraryFileName(STEMS[1], ExpectedMajor(1)),
         LibraryFileName(STEMS[2], ExpectedMajor(2)), LibraryFileName(STEMS[3], ExpectedMajor(3)),
         E.Message]);
  end;
end;

procedure TFFmpegLibrary.BindAll;
var
  U, S, C, F, V: TFFmpegDynLib;
begin
  U := FLibs[0];
  S := FLibs[1];
  C := FLibs[2];
  F := FLibs[3];
  V := FLibs[4];
  try
    U.Bind(FFlat.avutil_version, 'avutil_version');
    U.Bind(FFlat.avutil_license, 'avutil_license');
    U.Bind(FFlat.avutil_configuration, 'avutil_configuration');
    U.Bind(FFlat.av_log_set_level, 'av_log_set_level');
    U.Bind(FFlat.av_frame_alloc, 'av_frame_alloc');
    U.Bind(FFlat.av_frame_free, 'av_frame_free');
    U.Bind(FFlat.av_frame_unref, 'av_frame_unref');
    U.Bind(FFlat.av_frame_get_buffer, 'av_frame_get_buffer');
    U.Bind(FFlat.av_dict_get, 'av_dict_get');
    U.Bind(FFlat.av_strerror, 'av_strerror');
    U.Bind(FFlat.av_channel_layout_default, 'av_channel_layout_default');
    U.Bind(FFlat.av_channel_layout_uninit, 'av_channel_layout_uninit');
    U.Bind(FFlat.av_get_media_type_string, 'av_get_media_type_string');
    U.Bind(FFlat.av_get_sample_fmt_name, 'av_get_sample_fmt_name');
    U.Bind(FFlat.av_get_pix_fmt_name, 'av_get_pix_fmt_name');
    S.Bind(FFlat.swresample_version, 'swresample_version');
    S.Bind(FFlat.swresample_license, 'swresample_license');
    S.Bind(FFlat.swr_alloc_set_opts2, 'swr_alloc_set_opts2');
    S.Bind(FFlat.swr_init, 'swr_init');
    S.Bind(FFlat.swr_free, 'swr_free');
    S.Bind(FFlat.swr_convert, 'swr_convert');
    S.Bind(FFlat.swr_get_out_samples, 'swr_get_out_samples');
    C.Bind(FFlat.avcodec_version, 'avcodec_version');
    C.Bind(FFlat.avcodec_license, 'avcodec_license');
    C.Bind(FFlat.avcodec_find_decoder, 'avcodec_find_decoder');
    C.Bind(FFlat.avcodec_get_name, 'avcodec_get_name');
    C.Bind(FFlat.avcodec_alloc_context3, 'avcodec_alloc_context3');
    C.Bind(FFlat.avcodec_free_context, 'avcodec_free_context');
    C.Bind(FFlat.avcodec_parameters_to_context, 'avcodec_parameters_to_context');
    C.Bind(FFlat.avcodec_open2, 'avcodec_open2');
    C.Bind(FFlat.avcodec_send_packet, 'avcodec_send_packet');
    C.Bind(FFlat.avcodec_receive_frame, 'avcodec_receive_frame');
    C.Bind(FFlat.avcodec_flush_buffers, 'avcodec_flush_buffers');
    C.Bind(FFlat.av_packet_alloc, 'av_packet_alloc');
    C.Bind(FFlat.av_packet_free, 'av_packet_free');
    C.Bind(FFlat.av_packet_unref, 'av_packet_unref');
    F.Bind(FFlat.avformat_version, 'avformat_version');
    F.Bind(FFlat.avformat_license, 'avformat_license');
    F.Bind(FFlat.avformat_configuration, 'avformat_configuration');
    F.Bind(FFlat.avformat_open_input, 'avformat_open_input');
    F.Bind(FFlat.avformat_find_stream_info, 'avformat_find_stream_info');
    F.Bind(FFlat.avformat_close_input, 'avformat_close_input');
    F.Bind(FFlat.av_find_best_stream, 'av_find_best_stream');
    F.Bind(FFlat.av_read_frame, 'av_read_frame');
    F.Bind(FFlat.av_seek_frame, 'av_seek_frame');
    if V <> nil then
    begin
      V.Bind(FFlat.swscale_version, 'swscale_version');
      V.Bind(FFlat.swscale_license, 'swscale_license');
      V.Bind(FFlat.sws_getContext, 'sws_getContext');
      V.Bind(FFlat.sws_scale, 'sws_scale');
      V.Bind(FFlat.sws_freeContext, 'sws_freeContext');
    end;
  except
    on E: EFFmpegDynLibError do
      raise EFFmpegError.Create('FFmpeg: ' + E.Message);
  end;
end;

procedure TFFmpegLibrary.CheckVersions;
var
  Got: array[0..4] of UInt32;
  I, Last: Integer;
begin
  Got[0] := FFlat.avutil_version;
  Got[1] := FFlat.swresample_version;
  Got[2] := FFlat.avcodec_version;
  Got[3] := FFlat.avformat_version;
  Last := 3;
  if FHasVideo then
  begin
    Got[4] := FFlat.swscale_version;
    Last := 4;
  end;
  for I := 0 to Last do
    if Integer(Got[I] shr 16) <> ExpectedMajor(I) then
      raise EFFmpegError.CreateFmt('FFmpeg %s is version %s; this binding was made for major %d ' +
        '(rerun tools/ffmpeg_layout.py for another FFmpeg)', [STEMS[I], FFmpegVersionText(Got[I]),
        ExpectedMajor(I)]);
end;

function TFFmpegLibrary.FolderText: string;
begin
  if FFolder = '' then
    Result := 'the system search path'
  else
    Result := FFolder;
end;

procedure TFFmpegLibrary.CheckLicence(APolicy: TFFmpegLicencePolicy);
var
  Texts: array[0..4] of string;
  I, Last: Integer;
  NonFree, Gpl: Boolean;
  LowText: string;
begin
  Texts[0] := FFmpegText(FFlat.avutil_license);
  Texts[1] := FFmpegText(FFlat.swresample_license);
  Texts[2] := FFmpegText(FFlat.avcodec_license);
  Texts[3] := FFmpegText(FFlat.avformat_license);
  Last := 3;
  if FHasVideo then
  begin
    Texts[4] := FFmpegText(FFlat.swscale_license);
    Last := 4;
  end;
  FLicence := Texts[3];
  FConfiguration := FFmpegText(FFlat.avformat_configuration);
  NonFree := Pos('--enable-nonfree', FConfiguration) > 0;
  Gpl := Pos('--enable-gpl', FConfiguration) > 0;
  for I := 0 to Last do
  begin
    LowText := LowerCase(Texts[I]);
    if Pos('nonfree', LowText) > 0 then
      NonFree := True
    else if (Pos('gpl', LowText) > 0) and (Pos('lgpl', LowText) = 0) then
      Gpl := True;
  end;
  if NonFree then
  begin
    FLicence := 'nonfree and unredistributable';
    FWarning := 'This FFmpeg build is non-free (--enable-nonfree): it may not be redistributed.';
  end
  else if Gpl and (Pos('lgpl', LowerCase(FLicence)) > 0) then
    FLicence := 'GPL (configured with --enable-gpl)';
  if NonFree and (APolicy in [flpRedistributable, flpLGPL]) then
    raise EFFmpegError.CreateFmt('The FFmpeg libraries in %s are a non-free build (%s): they may not ' +
      'be redistributed. A redistributable build is needed.', [FolderText,
      FLicence]);
  if Gpl and (APolicy = flpLGPL) then
    raise EFFmpegError.CreateFmt('The FFmpeg libraries in %s are a GPL build (%s); this program accepts ' +
      'LGPL builds only.', [FolderText, FLicence]);
end;

function TFFmpegLibrary.LoadFilters: Boolean;
var
  Name, Lic: string;
  L: TFFmpegDynLib;
begin
  if FHasFilters then
    Exit(True);
  Result := False;
  FFiltersNote := '';
  Name := LibraryFileName(STEMS[5], ExpectedMajor(5));
  if FFolder <> '' then
    Name := IncludeTrailingPathDelimiter(FFolder) + Name;
  L := nil;
  try
    // avfilter needs swscale: loaded first, from the same folder - neither
    // Windows' LoadLibrary nor dlopen looks for a library's dependencies
    // in its own folder, only among the libraries already loaded
    if FLibs[4] = nil then
      LoadLib(4, FFolder);
    try
      L := TFFmpegDynLib.Load(Name, True);
    except
      on E: EFFmpegDynLibError do
        raise EFFmpegError.CreateFmt('FFmpeg''s filter library (%s) was not found - no speed change: %s',
          [LibraryFileName(STEMS[5], ExpectedMajor(5)), E.Message]);
    end;
    try
      L.Bind(FFlat.avfilter_version, 'avfilter_version');
      L.Bind(FFlat.avfilter_license, 'avfilter_license');
      L.Bind(FFlat.avfilter_get_by_name, 'avfilter_get_by_name');
      L.Bind(FFlat.avfilter_graph_alloc, 'avfilter_graph_alloc');
      L.Bind(FFlat.avfilter_graph_free, 'avfilter_graph_free');
      L.Bind(FFlat.avfilter_graph_create_filter, 'avfilter_graph_create_filter');
      L.Bind(FFlat.avfilter_link, 'avfilter_link');
      L.Bind(FFlat.avfilter_graph_config, 'avfilter_graph_config');
      L.Bind(FFlat.av_buffersrc_add_frame_flags, 'av_buffersrc_add_frame_flags');
      L.Bind(FFlat.av_buffersink_get_frame, 'av_buffersink_get_frame');
    except
      on E: EFFmpegDynLibError do
        raise EFFmpegError.Create('FFmpeg: ' + E.Message);
    end;
    if Integer(FFlat.avfilter_version shr 16) <> ExpectedMajor(5) then
      raise EFFmpegError.CreateFmt('FFmpeg avfilter is version %s; this binding was made for major %d',
        [FFmpegVersionText(FFlat.avfilter_version), ExpectedMajor(5)]);
    // the same licence rules as the other libraries
    Lic := LowerCase(FFmpegText(FFlat.avfilter_license));
    if (Pos('nonfree', Lic) > 0) and (FPolicy in [flpRedistributable, flpLGPL]) then
      raise EFFmpegError.Create('FFmpeg avfilter is a non-free build: it may not be redistributed');
    if (Pos('gpl', Lic) > 0) and (Pos('lgpl', Lic) = 0) and (FPolicy = flpLGPL) then
      raise EFFmpegError.Create('FFmpeg avfilter is a GPL build; this program accepts LGPL builds only');
    FLibs[5] := L;
    FHasFilters := True;
    FDescription := FDescription + ', avfilter ' + FFmpegVersionText(FFlat.avfilter_version);
    Result := True;
  except
    on E: Exception do
    begin
      FFiltersNote := E.Message;
      // nothing of a half-loaded avfilter stays callable
      FFlat.avfilter_version := nil;
      FFlat.avfilter_license := nil;
      FFlat.avfilter_get_by_name := nil;
      FFlat.avfilter_graph_alloc := nil;
      FFlat.avfilter_graph_free := nil;
      FFlat.avfilter_graph_create_filter := nil;
      FFlat.avfilter_link := nil;
      FFlat.avfilter_graph_config := nil;
      FFlat.av_buffersrc_add_frame_flags := nil;
      FFlat.av_buffersink_get_frame := nil;
      L.Free;
    end;
  end;
end;

function TFFmpegLibrary.ErrorText(ACode: Integer): string;
var
  Buf: array[0..255] of AnsiChar;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  if FFlat.av_strerror(ACode, @Buf[0], SizeOf(Buf)) = 0 then
    Result := FFmpegText(@Buf[0])
  else
    Result := Format('FFmpeg error %d', [ACode]);
end;

end.
