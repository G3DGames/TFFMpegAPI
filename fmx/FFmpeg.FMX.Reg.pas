{ @abstract(Design-time registration of the FFmpeg FMX component.)

  Compiled only into the design-time package dclFFmpegAPIFMX, which puts
  @code(TFFmpegAPI) (FireMonkey) on the "FFmpegAPI" page of the tool palette. }
unit FFmpeg.FMX.Reg;

{$I ..\lib\FFmpeg.inc}

interface

{ Registers the FMX TFFmpegAPI on the "FFmpegAPI" palette page. }
procedure Register;

implementation

uses
  Classes, DesignIntf, DesignEditors, FMX.Types, FFmpeg.FMX;

type
  { Adds the units the IDE-generated TFFmpegAPI event handlers need
    (TFFmpegSamples, ...) to the form's uses clause. }
  TFFmpegSelectionEditor = class(TSelectionEditor)
  public
    { Names FFmpeg.API, FFmpeg.Media and FFmpeg.Components. }
    procedure RequiresUnits(Proc: TGetStrProc); override;
  end;

procedure TFFmpegSelectionEditor.RequiresUnits(Proc: TGetStrProc);
begin
  Proc('FFmpeg.API');
  Proc('FFmpeg.Media');
  Proc('FFmpeg.Components');
end;

procedure Register;
begin
  // FMX class group: lets a VCL TFFmpegAPI of the same name be installed as
  // well, as with FMX / VCL TButton.
  GroupDescendentsWith(TFFmpegAPI, TFmxObject);
  RegisterComponents('FFmpegAPI', [TFFmpegAPI]);
  RegisterSelectionEditor(TFFmpegAPI, TFFmpegSelectionEditor);
end;

end.
