unit KRVN.ProviderRole;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  KRVN.Types,
  KRVN.Config,
  KRVN.Logger,
  KRVN.OutboundConnection,
  KRVN.ScreenCapture;

type
  TProviderStatusEvent = procedure(const AText: string) of object;
  TProviderSessionEvent = procedure(AActive: Boolean; const AMessage: string) of object;

  TProviderReconnectThread = class;

  TIncomingFileState = class
  public
    FileId: string;
    FileName: string;
    DestPath: string;
    Stream: TFileStream;
    BytesReceived: Int64;
    ExpectedSize: Int64;
    destructor Destroy; override;
  end;

  TProviderRole = class
  private
    FConfig: TAppConfig;
    FLogger: TKrvnLogger;
    FConn: TKrvnOutboundConnection;
    FCapture: TScreenCaptureThread;
    FReconnectThread: TProviderReconnectThread;
    FLock: TCriticalSection;
    FRunning: Boolean;
    FAuthenticated: Boolean;
    FRegistered: Boolean;
    FActiveSessionId: UInt64;
    FProviderId: string;
    FInstanceId: string;
    FLastPingAt: TDateTime;
    FLastPongAt: TDateTime;
    FLastRegisterAt: TDateTime;
    FLastFrameW: Integer;
    FLastFrameH: Integer;
    FIncomingFiles: TObjectDictionary<string, TIncomingFileState>;
    FOnStatus: TProviderStatusEvent;
    FOnSession: TProviderSessionEvent;

    function LoadOrCreateProviderId: string;
    function SecretPassword: string;
    procedure HandleConnectionState(Sender: TObject; AConnected: Boolean; const AReason: string);
    procedure HandlePacket(Sender: TObject; const AHeader: TKrvnPacketHeader; const APayload: TBytes);
    procedure HandleControl(AMsgType: Word; const AJson: string);
    procedure HandleData(const AHeader: TKrvnPacketHeader; const APayload: TBytes);
    procedure SendHello;
    procedure SendAuthBegin;
    procedure SendProviderRegister;
    procedure SendSessionAccept(ASessionId: UInt64);
    procedure SendSessionReject(ASessionId: UInt64; const AReason: string);
    procedure SendSessionClose(ASessionId: UInt64; const AReason: string);
    procedure HandleSessionOffer(const AJson: string);
    procedure HandleVideoSettings(const AJson: string);
    procedure HandleClipboardSet(const APayload: TBytes);
    procedure HandleFileOffer(const AJson: string);
    procedure HandleFileChunk(const AJson: string);
    procedure HandleFileEnd(const AJson: string);
    procedure StartCapture;
    procedure StopCapture;
    procedure FrameReady(Sender: TObject; const APayload: TBytes; AWidth, AHeight: Integer;
      AFrameNo: Cardinal);
    procedure SetStatus(const AText: string);
  public
    constructor Create(AConfig: TAppConfig; ALogger: TKrvnLogger);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    procedure Tick;
    procedure DisconnectSession;
    property OnStatus: TProviderStatusEvent read FOnStatus write FOnStatus;
    property OnSession: TProviderSessionEvent read FOnSession write FOnSession;
    property ActiveSessionId: UInt64 read FActiveSessionId;
    property Registered: Boolean read FRegistered;
  end;

  TProviderReconnectThread = class(TThread)
  private
    FOwner: TProviderRole;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TProviderRole);
  end;

implementation

uses
  System.JSON,
  System.IOUtils,
  System.DateUtils,
  System.StrUtils,
  System.NetEncoding,
  KRVN.Utils,
  Winapi.Windows,
  KRVN.Crypto,
  KRVN.Json,
  KRVN.FrameCodec,
  KRVN.InputInjector;

{ TIncomingFileState }

destructor TIncomingFileState.Destroy;
begin
  Stream.Free;
  inherited Destroy;
end;

{ TProviderReconnectThread }

constructor TProviderReconnectThread.Create(AOwner: TProviderRole);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

