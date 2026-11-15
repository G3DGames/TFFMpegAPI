{ FFmpegConsole - console demo and smoke test of the FFmpeg binding, without
  the component (TFFmpegLibrary, TFFmpegMediaFile, TFFmpegAudioDecoder
  directly).

  Usage:
    FFmpegConsole --check [--ffmpeg FOLDER] [--lgpl | --redistributable] [--video]
                         (load the libraries: versions, licence, build options)
    FFmpegConsole <file> [options]          (streams, chapters, tags)
    FFmpegConsole <file> --wav OUT.wav [--start S] [--end S] [--chapter N]
                         [--rate HZ] [--channels N]
                         (decode a range, or chapter N from 1, to 16-bit WAV)
    FFmpegConsole <file> --cover NAME      (write the cover art as NAME.jpg / .png)
    FFmpegConsole <file> --play [--start S] [--seconds N]
                         (play it on the sound output - WASAPI on Windows,
                         PulseAudio on Linux, silent elsewhere - printing the
                         player's clock once a second; N seconds, or to the end)
  --ffmpeg FOLDER: where FFmpeg's libraries are (default: next to the
           executable, then the system search path).
  --lgpl: accept LGPL builds only; --redistributable: refuse non-free builds.
  --video: also load swscale (video support; not used by this demo).

  It logs every step with its values. Like any user project it lists only
  its own sources: the library comes from the runtime package FFmpegAPI
  (Delphi's Dcp folder) - build it first. }
program FFmpegConsole;

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}{$ifdef UNIX}
  cthreads,   // FPC on Linux / macOS: threads (the player's) need it first
  {$endif}{$endif}
  SysUtils,
  Classes,
  DateUtils,
  // the library: DCUs of the runtime package FFmpegAPI (Delphi's Dcp folder)
  FFmpeg.API,
  FFmpeg.Media,
  FFmpeg.AudioOut,
  FFmpeg.Player;

const
  { Bytes per 16-bit sample. }
  BYTES_PER_SAMPLE = 2;
  { Largest 16-bit sample. }
  MAX_S16 = 32767;

{ "h:mm:ss.mmm" of ASeconds. }
function TimeText(ASeconds: Double): string;
var
  Ms: Int64;
begin
  if ASeconds < 0 then
    ASeconds := 0;
  Ms := Round(ASeconds * 1000);
  Result := Format('%d:%.2d:%.2d.%.3d', [Ms div 3600000, (Ms div 60000) mod 60, (Ms div 1000) mod 60,
    Ms mod 1000]);
end;

{ Writes interleaved float samples as a 16-bit PCM WAV file. }
procedure WriteWav(const AFileName: string; const ASamples: TFFmpegSamples; ARate, AChannels: Integer);
var
  S: TFileStream;
  Data: array of SmallInt;
  I: Integer;
  V: Single;
  U32: UInt32;
  U16: UInt16;

  procedure Put(const ATag: AnsiString);
  begin
    S.WriteBuffer(ATag[1], 4);
  end;

begin
  Data := nil;
  SetLength(Data, Length(ASamples));
  for I := 0 to High(ASamples) do
  begin
    V := ASamples[I];
    if V > 1 then
      V := 1
    else if V < -1 then
      V := -1;
    Data[I] := Round(V * MAX_S16);
  end;
  S := TFileStream.Create(AFileName, fmCreate);
  try
    Put('RIFF');
    U32 := 36 + Length(Data) * BYTES_PER_SAMPLE;
    S.WriteBuffer(U32, 4);
    Put('WAVE');
    Put('fmt ');
    U32 := 16;
    S.WriteBuffer(U32, 4);
    U16 := 1;                                   // PCM
    S.WriteBuffer(U16, 2);
    U16 := AChannels;
    S.WriteBuffer(U16, 2);
    U32 := ARate;
    S.WriteBuffer(U32, 4);
    U32 := ARate * AChannels * BYTES_PER_SAMPLE;  // bytes per second
    S.WriteBuffer(U32, 4);
    U16 := AChannels * BYTES_PER_SAMPLE;        // block align
    S.WriteBuffer(U16, 2);
    U16 := 8 * BYTES_PER_SAMPLE;                // bits per sample
    S.WriteBuffer(U16, 2);
    Put('data');
    U32 := Length(Data) * BYTES_PER_SAMPLE;
    S.WriteBuffer(U32, 4);
    if Length(Data) > 0 then
      S.WriteBuffer(Data[0], Length(Data) * BYTES_PER_SAMPLE);
  finally
    S.Free;
  end;
end;

var
  Lib: TFFmpegLibrary;
  F: TFFmpegMediaFile;
  Dec: TFFmpegAudioDecoder;
  Samples: TFFmpegSamples;
  Policy: TFFmpegLicencePolicy;
  Arg, MediaName, Folder, WavFile, CoverName, Ext, Extra: string;
  StartS, EndS: Double;
  Chapter, Rate, Channels, I: Integer;
  CheckOnly, WithVideo: Boolean;
  Cover: TBytes;
  Started: TDateTime;
  S: TFileStream;
  FS: TFormatSettings;
  PlayIt: Boolean;
  PlaySeconds: Double;
  Player: TFFmpegAudioPlayer;
begin
  ExitCode := 1;
  Lib := nil;
  F := nil;
  try
    try
      FS := FormatSettings;
      FS.DecimalSeparator := '.';
      Policy := flpAny;
      Folder := '';
      MediaName := '';
      WavFile := '';
      CoverName := '';
      StartS := 0;
      EndS := 0;
      Chapter := 0;
      Rate := 0;
      Channels := 0;
      CheckOnly := False;
      WithVideo := False;
      PlayIt := False;
      PlaySeconds := 0;
      I := 1;
      while I <= ParamCount do
      begin
        Arg := ParamStr(I);
        Inc(I);
        if Arg = '--check' then
          CheckOnly := True
        else if Arg = '--lgpl' then
          Policy := flpLGPL
        else if Arg = '--redistributable' then
          Policy := flpRedistributable
        else if Arg = '--video' then
          WithVideo := True
        else if Arg = '--play' then
          PlayIt := True
        else if (Arg = '--seconds') and (I <= ParamCount) then
        begin
          PlaySeconds := StrToFloat(ParamStr(I), FS);
          Inc(I);
        end
        else if (Arg = '--ffmpeg') and (I <= ParamCount) then
        begin
          Folder := ParamStr(I);
          Inc(I);
        end
        else if (Arg = '--wav') and (I <= ParamCount) then
        begin
          WavFile := ParamStr(I);
          Inc(I);
        end
        else if (Arg = '--cover') and (I <= ParamCount) then
        begin
          CoverName := ParamStr(I);
          Inc(I);
        end
        else if (Arg = '--start') and (I <= ParamCount) then
        begin
          StartS := StrToFloat(ParamStr(I), FS);
          Inc(I);
        end
        else if (Arg = '--end') and (I <= ParamCount) then
        begin
          EndS := StrToFloat(ParamStr(I), FS);
          Inc(I);
        end
        else if (Arg = '--chapter') and (I <= ParamCount) then
        begin
          Chapter := StrToInt(ParamStr(I));
          Inc(I);
        end
        else if (Arg = '--rate') and (I <= ParamCount) then
        begin
          Rate := StrToInt(ParamStr(I));
          Inc(I);
        end
        else if (Arg = '--channels') and (I <= ParamCount) then
        begin
          Channels := StrToInt(ParamStr(I));
          Inc(I);
        end
        else if (Length(Arg) > 1) and (Arg[1] = '-') then
        begin
          WriteLn(ErrOutput, 'Unknown option ', Arg, ' (run without arguments for the usage)');
          Exit;
        end
        else if MediaName = '' then
          MediaName := Arg
        else
        begin
          WriteLn(ErrOutput, 'Unexpected argument ', Arg);
          Exit;
        end;
      end;
      if not CheckOnly and (MediaName = '') then
      begin
        WriteLn('Usage: FFmpegConsole --check [--ffmpeg FOLDER] [--lgpl | --redistributable] [--video]');
        WriteLn('       FFmpegConsole <file> [--ffmpeg FOLDER]');
        WriteLn('       FFmpegConsole <file> --wav OUT.wav [--start S] [--end S] [--chapter N] [--rate HZ] [--channels N]');
        WriteLn('       FFmpegConsole <file> --cover NAME');
        WriteLn('       FFmpegConsole <file> --play [--start S] [--seconds N]');
        Exit;
      end;

      Lib := TFFmpegLibrary.Create(Folder, Policy, WithVideo);
      WriteLn(Lib.Description);
      WriteLn('Licence: ', Lib.Licence);
      if Lib.Warning <> '' then
        WriteLn('WARNING: ', Lib.Warning);
      WriteLn('Build options: ', Lib.Configuration);
      if CheckOnly then
      begin
        ExitCode := 0;
        Exit;
      end;

      F := TFFmpegMediaFile.Create(Lib, MediaName);
      WriteLn(Format('File %s: %s, %d stream(s), %d chapter(s), %d tag(s), %d kb/s', [MediaName,
        TimeText(F.Duration), Length(F.Streams), Length(F.Chapters), Length(F.Tags), F.BitRate div 1000]));
      for I := 0 to High(F.Streams) do
        with F.Streams[I] do
        begin
          Extra := '';
          case Kind of
            fmkAudio:
              Extra := Format('%d Hz, %d channel(s), %s', [SampleRate, Channels, SampleFormat]);
            fmkVideo:
              if IsCoverArt then
                Extra := Format('cover art, %dx%d', [Width, Height])
              else
                Extra := Format('%dx%d, %.3f fps, %s', [Width, Height, FrameRate, PixelFormat]);
          end;
          if Language <> '' then
            Extra := Extra + ' [' + Language + ']';
          if Title <> '' then
            Extra := Extra + ' "' + Title + '"';
          WriteLn(Format('  stream %d  %s  %s  %s', [Index, FFmpegMediaKindName(Kind), CodecName, Extra]));
        end;
      for I := 0 to High(F.Chapters) do
        WriteLn(Format('  chapter %d  %s --> %s  %s', [I + 1, TimeText(F.Chapters[I].StartTime),
          TimeText(F.Chapters[I].EndTime), F.Chapters[I].Title]));
      for I := 0 to High(F.Tags) do
        WriteLn(Format('  tag  %s = %s', [F.Tags[I].Key, Copy(F.Tags[I].Value, 1, 100)]));

      if CoverName <> '' then
      begin
        if F.CoverArt(Cover, Ext) then
        begin
          S := TFileStream.Create(CoverName + Ext, fmCreate);
          try
            S.WriteBuffer(Cover[0], Length(Cover));
          finally
            S.Free;
          end;
          WriteLn(Format('Cover art written to %s (%d bytes)', [CoverName + Ext, Length(Cover)]));
        end
        else
          WriteLn('No cover art');
      end;

      if WavFile <> '' then
      begin
        if Chapter > 0 then
        begin
          if Chapter > Length(F.Chapters) then
            raise EFFmpegError.CreateFmt('No chapter %d (the file has %d)', [Chapter, Length(F.Chapters)]);
          StartS := F.Chapters[Chapter - 1].StartTime;
          EndS := F.Chapters[Chapter - 1].EndTime;
        end;
        Dec := TFFmpegAudioDecoder.Create(F, -1, Rate, Channels);
        try
          Started := Now;
          Samples := Dec.Read(StartS, EndS);
          WriteLn(Format('Decoded %s --> %s: %d frames at %d Hz, %d channel(s), %d decode error(s), in %d ms',
            [TimeText(StartS), TimeText(EndS), Length(Samples) div Dec.Channels, Dec.SampleRate, Dec.Channels,
             Dec.DecodeErrors, MilliSecondsBetween(Now, Started)]));
          WriteWav(WavFile, Samples, Dec.SampleRate, Dec.Channels);
          WriteLn('WAV written to ', WavFile);
        finally
          Dec.Free;
        end;
      end;
      if PlayIt then
      begin
        Player := TFFmpegAudioPlayer.Create(Lib);
        try
          WriteLn('Sound output: ', Player.Output.Description);
          if Player.OutputNote <> '' then
            WriteLn('NOTE: ', Player.OutputNote);
          Player.Open(MediaName);
          Player.Play(StartS);
          Started := Now;
          while not Player.Ended and ((PlaySeconds <= 0) or (MilliSecondsBetween(Now, Started) < PlaySeconds * 1000)) do
          begin
            Sleep(1000);
            WriteLn(Format('  %s  (buffered %.2f s, underruns %d)', [TimeText(Player.Position),
              Player.Output.Buffered, Player.Output.Underruns]));
          end;
          if Player.LastError <> '' then
            WriteLn('ERROR: ', Player.LastError);
          WriteLn(Format('Stopped at %s', [TimeText(Player.Position)]));
        finally
          Player.Free;
        end;
      end;
      ExitCode := 0;
    except
      on E: Exception do
        WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
    end;
  finally
    F.Free;
    Lib.Free;
  end;
end.
