(* @abstract(@link(TCustomFFmpegAudio): the framework-free base of the FFmpeg
  audio components - the libraries, a media file, its streams, chapters,
  tags and cover art, and decoding on the calling thread or on a worker
  thread with events on the main thread.)

  Framework units (FFmpeg.FMX, a VCL or LCL one) only publish the
  properties and show handler exceptions their way. Events of a decode on
  the worker thread arrive on the main thread through TThread.Queue (a
  console program must call CheckSynchronize to receive them).

  Framework-free; compiles with Delphi and FPC. *)
unit FFmpeg.Components;

{$I FFmpeg.inc}

interface

uses
  SysUtils, Classes, SyncObjs,
  FFmpeg.API, FFmpeg.Media;

{$ifndef FPC}
const
  { Platforms of the FFmpeg components (ComponentPlatformsAttribute): 64-bit
    desktop and Android. lib/ still compiles for Win32, which a 32-bit IDE
    needs to load the design-time package. }
  FFMPEG_COMPONENT_PLATFORMS = pidWin64 or pidOSX64 or pidOSXArm64 or pidLinux64 or pidAndroidArm64;
{$endif}

type
  TCustomFFmpegAudio = class;

  { Decoded samples: interleaved float, AStart..AEnd seconds of the file. }
  TFFmpegDecodedEvent = procedure(Sender: TObject; const ASamples: TFFmpegSamples; AStart, AEnd: Double)
    of object;
  { Something failed; AMessage says what. }
  TFFmpegErrorEvent = procedure(Sender: TObject; const AMessage: string) of object;

  { The worker thread of @link(TCustomFFmpegAudio.DecodeAsync): opens the
    file again (a demuxer serves one reader), decodes the range, and queues
    the result to the main thread. }
  TFFmpegDecodeThread = class(TThread)
  private
    { The component (the thread never outlives it). }
    FOwner: TCustomFFmpegAudio;
    { What to decode. }
    FFileName: string;
    { Range start, s. }
    FStart: Double;
    { Range end, s (0 = to the end). }
    FEnd: Double;
    { Output rate (0 = the stream's). }
    FRate: Integer;
    { Output channels (0 = the stream's). }
    FChannels: Integer;
    { The decoder while it runs (for Cancel); read and written under
      FLock. }
    FDecoder: TFFmpegAudioDecoder;
    { Guards FDecoder: Cancel comes from the main thread while Execute
      makes and frees the decoder. }
    FLock: TCriticalSection;
    { The result. }
    FSamples: TFFmpegSamples;
    { '' or what failed. }
    FError: string;
    { Hands the result to the component (main thread). }
    procedure Deliver;
  protected
    { Decodes. }
    procedure Execute; override;
  public
    { A decode of AStart..AEnd of AFileName for AOwner (not started). }
    constructor Create(AOwner: TCustomFFmpegAudio; const AFileName: string; AStart, AEnd: Double;
      ARate, AChannels: Integer);
    { Frees the lock. }
    destructor Destroy; override;
    { Asks the decode to stop: at once when it has not started reading. }
    procedure Cancel;
  end;

  { FFmpeg audio: the libraries, a media file and its decoding. Set
    @link(FileName) and @link(Active); then the streams, chapters, tags and
    cover art are there, @link(Decode) decodes on the calling thread and
    @link(DecodeAsync) on a worker thread. }
  TCustomFFmpegAudio = class(TComponent)
  private
    { Backing field of @link(Active). }
    FActive: Boolean;
    { Active as read from the form file (applied in Loaded). }
    FStreamedActive: Boolean;
    { Backing field of @link(LibraryFolder). }
    FLibraryFolder: string;
    { Backing field of @link(LicencePolicy). }
    FLicencePolicy: TFFmpegLicencePolicy;
    { Backing field of @link(FileName). }
    FFileName: string;
    { Backing field of @link(SampleRate). }
    FSampleRate: Integer;
    { Backing field of @link(Channels). }
    FChannels: Integer;
    { Backing field of @link(Lib). }
    FLib: TFFmpegLibrary;
    { Backing field of @link(MediaFile). }
    FMediaFile: TFFmpegMediaFile;
    { Decoder of @link(Decode) (made on first use). }
    FDecoder: TFFmpegAudioDecoder;
    { The worker thread of the last DecodeAsync (freed by the next one or on
      destruction, after its result was delivered). }
    FThread: TFFmpegDecodeThread;
    { A DecodeAsync is running. }
    FBusy: Boolean;
    { Backing field of @link(OnOpen). }
    FOnOpen: TNotifyEvent;
    { Backing field of @link(OnOpenFailed). }
    FOnOpenFailed: TFFmpegErrorEvent;
    { Backing field of @link(OnClose). }
    FOnClose: TNotifyEvent;
    { Backing field of @link(OnDecoded). }
    FOnDecoded: TFFmpegDecodedEvent;
    { Backing field of @link(OnDecodeFailed). }
    FOnDecodeFailed: TFFmpegErrorEvent;
    { Opens or closes. }
    procedure SetActive(const AValue: Boolean);
    { Changes the file (reopens when active). }
    procedure SetFileName(const AValue: string);
    { Closes when the library settings change. }
    procedure SetLibraryFolder(const AValue: string);
    { Closes when the licence policy changes. }
    procedure SetLicencePolicy(const AValue: TFFmpegLicencePolicy);
    { Output rate (drops the decoder). }
    procedure SetSampleRate(const AValue: Integer);
    { Output channels (drops the decoder). }
    procedure SetChannels(const AValue: Integer);
    { The streams ('' file: none). }
    function GetStreams: TFFmpegStreamInfoArray;
    { The chapters. }
    function GetChapters: TFFmpegChapterArray;
    { The tags. }
    function GetTags: TFFmpegTagArray;
    { Length, s. }
    function GetDuration: Double;
    { Description of the libraries. }
    function GetDescription: string;
    { Waits for and frees the worker thread. }
    procedure FreeThread;
  protected
    { Applies Active read from the form file. }
    procedure Loaded; override;
    { Shows an exception an event handler raised (framework units override
      it; here it is dropped, as a component may not raise out of a queued
      event). }
    procedure ShowHandlerException(E: Exception); virtual;
    { Called by the worker thread's Deliver on the main thread. }
    procedure DecodeDone(AThread: TFFmpegDecodeThread);
  public
    { A component with no file. }
    constructor Create(AOwner: TComponent); override;
    { Cancels a decode, closes the file and unloads the libraries. }
    destructor Destroy; override;
    { Loads the libraries (once) and opens @link(FileName).
      @raises(EFFmpegError when that fails - @link(Active) := True reports
        through OnOpenFailed instead.) }
    procedure Open;
    { Closes the file (the libraries stay loaded). }
    procedure Close;
    { Decodes AStart..AEnd seconds (AEnd <= 0: to the end) on the calling
      thread, at @link(SampleRate) / @link(Channels).
      @raises(EFFmpegError when the file is not open or decoding fails.) }
    function Decode(AStart: Double = 0; AEnd: Double = 0): TFFmpegSamples;
    { Decodes chapter AIndex on the calling thread. }
    function DecodeChapter(AIndex: Integer): TFFmpegSamples;
    { Decodes AStart..AEnd on a worker thread; OnDecoded or OnDecodeFailed
      follows on the main thread. One at a time; a handler may start the
      next one (or close the file).
      @raises(EFFmpegError when the file is not open or a decode runs.) }
    procedure DecodeAsync(AStart: Double = 0; AEnd: Double = 0);
    { Asks a DecodeAsync in progress to stop (OnDecoded then gets what was
      decoded so far). }
    procedure CancelDecode;
    { The cover art (see @code(TFFmpegMediaFile.CoverArt)); False when there
      is none or no file is open. }
    function CoverArt(out AData: TBytes; out AExtension: string): Boolean;
    { The libraries (nil until opened). }
    property Lib: TFFmpegLibrary read FLib;
    { The open file (nil when closed). }
    property MediaFile: TFFmpegMediaFile read FMediaFile;
    { The streams of the open file. }
    property Streams: TFFmpegStreamInfoArray read GetStreams;
    { The chapters of the open file. }
    property Chapters: TFFmpegChapterArray read GetChapters;
    { The tags of the open file. }
    property Tags: TFFmpegTagArray read GetTags;
    { Length of the open file, s. }
    property Duration: Double read GetDuration;
    { The libraries, versions, licence and folder ('' until loaded). }
    property Description: string read GetDescription;
    { A DecodeAsync is running. }
    property Busy: Boolean read FBusy;
    { Open (setting it opens or closes; a failure goes to OnOpenFailed). At
      design time the value is only stored. }
    property Active: Boolean read FActive write SetActive default False;
    { Folder of FFmpeg's libraries ('' = next to the executable, then the
      system search path). }
    property LibraryFolder: string read FLibraryFolder write SetLibraryFolder;
    { Which FFmpeg builds are accepted (see TFFmpegLicencePolicy). }
    property LicencePolicy: TFFmpegLicencePolicy read FLicencePolicy write SetLicencePolicy
      default flpAny;
    { The media file. }
    property FileName: string read FFileName write SetFileName;
    { Samples per second of decoded audio (0 = the stream's). }
    property SampleRate: Integer read FSampleRate write SetSampleRate default 0;
    { Channels of decoded audio (0 = the stream's; 1 = mono). }
    property Channels: Integer read FChannels write SetChannels default 0;
    { The file was opened. }
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
    { Opening failed (Active := True). }
    property OnOpenFailed: TFFmpegErrorEvent read FOnOpenFailed write FOnOpenFailed;
    { The file was closed. }
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    { A DecodeAsync finished (main thread). }
    property OnDecoded: TFFmpegDecodedEvent read FOnDecoded write FOnDecoded;
    { A DecodeAsync failed (main thread). }
    property OnDecodeFailed: TFFmpegErrorEvent read FOnDecodeFailed write FOnDecodeFailed;
  end;

implementation

{ TFFmpegDecodeThread }

constructor TFFmpegDecodeThread.Create(AOwner: TCustomFFmpegAudio; const AFileName: string; AStart,
  AEnd: Double; ARate, AChannels: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FFileName := AFileName;
  FStart := AStart;
  FEnd := AEnd;
  FRate := ARate;
  FChannels := AChannels;
  FLock := TCriticalSection.Create;
end;

destructor TFFmpegDecodeThread.Destroy;
begin
  inherited;   // the thread has ended before the lock goes
  FreeAndNil(FLock);
end;

procedure TFFmpegDecodeThread.Cancel;
begin
  // Terminated first: Execute tests it under the lock once the decoder is
  // there, so a cancel is seen whichever side of that it falls on
  Terminate;
  FLock.Enter;
  try
    if FDecoder <> nil then
      FDecoder.Cancel;
  finally
    FLock.Leave;
  end;
end;

procedure TFFmpegDecodeThread.Execute;
var
  F: TFFmpegMediaFile;
  Dec_: TFFmpegAudioDecoder;
  Go: Boolean;
begin
  try
    F := TFFmpegMediaFile.Create(FOwner.Lib, FFileName);
    try
      Dec_ := TFFmpegAudioDecoder.Create(F, -1, FRate, FChannels);
      try
        FLock.Enter;
        try
          FDecoder := Dec_;
          Go := not Terminated;
        finally
          FLock.Leave;
        end;
        if Go then
          FSamples := Dec_.Read(FStart, FEnd);
      finally
        // out of Cancel's reach before it is freed
        FLock.Enter;
        try
          FDecoder := nil;
        finally
          FLock.Leave;
        end;
        Dec_.Free;
      end;
    finally
      F.Free;
    end;
  except
    on E: Exception do
      FError := E.Message;
  end;
  // removed from the queue if the thread is freed first (component closing)
  Queue(Deliver);
end;

procedure TFFmpegDecodeThread.Deliver;
begin
  FOwner.DecodeDone(Self);
end;

{ TCustomFFmpegAudio }

constructor TCustomFFmpegAudio.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLicencePolicy := flpAny;
end;

destructor TCustomFFmpegAudio.Destroy;
begin
  FreeThread;
  Close;
  FreeAndNil(FLib);
  inherited;
end;

procedure TCustomFFmpegAudio.FreeThread;
begin
  if FThread <> nil then
  begin
    FThread.Cancel;
    FThread.WaitFor;
    FreeAndNil(FThread);   // drops a result not delivered yet
  end;
  FBusy := False;
end;

procedure TCustomFFmpegAudio.Loaded;
begin
  inherited;
  if csDesigning in ComponentState then
    FActive := FStreamedActive
  else if FStreamedActive then
    SetActive(True);
  FStreamedActive := False;
end;

procedure TCustomFFmpegAudio.ShowHandlerException(E: Exception);
begin
  // framework units override this
end;

procedure TCustomFFmpegAudio.SetActive(const AValue: Boolean);
begin
  if csLoading in ComponentState then
  begin
    FStreamedActive := AValue;
    Exit;
  end;
  if csDesigning in ComponentState then
  begin
    FActive := AValue;
    Exit;
  end;
  if AValue = FActive then
    Exit;
  if AValue then
  begin
    try
      Open;
    except
      on E: Exception do
      begin
        if Assigned(FOnOpenFailed) then
          try
            FOnOpenFailed(Self, E.Message);
          except
            on H: Exception do
              ShowHandlerException(H);
          end
        else
          // no silent failure (as TWhisperAPI): shown, never raised - from
          // Loaded it would end the program before the form is there
          ShowHandlerException(E);
      end;
    end;
  end
  else
    Close;
end;

procedure TCustomFFmpegAudio.SetFileName(const AValue: string);
var
  WasActive: Boolean;
begin
  if AValue = FFileName then
    Exit;
  WasActive := FActive and not (csDesigning in ComponentState);
  if WasActive then
    Close;
  FFileName := AValue;
  if WasActive then
    SetActive(True);
end;

procedure TCustomFFmpegAudio.SetLibraryFolder(const AValue: string);
begin
  if AValue = FLibraryFolder then
    Exit;
  if not (csDesigning in ComponentState) then
  begin
    Close;
    FreeThread;
    FreeAndNil(FLib);
  end;
  FLibraryFolder := AValue;
end;

procedure TCustomFFmpegAudio.SetLicencePolicy(const AValue: TFFmpegLicencePolicy);
begin
  if AValue = FLicencePolicy then
    Exit;
  if not (csDesigning in ComponentState) then
  begin
    Close;
    FreeThread;
    FreeAndNil(FLib);
  end;
  FLicencePolicy := AValue;
end;

procedure TCustomFFmpegAudio.SetSampleRate(const AValue: Integer);
begin
  FSampleRate := AValue;
  FreeAndNil(FDecoder);
end;

procedure TCustomFFmpegAudio.SetChannels(const AValue: Integer);
begin
  FChannels := AValue;
  FreeAndNil(FDecoder);
end;

procedure TCustomFFmpegAudio.Open;
begin
  if FMediaFile <> nil then
    Exit;
  if FFileName = '' then
    raise EFFmpegError.Create('No FileName set');
  if FLib = nil then
    FLib := TFFmpegLibrary.Create(FLibraryFolder, FLicencePolicy);
  FMediaFile := TFFmpegMediaFile.Create(FLib, FFileName);
  FActive := True;
  if Assigned(FOnOpen) then
    try
      FOnOpen(Self);
    except
      on E: Exception do
        ShowHandlerException(E);
    end;
end;

procedure TCustomFFmpegAudio.Close;
var
  WasOpen: Boolean;
begin
  FreeThread;
  FreeAndNil(FDecoder);
  WasOpen := FMediaFile <> nil;
  FreeAndNil(FMediaFile);
  FActive := False;
  if WasOpen and Assigned(FOnClose) and not (csDestroying in ComponentState) then
    try
      FOnClose(Self);
    except
      on E: Exception do
        ShowHandlerException(E);
    end;
end;

function TCustomFFmpegAudio.Decode(AStart, AEnd: Double): TFFmpegSamples;
begin
  if FMediaFile = nil then
    raise EFFmpegError.Create('No file is open (set Active)');
  if FBusy then
    raise EFFmpegError.Create('A DecodeAsync is running');
  if FDecoder = nil then
    FDecoder := TFFmpegAudioDecoder.Create(FMediaFile, -1, FSampleRate, FChannels);
  Result := FDecoder.Read(AStart, AEnd);
end;

function TCustomFFmpegAudio.DecodeChapter(AIndex: Integer): TFFmpegSamples;
var
  Ch: TFFmpegChapterArray;
begin
  Ch := GetChapters;
  if (AIndex < 0) or (AIndex > High(Ch)) then
    raise EFFmpegError.CreateFmt('No chapter %d', [AIndex]);
  Result := Decode(Ch[AIndex].StartTime, Ch[AIndex].EndTime);
end;

procedure TCustomFFmpegAudio.DecodeAsync(AStart, AEnd: Double);
begin
  if FMediaFile = nil then
    raise EFFmpegError.Create('No file is open (set Active)');
  if FBusy then
    raise EFFmpegError.Create('A DecodeAsync is running');
  FreeThread;
  FBusy := True;
  FThread := TFFmpegDecodeThread.Create(Self, FFileName, AStart, AEnd, FSampleRate, FChannels);
  FThread.Start;
end;

procedure TCustomFFmpegAudio.CancelDecode;
begin
  if FThread <> nil then
    FThread.Cancel;
end;

procedure TCustomFFmpegAudio.DecodeDone(AThread: TFFmpegDecodeThread);
var
  Samples: TFFmpegSamples;
  Error: string;
  StartS, EndS: Double;
begin
  // A handler may start the next decode, close the file or change it, and
  // each of those frees AThread: take everything out of it first, and touch
  // neither it nor Self's fields once a handler has run.
  Samples := AThread.FSamples;
  AThread.FSamples := nil;
  Error := AThread.FError;
  StartS := AThread.FStart;
  EndS := AThread.FEnd;
  FBusy := False;
  try
    if Error <> '' then
    begin
      if Assigned(FOnDecodeFailed) then
        FOnDecodeFailed(Self, Error);
    end
    else if Assigned(FOnDecoded) then
      FOnDecoded(Self, Samples, StartS, EndS);
  except
    on E: Exception do
      ShowHandlerException(E);
  end;
end;

function TCustomFFmpegAudio.CoverArt(out AData: TBytes; out AExtension: string): Boolean;
begin
  AData := nil;
  AExtension := '';
  Result := (FMediaFile <> nil) and FMediaFile.CoverArt(AData, AExtension);
end;

function TCustomFFmpegAudio.GetStreams: TFFmpegStreamInfoArray;
begin
  if FMediaFile = nil then
    Result := nil
  else
    Result := FMediaFile.Streams;
end;

function TCustomFFmpegAudio.GetChapters: TFFmpegChapterArray;
begin
  if FMediaFile = nil then
    Result := nil
  else
    Result := FMediaFile.Chapters;
end;

function TCustomFFmpegAudio.GetTags: TFFmpegTagArray;
begin
  if FMediaFile = nil then
    Result := nil
  else
    Result := FMediaFile.Tags;
end;

function TCustomFFmpegAudio.GetDuration: Double;
begin
  if FMediaFile = nil then
    Result := 0
  else
    Result := FMediaFile.Duration;
end;

function TCustomFFmpegAudio.GetDescription: string;
begin
  if FLib = nil then
    Result := ''
  else
    Result := FLib.Description;
end;

end.
