(* @abstract(@link(TFFmpegAudioPlayer): plays an audio file - any format
  FFmpeg reads - on the platform's sound output, with a clock to time
  pictures or highlighted text by.)

  The file is STREAMED: @link(TFFmpegAudioStream) decodes it frame by frame
  from the playing position, resamples each frame to the output's rate and
  channels, and writes it into the output's ring buffer
  (FFmpeg.AudioOut), on a thread of its own. Nothing longer than a frame is
  held in memory, however long the file (a whole audiobook in one M4B is
  fine). @link(TFFmpegAudioPlayer.Position) is the output's clock: the time
  of the sound being heard now. A seek (@link(TFFmpegAudioPlayer.Play) with
  a time) stops the stream, flushes the output and streams again from
  there.

  @link(TFFmpegAudioPlayer.PlayRange) plays a stretch and stops exactly at
  its end (a word, for a reader that says one word at a time): the stream
  stops feeding the output there, so nothing of the next word is heard and
  @link(TFFmpegAudioPlayer.Ended) turns True when it has played out.
  @link(TFFmpegAudioPlayer.Speed) plays slower or faster without changing
  the pitch (FFmpeg's atempo filter, avfilter loaded on first use);
  Position stays the time IN THE FILE.
  @longCode(#
  Player := TFFmpegAudioPlayer.Create(Lib);       // the platform's output
  Player.Open('book.m4b');
  Player.Speed := 0.8;                             // slower, same pitch
  Player.Play(125.0);                              // from 2:05
  ... a timer: Highlight(Book.ClipAt(Audio, Player.Position)) ...
  Player.PlayRange(130.20, 130.55);                // one word, then silence
  #) *)
unit FFmpeg.Player;

{$I FFmpeg.inc}

interface

uses
  SysUtils, Classes,
  FFmpeg.API, FFmpeg.Media, FFmpeg.AudioOut;

type
  { Receives AFrames interleaved float frames at AData; False stops the
    stream. }
  TFFmpegSamplesSink = function(AData: PSingle; AFrames: Integer): Boolean of object;

  { Changes the tempo of interleaved float samples without changing their
    pitch: FFmpeg's atempo filter (abuffer -> atempo -> aformat ->
    abuffersink). Needs avfilter (TFFmpegLibrary.LoadFilters). }
  TFFmpegTempo = class
  private
    { The libraries. }
    FLib: TFFmpegLibrary;
    { The filter graph. }
    FGraph: Pointer;
    { Its buffer source. }
    FSrc: Pointer;
    { Its buffer sink. }
    FSink: Pointer;
    { Frame given to the source. }
    FIn: Pointer;
    { Frame taken from the sink. }
    FOut: Pointer;
    { Rate, Hz. }
    FRate: Integer;
    { Channels. }
    FChannels: Integer;
    { Time stamp of the next frame given, in samples. }
    FPts: Int64;
    { Takes every frame the sink has ready to ASink; False when ASink said
      stop. }
    function Drain(ASink: TFFmpegSamplesSink): Boolean;
  public
    { A tempo change of ATempo (0.5 .. 2: 0.8 = slower) for ARate Hz,
      AChannels channels of interleaved float.
      @raises(EFFmpegError when avfilter is not loaded or the graph cannot
        be made.) }
    constructor Create(ALib: TFFmpegLibrary; ARate, AChannels: Integer; ATempo: Double);
    { Frees the graph and frames. }
    destructor Destroy; override;
    { Gives AFrames frames at AData; what comes out goes to ASink. False
      when ASink said stop. }
    function Push(AData: PSingle; AFrames: Integer; ASink: TFFmpegSamplesSink): Boolean;
    { The end: what the filter still holds goes to ASink. }
    function Flush(ASink: TFFmpegSamplesSink): Boolean;
  end;

  { A decoder that streams: from a start time to the end of the file (or
    until the sink says stop), every frame resampled and handed to a sink
    at once. }
  TFFmpegAudioStream = class(TFFmpegDecoder)
  private
    { SwrContext (made from the first frame). }
    FSwr: Pointer;
    { Output layout. }
    FOutLayout: TAVChannelLayout;
    { Output rate. }
    FRate: Integer;
    { Output channels. }
    FChannels: Integer;
    { Resampled frames of the current input frame. }
    FBuf: array of Single;
    { Frames still to drop at the start (the seek lands before the start). }
    FSkip: Int64;
    { The start time asked for. }
    FStart: Double;
    { The first frame was seen. }
    FHaveStart: Boolean;
    { Where the samples go. }
    FSink: TFFmpegSamplesSink;
    { The sink said stop. }
    FStopped: Boolean;
    { Frames still to deliver before the range's end, -1 = no end. }
    FLeft: Int64;
    { The range's end was reached. }
    FRangeDone: Boolean;
    { The tempo change, nil at the normal speed (owned). }
    FTempo: TFFmpegTempo;
    { Resamples AFrame (nil = flush) and hands the result to the sink. }
    procedure Deliver(AFrame: Pointer);
    { Hands AFrames frames to the tempo change or the sink. }
    procedure Send(AData: PSingle; AFrames: Integer);
  protected
    { Resamples and delivers a frame; False when the sink stopped. }
    function TakeFrame(AFrame: Pointer; ATime: Double): Boolean; override;
    { Flushes the resampler into the sink. }
    procedure EndOfStream; override;
  public
    { A stream of audio stream AStream of AFile (-1 = the best), at ARate
      and AChannels. }
    constructor Create(AFile: TFFmpegMediaFile; AStream, ARate, AChannels: Integer);
    { Frees the resampler. }
    destructor Destroy; override;
    { Streams from AStart seconds to the end into ASink (on the calling
      thread). True when the end of the file was reached. }
    function Stream(AStart: Double; ASink: TFFmpegSamplesSink): Boolean; overload;
    { Streams from AStart to AEnd seconds (AEnd <= AStart = to the end of
      the file) at tempo ATempo (1 = as recorded; another value needs
      avfilter loaded). AEnd counts in the file: the sound handed out is
      (AEnd - AStart) / ATempo long. True when the range's end or the
      file's end was reached (not stopped by the sink). }
    function Stream(AStart, AEnd, ATempo: Double; ASink: TFFmpegSamplesSink): Boolean; overload;
  end;

  TFFmpegAudioPlayer = class;

  { The player's feeding thread: one stream from a start time. }
  TFFmpegFeedThread = class(TThread)
  private
    { The player. }
    FPlayer: TFFmpegAudioPlayer;
    { Where to start, s. }
    FStart: Double;
    { Where to stop, s (<= FStart: the end of the file). }
    FEnd: Double;
    { Tempo (1 = as recorded). }
    FTempo: Double;
    { What failed, '' if nothing. }
    FError: string;
    { Writes samples into the output (the stream's sink). }
    function Sink(AData: PSingle; AFrames: Integer): Boolean;
    { True when the thread should stop (the output's write wait asks). }
    function Cancelled: Boolean;
  protected
    { Opens the file, streams it into the output, marks the end. }
    procedure Execute; override;
  public
    { A feed of APlayer's file from AStart to AEnd seconds (AEnd <=
      AStart: to the end) at tempo ATempo, started at once. }
    constructor Create(APlayer: TFFmpegAudioPlayer; AStart, AEnd, ATempo: Double);
  end;

  { Plays one audio file at a time, streamed, with a clock. }
  TFFmpegAudioPlayer = class
  private
    { The libraries (not owned). }
    FLib: TFFmpegLibrary;
    { Backing field of @link(Output). }
    FOutput: TFFmpegAudioOutput;
    { FOutput is ours to free. }
    FOwnsOutput: Boolean;
    { Backing field of @link(OutputNote). }
    FOutputNote: string;
    { Backing field of @link(FileName). }
    FFileName: string;
    { Backing field of @link(Duration). }
    FDuration: Double;
    { The feed of the current play, nil when none. }
    FFeed: TFFmpegFeedThread;
    { Backing field of @link(Playing). }
    FPlaying: Boolean;
    { Backing field of @link(Speed). }
    FSpeed: Double;
    { File time the output's clock was set to by the last play. }
    FBase: Double;
    { End of the range being played, s (0 = none). }
    FRangeEnd: Double;
    { Stops and frees the feed. }
    procedure StopFeed;
    { Starts a feed from AFrom to AEnd (AEnd <= AFrom: to the end). }
    procedure StartFeed(AFrom, AEnd: Double);
    { Sets the speed (playing on from the same place). }
    procedure SetSpeed(AValue: Double);
  public
    { A player on ALib's FFmpeg. AOutput nil = the platform's output
      (TFFmpegAudioOutput.CreateDefault; @link(OutputNote) says when it
      fell back to silence); a given output is not owned. }
    constructor Create(ALib: TFFmpegLibrary; AOutput: TFFmpegAudioOutput = nil);
    { Stops and closes. }
    destructor Destroy; override;
    { Makes AFileName the file to play (reads its length; does not play).
      @raises(EFFmpegError when FFmpeg cannot open it or it is copy
        protected.) }
    procedure Open(const AFileName: string);
    { Plays from AFrom seconds (a seek: what was buffered is dropped). }
    procedure Play(AFrom: Double);
    { Plays from AFrom to ATo seconds and stops there exactly (ATo <=
      AFrom: to the end, as Play). @link(Ended) turns True once the range
      has played out. }
    procedure PlayRange(AFrom, ATo: Double);
    { Pauses (the clock stops; the stream waits). }
    procedure Pause;
    { Resumes after Pause. }
    procedure Resume;
    { Stops playing; Position goes back to 0. }
    procedure Stop;
    { The time IN THE FILE of the sound being heard now, s (at any
      speed). }
    function Position: Double;
    { True once the stream reached the end of the file and it has all been
      played. }
    function Ended: Boolean;
    { What failed in the stream, '' if nothing. }
    function LastError: string;
    { The libraries. }
    property Lib: TFFmpegLibrary read FLib;
    { The sound output. }
    property Output: TFFmpegAudioOutput read FOutput;
    { Why the output is silent ('' when the platform's output opened). }
    property OutputNote: string read FOutputNote;
    { The open file ('' when none). }
    property FileName: string read FFileName;
    { Its length, s. }
    property Duration: Double read FDuration;
    { Playing (not paused or stopped). }
    property Playing: Boolean read FPlaying;
    { Playing speed: 1 as recorded, 0.5 .. 2 (0.8 = slower), the pitch
      unchanged. Set while playing, it plays on from the same place (a
      range keeps its end). Another speed than 1 loads avfilter
      (TFFmpegLibrary.LoadFilters).
      @raises(EFFmpegError when avfilter cannot be loaded - the speed
        stays.) }
    property Speed: Double read FSpeed write SetSpeed;
  end;

implementation

uses
  Math;

const
  { Seconds of buffer in the platform's output. }
  OUTPUT_BUFFER_SECONDS = 2.0;
  { Slowest speed. }
  MIN_SPEED = 0.5;
  { Fastest speed. }
  MAX_SPEED = 2.0;

var
  { Number format with '.' (filter options), set once. }
  DotSettings: TFormatSettings;

{ The channel layout name of a channel count for a filter's options. }
function LayoutName(AChannels: Integer): string;
begin
  case AChannels of
    1: Result := 'mono';
    2: Result := 'stereo';
  else
    Result := IntToStr(AChannels) + 'c';
  end;
end;

{ TFFmpegTempo }

constructor TFFmpegTempo.Create(ALib: TFFmpegLibrary; ARate, AChannels: Integer; ATempo: Double);
var
  F: TFFmpegFlat;
  Tempo, Fmt: Pointer;

  { Checks a filter call. }
  procedure Check(ACode: Integer; const AWhat: string);
  begin
    if ACode < 0 then
      raise EFFmpegError.CreateFmt('FFmpeg could not %s for the speed change: %s', [AWhat,
        FLib.ErrorText(ACode)]);
  end;

  { Creates filter AName (instance AInst) with AArgs. }
  function Make(const AName, AInst, AArgs: string): Pointer;
  var
    Filt: Pointer;
    A: UTF8String;
  begin
    Filt := F.avfilter_get_by_name(PAnsiChar(UTF8String(AName)));
    if Filt = nil then
      raise EFFmpegError.CreateFmt('This FFmpeg has no %s filter', [AName]);
    Result := nil;
    A := UTF8String(AArgs);
    if AArgs = '' then
      Check(F.avfilter_graph_create_filter(Result, Filt, PAnsiChar(UTF8String(AInst)), nil, nil, FGraph),
        'create ' + AName)
    else
      Check(F.avfilter_graph_create_filter(Result, Filt, PAnsiChar(UTF8String(AInst)), PAnsiChar(A), nil,
        FGraph), 'create ' + AName);
  end;

begin
  inherited Create;
  FLib := ALib;
  FRate := ARate;
  FChannels := AChannels;
  if not FLib.HasFilters then
    raise EFFmpegError.Create('The speed change needs FFmpeg''s avfilter (TFFmpegLibrary.LoadFilters)');
  F := FLib.Flat;
  FGraph := F.avfilter_graph_alloc;
  if FGraph = nil then
    raise EFFmpegError.Create('FFmpeg could not make a filter graph');
  FSrc := Make('abuffer', 'in', Format('time_base=1/%d:sample_rate=%d:sample_fmt=flt:channel_layout=%s',
    [ARate, ARate, LayoutName(AChannels)]));
  Tempo := Make('atempo', 'tempo', 'tempo=' + FormatFloat('0.0###', ATempo, DotSettings));
  // the output exactly as the output device takes it
  Fmt := Make('aformat', 'format', Format('sample_fmts=flt:sample_rates=%d:channel_layouts=%s',
    [ARate, LayoutName(AChannels)]));
  FSink := Make('abuffersink', 'out', '');
  Check(F.avfilter_link(FSrc, 0, Tempo, 0), 'link');
  Check(F.avfilter_link(Tempo, 0, Fmt, 0), 'link');
  Check(F.avfilter_link(Fmt, 0, FSink, 0), 'link');
  Check(F.avfilter_graph_config(FGraph, nil), 'configure the filters');
  FIn := F.av_frame_alloc;
  FOut := F.av_frame_alloc;
end;

destructor TFFmpegTempo.Destroy;
begin
  if FLib <> nil then
  begin
    if FIn <> nil then
      FLib.Flat.av_frame_free(FIn);
    if FOut <> nil then
      FLib.Flat.av_frame_free(FOut);
    if FGraph <> nil then
      FLib.Flat.avfilter_graph_free(FGraph);
  end;
  inherited;
end;

function TFFmpegTempo.Drain(ASink: TFFmpegSamplesSink): Boolean;
var
  R, N: Integer;
begin
  Result := True;
  repeat
    R := FLib.Flat.av_buffersink_get_frame(FSink, FOut);
    if R < 0 then
      Break;   // EAGAIN (more input needed) or EOF
    N := FFmpegI32(FOut, FFOFS_FRAME_NB_SAMPLES);
    if (N > 0) and Result then
      Result := ASink(PSingle(FFmpegPtr(FOut, FFOFS_FRAME_DATA)), N);
    FLib.Flat.av_frame_unref(FOut);
  until not Result;
end;

function TFFmpegTempo.Push(AData: PSingle; AFrames: Integer; ASink: TFFmpegSamplesSink): Boolean;
var
  F: TFFmpegFlat;
begin
  if AFrames <= 0 then
    Exit(True);
  F := FLib.Flat;
  // a frame of ours: format, size, layout, time stamp, then its buffer
  PInteger(FFmpegAt(FIn, FFOFS_FRAME_NB_SAMPLES))^ := AFrames;
  PInteger(FFmpegAt(FIn, FFOFS_FRAME_FORMAT))^ := AV_SAMPLE_FMT_FLT;
  PInteger(FFmpegAt(FIn, FFOFS_FRAME_SAMPLE_RATE))^ := FRate;
  PInt64(FFmpegAt(FIn, FFOFS_FRAME_PTS))^ := FPts;
  F.av_channel_layout_default(PAVChannelLayout(FFmpegAt(FIn, FFOFS_FRAME_CH_LAYOUT)), FChannels);
  if F.av_frame_get_buffer(FIn, 0) < 0 then
    raise EFFmpegError.Create('FFmpeg could not allocate a frame for the speed change');
  Move(AData^, FFmpegPtr(FIn, FFOFS_FRAME_DATA)^, AFrames * FChannels * SizeOf(Single));
  Inc(FPts, AFrames);
  // flags 0: the source takes the data and resets the frame
  if F.av_buffersrc_add_frame_flags(FSrc, FIn, 0) < 0 then
  begin
    F.av_frame_unref(FIn);
    raise EFFmpegError.Create('FFmpeg''s speed change refused a frame');
  end;
  Result := Drain(ASink);
end;

function TFFmpegTempo.Flush(ASink: TFFmpegSamplesSink): Boolean;
begin
  FLib.Flat.av_buffersrc_add_frame_flags(FSrc, nil, 0);   // the end
  Result := Drain(ASink);
end;

{ TFFmpegAudioStream }

constructor TFFmpegAudioStream.Create(AFile: TFFmpegMediaFile; AStream, ARate, AChannels: Integer);
begin
  if AStream < 0 then
    AStream := AFile.BestStream(fmkAudio);
  if AStream < 0 then
    raise EFFmpegError.CreateFmt('%s has no audio', [AFile.FileName]);
  inherited Create(AFile, AStream);
  FRate := ARate;
  FChannels := AChannels;
  FillChar(FOutLayout, SizeOf(FOutLayout), 0);
  AFile.Lib.Flat.av_channel_layout_default(@FOutLayout, FChannels);
end;

destructor TFFmpegAudioStream.Destroy;
begin
  FreeAndNil(FTempo);
  if MediaFile <> nil then
  begin
    if FSwr <> nil then
      MediaFile.Lib.Flat.swr_free(FSwr);
    MediaFile.Lib.Flat.av_channel_layout_uninit(@FOutLayout);
  end;
  inherited;
end;

procedure TFFmpegAudioStream.Deliver(AFrame: Pointer);
var
  Room, Got, InCount, From: Integer;
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
  if Room * FChannels > Length(FBuf) then
    SetLength(FBuf, Room * FChannels);
  OutPtr := @FBuf[0];
  Got := MediaFile.Lib.Flat.swr_convert(FSwr, @OutPtr, Room, InData, InCount);
  if Got < 0 then
    raise EFFmpegError.CreateFmt('FFmpeg could not resample %s: %s', [MediaFile.FileName,
      MediaFile.Lib.ErrorText(Got)]);
  // the seek lands on a packet at or before the start: drop the frames
  // before it
  From := 0;
  if FSkip > 0 then
  begin
    From := Min(Got, FSkip);
    Dec(FSkip, From);
  end;
  Got := Got - From;
  // the range's end: nothing after it is handed out
  if (FLeft >= 0) and (Got > FLeft) then
    Got := FLeft;
  if FLeft >= 0 then
  begin
    Dec(FLeft, Got);
    if FLeft = 0 then
      FRangeDone := True;
  end;
  if Got > 0 then
    Send(@FBuf[From * FChannels], Got);
end;

procedure TFFmpegAudioStream.Send(AData: PSingle; AFrames: Integer);
begin
  if FStopped or not Assigned(FSink) then
    Exit;
  if FTempo <> nil then
  begin
    if not FTempo.Push(AData, AFrames, FSink) then
      FStopped := True;
  end
  else if not FSink(AData, AFrames) then
    FStopped := True;
end;

function TFFmpegAudioStream.TakeFrame(AFrame: Pointer; ATime: Double): Boolean;
begin
  if FSwr = nil then
  begin
    MediaFile.Check(MediaFile.Lib.Flat.swr_alloc_set_opts2(FSwr, @FOutLayout, AV_SAMPLE_FMT_FLT, FRate,
      PAVChannelLayout(FFmpegAt(AFrame, FFOFS_FRAME_CH_LAYOUT)), FFmpegI32(AFrame, FFOFS_FRAME_FORMAT),
      FFmpegI32(AFrame, FFOFS_FRAME_SAMPLE_RATE), 0, nil), 'set up resampling for');
    MediaFile.Check(MediaFile.Lib.Flat.swr_init(FSwr), 'start resampling for');
  end;
  if not FHaveStart then
  begin
    FHaveStart := True;
    if (ATime >= 0) and (ATime < FStart) then
      FSkip := Round((FStart - ATime) * FRate);
  end;
  if FRangeDone then
    Exit(False);   // nothing more is needed: decoding stops
  Deliver(AFrame);
  Result := not FStopped and not FRangeDone;
end;

procedure TFFmpegAudioStream.EndOfStream;
begin
  if (FSwr <> nil) and not FStopped and not FRangeDone then
    Deliver(nil);
end;

function TFFmpegAudioStream.Stream(AStart: Double; ASink: TFFmpegSamplesSink): Boolean;
begin
  Result := Stream(AStart, 0, 1, ASink);
end;

function TFFmpegAudioStream.Stream(AStart, AEnd, ATempo: Double; ASink: TFFmpegSamplesSink): Boolean;
var
  Ended: Boolean;
begin
  if AStart < 0 then
    AStart := 0;
  FStart := AStart;
  FSink := ASink;
  FStopped := False;
  FHaveStart := False;
  FSkip := 0;
  FRangeDone := False;
  if AEnd > AStart then
    FLeft := Round((AEnd - AStart) * FRate)
  else
    FLeft := -1;
  FreeAndNil(FTempo);
  if Abs(ATempo - 1) > 0.001 then
    FTempo := TFFmpegTempo.Create(MediaFile.Lib, FRate, FChannels, ATempo);
  if FSwr <> nil then
    MediaFile.Lib.Flat.swr_free(FSwr);   // a fresh resampler after a seek
  Ended := Run(AStart) or FRangeDone;
  // what the tempo change still holds
  if Ended and not FStopped and (FTempo <> nil) then
    if not FTempo.Flush(FSink) then
      FStopped := True;
  Result := Ended and not FStopped;
end;

{ TFFmpegFeedThread }

constructor TFFmpegFeedThread.Create(APlayer: TFFmpegAudioPlayer; AStart, AEnd, ATempo: Double);
begin
  FPlayer := APlayer;
  FStart := AStart;
  FEnd := AEnd;
  FTempo := ATempo;
  FreeOnTerminate := False;
  inherited Create(False);
end;

function TFFmpegFeedThread.Cancelled: Boolean;
begin
  Result := Terminated;
end;

function TFFmpegFeedThread.Sink(AData: PSingle; AFrames: Integer): Boolean;
begin
  Result := FPlayer.FOutput.Write(AData, AFrames, Cancelled) and not Terminated;
end;

procedure TFFmpegFeedThread.Execute;
var
  F: TFFmpegMediaFile;
  S: TFFmpegAudioStream;
begin
  try
    F := TFFmpegMediaFile.Create(FPlayer.FLib, FPlayer.FFileName);
    try
      S := TFFmpegAudioStream.Create(F, -1, FPlayer.FOutput.SampleRate, FPlayer.FOutput.Channels);
      try
        if S.Stream(FStart, FEnd, FTempo, Sink) then
          FPlayer.FOutput.MarkEnd;
      finally
        S.Free;
      end;
    finally
      F.Free;
    end;
  except
    on E: Exception do
    begin
      FError := E.Message;
      FPlayer.FOutput.MarkEnd;   // let what was written play out
    end;
  end;
end;

{ TFFmpegAudioPlayer }

constructor TFFmpegAudioPlayer.Create(ALib: TFFmpegLibrary; AOutput: TFFmpegAudioOutput);
begin
  inherited Create;
  FLib := ALib;
  FSpeed := 1;
  if AOutput <> nil then
    FOutput := AOutput
  else
  begin
    FOutput := TFFmpegAudioOutput.CreateDefault(FOutputNote, OUTPUT_BUFFER_SECONDS);
    FOwnsOutput := True;
  end;
end;

destructor TFFmpegAudioPlayer.Destroy;
begin
  StopFeed;
  if FOwnsOutput then
    FOutput.Free;
  inherited;
end;

procedure TFFmpegAudioPlayer.StopFeed;
begin
  if FFeed <> nil then
  begin
    FFeed.Terminate;
    FFeed.WaitFor;
    FreeAndNil(FFeed);
  end;
end;

procedure TFFmpegAudioPlayer.Open(const AFileName: string);
var
  F: TFFmpegMediaFile;
begin
  Stop;
  F := TFFmpegMediaFile.Create(FLib, AFileName);
  try
    if F.BestStream(fmkAudio) < 0 then
      raise EFFmpegError.CreateFmt('%s has no audio', [AFileName]);
    FDuration := F.Duration;
  finally
    F.Free;
  end;
  FFileName := AFileName;
end;

procedure TFFmpegAudioPlayer.StartFeed(AFrom, AEnd: Double);
begin
  if FFileName = '' then
    raise EFFmpegError.Create('No file is open');
  StopFeed;
  FOutput.Pause;
  AFrom := Max(AFrom, 0);
  // the output's clock counts the sound played; at another speed the file
  // time is FBase + (clock - FBase) * speed (Position)
  FOutput.Flush(AFrom);
  FBase := AFrom;
  if AEnd > AFrom then
    FRangeEnd := AEnd
  else
    FRangeEnd := 0;
  FFeed := TFFmpegFeedThread.Create(Self, AFrom, AEnd, FSpeed);
  FOutput.Play;
  FPlaying := True;
end;

procedure TFFmpegAudioPlayer.Play(AFrom: Double);
begin
  StartFeed(AFrom, 0);
end;

procedure TFFmpegAudioPlayer.PlayRange(AFrom, ATo: Double);
begin
  StartFeed(AFrom, ATo);
end;

procedure TFFmpegAudioPlayer.SetSpeed(AValue: Double);
var
  P: Double;
  WasPlaying: Boolean;
begin
  AValue := EnsureRange(AValue, MIN_SPEED, MAX_SPEED);
  if SameValue(AValue, FSpeed, 0.001) then
    Exit;
  if (Abs(AValue - 1) > 0.001) and not FLib.LoadFilters then
    raise EFFmpegError.Create(FLib.FiltersNote);
  P := Position;
  FSpeed := AValue;
  if FFeed = nil then
    Exit;
  // the feed runs at the old speed: start again from the same place
  WasPlaying := FPlaying;
  if (FRangeEnd > 0) and (P < FRangeEnd) then
    StartFeed(P, FRangeEnd)
  else if FRangeEnd = 0 then
    StartFeed(P, 0)
  else
    Exit;   // a range already played out
  if not WasPlaying then
    Pause;
end;

procedure TFFmpegAudioPlayer.Pause;
begin
  FOutput.Pause;
  FPlaying := False;
end;

procedure TFFmpegAudioPlayer.Resume;
begin
  if FFeed = nil then
    Exit;
  FOutput.Play;
  FPlaying := True;
end;

procedure TFFmpegAudioPlayer.Stop;
begin
  StopFeed;
  FOutput.Pause;
  FOutput.Flush(0);
  FBase := 0;
  FRangeEnd := 0;
  FPlaying := False;
end;

function TFFmpegAudioPlayer.Position: Double;
begin
  Result := FBase + (FOutput.Clock - FBase) * FSpeed;
end;

function TFFmpegAudioPlayer.Ended: Boolean;
begin
  Result := (FFeed <> nil) and FOutput.Drained;
end;

function TFFmpegAudioPlayer.LastError: string;
begin
  Result := '';
  if FFeed <> nil then
    Result := FFeed.FError;
  if Result = '' then
    Result := FOutput.LastError;
end;

initialization
  DotSettings := FormatSettings;
  DotSettings.DecimalSeparator := '.';

end.
