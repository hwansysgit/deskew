library deskewDll;

{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  RotationDetector in 'RotationDetector.pas',
  CmdLineOptions in 'CmdLineOptions.pas',
  ImageUtils in 'ImageUtils.pas',
  LibUnit in 'LibUnit.pas';

procedure RunDeskew(const input, output: PWideChar); stdcall; export;
begin
  RunDeskew_libMode(input, output);
end;

exports
  RunDeskew;

begin
{$IFDEF DEBUG}
{$IFNDEF FPC}
  ReportMemoryLeaksOnShutdown := True;
{$ENDIF}
{$ENDIF}
  System.IsMultiThread := True;
end.

