unit KRVN.ClientRole;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Graphics,
  KRVN.Types,
  KRVN.Config,
  KRVN.Logger,
  KRVN.OutboundConnection;

type
  TClientStatusEvent = procedure(const AText: string) of object;
  TClientProvidersEvent = procedure(const AJson: string) of object;
  TClientFrameEvent = procedure(ABitmap: TBitmap; AFrameNo: Cardinal) of object;
  TClientSessionEvent = procedure(AActive: Boolean; const AMessage: string) of object;

  TClientRole = class
  private
    FConfig: TAppConfig;
    FLogger: TKrvnLogger;
    FConn: TKrvnOutboundConnection;
    FAuthenticated: Boolean;
    FActiveSessionId: UInt64;
    FLastPongAt: TDateTime;
    FLastPingAt: TDateTime;
    FLastProvidersRequestAt: TDateTime;
    FOnStatus: TClientStatusEvent;
    FOnProviders: TClientProvidersEvent;
    FOnFrame: TClientFrameEvent;
    FOnSession: TClientSessionEvent;

    function SecretPassword: string;
    procedure SetStatus(const AText: string);
    procedure HandleConnState(Sender: TObject; AConnected: Boolean; const AReason: string);
    procedure HandlePacket(Sender: TObject; const AHeader: TKrvnPacketHeader; const APayload: TBytes);
    procedure HandleControl(AMsgType: Word; const AJson: string);
    procedure HandleData(const AHeader: TKrvnPacketHeader; const APayload: TBytes);
    procedure HandleVideoFrame(const APayload: TBytes);
    procedure SendHello;
    procedure SendAuthBegin;
  public
    constructor Create(AConfig: TAppConfig; ALogger: TKrvnLogger);
    destructor Destroy; override;
    function Connect: Boolean;
    procedure Disconnect;
    procedure Tick;
    procedure RequestProviders;
    procedure ConnectProvider(const AProviderKey, AProviderLogin, AProviderPassword: string);
    procedure ConnectHidden(const AMachineName, AProviderLogin, AProviderPassword: string);
    procedure DisconnectSession;
    procedure SendVideoSettings(AFps, AQuality: Integer; AScale: Double = 1.0);
    procedure SendInputEvent(const AEvent: TKrvnInputEvent);
    procedure SendClipboardText(const AText: string);
    procedure SendFile(const AFilePath: string);
    property ActiveSessionId: UInt64 read FActiveSessionId;
    property Authenticated: Boolean read FAuthenticated;
    property OnStatus: TClientStatusEvent read FOnStatus write FOnStatus;
    property OnProviders: TClientProvidersEvent read FOnProviders write FOnProviders;
    property OnFrame: TClientFrameEvent read FOnFrame write FOnFrame;
    property OnSession: TClientSessionEvent read FOnSession write FOnSession;
  end;

implementation

uses
  System.JSON,
  System.DateUtils,
  System.IOUtils,
  System.NetEncoding,
  Vcl.Imaging.jpeg,
  KRVN.Utils,
  KRVN.Crypto,
  KRVN.Json,
  KRVN.FrameCodec;

constructor TClientRole.Create(AConfig: TAppConfig; ALogger: TKrvnLogger);
begin
  inherited Create;
  FConfig := AConfig;
  FLogger := ALogger;
  FConn := TKrvnOutboundConnection.Create(FLogger, 2048);
  FConn.OnPacket := HandlePacket;
  FConn.OnState := HandleConnState;
  FLastPongAt := Now;
  FLastProvidersRequestAt := 0;
end;

destructor TClientRole.Destroy;
begin
  Disconnect;
  FConn.Free;
  inherited Destroy;
end;

function TClientRole.SecretPassword: string;
begin
  try
    Result := TKrvnCrypto.UnprotectStringDpapi(FConfig.ClientSecret);
  except
    Result := FConfig.ClientSecret;
  end;
end;

procedure TClientRole.SetStatus(const AText: string);
begin
  if Assigned(FOnStatus) then
    FOnStatus(AText);
end;

