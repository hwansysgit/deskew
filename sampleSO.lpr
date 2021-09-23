program sampleSO;

{$mode objfpc}{$H+}

uses
  Classes,dynlibs
  { you can add units after this };

type
  TMyProc=procedure(const input, output: PChar);

var
  MyLibC: TLibHandle = dynlibs.NilHandle;
  MyProc: TMyProc;
begin
  MyLibC := LoadLibrary('./libdeskewDll.so');
  if MyLibC = dynlibs.NilHandle then
  begin
       Writeln('Problem found');
       Exit;
  end;

  MyProc := TMyProc(dynlibs.GetProcedureAddress(MyLibC, PChar('RunDeskew')));
  if MyProc = nil then Exit else WriteLn('ProC Found');

  MyProc(PChar('../TestImages/5.png'), PChar('./outSO.png'));

  Writeln(GetLoadErrorStr);
  Exit;
end.

