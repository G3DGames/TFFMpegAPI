(* @abstract(Sound output with a clock: a ring buffer of float samples fed
  by a decoder, played on the platform's default output device, and the
  time of the sound being heard now.)

  @link(TFFmpegAudioOutput) is the platform-independent part - the ring
  buffer, the clock, play / pause, flush for a seek - and runs a thread of
  its own that owns the device. A descendant per platform opens the device
  and feeds it:
  @unorderedList(
    @item(@link(TFFmpegWasapiOutput) - Windows, WASAPI shared mode, 32-bit
      float at the device's own rate and channels, event driven (adapted
      from Lenticular.AudioOutput in SRDelphiFMX's MoviePlayerFMX). Delphi.)
    @item(@link(TFFmpegPulseOutput) - Linux (SteamOS's PipeWire included),
      PulseAudio's simple API, libpulse-simple.so.0 loaded at run time.)
    @item(@link(TFFmpegAudioQueueOutput) - macOS, AudioToolbox's AudioQueue
      on the default output device, AudioToolbox loaded at run time.)
    @item(@link(TFFmpegNullOutput) - every platform: no sound, the clock
      runs on a timer. The fallback when no device opens, so a reader still
      follows the text; also for tests.)
  )
  @link(TFFmpegAudioOutput.CreateDefault) picks the platform's output and
  falls back to the null one, saying why. Android follows later.

  @link(TFFmpegAudioOutput.Clock) is the time (on the source's time line,
  see @link(TFFmpegAudioOutput.Flush)) of the sound the listener hears now:
  what has really reached the device, less what still waits in it, smoothed
  between the device's reports - what pictures or highlighted words are
  timed by. *)
unit FFmpeg.AudioOut;

{$I FFmpeg.inc}

interface

uses
  SysUtils, Classes, SyncObjs,
  FFmpeg.DynLib;

type
  { Called while a write waits for room; True stops the wait. }
  TFFmpegCancelFunc = function: Boolean of object;

  TFFmpegAudioOutput = class;

  { The thread that owns the device of one @link(TFFmpegAudioOutput). }
  TFFmpegAudioThread = class(TThread)
  private
    { The output it works for (outlives the thread). }
    FOwner: TFFmpegAudioOutput;
  protected
    { Opens the device, reports whether that worked, then feeds it until
      Terminate. }
    procedure Execute; override;
  public
    { Creates the thread, running. }
    constructor Create(AOwner: TFFmpegAudioOutput);
    { Terminate was called (for the backends' loops). }
    function IsTerminated: Boolean;
  end;

  { Sound playing on an output device, fed from a ring buffer. }
  TFFmpegAudioOutput = class
  private
    { The output thread. }
    FThread: TFFmpegAudioThread;
    { Set by the thread once the device is open (or failed to open). }
    FReady: TEvent;
    { Set when the ring buffer has room. }
    FSpace: TEvent;
    { Why the device could not be opened, '' if it was. }
    FOpenError: string;
    { The ring buffer: FRingFrames frames of FChannels floats. }
    FRing: array of Single;
    { Frames the ring holds at most. }
    FRingFrames: Integer;
    { Where the next frame is read from. }
    FReadPos: Integer;
    { Frames waiting in the ring. }
    FFill: Integer;
    { Source time of the first frame written since the last flush, s. }
    FStartTime: Double;
    { Real frames handed to the device since the last flush. }
    FRealWritten: Int64;
    { Real frames the device had played at its last report. }
    FPlayed: Int64;
    { When FPlayed was last updated (seconds of a monotonic clock). }
    FPlayedAt: Double;
    { The device is playing. }
    FPlaying: Boolean;
    { Playing has been asked for. }
    FWantPlay: Boolean;
    { A flush was asked for: the backend drops what the device holds. }
    FResetWanted: Boolean;
    { The writer has written its last frame. }
    FEnded: Boolean;
    { Every written frame has been played. }
    FDrained: Boolean;
    { Times the device ran short. }
    FUnderruns: Int64;
    { The thread's first error while playing. }
    FError: string;
    { Seconds of buffer asked for. }
    FBufferSeconds: Double;
  protected
    { Guards the ring buffer and the clock (backends lock it to take frames
      and report). }
    FLock: TCriticalSection;
    { Backing field of @link(SampleRate); the backend sets it in Open. }
    FRate: Integer;
    { Backing field of @link(Channels); the backend sets it in Open. }
    FChannels: Integer;
    { Backing field of @link(Description); the backend sets it in Open. }
    FDescription: string;
    { Opens the device on the output thread: sets FRate, FChannels and
      FDescription; raises with a message when it cannot. }
    procedure BackendOpen; virtual; abstract;
    { Feeds the device until AThread is terminated (on the output thread). }
    procedure BackendRun(AThread: TFFmpegAudioThread); virtual; abstract;
    { Closes the device (on the output thread; also after a failed open). }
    procedure BackendClose; virtual; abstract;
    { Copies up to AFrames frames from the ring to ADst (lock held by the
      caller); returns how many. Counts an underrun when short and not
      ended. }
    function TakeFrames(ADst: PSingle; AFrames: Integer): Integer;
    { Records that APlayed real frames have been played (lock held). }
    procedure ReportPlayed(APlayed: Int64);
    { Records the first error while playing. }
    procedure SetError(const AText: string);
    { Signals that the ring has room (after taking frames). }
    procedure SignalSpace;
    { True when playing is asked for (lock held). }
    property WantPlay: Boolean read FWantPlay;
    { True once when a flush was asked for since the last call (lock held). }
    function TakeResetRequest: Boolean;
    { Sets whether the device is playing (lock held). }
    procedure SetPlaying(AValue: Boolean);
    { Marks everything written as played (lock held; the backend found the
      ring empty after the end and its device empty). }
    procedure SetDrained;
    { The writer has marked the end (lock held). }
    function EndedLocked: Boolean;
    { Frames waiting in the ring (lock held). }
    function FillLocked: Integer;
    { Real frames handed over since the last flush (lock held). }
    function RealWrittenLocked: Int64;
  public
    { Opens the device and starts the output thread, paused, with a ring
      buffer of ABufferSeconds.
      @raises(EFFmpegDynLibError or Exception saying what failed when the
        device cannot be opened.) }
    constructor Create(ABufferSeconds: Double = 2.0); virtual;
    { Stops playing and closes the device. }
    destructor Destroy; override;
    { The platform's output (WASAPI on Windows, PulseAudio on Linux,
      AudioQueue on macOS), or a
      @link(TFFmpegNullOutput) when it cannot be opened - ANote then says
      why ('' when the platform's output opened). }
    class function CreateDefault(out ANote: string; ABufferSeconds: Double = 2.0): TFFmpegAudioOutput;
    { Drops everything buffered (here and, on the device's next turn, in
      the device), and starts the clock again at ASourceTime: the time of
      the next frame written. For a seek. }
    procedure Flush(ASourceTime: Double);
    { Copies AFrames interleaved float frames (Channels floats each) into
      the ring buffer, waiting while it is full.
      @returns(False when ACancel stopped the wait before everything was
        written.) }
    function Write(ASrc: PSingle; AFrames: Integer; ACancel: TFFmpegCancelFunc): Boolean;
    { Marks the end of the sound: what is buffered still plays. }
    procedure MarkEnd;
    { Starts or resumes playing. }
    procedure Play;
    { Pauses; the clock stops. }
    procedure Pause;
    { Source time of the sound being heard now, s. }
    function Clock: Double;
    { Seconds of sound waiting in the ring buffer. }
    function Buffered: Double;
    { True once the end was marked and every frame played. }
    function Drained: Boolean;
    { Times the device ran short of sound once it had started (the wait for
      the first sound after opening or a seek is not counted). }
    function Underruns: Int64;
    { The output thread's first error while playing, '' if none. }
    function LastError: string;
    { The device's sample rate, frames a second. }
    property SampleRate: Integer read FRate;
    { The device's channels; a frame is this many floats. }
    property Channels: Integer read FChannels;
    { One line about the device for a log. }
    property Description: string read FDescription;
  end;
  { An output class (for CreateDefault's choice). }
  TFFmpegAudioOutputClass = class of TFFmpegAudioOutput;

  { No sound: the clock runs on a timer at 48 kHz stereo. }
  TFFmpegNullOutput = class(TFFmpegAudioOutput)
  protected
    { 48 kHz, 2 channels. }
    procedure BackendOpen; override;
    { Takes frames from the ring at real-time speed while playing. }
    procedure BackendRun(AThread: TFFmpegAudioThread); override;
    { Nothing to close. }
    procedure BackendClose; override;
  end;

{$ifdef FFMPEG_LINUX}
  { PulseAudio's pa_sample_spec. }
  TPaSampleSpec = record
    { pa_sample_format_t (PA_SAMPLE_FLOAT32LE = 5). }
    format: Int32;
    { Frames a second. }
    rate: UInt32;
    { Channels. }
    channels: Byte;
  end;
  { PulseAudio's pa_buffer_attr ($FFFFFFFF = the server's default). }
  TPaBufferAttr = record
    { Most bytes the server buffers. }
    maxlength: UInt32;
    { Target length of the playback buffer, bytes. }
    tlength: UInt32;
    { Bytes before playback starts. }
    prebuf: UInt32;
    { Least bytes the server asks for. }
    minreq: UInt32;
    { Recording fragment (unused). }
    fragsize: UInt32;
  end;

  { Linux: PulseAudio's simple API (PipeWire's pulse server included). }
  TFFmpegPulseOutput = class(TFFmpegAudioOutput)
  private
    { libpulse-simple. }
    FLib: TFFmpegDynLib;
    { The pa_simple stream. }
    FStream: Pointer;
    { pa_simple_new. }
    FNew: function(server, name: PAnsiChar; dir: Int32; dev, stream_name: PAnsiChar;
      const ss: Pointer; const map: Pointer; const attr: Pointer; error: PInteger): Pointer; cdecl;
    { pa_simple_write. }
    FWrite: function(s: Pointer; data: Pointer; bytes: NativeUInt; error: PInteger): Int32; cdecl;
    { pa_simple_get_latency. }
    FLatency: function(s: Pointer; error: PInteger): UInt64; cdecl;
    { pa_simple_flush. }
    FFlush: function(s: Pointer; error: PInteger): Int32; cdecl;
    { pa_simple_free. }
    FFree: procedure(s: Pointer); cdecl;
  protected
    { Connects to the sound server: 48 kHz stereo float, 100 ms buffer. }
    procedure BackendOpen; override;
    { Writes 10 ms pieces while playing; reports the played frames from
      the server's latency. }
    procedure BackendRun(AThread: TFFmpegAudioThread); override;
    { Frees the stream and the library. }
    procedure BackendClose; override;
  end;
{$endif}

{$ifdef FFMPEG_MACOS}
  { AudioToolbox's AudioStreamBasicDescription. }
  TAqStreamDescription = record
    { Frames a second. }
    mSampleRate: Double;
    { kAudioFormatLinearPCM ('lpcm'). }
    mFormatID: UInt32;
    { kAudioFormatFlagIsFloat or kAudioFormatFlagIsPacked. }
    mFormatFlags: UInt32;
    { Bytes a packet (= a frame for PCM). }
    mBytesPerPacket: UInt32;
    { Frames a packet (1 for PCM). }
    mFramesPerPacket: UInt32;
    { Bytes a frame. }
    mBytesPerFrame: UInt32;
    { Channels. }
    mChannelsPerFrame: UInt32;
    { Bits a sample. }
    mBitsPerChannel: UInt32;
    { Must be 0. }
    mReserved: UInt32;
  end;

  { AudioToolbox's AudioQueueBuffer, 64-bit layout (the padding written
    out, so the record has it whatever the alignment setting). }
  TAqBuffer = record
    { Bytes the buffer holds at most. }
    mAudioDataBytesCapacity: UInt32;
    { Padding before the pointer. }
    Pad1: UInt32;
    { The sound. }
    mAudioData: Pointer;
    { Bytes of sound in it. }
    mAudioDataByteSize: UInt32;
    { Padding before the pointer. }
    Pad2: UInt32;
    { Ours: the buffer's index. }
    mUserData: Pointer;
    { Packet descriptions it holds at most (0 for PCM). }
    mPacketDescriptionCapacity: UInt32;
    { Padding before the pointer. }
    Pad3: UInt32;
    { Packet descriptions (unused for PCM). }
    mPacketDescriptions: Pointer;
    { Packet descriptions in use. }
    mPacketDescriptionCount: UInt32;
  end;
  { A pointer to a TAqBuffer (AudioQueueBufferRef). }
  PAqBuffer = ^TAqBuffer;

  { macOS: AudioToolbox's AudioQueue on the default output device, 48 kHz
    stereo 32-bit float (the queue converts to the device's rate), a few
    short buffers filled from the ring. The clock counts the real frames of
    the buffers the queue has played (its callbacks). }
  TFFmpegAudioQueueOutput = class(TFFmpegAudioOutput)
  private
    { AudioToolbox. }
    FLib: TFFmpegDynLib;
    { The AudioQueue (AudioQueueRef). }
    FQueue: Pointer;
    { The queue's buffers. }
    FBuffers: array of PAqBuffer;
    { Each buffer is with the queue (guarded by FLock). }
    FBusy: array of Boolean;
    { Real frames in each buffer (the rest is silence). }
    FReal: array of Integer;
    { The generation each buffer was filled in (a seek starts a new one:
      buffers of an older one are not counted as played). }
    FGen: array of Integer;
    { The current generation. }
    FCurGen: Integer;
    { Real frames of the current generation the queue has played. }
    FPlayedReal: Int64;
    { Buffers with the queue. }
    FInFlight: Integer;
    { Frames a buffer holds. }
    FBufferFrames: Integer;
    { Set by the callback: a buffer came back. }
    FWake: TEvent;
    { AudioQueueNewOutput. }
    FNewOutput: function(inFormat, inCallbackProc, inUserData, inCallbackRunLoop, inCallbackRunLoopMode: Pointer;
      inFlags: UInt32; outAQ: PPointer): Int32; cdecl;
    { AudioQueueAllocateBuffer. }
    FAllocateBuffer: function(inAQ: Pointer; inBufferByteSize: UInt32; outBuffer: Pointer): Int32; cdecl;
    { AudioQueueEnqueueBuffer. }
    FEnqueueBuffer: function(inAQ: Pointer; inBuffer: PAqBuffer; inNumPacketDescs: UInt32;
      inPacketDescs: Pointer): Int32; cdecl;
    { AudioQueueStart. }
    FStart: function(inAQ: Pointer; inStartTime: Pointer): Int32; cdecl;
    { AudioQueuePause. }
    FPause: function(inAQ: Pointer): Int32; cdecl;
    { AudioQueueStop. }
    FStop: function(inAQ: Pointer; inImmediate: Byte): Int32; cdecl;
    { AudioQueueReset. }
    FReset: function(inAQ: Pointer): Int32; cdecl;
    { AudioQueueDispose. }
    FDispose: function(inAQ: Pointer; inImmediate: Byte): Int32; cdecl;
    { The queue gave ABuffer back (on the queue's own thread): free it,
      count its real frames as played when it is of this generation. }
    procedure BufferDone(ABuffer: PAqBuffer);
  protected
    { Makes the queue and its buffers: 48 kHz stereo float. }
    procedure BackendOpen; override;
    { Fills the free buffers while playing, starts and pauses the queue,
      drops what it holds on a seek. }
    procedure BackendRun(AThread: TFFmpegAudioThread); override;
    { Stops and disposes of the queue, unloads AudioToolbox. }
    procedure BackendClose; override;
  end;
{$endif}

{$if defined(FFMPEG_WINDOWS) and not defined(FPC)}
  { Windows: WASAPI shared mode at the device's mix rate and channels, as
    32-bit float, event driven (adapted from Lenticular.AudioOutput). }
  TFFmpegWasapiOutput = class(TFFmpegAudioOutput)
  private
    { IMMDeviceEnumerator. }
    FEnum: IUnknown;
    { IMMDevice. }
    FDevice: IUnknown;
    { IAudioClient. }
    FClient: IUnknown;
    { IAudioRenderClient. }
    FRender: IUnknown;
    { The device's event. }
    FWake: THandle;
    { The device buffer's size, frames. }
    FBufferFrames: Cardinal;
    { COM was initialised on the output thread. }
    FComInit: Boolean;
  protected
    { Opens the default output device. }
    procedure BackendOpen; override;
    { Feeds the device as it asks. }
    procedure BackendRun(AThread: TFFmpegAudioThread); override;
    { Stops and releases the device. }
    procedure BackendClose; override;
  end;
{$ifend}

{ Seconds of a monotonic clock (for smoothing between device reports). }
function FFmpegMonotonicSeconds: Double;

implementation

// Winapi.Windows declares a PSingle of its own: the implementation writes
// System.PSingle, the type the interface was declared with
uses
  {$if defined(FFMPEG_WINDOWS) and not defined(FPC)}Winapi.Windows, Winapi.ActiveX, Winapi.MMSystem,{$ifend}
  {$ifndef FPC}System.Diagnostics,{$endif}
  Math;

const
  { How long a write waits for room before asking whether to stop, ms. }
  WAIT_MS = 20;
  { The null output's and PulseAudio's rate and channels. }
  FIXED_RATE = 48000;
  { The null output's and PulseAudio's channel count. }
  FIXED_CHANNELS = 2;
  { How long the device has to open, ms. }
  OPEN_TIMEOUT_MS = 5000;

function FFmpegMonotonicSeconds: Double;
begin
  {$ifdef FPC}
  Result := GetTickCount64 / 1000;
  {$else}
  Result := TStopwatch.GetTimeStamp / TStopwatch.Frequency;
  {$endif}
end;

{ TFFmpegAudioThread }

constructor TFFmpegAudioThread.Create(AOwner: TFFmpegAudioOutput);
begin
  FOwner := AOwner;
  inherited Create(False);
end;

function TFFmpegAudioThread.IsTerminated: Boolean;
begin
  Result := Terminated;
end;

procedure TFFmpegAudioThread.Execute;
begin
  try
    try
      FOwner.BackendOpen;
    except
      on E: Exception do
      begin
        FOwner.FOpenError := E.Message;
        FOwner.FReady.SetEvent;
        Exit;
      end;
    end;
    FOwner.FReady.SetEvent;
    try
      FOwner.BackendRun(Self);
    except
      on E: Exception do
        FOwner.SetError(E.Message);
    end;
  finally
    try
      FOwner.BackendClose;
    except
      // closing a broken device: nothing more to do
    end;
  end;
end;

{ TFFmpegAudioOutput }

constructor TFFmpegAudioOutput.Create(ABufferSeconds: Double);
begin
  inherited Create;
  FBufferSeconds := ABufferSeconds;
  FLock := TCriticalSection.Create;
  FReady := TEvent.Create(nil, True, False, '');
  FSpace := TEvent.Create(nil, False, False, '');
  FThread := TFFmpegAudioThread.Create(Self);
  if FReady.WaitFor(OPEN_TIMEOUT_MS) <> wrSignaled then
    raise Exception.Create('Sound output: the device did not open within 5 s');
  if FOpenError <> '' then
    raise Exception.Create(FOpenError);
  FRingFrames := Max(FRate div 10, Round(FRate * ABufferSeconds));
  SetLength(FRing, FRingFrames * FChannels);
end;

destructor TFFmpegAudioOutput.Destroy;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FSpace.Free;
  FReady.Free;
  FLock.Free;
  inherited;
end;

class function TFFmpegAudioOutput.CreateDefault(out ANote: string; ABufferSeconds: Double): TFFmpegAudioOutput;
var
  Cls: TFFmpegAudioOutputClass;
begin
  ANote := '';
  Cls := nil;
  {$if defined(FFMPEG_WINDOWS) and not defined(FPC)}
  Cls := TFFmpegWasapiOutput;
  {$elseif defined(FFMPEG_LINUX)}
  Cls := TFFmpegPulseOutput;
  {$elseif defined(FFMPEG_MACOS)}
  Cls := TFFmpegAudioQueueOutput;
  {$ifend}
  if Cls <> nil then
    try
      Exit(Cls.Create(ABufferSeconds));
    except
      on E: Exception do
        ANote := E.Message + ' - playing silently (the clock still runs)';
    end
  else
    ANote := 'No sound output on this platform yet - playing silently (the clock still runs)';
  Result := TFFmpegNullOutput.Create(ABufferSeconds);
end;

function TFFmpegAudioOutput.TakeFrames(ADst: System.PSingle; AFrames: Integer): Integer;
var
  I, Chunk: Integer;
begin
  Result := Min(AFrames, FFill);
  I := Result;
  while I > 0 do
  begin
    Chunk := Min(I, FRingFrames - FReadPos);
    Move(FRing[FReadPos * FChannels], ADst^, Chunk * FChannels * SizeOf(Single));
    Inc(ADst, Chunk * FChannels);
    FReadPos := (FReadPos + Chunk) mod FRingFrames;
    Dec(I, Chunk);
  end;
  Dec(FFill, Result);
  Inc(FRealWritten, Result);
  // a short take counts only once sound has started (FRealWritten above
  // this take's own frames): waiting for the first sound after Open or a
  // seek is not an underrun
  if (Result < AFrames) and not FEnded and FWantPlay and (FRealWritten > Result) then
    Inc(FUnderruns);
end;

procedure TFFmpegAudioOutput.ReportPlayed(APlayed: Int64);
begin
  FPlayed := Max(FPlayed, Min(APlayed, FRealWritten));
  FPlayedAt := FFmpegMonotonicSeconds;
end;

procedure TFFmpegAudioOutput.SetError(const AText: string);
begin
  FLock.Enter;
  try
    if FError = '' then
      FError := AText;
  finally
    FLock.Leave;
  end;
end;

procedure TFFmpegAudioOutput.SignalSpace;
begin
  FSpace.SetEvent;
end;

function TFFmpegAudioOutput.TakeResetRequest: Boolean;
begin
  Result := FResetWanted;
  FResetWanted := False;
end;

procedure TFFmpegAudioOutput.SetPlaying(AValue: Boolean);
begin
  if AValue <> FPlaying then
  begin
    FPlaying := AValue;
    FPlayedAt := FFmpegMonotonicSeconds;
  end;
end;

procedure TFFmpegAudioOutput.SetDrained;
begin
  FDrained := True;
  FPlayed := FRealWritten;
end;

function TFFmpegAudioOutput.EndedLocked: Boolean;
begin
  Result := FEnded;
end;

function TFFmpegAudioOutput.FillLocked: Integer;
begin
  Result := FFill;
end;

function TFFmpegAudioOutput.RealWrittenLocked: Int64;
begin
  Result := FRealWritten;
end;

procedure TFFmpegAudioOutput.Flush(ASourceTime: Double);
begin
  FLock.Enter;
  try
    FReadPos := 0;
    FFill := 0;
    FRealWritten := 0;
    FPlayed := 0;
    FPlayedAt := FFmpegMonotonicSeconds;
    FEnded := False;
    FDrained := False;
    FStartTime := ASourceTime;
    FResetWanted := True;
  finally
    FLock.Leave;
  end;
  FSpace.SetEvent;
end;

function TFFmpegAudioOutput.Write(ASrc: System.PSingle; AFrames: Integer; ACancel: TFFmpegCancelFunc): Boolean;
var
  Chunk, WritePos: Integer;
begin
  while AFrames > 0 do
  begin
    FLock.Enter;
    try
      WritePos := (FReadPos + FFill) mod FRingFrames;
      Chunk := Min(AFrames, Min(FRingFrames - FFill, FRingFrames - WritePos));
      if Chunk > 0 then
      begin
        Move(ASrc^, FRing[WritePos * FChannels], Chunk * FChannels * SizeOf(Single));
        Inc(FFill, Chunk);
      end;
    finally
      FLock.Leave;
    end;
    if Chunk > 0 then
    begin
      Inc(ASrc, Chunk * FChannels);
      Dec(AFrames, Chunk);
    end
    else
    begin
      if Assigned(ACancel) and ACancel() then
        Exit(False);
      FSpace.WaitFor(WAIT_MS);
    end;
  end;
  Result := True;
end;

procedure TFFmpegAudioOutput.MarkEnd;
begin
  FLock.Enter;
  try
    FEnded := True;
  finally
    FLock.Leave;
  end;
end;

procedure TFFmpegAudioOutput.Play;
begin
  FLock.Enter;
  try
    FWantPlay := True;
  finally
    FLock.Leave;
  end;
end;

procedure TFFmpegAudioOutput.Pause;
begin
  FLock.Enter;
  try
    FWantPlay := False;
  finally
    FLock.Leave;
  end;
end;

function TFFmpegAudioOutput.Clock: Double;
var
  Frames: Double;
begin
  FLock.Enter;
  try
    Frames := FPlayed;
    // between the device's reports the sound plays on; never past what has
    // really been handed over
    if FPlaying and (FRate > 0) then
      Frames := Min(Frames + (FFmpegMonotonicSeconds - FPlayedAt) * FRate, FRealWritten);
    if FRate > 0 then
      Result := FStartTime + Frames / FRate
    else
      Result := FStartTime;
  finally
    FLock.Leave;
  end;
end;

function TFFmpegAudioOutput.Buffered: Double;
begin
  FLock.Enter;
  try
    Result := FFill / Max(FRate, 1);
  finally
    FLock.Leave;
  end;
end;

function TFFmpegAudioOutput.Drained: Boolean;
begin
  FLock.Enter;
  try
    Result := FDrained;
  finally
    FLock.Leave;
  end;
end;

function TFFmpegAudioOutput.Underruns: Int64;
begin
  FLock.Enter;
  try
    Result := FUnderruns;
  finally
    FLock.Leave;
  end;
end;

function TFFmpegAudioOutput.LastError: string;
begin
  FLock.Enter;
  try
    Result := FError;
  finally
    FLock.Leave;
  end;
end;

{ TFFmpegNullOutput }

procedure TFFmpegNullOutput.BackendOpen;
begin
  FRate := FIXED_RATE;
  FChannels := FIXED_CHANNELS;
  FDescription := Format('no sound device (silent output), %d Hz, %d channels, clock on a timer',
    [FRate, FChannels]);
end;

procedure TFFmpegNullOutput.BackendRun(AThread: TFFmpegAudioThread);
var
  Scratch: array of Single;
  Last, Now_, Debt: Double;
  Want, Got: Integer;
begin
  SetLength(Scratch, FRate * FChannels);   // up to one second a turn
  Last := FFmpegMonotonicSeconds;
  Debt := 0;
  while not AThread.IsTerminated do
  begin
    Sleep(10);
    Now_ := FFmpegMonotonicSeconds;
    FLock.Enter;
    try
      TakeResetRequest;
      SetPlaying(WantPlay);
      if WantPlay then
      begin
        Debt := Debt + (Now_ - Last) * FRate;
        Want := Min(Trunc(Debt), FRate);
        Got := TakeFrames(@Scratch[0], Want);
        Debt := Debt - Want;
        ReportPlayed(RealWrittenLocked);
        if EndedLocked and (FillLocked = 0) then
          SetDrained;
        if Got > 0 then
          SignalSpace;
      end
      else
        Debt := 0;
    finally
      FLock.Leave;
    end;
    Last := Now_;
  end;
end;

procedure TFFmpegNullOutput.BackendClose;
begin
end;

{$ifdef FFMPEG_LINUX}
{ TFFmpegPulseOutput }

const
  { PA_STREAM_PLAYBACK. }
  PA_STREAM_PLAYBACK = 1;
  { PA_SAMPLE_FLOAT32LE. }
  PA_SAMPLE_FLOAT32LE = 5;
  { Frames written a turn: 10 ms. }
  PULSE_PIECE_MS = 10;
  { The playback buffer asked for, ms. }
  PULSE_BUFFER_MS = 100;
  { pa_simple_get_latency's answer when it failed: (pa_usec_t) -1. }
  PULSE_NO_LATENCY = High(UInt64);
  { Longest latency believed, s (a wild figure must not hold the end up). }
  PULSE_MAX_LATENCY = 2.0;
  { Added to the latency before the sound counts as played out, s. }
  PULSE_DRAIN_MARGIN = 0.05;

procedure TFFmpegPulseOutput.BackendOpen;
var
  Spec: TPaSampleSpec;
  Attr: TPaBufferAttr;
  Err: Integer;
begin
  FLib := TFFmpegDynLib.Load('libpulse-simple.so.0', True);
  FLib.Bind(FNew, 'pa_simple_new');
  FLib.Bind(FWrite, 'pa_simple_write');
  FLib.Bind(FLatency, 'pa_simple_get_latency');
  FLib.Bind(FFlush, 'pa_simple_flush');
  FLib.Bind(FFree, 'pa_simple_free');
  FRate := FIXED_RATE;
  FChannels := FIXED_CHANNELS;
  Spec.format := PA_SAMPLE_FLOAT32LE;
  Spec.rate := FRate;
  Spec.channels := FChannels;
  Attr.maxlength := $FFFFFFFF;
  Attr.tlength := FRate * FChannels * SizeOf(Single) * PULSE_BUFFER_MS div 1000;
  Attr.prebuf := $FFFFFFFF;
  Attr.minreq := $FFFFFFFF;
  Attr.fragsize := $FFFFFFFF;
  Err := 0;
  FStream := FNew(nil, 'FFmpegAPI', PA_STREAM_PLAYBACK, nil, 'playback', @Spec, nil, @Attr, @Err);
  if FStream = nil then
    raise Exception.CreateFmt('Sound output: no PulseAudio / PipeWire server could be reached (error %d)',
      [Err]);
  FDescription := Format('PulseAudio (simple API), %d Hz, %d channels, 32-bit float, %d ms buffer',
    [FRate, FChannels, PULSE_BUFFER_MS]);
end;

procedure TFFmpegPulseOutput.BackendRun(AThread: TFFmpegAudioThread);
var
  Piece: array of Single;
  Frames, Got, Err: Integer;
  Lat: UInt64;
  Playing, Reset, Wrote: Boolean;
  LastWrite, LatAtWrite: Double;
begin
  Frames := FRate * PULSE_PIECE_MS div 1000;
  SetLength(Piece, Frames * FChannels);
  LastWrite := 0;
  LatAtWrite := 0;
  while not AThread.IsTerminated do
  begin
    FLock.Enter;
    try
      Reset := TakeResetRequest;
      Playing := WantPlay;
      SetPlaying(Playing);
      Got := 0;
      if Playing then
        Got := TakeFrames(@Piece[0], Frames);
    finally
      FLock.Leave;
    end;
    if Reset then
    begin
      FFlush(FStream, @Err);
      LastWrite := 0;
      LatAtWrite := 0;
    end;
    Wrote := Got > 0;
    if Wrote then
    begin
      SignalSpace;
      // blocks until the server has room: this paces the loop
      if FWrite(FStream, @Piece[0], Got * FChannels * SizeOf(Single), @Err) < 0 then
      begin
        SetError(Format('PulseAudio write failed (error %d)', [Err]));
        Break;
      end;
    end
    else
      Sleep(5);
    Lat := FLatency(FStream, @Err);
    if Lat = PULSE_NO_LATENCY then
      Lat := 0;   // not known: nothing taken off what was handed over
    if Wrote then
    begin
      // when the last piece went to the server, and how long the server
      // then said it takes to be heard (its buffer and the device's)
      LastWrite := FFmpegMonotonicSeconds;
      LatAtWrite := Min(Lat / 1000000, PULSE_MAX_LATENCY);
      if LatAtWrite <= 0 then
        LatAtWrite := PULSE_BUFFER_MS / 1000;
    end;
    FLock.Enter;
    try
      ReportPlayed(RealWrittenLocked - Int64(Lat) * FRate div 1000000);
      // played out: the server says nothing waits - or, as its figure can
      // hold the device's own latency and never reach 0 (and is no figure
      // at all after an error), the last piece was written longer ago
      // than it took to be heard. Without the second test Drained could
      // stay False for ever: no Ended, no next audio file.
      if EndedLocked and (FillLocked = 0) and ((Lat = 0) or
        (FFmpegMonotonicSeconds - LastWrite >= LatAtWrite + PULSE_DRAIN_MARGIN)) then
        SetDrained;
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TFFmpegPulseOutput.BackendClose;
begin
  if (FStream <> nil) and Assigned(FFree) then
    FFree(FStream);
  FStream := nil;
  FreeAndNil(FLib);
end;
{$endif}

{$ifdef FFMPEG_MACOS}
{ TFFmpegAudioQueueOutput }

const
  { AudioToolbox (macOS 11 and later: in the dyld shared cache, not on disk -
    TFFmpegDynLib.Load tries /System/Library/ paths anyway). }
  AUDIOTOOLBOX_LIB = '/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox';
  { kAudioFormatLinearPCM: 'lpcm'. }
  AQ_FORMAT_LINEAR_PCM = $6C70636D;
  { kAudioFormatFlagIsFloat or kAudioFormatFlagIsPacked. }
  AQ_FLAGS_FLOAT_PACKED = $1 or $8;
  { Buffers the queue gets. }
  AQ_BUFFERS = 4;
  { Sound in a buffer, ms (four: 100 ms in the queue, as PulseAudio's). }
  AQ_PIECE_MS = 25;

{ The queue's output callback (AudioQueueOutputCallback), on the queue's
  own thread: a buffer has been played. }
procedure AqOutputCallback(inUserData, inAQ: Pointer; inBuffer: PAqBuffer); cdecl;
begin
  TFFmpegAudioQueueOutput(inUserData).BufferDone(inBuffer);
end;

{ Raises when an AudioQueue call failed. }
procedure CheckAq(AStatus: Int32; const AStep: string);
begin
  if AStatus <> 0 then
    raise Exception.CreateFmt('Sound output: %s failed (OSStatus %d)', [AStep, AStatus]);
end;

procedure TFFmpegAudioQueueOutput.BufferDone(ABuffer: PAqBuffer);
var
  I: Integer;
begin
  I := Integer(NativeInt(ABuffer^.mUserData));
  FLock.Enter;
  try
    if (I >= 0) and (I <= High(FBusy)) then
    begin
      if FBusy[I] then
      begin
        FBusy[I] := False;
        Dec(FInFlight);
      end;
      // played sound of this generation (a buffer dropped by a seek, or
      // coming back after the writer asked for one, is not)
      if (FGen[I] = FCurGen) and not FResetWanted then
      begin
        Inc(FPlayedReal, FReal[I]);
        ReportPlayed(FPlayedReal);
      end;
      FReal[I] := 0;
    end;
  finally
    FLock.Leave;
  end;
  if FWake <> nil then
    FWake.SetEvent;
end;

procedure TFFmpegAudioQueueOutput.BackendOpen;
var
  Desc: TAqStreamDescription;
  I: Integer;
begin
  FLib := TFFmpegDynLib.Load(AUDIOTOOLBOX_LIB, True);
  FLib.Bind(FNewOutput, 'AudioQueueNewOutput');
  FLib.Bind(FAllocateBuffer, 'AudioQueueAllocateBuffer');
  FLib.Bind(FEnqueueBuffer, 'AudioQueueEnqueueBuffer');
  FLib.Bind(FStart, 'AudioQueueStart');
  FLib.Bind(FPause, 'AudioQueuePause');
  FLib.Bind(FStop, 'AudioQueueStop');
  FLib.Bind(FReset, 'AudioQueueReset');
  FLib.Bind(FDispose, 'AudioQueueDispose');
  FRate := FIXED_RATE;
  FChannels := FIXED_CHANNELS;
  FillChar(Desc, SizeOf(Desc), 0);
  Desc.mSampleRate := FRate;
  Desc.mFormatID := AQ_FORMAT_LINEAR_PCM;
  Desc.mFormatFlags := AQ_FLAGS_FLOAT_PACKED;
  Desc.mBytesPerPacket := FChannels * SizeOf(Single);
  Desc.mFramesPerPacket := 1;
  Desc.mBytesPerFrame := FChannels * SizeOf(Single);
  Desc.mChannelsPerFrame := FChannels;
  Desc.mBitsPerChannel := 32;
  FWake := TEvent.Create(nil, False, False, '');
  // no run loop: the callbacks come on one of the queue's own threads
  CheckAq(FNewOutput(@Desc, @AqOutputCallback, Self, nil, nil, 0, @FQueue), 'opening an output queue');
  FBufferFrames := FRate * AQ_PIECE_MS div 1000;
  SetLength(FBuffers, AQ_BUFFERS);
  SetLength(FBusy, AQ_BUFFERS);
  SetLength(FReal, AQ_BUFFERS);
  SetLength(FGen, AQ_BUFFERS);
  for I := 0 to AQ_BUFFERS - 1 do
  begin
    CheckAq(FAllocateBuffer(FQueue, FBufferFrames * FChannels * SizeOf(Single), @FBuffers[I]),
      'allocating its buffers');
    FBuffers[I]^.mUserData := Pointer(NativeInt(I));
  end;
  FDescription := Format('AudioQueue (macOS default output device), %d Hz, %d channels, 32-bit float, ' +
    '%d x %d ms buffers', [FRate, FChannels, AQ_BUFFERS, AQ_PIECE_MS]);
end;

procedure TFFmpegAudioQueueOutput.BackendRun(AThread: TFFmpegAudioThread);
var
  I, Real, Give: Integer;
  Want, Reset, Running, AtEnd, Fill: Boolean;
  St: Int32;
begin
  Running := False;
  try
    while not AThread.IsTerminated do
    begin
      FWake.WaitFor(10);
      FLock.Enter;
      try
        Reset := TakeResetRequest;
        if Reset then
        begin
          // what the queue holds now belongs to the time before the seek
          Inc(FCurGen);
          FPlayedReal := 0;
        end;
        Want := WantPlay;
      finally
        FLock.Leave;
      end;
      if Reset then
        FReset(FQueue);   // its buffers come back through the callback, not counted
      // the free buffers, filled while playing: real sound, silence after it
      // before the end (the queue keeps running through an underrun), only
      // the real sound after the end
      if Want then
        for I := 0 to High(FBuffers) do
        begin
          Fill := False;
          Real := 0;
          AtEnd := False;
          FLock.Enter;
          try
            if not FBusy[I] then
            begin
              Real := TakeFrames(System.PSingle(FBuffers[I]^.mAudioData), FBufferFrames);
              AtEnd := EndedLocked;
              if not (AtEnd and (Real = 0)) then
              begin
                Fill := True;
                FReal[I] := Real;
                FGen[I] := FCurGen;
                FBusy[I] := True;
                Inc(FInFlight);
              end;
            end;
          finally
            FLock.Leave;
          end;
          if not Fill then
            Continue;
          Give := FBufferFrames;
          if AtEnd then
            Give := Real
          else if Real < FBufferFrames then
            FillChar(PByte(FBuffers[I]^.mAudioData)[Real * FChannels * SizeOf(Single)],
              (FBufferFrames - Real) * FChannels * SizeOf(Single), 0);
          FBuffers[I]^.mAudioDataByteSize := Give * FChannels * SizeOf(Single);
          St := FEnqueueBuffer(FQueue, FBuffers[I], 0, nil);
          if St <> 0 then
          begin
            FLock.Enter;
            try
              FBusy[I] := False;
              Dec(FInFlight);
            finally
              FLock.Leave;
            end;
            SetError(Format('Sound output: the queue took no more sound (OSStatus %d) - device gone? ' +
              'Play again to use the current device', [St]));
            Exit;
          end;
          SignalSpace;
        end;
      // play / pause (after filling: the queue starts with sound in it)
      if Want and not Running then
      begin
        St := FStart(FQueue, nil);
        if St <> 0 then
        begin
          SetError(Format('Sound output: the queue did not start (OSStatus %d)', [St]));
          Exit;
        end;
        Running := True;
      end
      else if not Want and Running then
      begin
        FPause(FQueue);
        Running := False;
      end;
      FLock.Enter;
      try
        SetPlaying(Running);
        if EndedLocked and (FillLocked = 0) and (FInFlight = 0) then
          SetDrained;
      finally
        FLock.Leave;
      end;
    end;
  finally
    if Running and (FQueue <> nil) then
      FStop(FQueue, 1);
  end;
end;

procedure TFFmpegAudioQueueOutput.BackendClose;
begin
  if FQueue <> nil then
  begin
    FStop(FQueue, 1);
    // frees the buffers too; callbacks may still come until it returns
    FDispose(FQueue, 1);
    FQueue := nil;
  end;
  FBuffers := nil;
  FreeAndNil(FWake);
  FreeAndNil(FLib);
end;
{$endif}

{$if defined(FFMPEG_WINDOWS) and not defined(FPC)}
{ TFFmpegWasapiOutput }

const
  { The MMDevice enumerator. }
  CLSID_MMDeviceEnumerator: TGUID = '{BCDE0395-E52F-467C-8E3D-C4579291692E}';
  { IAudioClient. }
  IID_IAudioClient: TGUID = '{1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}';
  { IAudioRenderClient. }
  IID_IAudioRenderClient: TGUID = '{F294ACFC-3146-4483-A7BF-ADDCA7C260E2}';
  { 32-bit float samples, in WAVEFORMATEXTENSIBLE.SubFormat. }
  KSDATAFORMAT_SUBTYPE_IEEE_FLOAT: TGUID = '{00000003-0000-0010-8000-00AA00389B71}';
  { EDataFlow: output. }
  eRender = 0;
  { ERole: the console default. }
  eConsole = 0;
  { Shared with other programs. }
  AUDCLNT_SHAREMODE_SHARED = 0;
  { The device signals an event when it wants more sound. }
  AUDCLNT_STREAMFLAGS_EVENTCALLBACK = $00040000;
  { Windows converts the format if it must. }
  AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM = $80000000;
  { With AUTOCONVERTPCM: good quality rate conversion. }
  AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY = $08000000;
  { WAVEFORMATEX.wFormatTag of a WAVEFORMATEXTENSIBLE. }
  WAVE_FORMAT_EXTENSIBLE = $FFFE;
  { The device buffer asked for: 100 ms, in 100-ns units. }
  DEVICE_BUFFER_HNS = 1000000;
  { The endpoint is gone: unplugged, disabled, or its format was changed. }
  AUDCLNT_E_DEVICE_INVALIDATED = HRESULT($88890004);
  { Failed turns in a row (20 ms each) after which the device counts as
    lost whatever its error says: two seconds. }
  MAX_DEVICE_FAILS = 100;

type
  { WAVEFORMATEXTENSIBLE: a WAVEFORMATEX (packed, 18 bytes) and the rest. }
  TWaveFormatExtensible = packed record
    { The basic format. }
    Format: TWaveFormatEx;
    { Bits that carry the sample. }
    wValidBitsPerSample: Word;
    { Which speakers the channels are. }
    dwChannelMask: DWORD;
    { The sample type. }
    SubFormat: TGUID;
  end;
  { A pointer to a TWaveFormatExtensible. }
  PWaveFormatExtensible = ^TWaveFormatExtensible;

  { An audio endpoint (mmdeviceapi.h). }
  IMMDevice = interface(IUnknown)
    ['{D666063F-1587-4E43-81F1-B948E807363F}']
    { Makes an object on the device. }
    function Activate(const iid: TGUID; dwClsCtx: DWORD; pActivationParams: Pointer;
      out ppInterface): HRESULT; stdcall;
    { Not used. }
    function OpenPropertyStore(stgmAccess: DWORD; out ppProperties: IUnknown): HRESULT; stdcall;
    { Not used. }
    function GetId(out ppstrId: PWideChar): HRESULT; stdcall;
    { Not used. }
    function GetState(out pdwState: DWORD): HRESULT; stdcall;
  end;

  { Finds audio endpoints (mmdeviceapi.h). }
  IMMDeviceEnumerator = interface(IUnknown)
    ['{A95664D2-9614-4F35-A746-DE8DB63617E6}']
    { Not used. }
    function EnumAudioEndpoints(dataFlow: Integer; dwStateMask: DWORD; out ppDevices: IUnknown): HRESULT; stdcall;
    { The default endpoint for a direction and role. }
    function GetDefaultAudioEndpoint(dataFlow, role: Integer; out ppEndpoint: IMMDevice): HRESULT; stdcall;
    { Not used. }
    function GetDevice(pwstrId: PWideChar; out ppDevice: IMMDevice): HRESULT; stdcall;
    { Not used. }
    function RegisterEndpointNotificationCallback(pClient: IUnknown): HRESULT; stdcall;
    { Not used. }
    function UnregisterEndpointNotificationCallback(pClient: IUnknown): HRESULT; stdcall;
  end;

  { A stream on an endpoint (audioclient.h). }
  IAudioClient = interface(IUnknown)
    ['{1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}']
    { Opens the stream. }
    function Initialize(ShareMode: Integer; StreamFlags: DWORD; hnsBufferDuration, hnsPeriodicity: Int64;
      pFormat: PWaveFormatEx; AudioSessionGuid: PGUID): HRESULT; stdcall;
    { The device buffer's size in frames. }
    function GetBufferSize(out NumBufferFrames: UINT32): HRESULT; stdcall;
    { Not used. }
    function GetStreamLatency(out phnsLatency: Int64): HRESULT; stdcall;
    { Frames in the device buffer not yet played. }
    function GetCurrentPadding(out NumPaddingFrames: UINT32): HRESULT; stdcall;
    { Not used. }
    function IsFormatSupported(ShareMode: Integer; pFormat: PWaveFormatEx;
      out ppClosestMatch: PWaveFormatEx): HRESULT; stdcall;
    { The shared-mode mix format; free it with CoTaskMemFree. }
    function GetMixFormat(out ppDeviceFormat: PWaveFormatEx): HRESULT; stdcall;
    { Not used. }
    function GetDevicePeriod(out phnsDefaultDevicePeriod, phnsMinimumDevicePeriod: Int64): HRESULT; stdcall;
    { Starts the stream. }
    function Start: HRESULT; stdcall;
    { Stops the stream, keeping what is buffered. }
    function Stop: HRESULT; stdcall;
    { Drops what is buffered (stream stopped). }
    function Reset: HRESULT; stdcall;
    { The event signalled when the device wants more. }
    function SetEventHandle(eventHandle: THandle): HRESULT; stdcall;
    { Another interface on the stream. }
    function GetService(const riid: TGUID; out ppv): HRESULT; stdcall;
  end;

  { Writes into the device buffer (audioclient.h). }
  IAudioRenderClient = interface(IUnknown)
    ['{F294ACFC-3146-4483-A7BF-ADDCA7C260E2}']
    { The next free part of the device buffer. }
    function GetBuffer(NumFramesRequested: UINT32; out ppData: PByte): HRESULT; stdcall;
    { Hands the part back, filled. }
    function ReleaseBuffer(NumFramesWritten: UINT32; dwFlags: DWORD): HRESULT; stdcall;
  end;

{ Raises when a WASAPI call failed. }
procedure CheckHR(AHR: HRESULT; const AStep: string);
begin
  if Failed(AHR) then
    raise Exception.CreateFmt('Sound output: %s failed (HRESULT $%.8x, %s)', [AStep, Cardinal(AHR),
      SysErrorMessage(Cardinal(AHR))]);
end;

procedure TFFmpegWasapiOutput.BackendOpen;
var
  Enum: IMMDeviceEnumerator;
  Device: IMMDevice;
  Client: IAudioClient;
  Render: IAudioRenderClient;
  Mix: PWaveFormatEx;
  Fmt: TWaveFormatExtensible;
  Mask: Cardinal;
begin
  CoInitializeEx(nil, COINIT_MULTITHREADED);
  FComInit := True;
  CheckHR(CoCreateInstance(CLSID_MMDeviceEnumerator, nil, CLSCTX_ALL, IMMDeviceEnumerator, Enum),
    'creating the device enumerator');
  CheckHR(Enum.GetDefaultAudioEndpoint(eRender, eConsole, Device), 'finding the default output device');
  CheckHR(Device.Activate(IID_IAudioClient, CLSCTX_ALL, nil, Client), 'opening the device');
  CheckHR(Client.GetMixFormat(Mix), 'reading its mix format');
  try
    FRate := Mix.nSamplesPerSec;
    FChannels := Mix.nChannels;
    if (Mix.wFormatTag = WAVE_FORMAT_EXTENSIBLE) and (Mix.cbSize >= 22) then
      Mask := PWaveFormatExtensible(Mix).dwChannelMask
    else if FChannels = 1 then
      Mask := $4
    else
      Mask := $3;
  finally
    CoTaskMemFree(Mix);
  end;
  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.Format.wFormatTag := WAVE_FORMAT_EXTENSIBLE;
  Fmt.Format.nChannels := FChannels;
  Fmt.Format.nSamplesPerSec := FRate;
  Fmt.Format.wBitsPerSample := 32;
  Fmt.Format.nBlockAlign := FChannels * 4;
  Fmt.Format.nAvgBytesPerSec := FRate * Fmt.Format.nBlockAlign;
  Fmt.Format.cbSize := 22;
  Fmt.wValidBitsPerSample := 32;
  Fmt.dwChannelMask := Mask;
  Fmt.SubFormat := KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
  CheckHR(Client.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK or
    AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM or AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, DEVICE_BUFFER_HNS, 0,
    @Fmt, nil), 'starting a shared stream (32-bit float)');
  CheckHR(Client.GetBufferSize(FBufferFrames), 'reading its buffer size');
  FWake := CreateEvent(nil, False, False, nil);
  CheckHR(Client.SetEventHandle(FWake), 'setting its event');
  CheckHR(Client.GetService(IID_IAudioRenderClient, Render), 'getting its render client');
  FEnum := Enum;
  FDevice := Device;
  FClient := Client;
  FRender := Render;
  FDescription := Format('WASAPI default output device, %d Hz, %d channels (mask $%x), 32-bit float, ' +
    'device buffer %d frames (%.0f ms), shared mode', [FRate, FChannels, Mask, FBufferFrames,
    FBufferFrames * 1000 / FRate]);
end;

procedure TFFmpegWasapiOutput.BackendRun(AThread: TFFmpegAudioThread);
var
  Client: IAudioClient;
  Render: IAudioRenderClient;
  Padding: UINT32;
  Want, Real, Give, Fails: Integer;
  Data: PByte;
  Running, AtEnd: Boolean;
  HR: HRESULT;
begin
  Client := FClient as IAudioClient;
  Render := FRender as IAudioRenderClient;
  Running := False;
  Fails := 0;
  try
    while not AThread.IsTerminated do
    begin
      WaitForSingleObject(FWake, 20);
      FLock.Enter;
      try
        if TakeResetRequest then
        begin
          // a seek: drop what the device still holds
          if Running then
            Client.Stop;
          Client.Reset;
          Running := False;
        end;
        if WantPlay <> Running then
        begin
          if WantPlay then
            Running := Succeeded(Client.Start)
          else
          begin
            Client.Stop;
            Running := False;
          end;
          SetPlaying(Running);
        end;
      finally
        FLock.Leave;
      end;
      if not Running then
        Continue;
      // a device that is gone (headphones unplugged, another output
      // chosen in Windows) fails here on every turn, for ever: it was
      // passed over in silence - no sound, no error, the clock stopped.
      // Now LastError says so and the output stops; TFFmpegAudioPlayer
      // opens the default device afresh at its next Play.
      HR := Client.GetCurrentPadding(Padding);
      if Failed(HR) then
      begin
        Inc(Fails);
        if (HR = AUDCLNT_E_DEVICE_INVALIDATED) or (Fails >= MAX_DEVICE_FAILS) then
        begin
          SetError(Format('Sound output: the device is gone or no longer answers (HRESULT $%.8x) - ' +
            'unplugged or switched? Play again to use the current device', [Cardinal(HR)]));
          Break;
        end;
        Continue;
      end;
      Fails := 0;
      Want := Integer(FBufferFrames) - Integer(Padding);
      FLock.Enter;
      try
        // real sound played: handed over, less what waits in the device
        // (silence is only written when nothing real waits)
        ReportPlayed(RealWrittenLocked - Int64(Padding));
        if EndedLocked and (FillLocked = 0) and (Padding = 0) then
          SetDrained;
      finally
        FLock.Leave;
      end;
      if Want <= 0 then
        Continue;
      if Failed(Render.GetBuffer(Want, Data)) then
        Continue;
      FLock.Enter;
      try
        Real := TakeFrames(System.PSingle(Data), Want);
        AtEnd := EndedLocked;
      finally
        FLock.Leave;
      end;
      // Short of sound: before the end the rest is silence (the device keeps
      // running through an underrun). After the end nothing but the real
      // frames is handed over - silence would keep the device's buffer full
      // for ever, its padding would never reach 0, and neither the clock nor
      // Drained would get to the end.
      Give := Want;
      if AtEnd then
        Give := Real
      else if Real < Want then
        FillChar(PByte(Data)[Real * FChannels * SizeOf(Single)], (Want - Real) * FChannels * SizeOf(Single), 0);
      Render.ReleaseBuffer(Give, 0);
      SignalSpace;
    end;
  finally
    if Running then
      Client.Stop;
  end;
end;

procedure TFFmpegWasapiOutput.BackendClose;
begin
  FRender := nil;
  FClient := nil;
  FDevice := nil;
  FEnum := nil;
  if FWake <> 0 then
    CloseHandle(FWake);
  FWake := 0;
  if FComInit then
    CoUninitialize;
  FComInit := False;
end;
{$ifend}

end.
