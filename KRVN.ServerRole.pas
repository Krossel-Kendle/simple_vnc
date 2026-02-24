unit KRVN.ServerRole;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  IdContext,
  IdCustomTCPServer,
  IdTCPServer,
  KRVN.Types,
  KRVN.Config,
  KRVN.Logger,
  KRVN.Utils;

type
  TProviderRecord = class
  public
    ProviderId: string;
    InstanceId: string;
    ProviderKey: string;
    MachineName: string;
    DisplayName: string;
    Visibility: TKrvnVisibility;
    AuthMode: string;
    CapabilitiesJson: string;
    ConnId: Int64;
    Online: Boolean;
    LastSeen: TDateTime;
    RegisteredAt: TDateTime;
  end;

  TSessionRecord = class
  public
    SessionId: UInt64;
    ClientConnId: Int64;
    ProviderConnId: Int64;
    ProviderKey: string;
    State: TSessionState;
    CreatedAt: TDateTime;
    LastActivityAt: TDateTime;
  end;

  TServerConnState = class;

  TServerWriterThread = class(TThread)
  private
    FState: TServerConnState;
  protected
    procedure Execute; override;
  public
    constructor Create(AState: TServerConnState);
  end;

  TServerConnState = class
  private
    FSeq: Integer;
  public
    ConnId: Int64;
    Context: TIdServerContext;
    Queue: TBytesQueue;
    Writer: TServerWriterThread;
    RoleWanted: TKrvnRole;
    Username: string;
    Authenticated: Boolean;
    PendingUsername: string;
    PendingNonce: TBytes;
    ProviderKey: string;
    constructor Create(AConnId: Int64; AContext: TIdServerContext);
    destructor Destroy; override;
    function NextSeq: Cardinal;
    procedure SendFrame(const AFrame: TBytes);
  end;

  TServerRole = class
  private
    FConfig: TAppConfig;
    FLogger: TKrvnLogger;
    FServer: TIdTCPServer;
    FLock: TCriticalSection;
    FConnections: TObjectDictionary<Int64, TServerConnState>;
    FProvidersByKey: TObjectDictionary<string, TProviderRecord>;
    FProvidersById: TObjectDictionary<string, TProviderRecord>;
    FSessions: TObjectDictionary<UInt64, TSessionRecord>;
    FNextConnId: Int64;
    FNextSessionId: Int64;

    function NextConnId: Int64;
    function NextSessionId: UInt64;
    function FindConnection(AConnId: Int64): TServerConnState;
    function MakeProviderKey(const AProviderId: string): string;
    function ResolveHiddenProvider(const AMachineName: string; out AProvider: TProviderRecord;
      out AError: string): Boolean;
    procedure SendJson(AConn: TServerConnState; AMsgType: Word; const AJson: string;
      ASessionId: UInt64 = 0);
    procedure SendError(AConn: TServerConnState; const ACode, AMessage: string);
    procedure CloseSession(ASessionId: UInt64; const AReason: string; ANotifyPeer: Boolean);

    procedure ServerConnect(AContext: TIdContext);
    procedure ServerDisconnect(AContext: TIdContext);
    procedure ServerExecute(AContext: TIdContext);
    procedure HandleDisconnectCleanup(AConn: TServerConnState);

    procedure HandlePacket(AConn: TServerConnState; const AHeader: TKrvnPacketHeader;
      const APayload: TBytes);
    procedure HandleControl(AConn: TServerConnState; AMsgType: Word; const APayload: TBytes);
    procedure HandleDataPlane(AConn: TServerConnState; const AHeader: TKrvnPacketHeader;
      const APayload: TBytes);

    procedure HandleHello(AConn: TServerConnState; const AJson: string);
    procedure HandleAuthBegin(AConn: TServerConnState; const AJson: string);
    procedure HandleAuthProof(AConn: TServerConnState; const AJson: string);
    procedure HandleProviderRegister(AConn: TServerConnState; const AJson: string);
    procedure HandleListProviders(AConn: TServerConnState);
    procedure HandleConnectProvider(AConn: TServerConnState; const AJson: string; AHidden: Boolean);
    procedure HandleSessionAccept(AConn: TServerConnState; const AJson: string);
    procedure HandleSessionReject(AConn: TServerConnState; const AJson: string);
    procedure HandleSessionClose(AConn: TServerConnState; const AJson: string);
    procedure HandleVideoSettings(AConn: TServerConnState; const AJson: string);
    function BuildProvidersListJson: string;
  public
    constructor Create(AConfig: TAppConfig; ALogger: TKrvnLogger);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    function IsRunning: Boolean;
    function ProvidersSummary: TArray<string>;
    function SessionsSummary: TArray<string>;
  end;

