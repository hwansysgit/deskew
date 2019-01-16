{
  Deskew
  by Marek Mauder
  http://galfar.vevb.net/deskew

  The contents of this file are used with permission, subject to the Mozilla
  Public License Version 1.1 (the "License"); you may not use this file except
  in compliance with the License. You may obtain a copy of the License at
  http://www.mozilla.org/MPL/MPL-1.1.html

  Software distributed under the License is distributed on an "AS IS" basis,
  WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
  the specific language governing rights and limitations under the License.

  Alternatively, the contents of this file may be used under the terms of the
  GNU Lesser General Public License (the  "LGPL License"), in which case the
  provisions of the LGPL License are applicable instead of those above.
  If you wish to allow use of your version of this file only under the terms
  of the LGPL License and not to allow others to use your version of this file
  under the MPL, indicate your decision by deleting  the provisions above and
  replace  them with the notice and other provisions required by the LGPL
  License.  If you do not delete the provisions above, a recipient may use
  your version of this file under either the MPL or the LGPL License.

  For more information about the LGPL: http://www.gnu.org/copyleft/lesser.html
}
unit RotationDetector;

interface

uses
  Types,
  SysUtils,
  Math,
  ImagingUtility;

type
  TCalcSkewAngleStats = record
    PixelCount: Integer;
    TestedPixels: Integer;
    AccumulatorSize: Integer;
    AccumulatedCounts: Integer;
    BestCount: Integer;
  end;
  PCalcSkewAngleStats = ^TCalcSkewAngleStats;

{ Calculates rotation angle for given 8bit grayscale image.
  Useful for finding skew of scanned documents etc.
  Uses Hough transform internally.
  MaxAngle is maximal (abs. value) expected skew angle in degrees (to speed things up)
  and Threshold (0..255) is used to classify pixel as black (text) or white (background).
  Area of interest rectangle can be defined to restrict the detection to
  work only in defined part of image (useful when the document has text only in
  smaller area of page and non-text features outside the area confuse the rotation detector).
  Various calculations stats can be retrieved by passing Stats parameter.}
function CalcRotationAngle(const MaxAngle: Double; Treshold: Integer;
  Width, Height: Integer; Pixels: PByteArray; DetectionArea: PRect = nil;
  Stats: PCalcSkewAngleStats = nil): Double;

implementation

function CalcRotationAngle(const MaxAngle: Double; Treshold: Integer;
  Width, Height: Integer; Pixels: PByteArray; DetectionArea: PRect; Stats: PCalcSkewAngleStats): Double;
const
  // Number of "best" lines we take into account when determining
  // resulting rotation angle (lines with most votes).
  BestLinesCount = 20;
  // Angle step used in alpha parameter quantization
  AlphaStep = 0.1;
type
  TLine = record
    Count: Integer;
    Index: Integer;
    Alpha: Double;
    Distance: Double;
  end;
  TLineArray = array of TLine;
