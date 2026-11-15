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
  @longCode(#
  Player := TFFmpegAudioPlayer.Create(Lib);       // the platform's output
  Player.Open('book.m4b');
  Player.Play(125.0);                              // from 2:05
  ... a timer: Highlight(Book.ClipAt(Audio, Player.Position)) ...
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
    { Resamples AFrame (nil = flush) and hands the result to the sink. }
    procedure Deliver(AFrame: Pointer);
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
    function Stream(AStart: Double; ASink: TFFmpegSamplesSink): Boolean;
  end;

  TFFmpegAudioPlayer = class;

  { The player's feeding thread: one stream from a start time. }
  TFFmpegFeedThread = class(TThread)
  private
    { The player. }
    FPlayer: TFFmpegAudioPlayer;
    { Where to start, s. }
    FStart: Double;
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
    { A feed of APlayer's file from AStart seconds (started at once). }
    constructor Create(APlayer: TFFmpegAudioPlayer; AStart: Double);
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
    { Stops and frees the feed. }
    procedure StopFeed;
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
    { Pauses (the clock stops; the stream waits). }
    procedure Pause;
    { Resumes after Pause. }
    procedure Resume;
    { Stops playing; Position goes back to 0. }
    procedure Stop;
    { The time of the sound being heard now, s. }
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
  end;

implementation

uses
  Math;

const
  { Seconds of buffer in the platform's output. }
  OUTPUT_BUFFER_SECONDS = 2.0;

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
  if (Got > From) and Assigned(FSink) and not FStopped then
    if not FSink(@FBuf[From * FChannels], Got - From) then
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
  Deliver(AFrame);
  Result := not FStopped;
end;

procedure TFFmpegAudioStream.EndOfStream;
begin
  if (FSwr <> nil) and not FStopped then
    Deliver(nil);
end;

function TFFmpegAudioStream.Stream(AStart: Double; ASink: TFFmpegSamplesSink): Boolean;
begin
  if AStart < 0 then
    AStart := 0;
  FStart := AStart;
  FSink := ASink;
  FStopped := False;
  FHaveStart := False;
  FSkip := 0;
  if FSwr <> nil then
    MediaFile.Lib.Flat.swr_free(FSwr);   // a fresh resampler after a seek
  Result := Run(AStart) and not FStopped;
end;

{ TFFmpegFeedThread }

constructor TFFmpegFeedThread.Create(APlayer: TFFmpegAudioPlayer; AStart: Double);
begin
  FPlayer := APlayer;
  FStart := AStart;
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
        if S.Stream(FStart, Sink) then
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

procedure TFFmpegAudioPlayer.Play(AFrom: Double);
begin
  if FFileName = '' then
    raise EFFmpegError.Create('No file is open');
  StopFeed;
  FOutput.Pause;
  FOutput.Flush(Max(AFrom, 0));
  FFeed := TFFmpegFeedThread.Create(Self, Max(AFrom, 0));
  FOutput.Play;
  FPlaying := True;
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
  FPlaying := False;
end;

function TFFmpegAudioPlayer.Position: Double;
begin
  Result := FOutput.Clock;
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

end.