implementation

uses
  System.JSON,
  System.Hash,
  System.NetEncoding,
  System.DateUtils,
  IdException,
  IdExceptionCore,
  IdSocketHandle,
  KRVN.PacketCodec,
  KRVN.Json,
  KRVN.Crypto;

{ TServerWriterThread }

constructor TServerWriterThread.Create(AState: TServerConnState);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FState := AState;
end;

procedure TServerWriterThread.Execute;
var
  LFrame: TBytes;
begin
  while not Terminated do
  begin
    if not FState.Queue.Dequeue(LFrame, 200) then
      Continue;
    try
      if (FState.Context <> nil) and (FState.Context.Connection <> nil) and
        FState.Context.Connection.Connected then
        TKrvnPacketCodec.WriteFrame(FState.Context.Connection.IOHandler, LFrame)
      else
        Break;
    except
      Break;
    end;
  end;
end;

{ TServerConnState }

constructor TServerConnState.Create(AConnId: Int64; AContext: TIdServerContext);
begin
  inherited Create;
  ConnId := AConnId;
  Context := AContext;
  Queue := TBytesQueue.Create(1024);
  RoleWanted := krUnknown;
  Authenticated := False;
  FSeq := 0;
  Writer := TServerWriterThread.Create(Self);
end;

destructor TServerConnState.Destroy;
begin
  if Writer <> nil then
  begin
    Writer.Terminate;
    Writer.WaitFor;
    Writer.Free;
  end;
  Queue.Free;
  inherited Destroy;
end;

function TServerConnState.NextSeq: Cardinal;
begin
  Result := Cardinal(TInterlocked.Increment(FSeq));
end;

procedure TServerConnState.SendFrame(const AFrame: TBytes);
begin
  // Prefer newest packets when queue is saturated (video-heavy scenarios).
  Queue.Enqueue(AFrame, True);
end;

{ TServerRole }

constructor TServerRole.Create(AConfig: TAppConfig; ALogger: TKrvnLogger);
begin
  inherited Create;
  FConfig := AConfig;
  FLogger := ALogger;
  FLock := TCriticalSection.Create;
  FConnections := TObjectDictionary<Int64, TServerConnState>.Create([doOwnsValues]);
  FProvidersByKey := TObjectDictionary<string, TProviderRecord>.Create([doOwnsValues]);
  FProvidersById := TObjectDictionary<string, TProviderRecord>.Create;
  FSessions := TObjectDictionary<UInt64, TSessionRecord>.Create([doOwnsValues]);

  FServer := TIdTCPServer.Create(nil);
  FServer.OnConnect := ServerConnect;
  FServer.OnDisconnect := ServerDisconnect;
  FServer.OnExecute := ServerExecute;
  FServer.DefaultPort := FConfig.ServerPort;
end;

destructor TServerRole.Destroy;
begin
  Stop;
  FServer.Free;
  FSessions.Free;
  FProvidersById.Free;
  FProvidersByKey.Free;
  FConnections.Free;
  FLock.Free;
  inherited Destroy;
end;

function TServerRole.NextConnId: Int64;
begin
  Result := TInterlocked.Increment(FNextConnId);
end;

function TServerRole.NextSessionId: UInt64;
begin
  Result := UInt64(TInterlocked.Increment(FNextSessionId));
end;

function TServerRole.FindConnection(AConnId: Int64): TServerConnState;
begin
  if not FConnections.TryGetValue(AConnId, Result) then
    Result := nil;
end;

function TServerRole.MakeProviderKey(const AProviderId: string): string;
var
  LHash: string;
  LCandidate: string;
  LIndex: Integer;
begin
  LHash := UpperCase(THashSHA2.GetHashString(AProviderId, THashSHA2.TSHA2Version.SHA256));
  LCandidate := 'P-' + Copy(LHash, 1, 4);
  LIndex := 1;
  while FProvidersByKey.ContainsKey(LCandidate) and
    (FProvidersByKey[LCandidate].ProviderId <> AProviderId) do
  begin
    Inc(LIndex);
    LCandidate := 'P-' + Copy(LHash, 1, 3) + IntToHex(LIndex mod 16, 1);
  end;
  Result := LCandidate;
end;

procedure TServerRole.SendJson(AConn: TServerConnState; AMsgType: Word; const AJson: string;
  ASessionId: UInt64);
var
  LFrame: TBytes;
