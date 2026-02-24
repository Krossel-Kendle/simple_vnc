unit KRVN.FrameCodec;

interface

uses
  System.SysUtils,
  KRVN.Types;

function BuildVideoFramePayload(AFrameNo, ATimestampMs: Cardinal; AWidth, AHeight: Word;
  AQuality: Byte; AFrameFlags: Word; const AJpegData: TBytes): TBytes;
function TryParseVideoFramePayload(const APayload: TBytes; out AMeta: TKrvnVideoFrameMeta;
  out AFrameData: TBytes): Boolean;
function BuildInputPayload(const AEvent: TKrvnInputEvent): TBytes;
function TryParseInputPayload(const APayload: TBytes; out AEvent: TKrvnInputEvent): Boolean;

implementation

function BuildVideoFramePayload(AFrameNo, ATimestampMs: Cardinal; AWidth, AHeight: Word;
  AQuality: Byte; AFrameFlags: Word; const AJpegData: TBytes): TBytes;
var
  LMeta: TKrvnVideoFrameMeta;
begin
  FillChar(LMeta, SizeOf(LMeta), 0);
  LMeta.FrameNo := AFrameNo;
  LMeta.TimestampMs := ATimestampMs;
  LMeta.Width := AWidth;
  LMeta.Height := AHeight;
  LMeta.Format := 1; // JPEG
  LMeta.Quality := AQuality;
  LMeta.Flags := AFrameFlags;
  LMeta.DataLen := Length(AJpegData);

  SetLength(Result, SizeOf(TKrvnVideoFrameMeta) + Length(AJpegData));
  Move(LMeta, Result[0], SizeOf(TKrvnVideoFrameMeta));
  if Length(AJpegData) > 0 then
    Move(AJpegData[0], Result[SizeOf(TKrvnVideoFrameMeta)], Length(AJpegData));
end;

function TryParseVideoFramePayload(const APayload: TBytes; out AMeta: TKrvnVideoFrameMeta;
  out AFrameData: TBytes): Boolean;
begin
  Result := False;
  SetLength(AFrameData, 0);
  FillChar(AMeta, SizeOf(AMeta), 0);
  if Length(APayload) < SizeOf(TKrvnVideoFrameMeta) then
    Exit;
  Move(APayload[0], AMeta, SizeOf(TKrvnVideoFrameMeta));
  if Length(APayload) < SizeOf(TKrvnVideoFrameMeta) + Integer(AMeta.DataLen) then
    Exit;
  SetLength(AFrameData, AMeta.DataLen);
  if AMeta.DataLen > 0 then
    Move(APayload[SizeOf(TKrvnVideoFrameMeta)], AFrameData[0], AMeta.DataLen);
  Result := True;
end;

function BuildInputPayload(const AEvent: TKrvnInputEvent): TBytes;
begin
  SetLength(Result, SizeOf(TKrvnInputEvent));
  Move(AEvent, Result[0], SizeOf(TKrvnInputEvent));
end;

function TryParseInputPayload(const APayload: TBytes; out AEvent: TKrvnInputEvent): Boolean;
begin
  Result := Length(APayload) >= SizeOf(TKrvnInputEvent);
  if not Result then
    Exit;
  Move(APayload[0], AEvent, SizeOf(TKrvnInputEvent));
end;

end.