procedure TProviderReconnectThread.Execute;
const
  BACKOFF: array[0..6] of Integer = (1, 2, 5, 10, 20, 30, 60);
var
  LBackoffIdx: Integer;
  LDelay: Integer;
begin
  LBackoffIdx := 0;
  while not Terminated do
  begin
    if not FOwner.FRunning then
    begin
      Sleep(100);
      Continue;
    end;
    if not FOwner.FConn.IsConnected then
    begin
      if FOwner.FConn.Connect(FOwner.FConfig.ProviderServerIp, FOwner.FConfig.ProviderServerPort) then
      begin
        LBackoffIdx := 0;
        FOwner.SendHello;
        FOwner.SendAuthBegin;
      end
      else
      begin
        LDelay := BACKOFF[LBackoffIdx];
        if LBackoffIdx < High(BACKOFF) then
          Inc(LBackoffIdx);
        Sleep(LDelay * 1000);
      end;
    end
    else
    begin
      FOwner.Tick;
      Sleep(250);
    end;
  end;
end;

{ TProviderRole }

constructor TProviderRole.Create(AConfig: TAppConfig; ALogger: TKrvnLogger);
begin
  inherited Create;
  FConfig := AConfig;
  FLogger := ALogger;
  FLock := TCriticalSection.Create;
  FConn := TKrvnOutboundConnection.Create(FLogger, 1024);
  FConn.OnPacket := HandlePacket;
  FConn.OnState := HandleConnectionState;
  FIncomingFiles := TObjectDictionary<string, TIncomingFileState>.Create([doOwnsValues]);
  FProviderId := LoadOrCreateProviderId;
  FInstanceId := '';
  FLastPongAt := Now;
  FLastRegisterAt := 0;
end;

destructor TProviderRole.Destroy;
begin
  Stop;
  FIncomingFiles.Free;
  FConn.Free;
  FLock.Free;
  inherited Destroy;
end;

function TProviderRole.LoadOrCreateProviderId: string;
var
  LPath: string;
  LGuid: TGUID;
begin
  LPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'provider.id');
  if TFile.Exists(LPath) then
    Exit(Trim(TFile.ReadAllText(LPath, TEncoding.UTF8)));

  CreateGUID(LGuid);
  Result := GuidToString(LGuid);
  TFile.WriteAllText(LPath, Result, TEncoding.UTF8);
end;

function TProviderRole.SecretPassword: string;
begin
  try
    Result := TKrvnCrypto.UnprotectStringDpapi(FConfig.ProviderServerSecret);
  except
    Result := FConfig.ProviderServerSecret;
  end;
end;

procedure TProviderRole.SetStatus(const AText: string);
begin
  if Assigned(FOnStatus) then
    FOnStatus(AText);
end;

procedure TProviderRole.Start;
var
  LGuid: TGUID;
begin
  if FRunning then
    Exit;
  CreateGUID(LGuid);
  FInstanceId := GuidToString(LGuid);
  FRunning := True;
  FAuthenticated := False;
  FRegistered := False;
  FActiveSessionId := 0;
  FLastRegisterAt := 0;
  FReconnectThread := TProviderReconnectThread.Create(Self);
  FLogger.Info('Provider', 'Started');
  SetStatus('Provider starting...');
end;

procedure TProviderRole.Stop;
begin
  if not FRunning then
    Exit;
  FRunning := False;
  if FReconnectThread <> nil then
  begin
    FReconnectThread.Terminate;
    FReconnectThread.WaitFor;
    FreeAndNil(FReconnectThread);
  end;
  StopCapture;
  FConn.Disconnect('provider stop');
  FAuthenticated := False;
  FRegistered := False;
  FActiveSessionId := 0;
  SetStatus('Provider stopped');
  FLogger.Info('Provider', 'Stopped');
end;

procedure TProviderRole.Tick;
var
  LPingElapsed: Integer;
  LPongElapsed: Integer;