begin
  if AConn = nil then
    Exit;
  LFrame := TKrvnPacketCodec.BuildFrame(AMsgType, 0, ASessionId, KRVN_CHANNEL_CONTROL,
    AConn.NextSeq, TEncoding.UTF8.GetBytes(AJson));
  AConn.SendFrame(LFrame);
end;

procedure TServerRole.SendError(AConn: TServerConnState; const ACode, AMessage: string);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('code', ACode);
    LObj.AddPair('message', AMessage);
    SendJson(AConn, KRVN_MSG_ERROR, LObj.ToJSON);
  finally
    LObj.Free;
  end;
end;

procedure TServerRole.Start;
var
  LBinding: TIdSocketHandle;
begin
  if FServer.Active then
    Exit;
  FServer.Bindings.Clear;
  LBinding := FServer.Bindings.Add;
  LBinding.IP := FConfig.ServerBindIp;
  LBinding.Port := FConfig.ServerPort;
  FServer.DefaultPort := FConfig.ServerPort;
  FServer.Active := True;
  FLogger.Info('Server', Format('Started on %s:%d', [FConfig.ServerBindIp, FConfig.ServerPort]));
end;

procedure TServerRole.Stop;
begin
  if not FServer.Active then
    Exit;
  FServer.Active := False;
  FLogger.Info('Server', 'Stopped');
end;

function TServerRole.IsRunning: Boolean;
begin
  Result := FServer.Active;
end;

procedure TServerRole.ServerConnect(AContext: TIdContext);
var
  LConn: TServerConnState;
begin
  if not (AContext is TIdServerContext) then
    Exit;
  LConn := TServerConnState.Create(NextConnId, TIdServerContext(AContext));
  AContext.Data := LConn;
  FLock.Enter;
  try
    FConnections.Add(LConn.ConnId, LConn);
  finally
    FLock.Leave;
  end;
  FLogger.Info('Server', Format('New connection %d', [LConn.ConnId]), LConn.ConnId);
end;

procedure TServerRole.ServerDisconnect(AContext: TIdContext);
var
  LConn: TServerConnState;
begin
  if AContext = nil then
    Exit;
  LConn := TServerConnState(AContext.Data);
  AContext.Data := nil;
  if LConn = nil then
    Exit;
  FLock.Enter;
  try
    HandleDisconnectCleanup(LConn);
    FConnections.Remove(LConn.ConnId);
  finally
    FLock.Leave;
  end;
  FLogger.Info('Server', Format('Connection closed %d', [LConn.ConnId]), LConn.ConnId);
end;

procedure TServerRole.ServerExecute(AContext: TIdContext);
var
  LConn: TServerConnState;
  LHeader: TKrvnPacketHeader;
  LPayload: TBytes;
begin
  LConn := TServerConnState(AContext.Data);
  if LConn = nil then
    Exit;
  try
    TKrvnPacketCodec.ReadPacket(AContext.Connection.IOHandler, LHeader, LPayload);
    HandlePacket(LConn, LHeader, LPayload);
  except
    on E: EIdConnClosedGracefully do
      AContext.Connection.Disconnect;
    on E: EIdReadTimeout do
      Exit;
    on E: Exception do
    begin
      FLogger.Warn('Server', Format('Read error on conn %d: %s', [LConn.ConnId, E.Message]), LConn.ConnId);
      AContext.Connection.Disconnect;
    end;
  end;
end;

procedure TServerRole.HandlePacket(AConn: TServerConnState; const AHeader: TKrvnPacketHeader;
  const APayload: TBytes);
begin
  if AHeader.MsgType = KRVN_MSG_PING then
  begin
    SendJson(AConn, KRVN_MSG_PONG, '{"ok":true}');
    Exit;
  end;

  if AHeader.SessionId > 0 then
    HandleDataPlane(AConn, AHeader, APayload)
  else
    HandleControl(AConn, AHeader.MsgType, APayload);
end;

procedure TServerRole.HandleControl(AConn: TServerConnState; AMsgType: Word; const APayload: TBytes);
var
  LJson: string;
begin
  LJson := TEncoding.UTF8.GetString(APayload);
  case AMsgType of
    KRVN_MSG_HELLO:
      HandleHello(AConn, LJson);
    KRVN_MSG_AUTH_BEGIN:
      HandleAuthBegin(AConn, LJson);
    KRVN_MSG_AUTH_PROOF:
      HandleAuthProof(AConn, LJson);
    KRVN_MSG_PROVIDER_REGISTER:
      HandleProviderRegister(AConn, LJson);
    KRVN_MSG_CLIENT_LIST_PROVIDERS:
      HandleListProviders(AConn);
    KRVN_MSG_CLIENT_CONNECT_PROVIDER:
      HandleConnectProvider(AConn, LJson, False);
    KRVN_MSG_CLIENT_CONNECT_HIDDEN:
      HandleConnectProvider(AConn, LJson, True);
    KRVN_MSG_SESSION_ACCEPT:
      HandleSessionAccept(AConn, LJson);
    KRVN_MSG_SESSION_REJECT:
      HandleSessionReject(AConn, LJson);
    KRVN_MSG_SESSION_CLOSE:
      HandleSessionClose(AConn, LJson);
    KRVN_MSG_VIDEO_SETTINGS:
      HandleVideoSettings(AConn, LJson);
  else
    SendError(AConn, 'UNSUPPORTED_MSG', 'Unsupported control message');
  end;
