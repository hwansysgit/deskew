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
unit MainUnit;

{$I ImagingOptions.inc}

interface

procedure RunDeskew;
procedure RunDeskew_libMode(intput , output : string);

implementation

uses
  Types,
  SysUtils,
  Classes,
  Winapi.Windows,
  vcl.Dialogs,
  ImagingTypes,
  Imaging,
  ImagingClasses,
  ImagingFormats,
  ImagingUtility,
  ImagingExtras,
  // Project units
  CmdLineOptions,
  ImageUtils,
  RotationDetector;

const
  SAppTitle = 'Deskew 1.30 (2019-06-07)'
    {$IF Defined(CPUX64)} + ' x64'
    {$ELSEIF Defined(CPUX86)} + ' x86'
    {$ELSEIF Defined(CPUARM)} + ' ARM'
    {$IFEND}
    {$IFDEF DEBUG} + ' (DEBUG)'{$ENDIF}
    + ' by Marek Mauder';
  SAppHome = 'http://galfar.vevb.net/deskew/';

var
  // Program options
  Options: TCmdLineOptions;
  // Input and output image
  InputImage, OutputImage: TSingleImage;

procedure WriteUsage;
var
  InFilter, OutFilter: string;
  I, Count: Integer;
  Fmt: TImageFileFormat;
begin
  InFilter := '';
  OutFilter := '';

  Count := GetFileFormatCount;
  for I := 0 to Count - 1 do
  begin
    Fmt := GetFileFormatAtIndex(I);
    if Fmt.CanLoad then
      InFilter := InFilter + Fmt.Extensions[0] + Iff(I < Count - 1, ', ', '');
    if Fmt.CanSave then
      OutFilter := OutFilter + Fmt.Extensions[0] + Iff(I < Count - 1, ', ', '');
  end;

end;

function FormatNiceNumber(const X: Int64; Width : Integer = 16): string;
var
  FmtStr: string;
begin
  if Width = 0 then
    FmtStr := '%.0n'
  else
    FmtStr := '%' + IntToStr(Width) + '.0n';
  Result := Format(FmtStr, [X * 1.0], GetFormatSettingsForFloats);
end;

var
  Time: Int64;


function DoDeskew: Boolean;
var
  SkewAngle: Double;
  Threshold: Integer;
  ContentRect: TRect;
  Stats: TCalcSkewAngleStats;

  procedure WriteStats;
  begin
  end;

begin
  Result := False;
  Threshold := 0;

  // Clone input image and convert it to 8bit grayscale. This will be our
  // working image.
  OutputImage.Assign(InputImage);
  InputImage.Format := ifGray8;

  // Determine threshold level for black/white pixel classification during skew detection
  case Options.ThresholdingMethod of
    tmExplicit:
      begin
        // Use explicit threshold
        Threshold := Options.ThresholdLevel;
      end;
    tmOtsu:
      begin
        // Determine the threshold automatically
        Time := GetTimeMicroseconds;
        Threshold := OtsuThresholding(InputImage.ImageDataPointer^);
      end;
  end;

  // Determine the content rect - where exactly to detect rotated text
  ContentRect := InputImage.BoundsRect;
  if not IsRectEmpty(Options.ContentRect) then
  begin
    if not IntersectRect(ContentRect, Options.ContentRect, InputImage.BoundsRect) then
      ContentRect := InputImage.BoundsRect;
  end;

  Time := GetTimeMicroseconds;
  SkewAngle := CalcRotationAngle(Options.MaxAngle, Threshold,
    InputImage.Width, InputImage.Height, InputImage.Bits,
    @ContentRect, @Stats);

  if Options.ShowStats then
    WriteStats;

  if ofDetectOnly in Options.OperationalFlags then
    Exit;

  // Check if detected skew angle is higher than "skip" threshold - may not
  // want to do rotation needlessly.
  if Abs(SkewAngle) >= Options.SkipAngle then
  begin
    Result := True;

    // Finally, rotate the image. We rotate the original input image, not the working
    // one so the color space is preserved if possible.

    // Rotation is optimized for Gray8, RGB24, and ARGB32 formats at this time
    if not (OutputImage.Format in ImageUtils.SupportedRotationFormats) then
    begin
      if OutputImage.Format = ifIndex8 then
      begin
        if PaletteHasAlpha(OutputImage.Palette, OutputImage.PaletteEntries) then
          OutputImage.Format := ifA8R8G8B8
        else if PaletteIsGrayScale(OutputImage.Palette, OutputImage.PaletteEntries) then
          OutputImage.Format := ifGray8
        else
          OutputImage.Format := ifR8G8B8;
      end
      else if OutputImage.FormatInfo.HasAlphaChannel then
        OutputImage.Format := ifA8R8G8B8
      else if (OutputImage.Format = ifBinary) or OutputImage.FormatInfo.HasGrayChannel then
        OutputImage.Format := ifGray8
      else
        OutputImage.Format := ifR8G8B8;
    end;

    if (Options.BackgroundColor and $FF000000) <> $FF000000 then
    begin
      // User explicitly requested some alpha in background color
      OutputImage.Format := ifA8R8G8B8;
    end
    else if (OutputImage.Format = ifGray8) and not (
      (GetRedValue(Options.BackgroundColor) = GetGreenValue(Options.BackgroundColor)) and
      (GetBlueValue(Options.BackgroundColor) = GetGreenValue(Options.BackgroundColor))) then
    begin
      // Some non-grayscale background for gray image was requested
      OutputImage.Format := ifR8G8B8;
    end;

    Time := GetTimeMicroseconds;
    ImageUtils.RotateImage(OutputImage.ImageDataPointer^, SkewAngle, Options.BackgroundColor,
      Options.ResamplingFilter, not (ofAutoCrop in Options.OperationalFlags));

  end
  else
    OutputDebugString('Skipping deskewing step, skew angle lower than threshold of ');

  if (Options.ForcedOutputFormat <> ifUnknown) and (OutputImage.Format <> Options.ForcedOutputFormat) then
  begin
    // Force output format. For example Deskew won't automatically
    // save image as binary if the input was binary since it
    // might degrade the output a lot (rotation adds a lot of colors to image).
    OutputImage.Format := Options.ForcedOutputFormat;
    Result := True;
  end;