begin
  if not FConn.IsConnected then
    Exit;

  LPingElapsed := SecondsBetween(Now, FLastPingAt);
  if LPingElapsed >= 10 then
  begin
    FConn.SendPacket(KRVN_MSG_PING, 0, KRVN_CHANNEL_CONTROL, Utf8Bytes('{"ping":1}'));
    FLastPingAt := Now;
  end;

  LPongElapsed := SecondsBetween(Now, FLastPongAt);
  if LPongElapsed > 30 then
  begin
    FLogger.Warn('Provider', 'Ping timeout. Reconnecting.');
    FConn.Disconnect('pong timeout');
    Exit;
  end;

  // Re-register periodically to heal transient missed registration/list states.
  if FAuthenticated and (SecondsBetween(Now, FLastRegisterAt) >= 20) then
  begin
    SendProviderRegister;
    if not FRegistered then
      SetStatus('Authenticated, registering...');
  end;
end;

procedure TProviderRole.DisconnectSession;
begin
  if FActiveSessionId = 0 then
    Exit;
  SendSessionClose(FActiveSessionId, 'provider_user_disconnect');
  StopCapture;
  FActiveSessionId := 0;
end;

procedure TProviderRole.HandleConnectionState(Sender: TObject; AConnected: Boolean;
  const AReason: string);
begin
  if AConnected then
  begin
    SetStatus('Connected to server');
    FLogger.Info('Provider', 'Connected to server');
    FLastPongAt := Now;
    FLastPingAt := 0;
  end
  else
  begin
    StopCapture;
    FActiveSessionId := 0;
    FAuthenticated := False;
    FRegistered := False;
    FLastRegisterAt := 0;
    SetStatus('Disconnected: ' + AReason);
    if Assigned(FOnSession) then
      FOnSession(False, 'Session closed');
  end;
end;

