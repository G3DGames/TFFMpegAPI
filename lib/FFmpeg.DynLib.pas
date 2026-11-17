{ @abstract(Cross-platform, cross-compiler loading of dynamic libraries
  (DLL / .so / .dylib).)

  @link(TFFmpegDynLib) wraps one loaded library. It follows the approach of
  Castle Game Engine's TDynLib (one object per library, a selectable policy
  for missing symbols, a Load that can raise or return nil) with these
  differences:

  @unorderedList(
    @item(Library search covers the executable's folder and, on macOS, the
      app bundle's Contents/MacOS and Contents/Frameworks folders before the
      operating-system search path. Linux dlopen does not look next to the
      executable unless the binary has an $ORIGIN rpath.)
    @item(Failures report every path tried and the OS error message.)
    @item(Warnings go to an event (@link(TFFmpegDynLib.OnWarning)), so there is
      no dependency on any logging framework.)
    @item(Symbols are looked up by @code(string); the platform-specific
      conversion is done here.)
    @item(Missing optional symbols are collected in
      @link(TFFmpegDynLib.MissingSymbols) for diagnostics.)
  )

  Compiles with Delphi (Windows, macOS, Linux) and Free Pascal.

  @bold(Important:) procedural variables bound from a library dangle once the
  library is freed. Owners of such variables must clear them before (or
  immediately after) freeing the @link(TFFmpegDynLib) - see
  @code(TFFmpegLibrary.Destroy) for the pattern.

  Adapted from TSteamDynLib of TSteamAPI (Steamworks.DynLib), same author
  and conventions; only names and examples differ.

  Example:
  @longCode(#
  var
    Lib: TFFmpegDynLib;
    avutil_license: function: PAnsiChar; cdecl;
  begin
    Lib := TFFmpegDynLib.Load('avutil-60.dll', False);
    if Lib = nil then
      Exit; // not installed
    try
      Lib.Bind(avutil_license, 'avutil_license');
      ...
    finally
      avutil_license := nil;
      FreeAndNil(Lib);
    end;
  end;
  #)
}
unit FFmpeg.DynLib;

{$I FFmpeg.inc}

interface

uses
  SysUtils, Classes
  {$ifdef FPC}, DynLibs{$endif}
  {$ifdef MSWINDOWS}, Windows{$endif}
  {$if not defined(MSWINDOWS) and not defined(FPC)}, Posix.Dlfcn{$endif};

type
  { Native library handle. }
  TFFmpegLibHandle = {$ifdef FPC}TLibHandle{$else}HMODULE{$endif};

const
  { Value of a @link(TFFmpegLibHandle) that does not refer to a library. }
  InvalidFFmpegLibHandle = {$ifdef FPC}NilHandle{$else}0{$endif};