end;

procedure RunDeskew;

  procedure EnsureOutputLocation(const FileName: string);
  var
    Dir, Path: string;
  begin
    Path := ExpandFileName(FileName);
    Dir := GetFileDir(Path);
    if Dir <> '' then
      ForceDirectories(Dir);
  end;

  procedure CopyFile(const SrcPath, DestPath: string);
  var
    SrcStream, DestStream: TFileStream;
  begin
    if SameText(SrcPath, DestPath) then
      Exit; // No need to copy anything

    SrcStream := TFileStream.Create(SrcPath, fmOpenRead);
    DestStream := TFileStream.Create(DestPath, fmCreate);
    DestStream.CopyFrom(SrcStream, SrcStream.Size);
    DestStream.Free;
    SrcStream.Free;
  end;

  procedure SetImagingOptions;
  begin
    if Options.JpegCompressionQuality <> -1 then
    begin
      Imaging.SetOption(ImagingJpegQuality, Options.JpegCompressionQuality);
      Imaging.SetOption(ImagingTiffJpegQuality, Options.JpegCompressionQuality);
      Imaging.SetOption(ImagingJNGQuality, Options.JpegCompressionQuality);
    end;
    if Options.TiffCompressionScheme <> -1 then
      Imaging.SetOption(ImagingTiffCompression, Options.TiffCompressionScheme);
  end;

var
  Changed: Boolean;
begin
{$IF Defined(FPC) and not Defined(MSWINDOWS)}
  // Flush after WriteLn also when output is redirected to file/pipe
  if Textrec(Output).FlushFunc = nil then
    Textrec(Output).FlushFunc := Textrec(Output).InOutFunc;
{$IFEND}

  OutputDebugString(SAppTitle);
  OutputDebugString(SAppHome);

  Options := TCmdLineOptions.Create;
  InputImage := TSingleImage.Create;
  OutputImage := TSingleImage.Create;

  SetImagingOptions;

  Time := GetTimeMicroseconds;
  InputImage.LoadFromFile('e:\dgb\pngs\Page_5.jpg');

  Changed := DoDeskew();

  GlobalMetadata.CopyLoadedMetaItemsForSaving;
            // Save the output
  OutputImage.SaveToFile('e:\dgb\pngs\Page_5d.jpg');

  Options.Free;
  InputImage.Free;
  OutputImage.Free;

end;

procedure RunDeskew_libMode(intput , output : string);

  function GetAString(indata:string): PChar;
  var
    aString: string;
  begin
    result := StrAlloc(length(indata) + 1);
    StrPCopy(result, aString);
  end;

  procedure FreeString(aString: PChar);
  begin
    StrDispose(aString);
  end;

  procedure EnsureOutputLocation(const FileName: string);
  var
    Dir, Path: string;
  begin
    Path := ExpandFileName(FileName);
    Dir := GetFileDir(Path);
    if Dir <> '' then
      ForceDirectories(Dir);
  end;

  procedure CopyFile(const SrcPath, DestPath: string);
  var
    SrcStream, DestStream: TFileStream;
  begin
    if SameText(SrcPath, DestPath) then
      Exit; // No need to copy anything

    SrcStream := TFileStream.Create(SrcPath, fmOpenRead);
    DestStream := TFileStream.Create(DestPath, fmCreate);
    DestStream.CopyFrom(SrcStream, SrcStream.Size);
    DestStream.Free;
    SrcStream.Free;
  end;

  procedure SetImagingOptions;
  begin
    if Options.JpegCompressionQuality <> -1 then
    begin
      Imaging.SetOption(ImagingJpegQuality, Options.JpegCompressionQuality);
      Imaging.SetOption(ImagingTiffJpegQuality, Options.JpegCompressionQuality);
      Imaging.SetOption(ImagingJNGQuality, Options.JpegCompressionQuality);
    end;
    if Options.TiffCompressionScheme <> -1 then
      Imaging.SetOption(ImagingTiffCompression, Options.TiffCompressionScheme);
  end;

var
  Changed: Boolean;
  pInput : PChar;
  pOutput : PChar;
begin
  Options := TCmdLineOptions.Create;
  InputImage := TSingleImage.Create;
  OutputImage := TSingleImage.Create;

  SetImagingOptions;

  Time := GetTimeMicroseconds;
  //pInput := StrNew(PChar(intput));
  //pOutput := StrNew(PChar(output));

  InputImage.LoadFromFile(intput);

  try
    Changed := DoDeskew();
  except
      on e: Exception do
      begin
         ShowMessage(e.Message);
      end;
   end;

  GlobalMetadata.CopyLoadedMetaItemsForSaving;
            // Save the output

  try
    OutputImage.SaveToFile(output);
  except
      on e: Exception do
      begin
         ShowMessage(e.Message);
      end;
   end;

  //StrDispose(pInput);
  //StrDispose(pOutput);
  Options.Free;
  InputImage.Free;
  OutputImage.Free;

end;

end.