end;

procedure TServerRole.HandleDataPlane(AConn: TServerConnState; const AHeader: TKrvnPacketHeader;
  const APayload: TBytes);
var
  LSession: TSessionRecord;
  LDestConnId: Int64;
  LDest: TServerConnState;
  LFrame: TBytes;
begin
  FLock.Enter;
  try
    if not FSessions.TryGetValue(AHeader.SessionId, LSession) then
      Exit;
    LSession.LastActivityAt := Now;
    if AConn.ConnId = LSession.ClientConnId then
      LDestConnId := LSession.ProviderConnId
    else
      LDestConnId := LSession.ClientConnId;
    LDest := FindConnection(LDestConnId);
    if LDest = nil then
      Exit;
    LFrame := TKrvnPacketCodec.BuildFrame(AHeader.MsgType, AHeader.Flags, AHeader.SessionId,
      AHeader.ChannelId, AHeader.Seq, APayload);
    LDest.SendFrame(LFrame);
  finally
    FLock.Leave;
  end;
end;

procedure TServerRole.HandleDisconnectCleanup(AConn: TServerConnState);
var
  LPair: TPair<string, TProviderRecord>;
  LSessionIds: TList<UInt64>;
  LSessPair: TPair<UInt64, TSessionRecord>;
  LId: UInt64;
begin
  for LPair in FProvidersByKey do
    if LPair.Value.ConnId = AConn.ConnId then
    begin
      LPair.Value.Online := False;
      LPair.Value.LastSeen := Now;
    end;

  LSessionIds := TList<UInt64>.Create;
  try
    for LSessPair in FSessions do
      if (LSessPair.Value.ClientConnId = AConn.ConnId) or (LSessPair.Value.ProviderConnId = AConn.ConnId) then
        LSessionIds.Add(LSessPair.Key);
    for LId in LSessionIds do
      CloseSession(LId, 'peer_disconnected', True);
  finally
    LSessionIds.Free;
  end;
end;

function TServerRole.ResolveHiddenProvider(const AMachineName: string; out AProvider: TProviderRecord;
  out AError: string): Boolean;
var
  LMatches: TObjectList<TProviderRecord>;
  LPair: TPair<string, TProviderRecord>;
  I: Integer;
begin
  Result := False;
  AProvider := nil;
  AError := '';
  LMatches := TObjectList<TProviderRecord>.Create(False);
  try
    for LPair in FProvidersByKey do
      if LPair.Value.Online and SameText(LPair.Value.MachineName, AMachineName) then
        LMatches.Add(LPair.Value);

    if LMatches.Count = 0 then
    begin
      AError := 'NOT_FOUND';
      Exit(False);
    end;

    if LMatches.Count = 1 then
    begin
      AProvider := LMatches[0];
      Exit(True);
    end;

    case FConfig.HiddenResolvePolicy of
      hrFirst:
        begin
          AProvider := LMatches[0];
          for I := 1 to LMatches.Count - 1 do
            if LMatches[I].RegisteredAt < AProvider.RegisteredAt then
              AProvider := LMatches[I];
          Result := True;
        end;
      hrLast:
        begin
          AProvider := LMatches[0];
          for I := 1 to LMatches.Count - 1 do
            if LMatches[I].RegisteredAt > AProvider.RegisteredAt then
              AProvider := LMatches[I];
          Result := True;
        end;
    else
      AError := 'MULTIPLE_MATCHES';
    end;
  finally
    LMatches.Free;
  end;
end;

procedure TServerRole.CloseSession(ASessionId: UInt64; const AReason: string; ANotifyPeer: Boolean);
var
  LSession: TSessionRecord;
  LClientConn: TServerConnState;
  LProviderConn: TServerConnState;
  LObj: TJSONObject;