var
  AlphaStart, MinDist, SumAngles: Double;
  AlphaSteps, DistCount, AccumulatorSize, I, AccumulatedCounts: Integer;
  BestLines: TLineArray;
  HoughAccumulator: array of Integer;
  PageWidth, PageHeight: Integer;
  ContentRect: TRect;

  // Classifies pixel at [X, Y] as black or white using threshold.
  function IsPixelBlack(X, Y: Integer): Boolean;
  begin
    Result := Pixels[Y * Width + X] < Treshold;
  end;

  // Calculates final angle for given angle step.
  function GetFinalAngle(StepIndex: Integer): Double;
  begin
    Result := AlphaStart + StepIndex * AlphaStep;
  end;

  // Calculates angle and distance parameters for all lines
  // going through point [X, Y].
  procedure CalcLines(X, Y: Integer);
  var
    D, Rads: Double;
    I, DIndex, Index: Integer;
    Sin, Cos: Extended;
  begin
    for I := 0 to AlphaSteps - 1 do
    begin
      // Angle for current step in radians
      Rads := GetFinalAngle(I) * PI / 180;
      SinCos(Rads, Sin, Cos);
      // Parameter D(distance from origin) of the line y=tg(alpha)x + d
      D := Y * Cos - X * Sin;
      // Calc index into accumulator for current line
      DIndex := Trunc(D - MinDist);
      Index := DIndex * AlphaSteps + I;
      // Add one vote for current line
      HoughAccumulator[Index] := HoughAccumulator[Index] + 1;
    end;
  end;

  // Uses Hough transform to calculate all lines that intersect
  // interesting points (those classified as beign on base line of the text).
  procedure CalcHoughTransform;
  var
    Y, X: Integer;
  begin
    for Y := 0 to PageHeight - 1 do
      for X := 0 to PageWidth - 1 do
      begin
        if IsPixelBlack(ContentRect.Left + X, ContentRect.Top + Y) and
          not IsPixelBlack(ContentRect.Left + X, ContentRect.Top + Y + 1) then
        begin
          CalcLines(X, Y);
        end;
      end;
  end;

  // Chooses "best" lines (with the most votes) from the accumulator
  function GetBestLines(Count: Integer): TLineArray;
  var
    I, J, DistIndex, AlphaIndex: Integer;
    Temp: TLine;
  begin
    SetLength(Result, Count);

    for I := 0 to AccumulatorSize - 1 do
    begin
      if HoughAccumulator[I] > Result[Count - 1].Count then
      begin
        // Current line has more votes than the last selected one,
        // let's put it the pot
        Result[Count - 1].Count := HoughAccumulator[I];
        Result[Count - 1].Index := I;
        J := Count - 1;

        // Sort the lines based on number of votes
        while (J > 0) and (Result[J].Count > Result[J - 1].Count) do
        begin
          Temp := Result[J];
          Result[J] := Result[J - 1];
          Result[J - 1] := Temp;
          J := J - 1;
        end;
      end;

      AccumulatedCounts := AccumulatedCounts + HoughAccumulator[I];
    end;

    for I := 0 to Count - 1 do
    begin
      // Caculate line angle and distance according to index in the accumulator
      DistIndex := Result[I].Index div AlphaSteps;
      AlphaIndex := Result[I].Index - DistIndex * AlphaSteps;
      Result[I].Alpha := GetFinalAngle(AlphaIndex);
      Result[I].Distance := DistIndex + MinDist;
    end;
  end;

begin
  AccumulatedCounts := 0;

  // Use supplied page content rect or just the whole image
  ContentRect := Rect(0, 0, Width, Height);
  if DetectionArea <> nil then
  begin
    Assert((RectWidth(DetectionArea^) <= Width) and (RectHeight(DetectionArea^) <= Height));
    ContentRect := DetectionArea^;
  end;

  PageWidth := ContentRect.Right - ContentRect.Left;
  PageHeight := ContentRect.Bottom - ContentRect.Top;
  if (ContentRect.Bottom = Height) then
    Dec(PageHeight); // Don't check for black pixels outsize of image in CalcHoughTransform()

  AlphaStart := -MaxAngle;
  AlphaSteps := Ceil(2 * MaxAngle / AlphaStep); // Number of angle steps = samples from interval <-MaxAngle, MaxAngle>
  MinDist := -Max(PageWidth, PageHeight);
  DistCount := 2 * (PageWidth + PageHeight);

  // Determine the size of line accumulator
  AccumulatorSize := DistCount * AlphaSteps;
  SetLength(HoughAccumulator, AccumulatorSize);

  // Calculate Hough transform
  CalcHoughTransform;

  // Get the best lines with most votes
  BestLines := GetBestLines(BestLinesCount);

  // Average angles of the selected lines to get the rotation angle of the image
  SumAngles := 0;
  for I := 0 to BestLinesCount - 1 do
    SumAngles := SumAngles + BestLines[I].Alpha;

  Result := SumAngles / BestLinesCount;

  if Stats <> nil then
  begin
    Stats.BestCount := BestLines[0].Count;
    Stats.PixelCount := PageWidth * PageHeight;
    Stats.AccumulatorSize := AccumulatorSize;
    Stats.AccumulatedCounts := AccumulatedCounts;
    Stats.TestedPixels := AccumulatedCounts div AlphaSteps;
  end;
end;


end.