function TClientRole.Connect: Boolean;
begin
  Result := FConn.Connect(FConfig.ClientServerIp, FConfig.ClientServerPort);
  if Result then
  begin
    SendHello;
    SendAuthBegin;
  end;
end;

procedure TClientRole.Disconnect;
begin
  FConn.Disconnect('client disconnect');
  FAuthenticated := False;
  FActiveSessionId := 0;
end;

procedure TClientRole.Tick;
begin
  if not FConn.IsConnected then
    Exit;
  if SecondsBetween(Now, FLastPingAt) >= 10 then
  begin
    FConn.SendPacket(KRVN_MSG_PING, 0, KRVN_CHANNEL_CONTROL, Utf8Bytes('{"ping":1}'));
    FLastPingAt := Now;
  end;
  if SecondsBetween(Now, FLastPongAt) > 30 then
  begin
    FLogger.Warn('Client', 'Ping timeout');
    FConn.Disconnect('pong timeout');
  end;
end;

procedure TClientRole.SendHello;
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('role', 'client');
    LObj.AddPair('appVersion', '1.0.0');
    LObj.AddPair('protocol', TJSONNumber.Create(KRVN_PROTOCOL_VERSION));
    LObj.AddPair('machineName', GetEnvironmentVariable('COMPUTERNAME'));
    FConn.SendControlJson(KRVN_MSG_HELLO, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TClientRole.SendAuthBegin;
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('username', FConfig.ClientUsername);
    FConn.SendControlJson(KRVN_MSG_AUTH_BEGIN, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TClientRole.HandleConnState(Sender: TObject; AConnected: Boolean; const AReason: string);
begin
  if AConnected then
  begin
    SetStatus('Connected');
    FLastPingAt := 0;
    FLastPongAt := Now;
    FLastProvidersRequestAt := 0;
  end
  else
  begin
    FAuthenticated := False;
    FActiveSessionId := 0;
    FLastProvidersRequestAt := 0;
    SetStatus('Disconnected: ' + AReason);
    if Assigned(FOnSession) then
      FOnSession(False, 'Session closed');
  end;
end;

procedure TClientRole.HandlePacket(Sender: TObject; const AHeader: TKrvnPacketHeader;
  const APayload: TBytes);
begin
  if AHeader.SessionId > 0 then
    HandleData(AHeader, APayload)
  else
    HandleControl(AHeader.MsgType, TEncoding.UTF8.GetString(APayload));
end;

procedure TClientRole.HandleControl(AMsgType: Word; const AJson: string);
var
  LObj: TJSONObject;
  LSalt: TBytes;
  LNonce: TBytes;
  LHash: TBytes;
  LProof: TBytes;
  LResp: TJSONObject;
begin
  case AMsgType of
    KRVN_MSG_AUTH_CHALLENGE:
      begin
        LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
        if LObj = nil then
          Exit;
        try
          LSalt := TNetEncoding.Base64.DecodeStringToBytes(JsonGetStr(LObj, 'salt', ''));
          LNonce := TNetEncoding.Base64.DecodeStringToBytes(JsonGetStr(LObj, 'nonce', ''));
          LHash := TKrvnCrypto.DerivePasswordHash(SecretPassword, LSalt, JsonGetInt(LObj, 'iterations', 200000));
          LProof := TKrvnCrypto.BuildAuthProof(LHash, LNonce);

          LResp := TJSONObject.Create;
          try
            LResp.AddPair('username', FConfig.ClientUsername);
            LResp.AddPair('proof', TNetEncoding.Base64.EncodeBytesToString(LProof));
            FConn.SendControlJson(KRVN_MSG_AUTH_PROOF, LResp);
          finally
            LResp.Free;
          end;
        finally
          LObj.Free;
        end;
      end;
    KRVN_MSG_AUTH_OK:
      begin
        FAuthenticated := True;
        SetStatus('Authenticated');
        RequestProviders;
      end;
    KRVN_MSG_AUTH_FAIL:
      begin
        FAuthenticated := False;
        SetStatus('Auth failed');
      end;
    KRVN_MSG_PROVIDERS_LIST:
      if Assigned(FOnProviders) then
        FOnProviders(AJson);
    KRVN_MSG_SESSION_ACTIVE:
      begin
        LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
        if LObj <> nil then
        begin
          try
            FActiveSessionId := StrToUInt64Def(JsonGetStr(LObj, 'sessionId', '0'), 0);
            FConn.SendPacket(KRVN_MSG_CH_OPEN, FActiveSessionId, KRVN_CHANNEL_VIDEO, nil);
            FConn.SendPacket(KRVN_MSG_CH_OPEN, FActiveSessionId, KRVN_CHANNEL_INPUT, nil);
            FConn.SendPacket(KRVN_MSG_CH_OPEN, FActiveSessionId, KRVN_CHANNEL_CLIPBOARD, nil);
            FConn.SendPacket(KRVN_MSG_CH_OPEN, FActiveSessionId, KRVN_CHANNEL_FILES, nil);
            if Assigned(FOnSession) then
              FOnSession(True, 'Session ' + UIntToStr(FActiveSessionId) + ' active');
          finally
            LObj.Free;
          end;
        end;
      end;
    KRVN_MSG_SESSION_REJECT:
      begin
        SetStatus('Session rejected');
        if Assigned(FOnSession) then
          FOnSession(False, 'Session rejected: ' + AJson);
      end;
    KRVN_MSG_SESSION_CLOSE:
      begin
        FActiveSessionId := 0;
        if Assigned(FOnSession) then
          FOnSession(False, 'Session closed');
      end;
    KRVN_MSG_PONG:
      FLastPongAt := Now;
    KRVN_MSG_ERROR:
      SetStatus('Server error: ' + AJson);
    KRVN_MSG_FILE_RESULT:
      SetStatus('File transfer response: ' + AJson);
  end;
end;

procedure TClientRole.HandleData(const AHeader: TKrvnPacketHeader; const APayload: TBytes);
begin
  if AHeader.SessionId <> FActiveSessionId then
    Exit;
  if (AHeader.MsgType = KRVN_MSG_VIDEO_FRAME) and (AHeader.ChannelId = KRVN_CHANNEL_VIDEO) then
    HandleVideoFrame(APayload);
end;

procedure TClientRole.HandleVideoFrame(const APayload: TBytes);
var
  LMeta: TKrvnVideoFrameMeta;
  LData: TBytes;
  LStream: TMemoryStream;
  LJpeg: TJPEGImage;
  LBitmap: TBitmap;
begin
  if not TryParseVideoFramePayload(APayload, LMeta, LData) then
    Exit;
  LStream := TMemoryStream.Create;
  LJpeg := TJPEGImage.Create;
  LBitmap := TBitmap.Create;
  try
    if Length(LData) = 0 then
      Exit;
    LStream.WriteBuffer(LData[0], Length(LData));
    LStream.Position := 0;
    LJpeg.LoadFromStream(LStream);
    LBitmap.Assign(LJpeg);
    if Assigned(FOnFrame) then
    begin
      FOnFrame(LBitmap, LMeta.FrameNo);
      LBitmap := nil; // Ownership transferred to UI callback.
    end;
  finally
    LBitmap.Free;
    LJpeg.Free;
    LStream.Free;
  end;
end;

procedure TClientRole.RequestProviders;
var
  LObj: TJSONObject;
begin
  if not FAuthenticated then
    Exit;
  FLastProvidersRequestAt := Now;
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('includeHidden', TJSONBool.Create(False));
    FConn.SendControlJson(KRVN_MSG_CLIENT_LIST_PROVIDERS, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TClientRole.ConnectProvider(const AProviderKey, AProviderLogin, AProviderPassword: string);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('providerKey', AProviderKey);
    LObj.AddPair('providerLogin', AProviderLogin);
    LObj.AddPair('providerPassword', AProviderPassword);
    FConn.SendControlJson(KRVN_MSG_CLIENT_CONNECT_PROVIDER, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TClientRole.ConnectHidden(const AMachineName, AProviderLogin, AProviderPassword: string);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('machineName', AMachineName);
    LObj.AddPair('providerLogin', AProviderLogin);
    LObj.AddPair('providerPassword', AProviderPassword);
    FConn.SendControlJson(KRVN_MSG_CLIENT_CONNECT_HIDDEN, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TClientRole.DisconnectSession;
var
  LObj: TJSONObject;
begin
  if FActiveSessionId = 0 then
    Exit;
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('sessionId', TJSONNumber.Create(Int64(FActiveSessionId)));
    LObj.AddPair('reason', 'client_disconnect');
    FConn.SendControlJson(KRVN_MSG_SESSION_CLOSE, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TClientRole.SendVideoSettings(AFps, AQuality: Integer; AScale: Double);
var
  LObj: TJSONObject;
begin
  if FActiveSessionId = 0 then
    Exit;
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('sessionId', TJSONNumber.Create(Int64(FActiveSessionId)));
    LObj.AddPair('fps', TJSONNumber.Create(AFps));
    LObj.AddPair('quality', TJSONNumber.Create(AQuality));
    LObj.AddPair('scale', TJSONNumber.Create(AScale));
    FConn.SendControlJson(KRVN_MSG_VIDEO_SETTINGS, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TClientRole.SendInputEvent(const AEvent: TKrvnInputEvent);
begin
  if FActiveSessionId = 0 then
    Exit;
  FConn.SendPacket(KRVN_MSG_INPUT_EVENT, FActiveSessionId, KRVN_CHANNEL_INPUT, BuildInputPayload(AEvent));
end;

procedure TClientRole.SendClipboardText(const AText: string);
begin
  if FActiveSessionId = 0 then
    Exit;
  if Length(AText) > 256 * 1024 then
    Exit;
  FConn.SendPacket(KRVN_MSG_CLIPBOARD_SET, FActiveSessionId, KRVN_CHANNEL_CLIPBOARD, Utf8Bytes(AText));
end;

procedure TClientRole.SendFile(const AFilePath: string);
var
  LFileId: string;
  LGuid: TGUID;
  LOffer: TJSONObject;
  LChunk: TJSONObject;
  LEndObj: TJSONObject;
  LStream: TFileStream;
  LBuffer: TBytes;
  LRead: Integer;
  LFileSize: Int64;
  LSizeStream: TFileStream;
begin
  if (FActiveSessionId = 0) or (not TFile.Exists(AFilePath)) then
    Exit;
  CreateGUID(LGuid);
  LFileId := GuidToString(LGuid);
  LSizeStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
  try
    LFileSize := LSizeStream.Size;
  finally
    LSizeStream.Free;
  end;

  LOffer := TJSONObject.Create;
  try
    LOffer.AddPair('fileId', LFileId);
    LOffer.AddPair('name', ExtractFileName(AFilePath));
    LOffer.AddPair('size', TJSONNumber.Create(LFileSize));
    FConn.SendPacket(KRVN_MSG_FILE_OFFER, FActiveSessionId, KRVN_CHANNEL_FILES, JsonToBytes(LOffer));
  finally
    LOffer.Free;
  end;

  LStream := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(LBuffer, 32 * 1024);
    while True do
    begin
      LRead := LStream.Read(LBuffer[0], Length(LBuffer));
      if LRead <= 0 then
        Break;
      LChunk := TJSONObject.Create;
      try
        LChunk.AddPair('fileId', LFileId);
        LChunk.AddPair('data', TNetEncoding.Base64.EncodeBytesToString(Copy(LBuffer, 0, LRead)));
        FConn.SendPacket(KRVN_MSG_FILE_CHUNK, FActiveSessionId, KRVN_CHANNEL_FILES, JsonToBytes(LChunk));
      finally
        LChunk.Free;
      end;
    end;
  finally
    LStream.Free;
  end;

  LEndObj := TJSONObject.Create;
  try
    LEndObj.AddPair('fileId', LFileId);
    FConn.SendPacket(KRVN_MSG_FILE_END, FActiveSessionId, KRVN_CHANNEL_FILES, JsonToBytes(LEndObj));
  finally
    LEndObj.Free;
  end;
end;

end.