type
  { Raised when a library cannot be loaded, or a required symbol is missing
    while @link(TFFmpegDynLib.SymbolErrorMode) is @link(semRaise). }
  EFFmpegDynLibError = class(Exception);

  { What @link(TFFmpegDynLib.Symbol) and @link(TFFmpegDynLib.Bind) do when a
    required symbol is missing. }
  TFFmpegSymbolErrorMode = (
    { Raise @link(EFFmpegDynLibError). }
    semRaise,
    { Return @nil silently. }
    semReturnNil,
    { Fire @link(TFFmpegDynLib.OnWarning) and return @nil. }
    semWarnAndReturnNil
  );

  { Event used for non-fatal library problems. }
  TFFmpegDynLibWarningEvent = procedure(Sender: TObject; const AMessage: string) of object;

  { One loaded dynamic library. Create it with @link(Load) or @link(LoadFirst);
    @link(Destroy) unloads it. }
  TFFmpegDynLib = class
  private
    { Backing field of @link(Handle). }
    FHandle: TFFmpegLibHandle;
    { Backing field of @link(Name). }
    FName: string;
    { Backing field of @link(FileName). }
    FFileName: string;
    { Backing field of @link(SymbolErrorMode). }
    FSymbolErrorMode: TFFmpegSymbolErrorMode;
    { Backing field of @link(MissingSymbols). }
    FMissing: TStringList;
    { Backing field of @link(OnWarning). }
    FOnWarning: TFFmpegDynLibWarningEvent;
    { Loads one file. @returns(@false with AError set on failure.) }
    class function TryLoadFile(const AFileName: string; out AHandle: TFFmpegLibHandle;
      out AError: string): Boolean; static;
    { GetProcAddress without any error handling. }
    function RawSymbol(const AName: string): Pointer;
    { The full file name of loaded library AHandle (Windows: from the
      loader, so a library found on PATH gets its folder); AFallback where
      that is not known. }
    class function LoadedFileName(AHandle: TFFmpegLibHandle; const AFallback: string): string; static;
    { Raises @link(OnWarning) if assigned. }
    procedure Warn(const AMessage: string);
  public
    { Wraps an already loaded handle. Normally use @link(Load) instead.
      @param(AName  Name the library was requested by.)
      @param(AFileName  Full file name, if known.)
      @param(AHandle  Valid handle; ownership passes to this object.)
      @raises(EFFmpegDynLibError if AHandle is invalid.) }
    constructor Create(const AName, AFileName: string; AHandle: TFFmpegLibHandle);

    { Unloads the library. Procedural variables bound from it become invalid. }
    destructor Destroy; override;

    { Candidate file names tried, in order, when loading AName.
      If AName contains a path only AName itself is returned. Otherwise:
      the executable's folder (made absolute), (macOS) the bundle's Contents/MacOS and
      Contents/Frameworks, then the bare name for the OS search path. }
    class function CandidatePaths(const AName: string): TStringList; static;

    { Loads a library.
      @param(AName  File name with or without a path, e.g. @code('avutil-60.dll').)
      @param(ARaiseOnError  If @true a failure raises @link(EFFmpegDynLibError),
        otherwise @nil is returned.)
      @returns(The loaded library, or @nil (only when ARaiseOnError is @false).)
      @raises(EFFmpegDynLibError when the library cannot be loaded and ARaiseOnError is @true.) }
    class function Load(const AName: string; ARaiseOnError: Boolean = True): TFFmpegDynLib;

    { Loads the first library of ANames that can be loaded.
      Useful when a library ships under several names. }
    class function LoadFirst(const ANames: array of string; ARaiseOnError: Boolean = True): TFFmpegDynLib;

    { Address of an exported symbol, honouring @link(SymbolErrorMode) when it
      is missing.
      @raises(EFFmpegDynLibError if missing and SymbolErrorMode = semRaise.) }
    function Symbol(const AName: string): Pointer;

    { @true if the library exports AName. Never raises, never warns. }
    function HasSymbol(const AName: string): Boolean;

    { Binds an export into a procedural variable.

      @param(AProc  Procedural variable (passed untyped) that receives the address.)
      @param(AName  Export name.)
      @param(ARequired  When @true a missing symbol is handled by
        @link(SymbolErrorMode); when @false it silently yields @nil and is
        recorded in @link(MissingSymbols).)
      @returns(@true if the symbol was found.)

      @longCode(#
      var
        avutil_version: function: UInt32; cdecl;
      ...
      Lib.Bind(avutil_version, 'avutil_version');
      #) }
    function Bind(var AProc; const AName: string; ARequired: Boolean = True): Boolean;

    { Name the library was requested by. }
    property Name: string read FName;
    { File the library was loaded from: the full path (on Windows also for a
      library found on PATH; elsewhere the bare name in that case). }
    property FileName: string read FFileName;
    { Native handle. }
    property Handle: TFFmpegLibHandle read FHandle;
    { Policy for missing required symbols. Default @link(semRaise). }
    property SymbolErrorMode: TFFmpegSymbolErrorMode read FSymbolErrorMode write FSymbolErrorMode default semRaise;
    { Symbols requested with @link(Bind) or @link(Symbol) that were not found. }
    property MissingSymbols: TStringList read FMissing;
    { Fired for @link(semWarnAndReturnNil) and non-fatal unload problems. }
    property OnWarning: TFFmpegDynLibWarningEvent read FOnWarning write FOnWarning;
  end;

implementation

{ TFFmpegDynLib }

constructor TFFmpegDynLib.Create(const AName, AFileName: string; AHandle: TFFmpegLibHandle);
begin
  inherited Create;
  if AHandle = InvalidFFmpegLibHandle then
    raise EFFmpegDynLibError.CreateFmt('Invalid handle for library "%s"', [AName]);
  FName := AName;
  FFileName := AFileName;
  FHandle := AHandle;
  FSymbolErrorMode := semRaise;
  FMissing := TStringList.Create;
  FMissing.Sorted := True;
  FMissing.Duplicates := dupIgnore;
end;

destructor TFFmpegDynLib.Destroy;
var
  Ok: Boolean;
begin
  if FHandle <> InvalidFFmpegLibHandle then
  begin
    {$ifdef FPC}
    Ok := DynLibs.UnloadLibrary(FHandle);
    {$else}
      {$ifdef MSWINDOWS}
      Ok := Windows.FreeLibrary(FHandle);
      {$else}
      // Delphi on POSIX: FreeLibrary's result is unreliable (also noted by CGE)
      FreeLibrary(FHandle);
      Ok := True;
      {$endif}
    {$endif}
    if not Ok then
      Warn(Format('Unloading library "%s" failed', [FName]));
    FHandle := InvalidFFmpegLibHandle;
  end;
  FMissing.Free;
  inherited;
end;

procedure TFFmpegDynLib.Warn(const AMessage: string);
begin
  if Assigned(FOnWarning) then
    FOnWarning(Self, AMessage);
end;

class function TFFmpegDynLib.TryLoadFile(const AFileName: string; out AHandle: TFFmpegLibHandle;
  out AError: string): Boolean;
begin
  AError := '';
  {$ifdef FPC}
  AHandle := DynLibs.LoadLibrary(AFileName);
  if AHandle = InvalidFFmpegLibHandle then
    AError := DynLibs.GetLoadErrorStr;
  {$else}
    {$ifdef MSWINDOWS}
    AHandle := Windows.LoadLibrary(PChar(AFileName));
    if AHandle = InvalidFFmpegLibHandle then
      AError := SysErrorMessage(GetLastError);
    {$else}
    AHandle := LoadLibrary(PChar(AFileName));
    if AHandle = InvalidFFmpegLibHandle then
      AError := string(UTF8String(dlerror));
    {$endif}
  {$endif}
  Result := AHandle <> InvalidFFmpegLibHandle;
end;

class function TFFmpegDynLib.LoadedFileName(AHandle: TFFmpegLibHandle; const AFallback: string): string;
{$ifdef MSWINDOWS}
var
  Buf: array[0..MAX_PATH] of Char;
  N: DWORD;
{$endif}
begin
  Result := AFallback;
  {$ifdef MSWINDOWS}
  N := Windows.GetModuleFileName(HMODULE(AHandle), PChar(@Buf[0]), Length(Buf));
  if (N > 0) and (N < DWORD(Length(Buf))) then
    SetString(Result, PChar(@Buf[0]), N);
  {$endif}
end;

class function TFFmpegDynLib.CandidatePaths(const AName: string): TStringList;
var
  ExeDir: string;
begin
  Result := TStringList.Create;
  if ExtractFilePath(AName) <> '' then
  begin
    Result.Add(AName);
    Exit;
  end;
  // ParamStr(0) is argv[0] on Linux / macOS and may be relative to the
  // current directory ('FFmpegConsole/FFmpegConsole'): make it absolute so the
  // path tried, loaded and logged is exact.
  ExeDir := IncludeTrailingPathDelimiter(ExpandFileName(ExtractFilePath(ParamStr(0))));
  Result.Add(ExeDir + AName);
  {$ifdef FFMPEG_MACOS}
  // <App>.app/Contents/MacOS/<exe>  ->  also try Contents/Frameworks
  Result.Add(ExpandFileName(ExeDir + '..' + PathDelim + 'Frameworks' + PathDelim + AName));
  {$endif}
  Result.Add(AName); // OS search path
end;

class function TFFmpegDynLib.Load(const AName: string; ARaiseOnError: Boolean): TFFmpegDynLib;
var
  Paths: TStringList;
  Errors: string;
  I: Integer;
  H: TFFmpegLibHandle;
  Err: string;
begin
  Result := nil;
  Errors := '';
  {$ifdef FFMPEG_UNSUPPORTED_PLATFORM}
  if ARaiseOnError then
    raise EFFmpegDynLibError.CreateFmt('Dynamic library "%s" is not supported on this platform', [AName]);
  Exit;
  {$endif}
  Paths := CandidatePaths(AName);
  try
    for I := 0 to Paths.Count - 1 do
    begin
      // Explicit paths that do not exist are listed but not loaded;
      // the bare name is always tried (OS search path). macOS 11 and later
      // keep the system's libraries and frameworks in the dyld shared cache,
      // not on disk: a /System/Library/ or /usr/lib/ path is tried anyway
      if (ExtractFilePath(Paths[I]) <> '') and not FileExists(Paths[I])
        {$ifdef FFMPEG_MACOS} and not ((Pos('/System/Library/', Paths[I]) = 1) or
        (Pos('/usr/lib/', Paths[I]) = 1)){$endif} then
      begin
        Errors := Errors + sLineBreak + '  ' + Paths[I] + ': not present';
        Continue;
      end;
      if TryLoadFile(Paths[I], H, Err) then
        Exit(TFFmpegDynLib.Create(AName, LoadedFileName(H, Paths[I]), H));
      Errors := Errors + sLineBreak + '  ' + Paths[I];
      if Err <> '' then
        Errors := Errors + ': ' + Err;
    end;
  finally
    Paths.Free;
  end;
  if ARaiseOnError then
    raise EFFmpegDynLibError.CreateFmt('Cannot load dynamic library "%s". Tried:%s', [AName, Errors]);
end;

class function TFFmpegDynLib.LoadFirst(const ANames: array of string; ARaiseOnError: Boolean): TFFmpegDynLib;
var
  I: Integer;
  Msg: string;
begin
  Msg := '';
  for I := Low(ANames) to High(ANames) do
  begin
    try
      Result := Load(ANames[I], True);
      Exit;
    except
      on E: EFFmpegDynLibError do
        Msg := Msg + sLineBreak + E.Message;
    end;
  end;
  Result := nil;
  if ARaiseOnError then
    raise EFFmpegDynLibError.Create('None of the candidate libraries could be loaded:' + Msg);
end;

function TFFmpegDynLib.RawSymbol(const AName: string): Pointer;
begin
  {$ifdef FPC}
  Result := DynLibs.GetProcedureAddress(FHandle, AnsiString(AName));
  {$else}
    {$ifdef MSWINDOWS}
    Result := Windows.GetProcAddress(FHandle, PAnsiChar(AnsiString(AName)));
    {$else}
    Result := GetProcAddress(FHandle, PChar(AName));
    {$endif}
  {$endif}
end;

function TFFmpegDynLib.HasSymbol(const AName: string): Boolean;
begin
  Result := RawSymbol(AName) <> nil;
end;

function TFFmpegDynLib.Symbol(const AName: string): Pointer;
begin
  Result := RawSymbol(AName);
  if Result = nil then
  begin
    FMissing.Add(AName);
    case FSymbolErrorMode of
      semRaise:
        raise EFFmpegDynLibError.CreateFmt('Symbol "%s" not found in library "%s"', [AName, FFileName]);
      semWarnAndReturnNil:
        Warn(Format('Symbol "%s" not found in library "%s"', [AName, FFileName]));
      semReturnNil: ;
    end;
  end;
end;

function TFFmpegDynLib.Bind(var AProc; const AName: string; ARequired: Boolean): Boolean;
begin
  if ARequired then
    Pointer(AProc) := Symbol(AName)
  else
  begin
    Pointer(AProc) := RawSymbol(AName);
    if Pointer(AProc) = nil then
      FMissing.Add(AName);
  end;
  Result := Pointer(AProc) <> nil;
end;

end.
