(* @abstract(Media files through FFmpeg: their streams, chapters, tags and
  cover art, the copy-protection check, and decoding audio to any rate and
  channel count.)

  @link(TFFmpegMediaFile) opens a file and describes it: every stream
  (audio, video, subtitle, data, attached picture) with its facts, the
  chapters (an audiobook's), the tags, and the cover art an M4B or MP3
  carries. @link(TFFmpegAudioDecoder) decodes any time range of an audio
  stream to interleaved 32-bit float at the rate and channel count asked
  for - reading an audiobook one chapter at a time keeps memory small
  however long it is.

  Video: every video stream is described (size, frame rate, pixel format),
  and @link(TFFmpegDecoder) holds what any decoder needs (opening the codec,
  seeking, the packet loop, error counting), so a video decoder can be
  added beside the audio one; none is written yet.

  Copy-protected files (an Audible .aax straight from Audible, FairPlay)
  are refused with a clear message by @link(FFmpegMp4Protection), read from
  the file's header before FFmpeg sees it. No decryption is offered.

  Framework-free; compiles with Delphi and FPC. *)
unit FFmpeg.Media;

{$I FFmpeg.inc}

interface

uses
  SysUtils, Classes,
  FFmpeg.API;

type
  { What a stream holds. }
  TFFmpegMediaKind = (
    { Unknown. }
    fmkUnknown,
    { Video. }
    fmkVideo,
    { Audio. }
    fmkAudio,
    { Data. }
    fmkData,
    { Subtitles. }
    fmkSubtitle,
    { An attachment (fonts in a Matroska file). }
    fmkAttachment
  );

  { One stream of a media file. Times in seconds (0 when unknown). }
  TFFmpegStreamInfo = record
    { Index in the file. }
    Index: Integer;
    { What it holds. }
    Kind: TFFmpegMediaKind;
    { Codec name, e.g. 'aac', 'h264', 'mjpeg'. }
    CodecName: string;
    { Language tag ('eng', ...; '' when none). }
    Language: string;
    { Title tag ('' when none). }
    Title: string;
    { Length, s. }
    Duration: Double;
    { Bits per second (0 when unknown). }
    BitRate: Int64;
    { The default stream of its kind. }
    IsDefault: Boolean;
    { A picture (cover art) rather than video: its data is
      @link(TFFmpegMediaFile.CoverArt). }
    IsCoverArt: Boolean;
    { Audio: samples per second. }
    SampleRate: Integer;
    { Audio: channels. }
    Channels: Integer;
    { Audio: sample format name ('fltp', 's16', ...). }
    SampleFormat: string;
    { Video: width in pixels. }
    Width: Integer;
    { Video: height in pixels. }
    Height: Integer;
    { Video: average frames per second (0 when unknown). }
    FrameRate: Double;
    { Video: pixel format name ('yuv420p', ...). }
    PixelFormat: string;
  end;
  { The streams of a file, in file order. }
  TFFmpegStreamInfoArray = array of TFFmpegStreamInfo;

  { One chapter. Times in seconds from the start of the file. }
  TFFmpegChapter = record
    { Title ('' when none). }
    Title: string;
    { Start, s. }
    StartTime: Double;
    { End, s. }
    EndTime: Double;
  end;
  { The chapters, in order. }
  TFFmpegChapterArray = array of TFFmpegChapter;

  { One tag (metadata entry) of a file. }
  TFFmpegTag = record
    { Key, as FFmpeg names it ('title', 'artist', 'album', 'date', ...). }
    Key: string;
    { Value. }
    Value: string;
  end;
  { The tags, in file order. }
  TFFmpegTagArray = array of TFFmpegTag;

  { Interleaved 32-bit float samples (L R L R ... for stereo). }
  TFFmpegSamples = array of Single;

  { An open media file. Reading (decoding) uses its demuxer, so one decoder
    at a time per file; open the file twice for two at once. }
  TFFmpegMediaFile = class
  private
    { Libraries (not owned). }
    FLib: TFFmpegLibrary;
    { AVFormatContext. }
    FFormat: Pointer;
    { Backing field of @link(FileName). }
    FFileName: string;
    { Backing field of @link(Streams). }
    FStreams: TFFmpegStreamInfoArray;
    { Backing field of @link(Chapters). }
    FChapters: TFFmpegChapterArray;
    { Backing field of @link(Tags). }
    FTags: TFFmpegTagArray;
    { Backing field of @link(Duration). }
    FDuration: Double;
    { Backing field of @link(StartOffset). }
    FStartOffset: Double;
    { Backing field of @link(BitRate). }
    FBitRate: Int64;
    { True once a decoder has read packets from the file: the demuxer is no
      longer at the start, so the next read seeks, whichever decoder it is. }
    FUsed: Boolean;
    { Reads the streams. }
    procedure ReadStreams;
    { Reads the chapters. }
    procedure ReadChapters;
    { The entries of an AVDictionary. }
    function ReadTags(ADict: Pointer): TFFmpegTagArray;
  public
    { Opens AFileName (any format FFmpeg reads) and reads its streams,
      chapters and tags.
      @raises(EFFmpegError when the file is copy protected or FFmpeg cannot
        open it.) }
    constructor Create(ALib: TFFmpegLibrary; const AFileName: string);
    { Closes the file. }
    destructor Destroy; override;
    { Raises EFFmpegError for a negative FFmpeg result (AWhat: 'open', ...). }
    procedure Check(ACode: Integer; const AWhat: string);
    { The value of tag AKey (case ignored; '' when absent). }
    function Tag(const AKey: string): string;
    { The best stream of AKind (FFmpeg's choice; -1 when none). Cover art
      is never the best video. }
    function BestStream(AKind: TFFmpegMediaKind): Integer;
    { The cover art: the data of the first attached picture, as stored
      (JPEG or PNG); AExtension gets '.jpg', '.png' or '.bin'. False when
      the file has none. }
    function CoverArt(out AData: TBytes; out AExtension: string): Boolean;
    { The libraries. }
    property Lib: TFFmpegLibrary read FLib;
    { AVFormatContext (for decoders). }
    property Handle: Pointer read FFormat;
    { The file. }
    property FileName: string read FFileName;
    { The streams. }
    property Streams: TFFmpegStreamInfoArray read FStreams;
    { The chapters (none for most files that are not audiobooks). }
    property Chapters: TFFmpegChapterArray read FChapters;
    { The file's tags. }
    property Tags: TFFmpegTagArray read FTags;
    { Length, s (0 when FFmpeg does not know). }
    property Duration: Double read FDuration;
    { Start of the file's time line, s; every time here is relative to it. }
    property StartOffset: Double read FStartOffset;
    { Bits per second of the whole file (0 when unknown). }
    property BitRate: Int64 read FBitRate;
  end;

  { What every decoder needs: the codec of one stream, seeking, and the
    packet loop. Descendants turn frames into their output. }
  TFFmpegDecoder = class
  private
    { The file (not owned). }
    FFile: TFFmpegMediaFile;
    { AVCodecContext. }
    FCodec: Pointer;
    { AVPacket. }
    FPacket: Pointer;
    { AVFrame. }
    FFrame: Pointer;
    { Backing field of @link(Stream). }
    FStream: Integer;
    { Time base of the stream, seconds per unit. }
    FTimeBase: Double;
    { Backing field of @link(DecodeErrors). }
    FDecodeErrors: Integer;
    { Backing field of @link(Cancelled). }
    FCancelled: Boolean;
  protected
    { Takes one decoded frame at ATime seconds (on the file's time line);
      returns False to stop reading. }
    function TakeFrame(AFrame: Pointer; ATime: Double): Boolean; virtual; abstract;
    { Called after the last frame of a read when the end of the file was
      reached (flush buffered output). }
    procedure EndOfStream; virtual;
    { Seeks to AStart (seconds) when needed and feeds frames to TakeFrame
      until it returns False or the file ends; True when the end was
      reached. }
    function Run(AStart: Double): Boolean;
  public
    { A decoder for stream AStream of AFile.
      @raises(EFFmpegError when the stream does not exist or its codec is not
        in this FFmpeg build.) }
    constructor Create(AFile: TFFmpegMediaFile; AStream: Integer);
    { Frees the codec. }
    destructor Destroy; override;
    { The file. }
    property MediaFile: TFFmpegMediaFile read FFile;
    { The stream decoded. }
    property Stream: Integer read FStream;
    { Asks a read in progress to stop (any thread): it stops at the next
      packet and returns what it has; @link(Cancelled) tells. Reset by the
      next read. }
    procedure Cancel;
    { Packets the decoder rejected so far (damaged data is skipped). }
    property DecodeErrors: Integer read FDecodeErrors;
    { The last read was stopped by @link(Cancel). }
    property Cancelled: Boolean read FCancelled;
  end;

  { Decodes an audio stream to interleaved 32-bit float. }
  TFFmpegAudioDecoder = class(TFFmpegDecoder)
  private
    { SwrContext (made from the first frame of a read). }
    FSwr: Pointer;
    { Output layout. }
    FOutLayout: TAVChannelLayout;
    { Samples of the read so far. }
    FBuf: TFFmpegSamples;
    { Frames (samples per channel) in FBuf. }
    FCount: Int64;
    { Time of the first frame of the read. }
    FBufStart: Double;
    { A first frame was taken. }
    FHaveStart: Boolean;
    { End of the range of the read (0 = to the end). }
    FEnd: Double;
    { Backing field of @link(SampleRate). }
    FSampleRate: Integer;
    { Backing field of @link(Channels). }
    FChannels: Integer;
    { Makes room for ANeed frames. }
    procedure Grow(ANeed: Int64);
    { Resamples AFrame (nil = flush) into FBuf. }
    procedure Convert(AFrame: Pointer);
  protected
    { Resamples the frame into the buffer; False past the range. }
    function TakeFrame(AFrame: Pointer; ATime: Double): Boolean; override;
    { Flushes the resampler. }
    procedure EndOfStream; override;
  public
    { A decoder for audio stream AStream of AFile (-1 = the best audio),
      giving ASampleRate samples per second (0 = the stream's) and
      AChannels channels (0 = the stream's; 1 = mixed down to mono).
      @raises(EFFmpegError when there is no such audio stream or its codec
        is missing.) }
    constructor Create(AFile: TFFmpegMediaFile; AStream: Integer = -1; ASampleRate: Integer = 0;
      AChannels: Integer = 0);
    { Frees the resampler. }
    destructor Destroy; override;
    { Decodes AStart..AEnd seconds (AEnd <= 0: to the end). Seeks, so any
      order of ranges works; reading in order is the fast path.
      @raises(EFFmpegError when reading fails or the range is too long to
        hold - read it in parts, e.g. by chapter.) }
    function Read(AStart: Double = 0; AEnd: Double = 0): TFFmpegSamples;
    { Samples per second of the output. }
    property SampleRate: Integer read FSampleRate;
    { Channels of the output. }
    property Channels: Integer read FChannels;
  end;

{ The copy protection of an MPEG-4 file (.m4b, .m4a, .mp4, .aax, ...), read
  from its header (the moov box) without FFmpeg: 'Audible DRM (adrm)',
  'FairPlay DRM (drms)', 'encrypted (sinf)' or 'encrypted (enca)'; '' when
  there is none or the file is not MPEG-4. A file a tool has decrypted has
  none, whatever its extension. }
function FFmpegMp4Protection(const AFileName: string): string;

{ Name of a media kind ('video', 'audio', ...). }
function FFmpegMediaKindName(AKind: TFFmpegMediaKind): string;

implementation

const
  { Names of the media kinds. }
  KIND_NAMES: array[TFFmpegMediaKind] of string = ('unknown', 'video', 'audio', 'data', 'subtitle',
    'attachment');

function FFmpegMediaKindName(AKind: TFFmpegMediaKind): string;
begin
  Result := KIND_NAMES[AKind];
end;

{ The kind of an AVMEDIA_TYPE_* value. }
function KindOf(AType: Integer): TFFmpegMediaKind;
begin
  case AType of
    AVMEDIA_TYPE_VIDEO: Result := fmkVideo;
    AVMEDIA_TYPE_AUDIO: Result := fmkAudio;
    AVMEDIA_TYPE_DATA: Result := fmkData;
    AVMEDIA_TYPE_SUBTITLE: Result := fmkSubtitle;
    AVMEDIA_TYPE_ATTACHMENT: Result := fmkAttachment;
  else
    Result := fmkUnknown;
  end;
end;

{ The AVMEDIA_TYPE_* value of a kind. }
function MediaTypeOf(AKind: TFFmpegMediaKind): Integer;
begin
  case AKind of
    fmkVideo: Result := AVMEDIA_TYPE_VIDEO;
    fmkAudio: Result := AVMEDIA_TYPE_AUDIO;
    fmkData: Result := AVMEDIA_TYPE_DATA;
    fmkSubtitle: Result := AVMEDIA_TYPE_SUBTITLE;
    fmkAttachment: Result := AVMEDIA_TYPE_ATTACHMENT;
  else
    Result := AVMEDIA_TYPE_UNKNOWN;
  end;
end;

{ A fraction as a number (0 for a zero denominator). }
function RationalValue(const R: TAVRational): Double;
begin
  if R.den = 0 then
    Result := 0
  else
    Result := R.num / R.den;
end;

function FFmpegMp4Protection(const AFileName: string): string;
const
  { Largest moov box read (it holds the index of the whole file). }
  MAX_MOOV = 64 * 1024 * 1024;
  { Box types that mean protection, and what they are. }
  MARKS: array[0..3] of AnsiString = ('adrm', 'drms', 'sinf', 'enca');
  NAMES: array[0..3] of string = ('Audible DRM (adrm)', 'FairPlay DRM (drms)', 'encrypted (sinf)',
    'encrypted (enca)');
var
  F: TFileStream;
  Head: array[0..7] of Byte;
  Big: array[0..7] of Byte;
  Size, Pos, Len: Int64;
  Kind: AnsiString;
  Moov: array of Byte;
  I, K, M: Integer;
  BoxSize: Int64;

  function BE32(const A: array of Byte; AAt: Integer): Int64;
  begin
    Result := (Int64(A[AAt]) shl 24) or (A[AAt + 1] shl 16) or (A[AAt + 2] shl 8) or A[AAt + 3];
  end;

begin
  Result := '';
  if not FileExists(AFileName) then
    Exit;
  F := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Len := F.Size;
    Pos := 0;
    Moov := nil;
    while Pos + 8 <= Len do
    begin
      F.Position := Pos;
      F.ReadBuffer(Head, 8);
      Size := BE32(Head, 0);
      SetLength(Kind, 4);
      Move(Head[4], Kind[1], 4);
      if (Pos = 0) and (Kind <> 'ftyp') then
        Exit;   // not MPEG-4
      if Size = 1 then
      begin
        F.ReadBuffer(Big, 8);
        Size := (BE32(Big, 0) shl 32) or BE32(Big, 4);
      end
      else if Size = 0 then
        Size := Len - Pos;
      if Size < 8 then
        Exit;
      if Kind = 'moov' then
      begin
        if Size > MAX_MOOV then
          Size := MAX_MOOV;
        if Pos + Size > Len then
          Size := Len - Pos;
        SetLength(Moov, Size);
        F.Position := Pos;
        F.ReadBuffer(Moov[0], Size);
        Break;
      end;
      Pos := Pos + Size;
    end;
  finally
    F.Free;
  end;
  // a mark counts where it is a box type: a plausible size in front of it
  for I := 4 to Length(Moov) - 4 do
    for K := Low(MARKS) to High(MARKS) do
    begin
      M := 1;
      while (M <= 4) and (Moov[I + M - 1] = Ord(MARKS[K][M])) do
        Inc(M);
      if M <= 4 then
        Continue;
      BoxSize := BE32(Moov, I - 4);
      if (BoxSize >= 8) and (I - 4 + BoxSize <= Length(Moov)) then
        Exit(NAMES[K]);
    end;
end;

{ TFFmpegMediaFile }

constructor TFFmpegMediaFile.Create(ALib: TFFmpegLibrary; const AFileName: string);
var
  Name: UTF8String;
  Protection: string;
  Start: Int64;
begin
  inherited Create;
  if ALib = nil then
    raise EFFmpegError.Create('TFFmpegMediaFile needs a loaded TFFmpegLibrary');
  FLib := ALib;
  FFileName := AFileName;
  Protection := FFmpegMp4Protection(AFileName);
  if Protection <> '' then
    raise EFFmpegError.CreateFmt('%s is copy protected (%s): it cannot be read. An .aax file straight ' +
      'from Audible is protected; a DRM-free copy is needed.', [AFileName, Protection]);
  Name := UTF8String(AFileName);
  Check(FLib.Flat.avformat_open_input(FFormat, PAnsiChar(Name), nil, nil), 'open');
  Check(FLib.Flat.avformat_find_stream_info(FFormat, nil), 'read the stream information of');
  Start := FFmpegI64(FFormat, FFOFS_FMT_START_TIME);
  if Start <> AV_NOPTS_VALUE then
    FStartOffset := Start / AV_TIME_BASE;
  if FFmpegI64(FFormat, FFOFS_FMT_DURATION) > 0 then
    FDuration := FFmpegI64(FFormat, FFOFS_FMT_DURATION) / AV_TIME_BASE;
  FBitRate := FFmpegI64(FFormat, FFOFS_FMT_BIT_RATE);
  FTags := ReadTags(FFmpegPtr(FFormat, FFOFS_FMT_METADATA));
  ReadStreams;
  ReadChapters;
end;

destructor TFFmpegMediaFile.Destroy;
begin
  if (FLib <> nil) and (FFormat <> nil) then
    FLib.Flat.avformat_close_input(FFormat);
  inherited;
end;

procedure TFFmpegMediaFile.Check(ACode: Integer; const AWhat: string);
begin
  if ACode < 0 then
    raise EFFmpegError.CreateFmt('FFmpeg could not %s %s: %s', [AWhat, FFileName, FLib.ErrorText(ACode)]);
end;

function TFFmpegMediaFile.ReadTags(ADict: Pointer): TFFmpegTagArray;
var
  E: PAVDictionaryEntry;
begin
  Result := nil;
  if ADict = nil then
    Exit;
  E := FLib.Flat.av_dict_get(ADict, '', nil, AV_DICT_IGNORE_SUFFIX);
  while E <> nil do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Key := FFmpegText(E^.key);
    Result[High(Result)].Value := FFmpegText(E^.value);
    E := FLib.Flat.av_dict_get(ADict, '', E, AV_DICT_IGNORE_SUFFIX);
  end;
end;

procedure TFFmpegMediaFile.ReadStreams;
var
  N, I, K: Integer;
  St, Par: Pointer;
  Info: TFFmpegStreamInfo;
  Tb: Double;
  D: Int64;
  StTags: TFFmpegTagArray;
begin
  N := FFmpegI32(FFormat, FFOFS_FMT_NB_STREAMS);
  SetLength(FStreams, N);
  for I := 0 to N - 1 do
  begin
    St := PPointer(FFmpegAt(FFmpegPtr(FFormat, FFOFS_FMT_STREAMS), I * SizeOf(Pointer)))^;
    Par := FFmpegPtr(St, FFOFS_STREAM_CODECPAR);
    Info := Default(TFFmpegStreamInfo);
    Info.Index := I;
    Info.Kind := KindOf(FFmpegI32(Par, FFOFS_PAR_CODEC_TYPE));
    Info.CodecName := FFmpegText(FLib.Flat.avcodec_get_name(FFmpegI32(Par, FFOFS_PAR_CODEC_ID)));
    Tb := RationalValue(TAVRational(FFmpegAt(St, FFOFS_STREAM_TIME_BASE)^));
    D := FFmpegI64(St, FFOFS_STREAM_DURATION);
    if (D <> AV_NOPTS_VALUE) and (D > 0) then
      Info.Duration := D * Tb
    else
      Info.Duration := FDuration;
    Info.BitRate := FFmpegI64(Par, FFOFS_PAR_BIT_RATE);
    Info.IsDefault := FFmpegI32(St, FFOFS_STREAM_DISPOSITION) and AV_DISPOSITION_DEFAULT <> 0;
    Info.IsCoverArt := FFmpegI32(St, FFOFS_STREAM_DISPOSITION) and AV_DISPOSITION_ATTACHED_PIC <> 0;
    StTags := ReadTags(FFmpegPtr(St, FFOFS_STREAM_METADATA));
    for K := 0 to High(StTags) do
      if SameText(StTags[K].Key, 'language') then
        Info.Language := StTags[K].Value
      else if SameText(StTags[K].Key, 'title') then
        Info.Title := StTags[K].Value;
    case Info.Kind of
      fmkAudio:
        begin
          Info.SampleRate := FFmpegI32(Par, FFOFS_PAR_SAMPLE_RATE);
          Info.Channels := PAVChannelLayout(FFmpegAt(Par, FFOFS_PAR_CH_LAYOUT))^.nb_channels;
          Info.SampleFormat := FFmpegText(FLib.Flat.av_get_sample_fmt_name(FFmpegI32(Par, FFOFS_PAR_FORMAT)));
        end;
      fmkVideo:
        begin
          Info.Width := FFmpegI32(Par, FFOFS_PAR_WIDTH);
          Info.Height := FFmpegI32(Par, FFOFS_PAR_HEIGHT);
          Info.FrameRate := RationalValue(TAVRational(FFmpegAt(St, FFOFS_STREAM_AVG_FRAME_RATE)^));
          if Info.FrameRate = 0 then
            Info.FrameRate := RationalValue(TAVRational(FFmpegAt(Par, FFOFS_PAR_FRAMERATE)^));
          Info.PixelFormat := FFmpegText(FLib.Flat.av_get_pix_fmt_name(FFmpegI32(Par, FFOFS_PAR_FORMAT)));
        end;
    end;
    FStreams[I] := Info;
  end;
end;

procedure TFFmpegMediaFile.ReadChapters;
var
  N, I: Integer;
  List: Pointer;
  Ch: PAVChapter;
  E: PAVDictionaryEntry;
  Tb: Double;
begin
  N := FFmpegI32(FFormat, FFOFS_FMT_NB_CHAPTERS);
  List := FFmpegPtr(FFormat, FFOFS_FMT_CHAPTERS);
  SetLength(FChapters, N);
  for I := 0 to N - 1 do
  begin
    Ch := PPointer(FFmpegAt(List, I * SizeOf(Pointer)))^;
    Tb := RationalValue(Ch^.time_base);
    FChapters[I].StartTime := Ch^.start * Tb - FStartOffset;
    FChapters[I].EndTime := Ch^.end_ * Tb - FStartOffset;
    E := FLib.Flat.av_dict_get(Ch^.metadata, 'title', nil, 0);
    if E <> nil then
      FChapters[I].Title := FFmpegText(E^.value)
    else
      FChapters[I].Title := '';
  end;
end;

function TFFmpegMediaFile.Tag(const AKey: string): string;
var
  I: Integer;
begin
  for I := 0 to High(FTags) do
    if SameText(FTags[I].Key, AKey) then
      Exit(FTags[I].Value);
  Result := '';
end;

function TFFmpegMediaFile.BestStream(AKind: TFFmpegMediaKind): Integer;
var
  I: Integer;
begin
  Result := FLib.Flat.av_find_best_stream(FFormat, MediaTypeOf(AKind), -1, -1, nil, 0);
  if Result < 0 then
    Result := -1;
  if (AKind = fmkVideo) and (Result >= 0) and FStreams[Result].IsCoverArt then
  begin
    Result := -1;
    for I := 0 to High(FStreams) do
      if (FStreams[I].Kind = fmkVideo) and not FStreams[I].IsCoverArt then
        Exit(I);
  end;
end;

function TFFmpegMediaFile.CoverArt(out AData: TBytes; out AExtension: string): Boolean;
var
  I, Size: Integer;
  St, Data: Pointer;
begin
  AData := nil;
  AExtension := '';
  for I := 0 to High(FStreams) do
    if FStreams[I].IsCoverArt then
    begin
      St := PPointer(FFmpegAt(FFmpegPtr(FFormat, FFOFS_FMT_STREAMS), I * SizeOf(Pointer)))^;
      Data := FFmpegPtr(St, FFOFS_STREAM_ATTACHED_PIC_DATA);
      Size := FFmpegI32(St, FFOFS_STREAM_ATTACHED_PIC_SIZE);
      if (Data = nil) or (Size <= 0) then
        Continue;
      SetLength(AData, Size);
      Move(Data^, AData[0], Size);
      if (Size >= 3) and (AData[0] = $FF) and (AData[1] = $D8) and (AData[2] = $FF) then
        AExtension := '.jpg'
      else if (Size >= 8) and (AData[0] = $89) and (AData[1] = Ord('P')) and (AData[2] = Ord('N')) and
        (AData[3] = Ord('G')) then
        AExtension := '.png'
      else
        AExtension := '.bin';
      Exit(True);
    end;
  Result := False;
end;

{ TFFmpegDecoder }

constructor TFFmpegDecoder.Create(AFile: TFFmpegMediaFile; AStream: Integer);
var
  St, Par, Decoder: Pointer;
begin
  inherited Create;
  if AFile = nil then
    raise EFFmpegError.Create('A decoder needs an open TFFmpegMediaFile');
  FFile := AFile;
  if (AStream < 0) or (AStream > High(AFile.Streams)) then
    raise EFFmpegError.CreateFmt('%s has no stream %d', [AFile.FileName, AStream]);
  FStream := AStream;
  St := PPointer(FFmpegAt(FFmpegPtr(AFile.Handle, FFOFS_FMT_STREAMS), AStream * SizeOf(Pointer)))^;
  FTimeBase := RationalValue(TAVRational(FFmpegAt(St, FFOFS_STREAM_TIME_BASE)^));
  Par := FFmpegPtr(St, FFOFS_STREAM_CODECPAR);
  Decoder := AFile.Lib.Flat.avcodec_find_decoder(FFmpegI32(Par, FFOFS_PAR_CODEC_ID));
  if Decoder = nil then
    raise EFFmpegError.CreateFmt('%s: this FFmpeg build has no decoder for %s', [AFile.FileName,
      AFile.Streams[AStream].CodecName]);
  FCodec := AFile.Lib.Flat.avcodec_alloc_context3(Decoder);
  if FCodec = nil then
    raise EFFmpegError.Create('FFmpeg: out of memory');
  AFile.Check(AFile.Lib.Flat.avcodec_parameters_to_context(FCodec, Par), 'set up the decoder for');
  AFile.Check(AFile.Lib.Flat.avcodec_open2(FCodec, Decoder, nil), 'open the decoder for');
  FPacket := AFile.Lib.Flat.av_packet_alloc;
  FFrame := AFile.Lib.Flat.av_frame_alloc;
  if (FPacket = nil) or (FFrame = nil) then
    raise EFFmpegError.Create('FFmpeg: out of memory');
end;

destructor TFFmpegDecoder.Destroy;
begin
  if FFile <> nil then
  begin
    if FFrame <> nil then
      FFile.Lib.Flat.av_frame_free(FFrame);
    if FPacket <> nil then
      FFile.Lib.Flat.av_packet_free(FPacket);
    if FCodec <> nil then
      FFile.Lib.Flat.avcodec_free_context(FCodec);
  end;
  inherited;
end;

procedure TFFmpegDecoder.Cancel;
begin
  FCancelled := True;
end;

procedure TFFmpegDecoder.EndOfStream;
begin
  // nothing buffered by default
end;

function TFFmpegDecoder.Run(AStart: Double): Boolean;
var
  F: TFFmpegFlat;
  R: Integer;
  Pts: Int64;
  Stop: Boolean;
  T: Double;

  // Takes every frame the decoder has ready.
  procedure Drain;
  begin
    repeat
      R := F.avcodec_receive_frame(FCodec, FFrame);
      if (R = AVERROR_EAGAIN) or (R = AVERROR_EOF) then
        Exit;
      if R < 0 then
      begin
        Inc(FDecodeErrors);
        Exit;
      end;
      Pts := FFmpegI64(FFrame, FFOFS_FRAME_PTS);
      if Pts <> AV_NOPTS_VALUE then
        T := Pts * FTimeBase - FFile.StartOffset
      else
        T := -1;   // the descendant goes on from the frame before
      if not TakeFrame(FFrame, T) then
        Stop := True;
    until Stop;
  end;

begin
  F := FFile.Lib.Flat;
  Result := False;
  Stop := False;
  FCancelled := False;
  // the position is the file's (its demuxer's), not this decoder's: a new
  // decoder on a file another one has read must seek, also to 0
  if FFile.FUsed or (AStart > 0) then
  begin
    if FTimeBase > 0 then
      FFile.Check(F.av_seek_frame(FFile.Handle, FStream, Round((AStart + FFile.StartOffset) / FTimeBase),
        AVSEEK_FLAG_BACKWARD), 'seek in');
    F.avcodec_flush_buffers(FCodec);
  end;
  FFile.FUsed := True;
  while not Stop do
  begin
    if FCancelled then
      Break;
    R := F.av_read_frame(FFile.Handle, FPacket);
    if R < 0 then
    begin
      // end of file (or a read error: decode what there is)
      F.avcodec_send_packet(FCodec, nil);
      Drain;
      Result := True;
      Break;
    end;
    if FFmpegI32(FPacket, FFOFS_PACKET_STREAM_INDEX) = FStream then
    begin
      if F.avcodec_send_packet(FCodec, FPacket) < 0 then
        Inc(FDecodeErrors);
      F.av_packet_unref(FPacket);
      Drain;
    end
    else
      F.av_packet_unref(FPacket);
  end;
  if Result then
    EndOfStream;
end;

{ TFFmpegAudioDecoder }

constructor TFFmpegAudioDecoder.Create(AFile: TFFmpegMediaFile; AStream: Integer; ASampleRate: Integer;
  AChannels: Integer);
begin
  if (AFile <> nil) and (AStream < 0) then
    AStream := AFile.BestStream(fmkAudio);
  if AFile = nil then
    raise EFFmpegError.Create('A decoder needs an open TFFmpegMediaFile');
  if AStream < 0 then
    raise EFFmpegError.CreateFmt('%s has no audio stream', [AFile.FileName]);
  if AFile.Streams[AStream].Kind <> fmkAudio then
    raise EFFmpegError.CreateFmt('%s: stream %d is not audio', [AFile.FileName, AStream]);
  inherited Create(AFile, AStream);
  FSampleRate := ASampleRate;
  if FSampleRate <= 0 then
    FSampleRate := AFile.Streams[AStream].SampleRate;
  FChannels := AChannels;
  if FChannels <= 0 then
    FChannels := AFile.Streams[AStream].Channels;
  if FChannels <= 0 then
    FChannels := 1;
  FillChar(FOutLayout, SizeOf(FOutLayout), 0);
  AFile.Lib.Flat.av_channel_layout_default(@FOutLayout, FChannels);
end;

destructor TFFmpegAudioDecoder.Destroy;
begin
  if MediaFile <> nil then
  begin
    if FSwr <> nil then
      MediaFile.Lib.Flat.swr_free(FSwr);
    MediaFile.Lib.Flat.av_channel_layout_uninit(@FOutLayout);
  end;
  inherited;
end;

procedure TFFmpegAudioDecoder.Grow(ANeed: Int64);
var
  NewLen: Int64;
begin
  if ANeed * FChannels <= Length(FBuf) then
    Exit;
  NewLen := Length(FBuf) * 2;
  if NewLen < ANeed * FChannels then
    NewLen := (ANeed + Int64(FSampleRate) * 60) * FChannels;
  if NewLen > High(Integer) then
    raise EFFmpegError.CreateFmt('%s: range too long to decode at once (read it in parts, e.g. by ' +
      'chapter)', [MediaFile.FileName]);
  SetLength(FBuf, NewLen);
end;

procedure TFFmpegAudioDecoder.Convert(AFrame: Pointer);
var
  Room, Got, InCount: Integer;
  OutPtr, InData: Pointer;
begin
  if AFrame <> nil then
  begin
    InCount := FFmpegI32(AFrame, FFOFS_FRAME_NB_SAMPLES);
    InData := FFmpegPtr(AFrame, FFOFS_FRAME_EXTENDED_DATA);
  end
  else
  begin
    InCount := 0;
    InData := nil;
  end;
  Room := MediaFile.Lib.Flat.swr_get_out_samples(FSwr, InCount) + 32;
  Grow(FCount + Room);
  OutPtr := @FBuf[FCount * FChannels];
  Got := MediaFile.Lib.Flat.swr_convert(FSwr, @OutPtr, Room, InData, InCount);
  if Got < 0 then
    raise EFFmpegError.CreateFmt('FFmpeg could not resample %s: %s', [MediaFile.FileName,
      MediaFile.Lib.ErrorText(Got)]);
  Inc(FCount, Got);
end;

function TFFmpegAudioDecoder.TakeFrame(AFrame: Pointer; ATime: Double): Boolean;
begin
  if ATime < 0 then
    ATime := FBufStart + FCount / FSampleRate;
  if (FEnd > 0) and (ATime >= FEnd) then
    Exit(False);
  if FSwr = nil then
  begin
    MediaFile.Check(MediaFile.Lib.Flat.swr_alloc_set_opts2(FSwr, @FOutLayout, AV_SAMPLE_FMT_FLT, FSampleRate,
      PAVChannelLayout(FFmpegAt(AFrame, FFOFS_FRAME_CH_LAYOUT)), FFmpegI32(AFrame, FFOFS_FRAME_FORMAT),
      FFmpegI32(AFrame, FFOFS_FRAME_SAMPLE_RATE), 0, nil), 'set up resampling for');
    MediaFile.Check(MediaFile.Lib.Flat.swr_init(FSwr), 'start resampling for');
  end;
  if not FHaveStart then
  begin
    FBufStart := ATime;
    FHaveStart := True;
  end;
  Convert(AFrame);
  Result := True;
end;

procedure TFFmpegAudioDecoder.EndOfStream;
begin
  if FSwr <> nil then
    Convert(nil);
end;

function TFFmpegAudioDecoder.Read(AStart: Double; AEnd: Double): TFFmpegSamples;
var
  First, Last: Int64;
begin
  Result := nil;
  if AStart < 0 then
    AStart := 0;
  FBuf := nil;
  FCount := 0;
  FBufStart := AStart;
  FHaveStart := False;
  FEnd := AEnd;
  // a fresh resampler per read: a read starts at a packet boundary
  if FSwr <> nil then
    MediaFile.Lib.Flat.swr_free(FSwr);
  try
    Run(AStart);
    // the decoder starts at a packet boundary at or before AStart: cut to
    // the range asked for
    First := Round((AStart - FBufStart) * FSampleRate);
    if First < 0 then
      First := 0;
    Last := FCount;
    if AEnd > 0 then
    begin
      Last := Round((AEnd - FBufStart) * FSampleRate);
      if Last > FCount then
        Last := FCount;
    end;
    if Last > First then
      Result := Copy(FBuf, Integer(First * FChannels), Integer((Last - First) * FChannels));
  finally
    FBuf := nil;
  end;
end;

end.