procedure TProviderRole.SendHello;
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('role', 'provider');
    LObj.AddPair('appVersion', '1.0.0');
    LObj.AddPair('protocol', TJSONNumber.Create(KRVN_PROTOCOL_VERSION));
    LObj.AddPair('machineName', GetEnvironmentVariable('COMPUTERNAME'));
    FConn.SendControlJson(KRVN_MSG_HELLO, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.SendAuthBegin;
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('username', FConfig.ProviderServerUser);
    FConn.SendControlJson(KRVN_MSG_AUTH_BEGIN, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.SendProviderRegister;
var
  LObj: TJSONObject;
  LCaps: TJSONObject;
  LVideoArr: TJSONArray;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('providerId', FProviderId);
    LObj.AddPair('instanceId', FInstanceId);
    LObj.AddPair('machineName', GetEnvironmentVariable('COMPUTERNAME'));
    LObj.AddPair('displayName', FConfig.ProviderDisplayName);
    LObj.AddPair('visibility', KrvnVisibilityToStr(FConfig.ProviderVisibility));
    LObj.AddPair('authMode', FConfig.ProviderAuthMode);
    LObj.AddPair('autoAccept', TJSONBool.Create(FConfig.ProviderAutoAccept));

    LCaps := TJSONObject.Create;
    LVideoArr := TJSONArray.Create;
    LVideoArr.Add('jpeg');
    LCaps.AddPair('video', LVideoArr);
    LCaps.AddPair('input', TJSONBool.Create(FConfig.ProviderAllowInput));
    LCaps.AddPair('clipboard', TJSONBool.Create(FConfig.ProviderAllowClipboard));
    LCaps.AddPair('files', TJSONBool.Create(FConfig.ProviderAllowFiles));
    LCaps.AddPair('monitors', TJSONNumber.Create(1));
    LObj.AddPair('capabilities', LCaps);
    FLastRegisterAt := Now;
    FConn.SendControlJson(KRVN_MSG_PROVIDER_REGISTER, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.SendSessionAccept(ASessionId: UInt64);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('sessionId', TJSONNumber.Create(Int64(ASessionId)));
    FConn.SendControlJson(KRVN_MSG_SESSION_ACCEPT, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.SendSessionReject(ASessionId: UInt64; const AReason: string);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('sessionId', TJSONNumber.Create(Int64(ASessionId)));
    LObj.AddPair('reason', AReason);
    FConn.SendControlJson(KRVN_MSG_SESSION_REJECT, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.SendSessionClose(ASessionId: UInt64; const AReason: string);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('sessionId', TJSONNumber.Create(Int64(ASessionId)));
    LObj.AddPair('reason', AReason);
    FConn.SendControlJson(KRVN_MSG_SESSION_CLOSE, LObj);
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.HandlePacket(Sender: TObject; const AHeader: TKrvnPacketHeader;
  const APayload: TBytes);
begin
  if AHeader.SessionId > 0 then
  begin
    HandleData(AHeader, APayload);
    Exit;
  end;
  HandleControl(AHeader.MsgType, TEncoding.UTF8.GetString(APayload));
end;

procedure TProviderRole.HandleControl(AMsgType: Word; const AJson: string);
var
  LObj: TJSONObject;
  LSalt: TBytes;
  LHash: TBytes;
  LNonce: TBytes;
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
            LResp.AddPair('username', FConfig.ProviderServerUser);
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
        SendProviderRegister;
      end;
    KRVN_MSG_AUTH_FAIL:
      begin
        FAuthenticated := False;
        FLogger.Error('Provider', 'Auth failed: ' + AJson);
        SetStatus('Auth failed');
      end;
    KRVN_MSG_PROVIDER_REGISTERED:
      begin
        FRegistered := True;
        SetStatus('Registered and online');
      end;
    KRVN_MSG_SESSION_OFFER:
      HandleSessionOffer(AJson);
    KRVN_MSG_SESSION_CLOSE:
      begin
        StopCapture;
        FActiveSessionId := 0;
        if Assigned(FOnSession) then
          FOnSession(False, 'Session closed by peer');
      end;
    KRVN_MSG_VIDEO_SETTINGS:
      HandleVideoSettings(AJson);
    KRVN_MSG_PONG:
      FLastPongAt := Now;
  end;
end;

procedure TProviderRole.HandleData(const AHeader: TKrvnPacketHeader; const APayload: TBytes);
var
  LEvent: TKrvnInputEvent;
begin
  if AHeader.SessionId <> FActiveSessionId then
    Exit;

  if (AHeader.MsgType = KRVN_MSG_INPUT_EVENT) and (AHeader.ChannelId = KRVN_CHANNEL_INPUT) then
  begin
    if not FConfig.ProviderAllowInput then
      Exit;
    if TryParseInputPayload(APayload, LEvent) then
      TKrvnInputInjector.Inject(LEvent, FLastFrameW, FLastFrameH);
    Exit;
  end;

  if (AHeader.MsgType = KRVN_MSG_CLIPBOARD_SET) and (AHeader.ChannelId = KRVN_CHANNEL_CLIPBOARD) then
  begin
    HandleClipboardSet(APayload);
    Exit;
  end;

  if (AHeader.MsgType = KRVN_MSG_FILE_OFFER) and (AHeader.ChannelId = KRVN_CHANNEL_FILES) then
    HandleFileOffer(TEncoding.UTF8.GetString(APayload))
  else if (AHeader.MsgType = KRVN_MSG_FILE_CHUNK) and (AHeader.ChannelId = KRVN_CHANNEL_FILES) then
    HandleFileChunk(TEncoding.UTF8.GetString(APayload))
  else if (AHeader.MsgType = KRVN_MSG_FILE_END) and (AHeader.ChannelId = KRVN_CHANNEL_FILES) then
    HandleFileEnd(TEncoding.UTF8.GetString(APayload));
end;

procedure TProviderRole.HandleSessionOffer(const AJson: string);
var
  LObj: TJSONObject;
  LAuthObj: TJSONObject;
  LSessionId: UInt64;
  LProviderUser: string;
  LProviderPass: string;
  LExpectedPass: string;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
    Exit;
  try
    LSessionId := StrToUInt64Def(JsonGetStr(LObj, 'sessionId', '0'), 0);
    if LSessionId = 0 then
      Exit;

    if FActiveSessionId <> 0 then
    begin
      SendSessionReject(LSessionId, 'provider_busy');
      Exit;
    end;

    if SameText(FConfig.ProviderAuthMode, 'login_password') then
    begin
      LAuthObj := LObj.GetValue('auth') as TJSONObject;
      LProviderUser := JsonGetStr(LAuthObj, 'providerLogin', '');
      LProviderPass := JsonGetStr(LAuthObj, 'providerPassword', '');
      try
        LExpectedPass := TKrvnCrypto.UnprotectStringDpapi(FConfig.ProviderSecret);
      except
        LExpectedPass := FConfig.ProviderSecret;
      end;
      if (not SameText(LProviderUser, FConfig.ProviderUser)) or (LProviderPass <> LExpectedPass) then
      begin
        SendSessionReject(LSessionId, 'bad_provider_credentials');
        Exit;
      end;
    end;

    if not FConfig.ProviderAutoAccept then
    begin
      SendSessionReject(LSessionId, 'provider_manual_mode_disabled');
      Exit;
    end;

    FActiveSessionId := LSessionId;
    SendSessionAccept(LSessionId);
    FConn.SendPacket(KRVN_MSG_CH_OPEN, FActiveSessionId, KRVN_CHANNEL_VIDEO, nil);
    FConn.SendPacket(KRVN_MSG_CH_OPEN, FActiveSessionId, KRVN_CHANNEL_INPUT, nil);
    FConn.SendPacket(KRVN_MSG_CH_OPEN, FActiveSessionId, KRVN_CHANNEL_CLIPBOARD, nil);
    FConn.SendPacket(KRVN_MSG_CH_OPEN, FActiveSessionId, KRVN_CHANNEL_FILES, nil);
    StartCapture;
    if Assigned(FOnSession) then
      FOnSession(True, 'Session ' + UIntToStr(LSessionId) + ' active');
    FLogger.Info('Provider', 'Session accepted ' + UIntToStr(LSessionId));
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.HandleVideoSettings(const AJson: string);
var
  LObj: TJSONObject;
  LQuality: Integer;
  LFps: Integer;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
    Exit;
  try
    LQuality := JsonGetInt(LObj, 'quality', FConfig.ProviderQuality);
    LFps := JsonGetInt(LObj, 'fps', FConfig.ProviderFps);
    FConfig.ProviderQuality := LQuality;
    FConfig.ProviderFps := LFps;
    if FCapture <> nil then
      FCapture.UpdateSettings(FConfig.ProviderFps, FConfig.ProviderQuality,
        FConfig.ProviderMaxWidth, FConfig.ProviderMaxHeight);
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.StartCapture;
begin
  if FCapture <> nil then
    Exit;
  FCapture := TScreenCaptureThread.Create(FConfig.ProviderFps, FConfig.ProviderQuality,
    FConfig.ProviderMaxWidth, FConfig.ProviderMaxHeight);
  FCapture.OnFrameReady := FrameReady;
end;

procedure TProviderRole.StopCapture;
begin
  if FCapture = nil then
    Exit;
  FCapture.Terminate;
  FCapture.WaitFor;
  FreeAndNil(FCapture);
end;

procedure TProviderRole.FrameReady(Sender: TObject; const APayload: TBytes; AWidth, AHeight: Integer;
  AFrameNo: Cardinal);
begin
  if (FActiveSessionId = 0) or not FConn.IsConnected then
    Exit;
  FLastFrameW := AWidth;
  FLastFrameH := AHeight;
  FConn.SendPacket(KRVN_MSG_VIDEO_FRAME, FActiveSessionId, KRVN_CHANNEL_VIDEO, APayload);
end;

procedure TProviderRole.HandleClipboardSet(const APayload: TBytes);
var
  LText: string;
  LData: HGLOBAL;
  LP: PChar;
begin
  if not FConfig.ProviderAllowClipboard then
    Exit;
  LText := TEncoding.UTF8.GetString(APayload);
  if Length(LText) > 256 * 1024 then
    Exit;

  if OpenClipboard(0) then
  try
    EmptyClipboard;
    LData := GlobalAlloc(GMEM_MOVEABLE, (Length(LText) + 1) * SizeOf(Char));
    if LData <> 0 then
    begin
      LP := GlobalLock(LData);
      if LP <> nil then
      begin
        StrPCopy(LP, LText);
        GlobalUnlock(LData);
        SetClipboardData(CF_UNICODETEXT, LData);
      end
      else
        GlobalFree(LData);
    end;
  finally
    CloseClipboard;
  end;
end;

procedure TProviderRole.HandleFileOffer(const AJson: string);
var
  LObj: TJSONObject;
  LFileId: string;
  LName: string;
  LSize: Int64;
  LState: TIncomingFileState;
  LResp: TJSONObject;
  LDir: string;
  LExt: string;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
    Exit;
  try
    LFileId := JsonGetStr(LObj, 'fileId', '');
    LName := JsonGetStr(LObj, 'name', '');
    LSize := StrToInt64Def(JsonGetStr(LObj, 'size', '0'), 0);

    LResp := TJSONObject.Create;
    try
      LResp.AddPair('fileId', LFileId);
      if not FConfig.ProviderAllowFiles then
      begin
        LResp.AddPair('accepted', TJSONBool.Create(False));
        LResp.AddPair('reason', 'files_disabled');
        FConn.SendPacket(KRVN_MSG_FILE_RESULT, FActiveSessionId, KRVN_CHANNEL_FILES, JsonToBytes(LResp));
        Exit;
      end;

      LExt := LowerCase(ExtractFileExt(LName));
      if MatchText(LExt, ['.exe', '.bat', '.cmd', '.ps1', '.vbs']) then
      begin
        LResp.AddPair('accepted', TJSONBool.Create(False));
        LResp.AddPair('reason', 'extension_blocked');
        FConn.SendPacket(KRVN_MSG_FILE_RESULT, FActiveSessionId, KRVN_CHANNEL_FILES, JsonToBytes(LResp));
        Exit;
      end;

      LDir := TPath.Combine(TPath.GetDocumentsPath, 'KRVN_Transfers');
      ForceDirectories(LDir);
      LState := TIncomingFileState.Create;
      LState.FileId := LFileId;
      LState.FileName := LName;
      LState.ExpectedSize := LSize;
      LState.DestPath := TPath.Combine(LDir, LName);
      LState.Stream := TFileStream.Create(LState.DestPath, fmCreate);
      if FIncomingFiles.ContainsKey(LFileId) then
        FIncomingFiles.Remove(LFileId);
      FIncomingFiles.Add(LFileId, LState);

      LResp.AddPair('accepted', TJSONBool.Create(True));
      LResp.AddPair('path', LState.DestPath);
      FConn.SendPacket(KRVN_MSG_FILE_RESULT, FActiveSessionId, KRVN_CHANNEL_FILES, JsonToBytes(LResp));
    finally
      LResp.Free;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.HandleFileChunk(const AJson: string);
var
  LObj: TJSONObject;
  LState: TIncomingFileState;
  LFileId: string;
  LData: TBytes;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
    Exit;
  try
    LFileId := JsonGetStr(LObj, 'fileId', '');
    if not FIncomingFiles.TryGetValue(LFileId, LState) then
      Exit;
    LData := TNetEncoding.Base64.DecodeStringToBytes(JsonGetStr(LObj, 'data', ''));
    if (Length(LData) > 0) and (LState.Stream <> nil) then
    begin
      LState.Stream.WriteBuffer(LData[0], Length(LData));
      Inc(LState.BytesReceived, Length(LData));
    end;
  finally
    LObj.Free;
  end;
end;

procedure TProviderRole.HandleFileEnd(const AJson: string);
var
  LObj: TJSONObject;
  LFileId: string;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
    Exit;
  try
    LFileId := JsonGetStr(LObj, 'fileId', '');
    if FIncomingFiles.ContainsKey(LFileId) then
      FIncomingFiles.Remove(LFileId);
  finally
    LObj.Free;
  end;
end;

end.
