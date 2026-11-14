(* @abstract(@link(TFFmpegAPI) for FireMonkey - the non-visual component that
  opens media files through FFmpeg and decodes their audio.)

  Drop one on a form (palette page "FFmpegAPI"), set
  @link(TFFmpegAPI.FileName) and @link(TFFmpegAPI.Active); the streams,
  chapters, tags and cover art are then there. Decode / DecodeChapter work
  on the calling thread, DecodeAsync on a worker thread with OnDecoded on
  the main thread. Everything except the exception display lives in the
  framework-free @code(TCustomFFmpegAudio) (FFmpeg.Components).
  @longCode(#
  procedure TfrmMain.btnOpenClick(Sender: TObject);
  begin
    FFmpegAPI1.FileName := edFile.Text;
    FFmpegAPI1.SampleRate := 16000;   // mono 16 kHz, e.g. for whisper.cpp
    FFmpegAPI1.Channels := 1;
    FFmpegAPI1.Active := True;
    FFmpegAPI1.DecodeAsync(0, 60);    // the first minute
  end;
  #) *)
unit FFmpeg.FMX;

{$I ..\lib\FFmpeg.inc}

interface

uses
  SysUtils, Classes, FMX.Types, FMX.Forms,
  FFmpeg.API, FFmpeg.Media, FFmpeg.Components;

type
  { FireMonkey TFFmpegAPI: @code(TCustomFFmpegAudio) with its properties
    published and handler exceptions shown by Application.ShowException. }
  [ComponentPlatformsAttribute(FFMPEG_COMPONENT_PLATFORMS)]
  TFFmpegAPI = class(TCustomFFmpegAudio)
  protected
    { Application.ShowException (Application.HandleException would show
      ExceptObject, which is nil outside an except block). }
    procedure ShowHandlerException(E: Exception); override;
  published
    { Opens the file. At design time the value is only stored. }
    property Active;
    { Folder of FFmpeg's libraries ('' = next to the executable). }
    property LibraryFolder;
    { Which FFmpeg builds are accepted (any, redistributable, LGPL only). }
    property LicencePolicy;
    { The media file. }
    property FileName;
    { Samples per second of decoded audio (0 = the stream's). }
    property SampleRate;
    { Channels of decoded audio (0 = the stream's; 1 = mono). }
    property Channels;
    { The file was opened. }
    property OnOpen;
    { Opening failed. }
    property OnOpenFailed;
    { The file was closed. }
    property OnClose;
    { A DecodeAsync finished (main thread). }
    property OnDecoded;
    { A DecodeAsync failed (main thread). }
    property OnDecodeFailed;
  end;

implementation

procedure TFFmpegAPI.ShowHandlerException(E: Exception);
begin
  if Application <> nil then
    Application.ShowException(E);
end;

end.
