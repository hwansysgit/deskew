{
  Deskew
  by Marek Mauder
  https://galfar.vevb.net/deskew
  https://github.com/galfar/deskew
  - - - - -
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
}
library deskew;

{$mode objfpc} {$H+}

uses
  RotationDetector in 'RotationDetector.pas',
  CmdLineOptions in 'CmdLineOptions.pas',
  ImageUtils in 'ImageUtils.pas',
  MainUnit in 'MainUnit.pas';

function PWToUtf8(const str: PWideChar): string;
begin
  result := UTF8Encode(WideString(str));
end;

procedure Run(const input : PChar ; const output:PChar); stdcall; export;
begin
  RunDeskew2(input,output);
end;

exports
  Run;

begin
end.