begin
  if not FSessions.TryGetValue(ASessionId, LSession) then
    Exit;
  if ANotifyPeer then
  begin
    LObj := TJSONObject.Create;
    try
      LObj.AddPair('sessionId', TJSONNumber.Create(Int64(ASessionId)));
      LObj.AddPair('reason', AReason);
      LClientConn := FindConnection(LSession.ClientConnId);
      LProviderConn := FindConnection(LSession.ProviderConnId);
      if LClientConn <> nil then
        SendJson(LClientConn, KRVN_MSG_SESSION_CLOSE, LObj.ToJSON);
      if LProviderConn <> nil then
        SendJson(LProviderConn, KRVN_MSG_SESSION_CLOSE, LObj.ToJSON);
    finally
      LObj.Free;
    end;
  end;
  FSessions.Remove(ASessionId);
end;

procedure TServerRole.HandleHello(AConn: TServerConnState; const AJson: string);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    if LObj = nil then
      raise EConvertError.Create('HELLO JSON invalid');
    AConn.RoleWanted := StrToKrvnRole(JsonGetStr(LObj, 'role', 'unknown'));
    FLogger.Info('Server', Format('HELLO role=%s', [KrvnRoleToStr(AConn.RoleWanted)]), AConn.ConnId);
  finally
    LObj.Free;
  end;
end;

procedure TServerRole.HandleAuthBegin(AConn: TServerConnState; const AJson: string);
var
  LObj: TJSONObject;
  LResp: TJSONObject;
  LUsername: string;
  LUser: TKrvnUser;
  LNonce: TBytes;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
  begin
    SendError(AConn, 'AUTH_BAD_REQUEST', 'Invalid JSON');
    Exit;
  end;
  try
    LUsername := JsonGetStr(LObj, 'username', '');
    LUser := FConfig.FindUser(LUsername);
    if LUser = nil then
    begin
      SendJson(AConn, KRVN_MSG_AUTH_FAIL, '{"reason":"invalid_username"}');
      Exit;
    end;

    LNonce := TKrvnCrypto.RandomBytes(16);
    AConn.PendingUsername := LUsername;
    AConn.PendingNonce := LNonce;

    LResp := TJSONObject.Create;
    try
      LResp.AddPair('salt', LUser.SaltB64);
      LResp.AddPair('iterations', TJSONNumber.Create(LUser.Iterations));
      LResp.AddPair('nonce', TNetEncoding.Base64.EncodeBytesToString(LNonce));
      SendJson(AConn, KRVN_MSG_AUTH_CHALLENGE, LResp.ToJSON);
    finally
      LResp.Free;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TServerRole.HandleAuthProof(AConn: TServerConnState; const AJson: string);
var
  LObj: TJSONObject;
  LUsername: string;
  LProofB64: string;
  LUser: TKrvnUser;
  LHash: TBytes;
  LExpectedProof: TBytes;
  LActualProof: TBytes;
  LRoleWanted: TKrvnRole;
  LAllowed: Boolean;
  LResp: TJSONObject;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
  begin
    SendJson(AConn, KRVN_MSG_AUTH_FAIL, '{"reason":"invalid_json"}');
    Exit;
  end;
  try
    LUsername := JsonGetStr(LObj, 'username', '');
    LProofB64 := JsonGetStr(LObj, 'proof', '');
    LUser := FConfig.FindUser(LUsername);
    if (LUser = nil) or not SameText(AConn.PendingUsername, LUsername) then
    begin
      SendJson(AConn, KRVN_MSG_AUTH_FAIL, '{"reason":"invalid_state"}');
      Exit;
    end;
    LHash := TNetEncoding.Base64.DecodeStringToBytes(LUser.HashB64);
    LExpectedProof := TKrvnCrypto.BuildAuthProof(LHash, AConn.PendingNonce);
    LActualProof := TNetEncoding.Base64.DecodeStringToBytes(LProofB64);
    if not ConstantTimeEquals(LExpectedProof, LActualProof) then
    begin
      SendJson(AConn, KRVN_MSG_AUTH_FAIL, '{"reason":"bad_proof"}');
      Exit;
    end;
    LRoleWanted := AConn.RoleWanted;
    if LRoleWanted = krUnknown then
      LRoleWanted := krClient;
    LAllowed := LUser.HasRole(LRoleWanted) or LUser.HasRole(krServerAdmin);
    if not LAllowed then
    begin
      SendJson(AConn, KRVN_MSG_AUTH_FAIL, '{"reason":"role_not_allowed"}');
      Exit;
    end;
    AConn.Authenticated := True;
    AConn.Username := LUsername;
    LResp := TJSONObject.Create;
    try
      LResp.AddPair('connId', TJSONNumber.Create(AConn.ConnId));
      LResp.AddPair('role', KrvnRoleToStr(LRoleWanted));
      SendJson(AConn, KRVN_MSG_AUTH_OK, LResp.ToJSON);
    finally
      LResp.Free;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TServerRole.HandleProviderRegister(AConn: TServerConnState; const AJson: string);
