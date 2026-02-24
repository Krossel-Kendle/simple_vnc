unit KRVN.PacketCodec;

interface

uses
  System.SysUtils,
  IdIOHandler,
  KRVN.Types;

type
  EKrvnProtocolError = class(Exception);

  TKrvnPacketCodec = class
  public
    class function BuildFrame(AMsgType: Word; AFlags: Cardinal; ASessionId: UInt64;
      AChannelId: Cardinal; ASeq: Cardinal; const APayload: TBytes): TBytes; static;
    class procedure ReadPacket(AIO: TIdIOHandler; out AHeader: TKrvnPacketHeader;
      out APayload: TBytes); static;
    class procedure WriteFrame(AIO: TIdIOHandler; const AFrame: TBytes); static;
    class function HeaderToBytes(const AHeader: TKrvnPacketHeader): TBytes; static;
    class function BytesToHeader(const AData: TBytes): TKrvnPacketHeader; static;
    class function IsMagicValid(const AHeader: TKrvnPacketHeader): Boolean; static;
  end;

implementation

uses
  IdGlobal;

class function TKrvnPacketCodec.HeaderToBytes(const AHeader: TKrvnPacketHeader): TBytes;
begin
  SetLength(Result, SizeOf(TKrvnPacketHeader));
  Move(AHeader, Result[0], SizeOf(TKrvnPacketHeader));
end;

class function TKrvnPacketCodec.BytesToHeader(const AData: TBytes): TKrvnPacketHeader;
begin
  if Length(AData) <> SizeOf(TKrvnPacketHeader) then
    raise EKrvnProtocolError.Create('Invalid header size');
  Move(AData[0], Result, SizeOf(TKrvnPacketHeader));
end;

class function TKrvnPacketCodec.IsMagicValid(const AHeader: TKrvnPacketHeader): Boolean;
begin
  Result := (AHeader.Magic[0] = 'K') and
    (AHeader.Magic[1] = 'R') and
    (AHeader.Magic[2] = 'V') and
    (AHeader.Magic[3] = 'N');
end;

class function TKrvnPacketCodec.BuildFrame(AMsgType: Word; AFlags: Cardinal; ASessionId: UInt64;
  AChannelId: Cardinal; ASeq: Cardinal; const APayload: TBytes): TBytes;
var
  LHeader: TKrvnPacketHeader;
  LHeaderBytes: TBytes;
begin
  if SizeOf(TKrvnPacketHeader) <> KRVN_HEADER_SIZE then
    raise EKrvnProtocolError.CreateFmt('Header mismatch: expected %d, actual %d',
      [KRVN_HEADER_SIZE, SizeOf(TKrvnPacketHeader)]);

  FillChar(LHeader, SizeOf(LHeader), 0);
  LHeader.Magic[0] := 'K';
  LHeader.Magic[1] := 'R';
  LHeader.Magic[2] := 'V';
  LHeader.Magic[3] := 'N';
  LHeader.Version := KRVN_PROTOCOL_VERSION;
  LHeader.HeaderSize := KRVN_HEADER_SIZE;
  LHeader.MsgType := AMsgType;
  LHeader.Flags := AFlags;
  LHeader.SessionId := ASessionId;
  LHeader.ChannelId := AChannelId;
  LHeader.Seq := ASeq;
  LHeader.PayloadLen := Length(APayload);
  LHeader.HeaderCrc32 := 0;
  LHeader.PayloadCrc32 := 0;

  LHeaderBytes := HeaderToBytes(LHeader);
  SetLength(Result, Length(LHeaderBytes) + Length(APayload));
  if Length(LHeaderBytes) > 0 then
    Move(LHeaderBytes[0], Result[0], Length(LHeaderBytes));
  if Length(APayload) > 0 then
    Move(APayload[0], Result[Length(LHeaderBytes)], Length(APayload));
end;

class procedure TKrvnPacketCodec.ReadPacket(AIO: TIdIOHandler; out AHeader: TKrvnPacketHeader;
  out APayload: TBytes);
var
  LHeaderId: TIdBytes;
  LPayloadId: TIdBytes;
  LHeaderBytes: TBytes;
begin
  SetLength(LHeaderId, KRVN_HEADER_SIZE);
  AIO.ReadBytes(LHeaderId, KRVN_HEADER_SIZE, False);
  SetLength(LHeaderBytes, KRVN_HEADER_SIZE);
  Move(LHeaderId[0], LHeaderBytes[0], KRVN_HEADER_SIZE);

  AHeader := BytesToHeader(LHeaderBytes);
  if not IsMagicValid(AHeader) then
    raise EKrvnProtocolError.Create('Invalid protocol magic');
  if AHeader.HeaderSize <> KRVN_HEADER_SIZE then
    raise EKrvnProtocolError.CreateFmt('Unsupported header size %d', [AHeader.HeaderSize]);

  if AHeader.PayloadLen > 0 then
  begin
    if AHeader.PayloadLen > 64 * 1024 * 1024 then
      raise EKrvnProtocolError.CreateFmt('Payload too large: %d', [AHeader.PayloadLen]);
    SetLength(LPayloadId, AHeader.PayloadLen);
    AIO.ReadBytes(LPayloadId, AHeader.PayloadLen, False);
    SetLength(APayload, AHeader.PayloadLen);
    Move(LPayloadId[0], APayload[0], AHeader.PayloadLen);
  end
  else
    SetLength(APayload, 0);
end;

class procedure TKrvnPacketCodec.WriteFrame(AIO: TIdIOHandler; const AFrame: TBytes);
var
  LOut: TIdBytes;
begin
  if Length(AFrame) = 0 then
    Exit;
  SetLength(LOut, Length(AFrame));
  Move(AFrame[0], LOut[0], Length(AFrame));
  AIO.Write(LOut);
end;

end.