var
  LObj: TJSONObject;
  LProvider: TProviderRecord;
  LProviderId: string;
  LCaps: TJSONValue;
  LResp: TJSONObject;
  LG: TGUID;
begin
  if not AConn.Authenticated then
  begin
    SendError(AConn, 'NOT_AUTH', 'Authenticate first');
    Exit;
  end;
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
  begin
    SendError(AConn, 'BAD_PROVIDER_JSON', 'Invalid provider payload');
    Exit;
  end;
  try
    LProviderId := JsonGetStr(LObj, 'providerId', '');
    if LProviderId = '' then
      begin
        CreateGUID(LG);
        LProviderId := GuidToString(LG);
      end;
    FLock.Enter;
    try
      if not FProvidersById.TryGetValue(LProviderId, LProvider) then
      begin
        LProvider := TProviderRecord.Create;
        LProvider.ProviderId := LProviderId;
        LProvider.ProviderKey := MakeProviderKey(LProviderId);
        FProvidersById.Add(LProviderId, LProvider);
        FProvidersByKey.Add(LProvider.ProviderKey, LProvider);
      end;
      LProvider.InstanceId := JsonGetStr(LObj, 'instanceId', '');
      LProvider.MachineName := JsonGetStr(LObj, 'machineName', 'UNKNOWN');
      LProvider.DisplayName := JsonGetStr(LObj, 'displayName', LProvider.MachineName);
      LProvider.Visibility := StrToKrvnVisibility(JsonGetStr(LObj, 'visibility', 'public'));
      LProvider.AuthMode := JsonGetStr(LObj, 'authMode', 'none');
      LProvider.ConnId := AConn.ConnId;
      LProvider.Online := True;
      LProvider.LastSeen := Now;
      if LProvider.RegisteredAt = 0 then
        LProvider.RegisteredAt := Now;
      AConn.ProviderKey := LProvider.ProviderKey;
      LCaps := LObj.GetValue('capabilities');
      if LCaps <> nil then
      begin
        LProvider.CapabilitiesJson := LCaps.ToJSON;
      end;
    finally
      FLock.Leave;
    end;

    LResp := TJSONObject.Create;
    try
      LResp.AddPair('ok', TJSONBool.Create(True));
      LResp.AddPair('providerKey', LProvider.ProviderKey);
      LResp.AddPair('serverTime', NowUtcIso8601);
      SendJson(AConn, KRVN_MSG_PROVIDER_REGISTERED, LResp.ToJSON);
    finally
      LResp.Free;
    end;
    FLogger.Info('Server', Format('Provider registered: %s (%s)', [LProvider.ProviderKey, LProvider.MachineName]), AConn.ConnId);
  finally
    LObj.Free;
  end;
end;

function TServerRole.BuildProvidersListJson: string;
var
  LRoot: TJSONObject;
  LArray: TJSONArray;
  LPair: TPair<string, TProviderRecord>;
  LItem: TJSONObject;
  LCapsObj: TJSONObject;
begin
  LRoot := TJSONObject.Create;
  try
    LArray := TJSONArray.Create;
    for LPair in FProvidersByKey do
    begin
      if not LPair.Value.Online then
        Continue;
      if LPair.Value.Visibility <> kvPublic then
        Continue;
      LItem := TJSONObject.Create;
      LItem.AddPair('providerId', LPair.Value.ProviderId);
      LItem.AddPair('instanceId', LPair.Value.InstanceId);
      LItem.AddPair('providerKey', LPair.Value.ProviderKey);
      LItem.AddPair('machineName', LPair.Value.MachineName);
      LItem.AddPair('displayName', LPair.Value.DisplayName);
      LItem.AddPair('visibility', KrvnVisibilityToStr(LPair.Value.Visibility));
      LItem.AddPair('authMode', LPair.Value.AuthMode);
      if Trim(LPair.Value.CapabilitiesJson) <> '' then
      begin
        LCapsObj := TJSONObject.ParseJSONValue(LPair.Value.CapabilitiesJson) as TJSONObject;
        if LCapsObj <> nil then
          LItem.AddPair('capabilities', LCapsObj);
      end;
      LItem.AddPair('online', TJSONBool.Create(LPair.Value.Online));
      LItem.AddPair('lastSeen', DateToISO8601(LPair.Value.LastSeen, True));
      LArray.AddElement(LItem);
    end;
    LRoot.AddPair('providers', LArray);
    Result := LRoot.ToJSON;
  finally
    LRoot.Free;
  end;
end;

procedure TServerRole.HandleListProviders(AConn: TServerConnState);
begin
  if not AConn.Authenticated then
  begin
    SendError(AConn, 'NOT_AUTH', 'Authenticate first');
    Exit;
  end;
  FLock.Enter;
  try
    SendJson(AConn, KRVN_MSG_PROVIDERS_LIST, BuildProvidersListJson);
  finally
    FLock.Leave;
  end;
end;

procedure TServerRole.HandleConnectProvider(AConn: TServerConnState; const AJson: string;
  AHidden: Boolean);
var
  LObj: TJSONObject;
  LProviderKey: string;
  LMachineName: string;
  LProviderLogin: string;
  LProviderPassword: string;
  LProvider: TProviderRecord;
  LProviderConn: TServerConnState;
  LSession: TSessionRecord;
  LSessionId: UInt64;
  LOffer: TJSONObject;
  LClientObj: TJSONObject;
  LAuthObj: TJSONObject;
  LErr: string;
begin
  if not AConn.Authenticated then
  begin
    SendError(AConn, 'NOT_AUTH', 'Authenticate first');
    Exit;
  end;
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
  begin
    SendError(AConn, 'BAD_CONNECT_JSON', 'Invalid connect payload');
    Exit;
  end;
  try
    LProviderKey := JsonGetStr(LObj, 'providerKey', '');
    LMachineName := JsonGetStr(LObj, 'machineName', '');
    LProviderLogin := JsonGetStr(LObj, 'providerLogin', '');
    LProviderPassword := JsonGetStr(LObj, 'providerPassword', '');

    FLock.Enter;
    try
      LProvider := nil;
      if AHidden then
      begin
        if not ResolveHiddenProvider(LMachineName, LProvider, LErr) then
        begin
          SendError(AConn, LErr, 'Hidden provider resolution failed');
          Exit;
        end;
      end
      else
      begin
        if not FProvidersByKey.TryGetValue(LProviderKey, LProvider) or not LProvider.Online then
        begin
          SendError(AConn, 'PROVIDER_OFFLINE', 'Provider unavailable');
          Exit;
        end;
      end;

      LProviderConn := FindConnection(LProvider.ConnId);
      if LProviderConn = nil then
      begin
        SendError(AConn, 'PROVIDER_CONN_NOT_FOUND', 'Provider connection not found');
        Exit;
      end;

      LSessionId := NextSessionId;
      LSession := TSessionRecord.Create;
      LSession.SessionId := LSessionId;
      LSession.ClientConnId := AConn.ConnId;
      LSession.ProviderConnId := LProvider.ConnId;
      LSession.ProviderKey := LProvider.ProviderKey;
      LSession.State := ssOffering;
      LSession.CreatedAt := Now;
      LSession.LastActivityAt := Now;
      FSessions.Add(LSessionId, LSession);

      LOffer := TJSONObject.Create;
      try
        LOffer.AddPair('sessionId', TJSONNumber.Create(Int64(LSessionId)));
        LClientObj := TJSONObject.Create;
        LClientObj.AddPair('connId', TJSONNumber.Create(AConn.ConnId));
        LClientObj.AddPair('username', AConn.Username);
        LOffer.AddPair('client', LClientObj);

        LAuthObj := TJSONObject.Create;
        LAuthObj.AddPair('providerLogin', LProviderLogin);
        LAuthObj.AddPair('providerPassword', LProviderPassword);
        LOffer.AddPair('auth', LAuthObj);
        SendJson(LProviderConn, KRVN_MSG_SESSION_OFFER, LOffer.ToJSON);
      finally
        LOffer.Free;
      end;
      FLogger.Info('Server', Format('Session offer %s from conn %d to provider %s',
        [UIntToStr(LSessionId), AConn.ConnId, LProvider.ProviderKey]), AConn.ConnId);
    finally
      FLock.Leave;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TServerRole.HandleSessionAccept(AConn: TServerConnState; const AJson: string);
var
  LObj: TJSONObject;
  LSessionId: UInt64;
  LSession: TSessionRecord;
  LClientConn: TServerConnState;
  LResp: TJSONObject;
  LProvider: TProviderRecord;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
    Exit;
  try
    LSessionId := StrToUInt64Def(JsonGetStr(LObj, 'sessionId', '0'), 0);
    FLock.Enter;
    try
      if not FSessions.TryGetValue(LSessionId, LSession) then
        Exit;
      if LSession.ProviderConnId <> AConn.ConnId then
        Exit;
      LSession.State := ssActive;
      LSession.LastActivityAt := Now;
      LClientConn := FindConnection(LSession.ClientConnId);
      if LClientConn = nil then
        Exit;
      if FProvidersByKey.TryGetValue(LSession.ProviderKey, LProvider) then
      begin
        LResp := TJSONObject.Create;
        try
          LResp.AddPair('sessionId', TJSONNumber.Create(Int64(LSessionId)));
          LResp.AddPair('providerKey', LProvider.ProviderKey);
          LResp.AddPair('displayName', LProvider.DisplayName);
          LResp.AddPair('machineName', LProvider.MachineName);
          SendJson(LClientConn, KRVN_MSG_SESSION_ACTIVE, LResp.ToJSON);
        finally
          LResp.Free;
        end;
      end;
    finally
      FLock.Leave;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TServerRole.HandleSessionReject(AConn: TServerConnState; const AJson: string);
var
  LObj: TJSONObject;
  LSessionId: UInt64;
  LReason: string;
  LSession: TSessionRecord;
  LClientConn: TServerConnState;
  LResp: TJSONObject;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
    Exit;
  try
    LSessionId := StrToUInt64Def(JsonGetStr(LObj, 'sessionId', '0'), 0);
    LReason := JsonGetStr(LObj, 'reason', 'rejected');
    FLock.Enter;
    try
      if not FSessions.TryGetValue(LSessionId, LSession) then
        Exit;
      LClientConn := FindConnection(LSession.ClientConnId);
      if LClientConn <> nil then
      begin
        LResp := TJSONObject.Create;
        try
          LResp.AddPair('sessionId', TJSONNumber.Create(Int64(LSessionId)));
          LResp.AddPair('reason', LReason);
          SendJson(LClientConn, KRVN_MSG_SESSION_REJECT, LResp.ToJSON);
        finally
          LResp.Free;
        end;
      end;
      FSessions.Remove(LSessionId);
    finally
      FLock.Leave;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TServerRole.HandleSessionClose(AConn: TServerConnState; const AJson: string);
var
  LObj: TJSONObject;
  LSessionId: UInt64;
  LReason: string;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
    Exit;
  try
    LSessionId := StrToUInt64Def(JsonGetStr(LObj, 'sessionId', '0'), 0);
    LReason := JsonGetStr(LObj, 'reason', 'user_disconnect');
    FLock.Enter;
    try
      CloseSession(LSessionId, LReason, True);
    finally
      FLock.Leave;
    end;
  finally
    LObj.Free;
  end;
end;

procedure TServerRole.HandleVideoSettings(AConn: TServerConnState; const AJson: string);
var
  LObj: TJSONObject;
  LSessionId: UInt64;
  LSession: TSessionRecord;
  LProviderConn: TServerConnState;
begin
  LObj := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if LObj = nil then
    Exit;
  try
    LSessionId := StrToUInt64Def(JsonGetStr(LObj, 'sessionId', '0'), 0);
    FLock.Enter;
    try
      if not FSessions.TryGetValue(LSessionId, LSession) then
        Exit;
      LProviderConn := FindConnection(LSession.ProviderConnId);
      if LProviderConn <> nil then
        SendJson(LProviderConn, KRVN_MSG_VIDEO_SETTINGS, LObj.ToJSON);
    finally
      FLock.Leave;
    end;
  finally
    LObj.Free;
  end;
end;

function TServerRole.ProvidersSummary: TArray<string>;
var
  LList: TList<string>;
  LPair: TPair<string, TProviderRecord>;
begin
  LList := TList<string>.Create;
  try
    FLock.Enter;
    try
      for LPair in FProvidersByKey do
      begin
        LList.Add(Format('%s | %s | %s | %s | %s',
          [LPair.Value.ProviderKey, LPair.Value.DisplayName, LPair.Value.MachineName,
          KrvnVisibilityToStr(LPair.Value.Visibility), BoolToStr(LPair.Value.Online, True)]));
      end;
    finally
      FLock.Leave;
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TServerRole.SessionsSummary: TArray<string>;
var
  LList: TList<string>;
  LPair: TPair<UInt64, TSessionRecord>;
begin
  LList := TList<string>.Create;
  try
    FLock.Enter;
    try
      for LPair in FSessions do
      begin
        LList.Add(Format('Session=%s Client=%d Provider=%d State=%d',
          [UIntToStr(LPair.Value.SessionId), LPair.Value.ClientConnId, LPair.Value.ProviderConnId,
          Ord(LPair.Value.State)]));
      end;
    finally
      FLock.Leave;
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

end.
