unit KRVN.OutboundConnection;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  IdTCPClient,
  KRVN.Types,
  KRVN.Utils,
  KRVN.PacketCodec,
  KRVN.Logger;

type
  TPacketReceivedEvent = procedure(Sender: TObject; const AHeader: TKrvnPacketHeader;
    const APayload: TBytes) of object;
  TConnectionStateEvent = procedure(Sender: TObject; AConnected: Boolean;
    const AReason: string) of object;

  TKrvnOutboundConnection = class;

  TOutboundReaderThread = class(TThread)
  private
    FOwner: TKrvnOutboundConnection;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TKrvnOutboundConnection);
  end;

  TOutboundWriterThread = class(TThread)
  private
    FOwner: TKrvnOutboundConnection;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TKrvnOutboundConnection);
  end;

  TKrvnOutboundConnection = class
  private
    FClient: TIdTCPClient;
    FSendQueue: TBytesQueue;
    FSeq: Integer;
    FReader: TOutboundReaderThread;
    FWriter: TOutboundWriterThread;
    FOnPacket: TPacketReceivedEvent;
    FOnState: TConnectionStateEvent;
    FLogger: TKrvnLogger;
    FLock: TCriticalSection;
    FClosing: Boolean;
    FHost: string;
    FPort: Integer;
    procedure SetConnectedState(AConnected: Boolean; const AReason: string);
    function NextSeq: Cardinal;
  public
    constructor Create(ALogger: TKrvnLogger; ASendQueueSize: Integer = 512);
    destructor Destroy; override;
    function Connect(const AHost: string; APort: Integer; AConnectTimeoutMs: Integer = 7000): Boolean;
    procedure Disconnect(const AReason: string = '');
    function IsConnected: Boolean;
    procedure SendFrame(const AFrame: TBytes);
    procedure SendPacket(AMsgType: Word; ASessionId: UInt64; AChannelId: Cardinal;
      const APayload: TBytes; AFlags: Cardinal = 0);
    procedure SendControlJson(AMsgType: Word; const AJson: TJSONObject; ASessionId: UInt64 = 0);
    property OnPacket: TPacketReceivedEvent read FOnPacket write FOnPacket;
    property OnState: TConnectionStateEvent read FOnState write FOnState;
    property Host: string read FHost;
    property Port: Integer read FPort;
    property Client: TIdTCPClient read FClient;
  end;

implementation

uses
  KRVN.Json;

constructor TOutboundReaderThread.Create(AOwner: TKrvnOutboundConnection);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

procedure TOutboundReaderThread.Execute;
var
  LHeader: TKrvnPacketHeader;
  LPayload: TBytes;
begin
  while not Terminated do
  begin
    try
      TKrvnPacketCodec.ReadPacket(FOwner.FClient.IOHandler, LHeader, LPayload);
      if Assigned(FOwner.FOnPacket) then
        FOwner.FOnPacket(FOwner, LHeader, LPayload);
    except
      on E: Exception do
      begin
        FOwner.FLogger.Warn('Net', 'Reader disconnect: ' + E.Message);
        FOwner.SetConnectedState(False, E.Message);
        Break;
      end;
    end;
  end;
end;

constructor TOutboundWriterThread.Create(AOwner: TKrvnOutboundConnection);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

procedure TOutboundWriterThread.Execute;
var
  LFrame: TBytes;
begin
  while not Terminated do
  begin
    if not FOwner.FSendQueue.Dequeue(LFrame, 200) then
      Continue;

    try
      TKrvnPacketCodec.WriteFrame(FOwner.FClient.IOHandler, LFrame);
    except
      on E: Exception do
      begin
        FOwner.FLogger.Warn('Net', 'Writer disconnect: ' + E.Message);
        FOwner.SetConnectedState(False, E.Message);
        Break;
      end;
    end;
  end;
end;

constructor TKrvnOutboundConnection.Create(ALogger: TKrvnLogger; ASendQueueSize: Integer);
begin
  inherited Create;
  FLogger := ALogger;
  FClient := TIdTCPClient.Create(nil);
  FClient.ReadTimeout := 0;
  FSendQueue := TBytesQueue.Create(ASendQueueSize);
  FLock := TCriticalSection.Create;
  FSeq := 0;
  FClosing := False;
end;

destructor TKrvnOutboundConnection.Destroy;
begin
  Disconnect('destroy');
  FLock.Free;
  FSendQueue.Free;
  FClient.Free;
  inherited Destroy;
end;

procedure TKrvnOutboundConnection.SetConnectedState(AConnected: Boolean; const AReason: string);
begin
  if not AConnected then
  begin
    Disconnect(AReason);
    Exit;
  end;
  FLock.Enter;
  try
    FClosing := False;
  finally
    FLock.Leave;
  end;
  if Assigned(FOnState) then
    FOnState(Self, True, AReason);
end;

function TKrvnOutboundConnection.NextSeq: Cardinal;
begin
  Result := Cardinal(TInterlocked.Increment(FSeq));
end;

function TKrvnOutboundConnection.Connect(const AHost: string; APort, AConnectTimeoutMs: Integer): Boolean;
begin
  Result := False;
  Disconnect('reconnect');

  FHost := AHost;
  FPort := APort;
  FClient.Host := AHost;
  FClient.Port := APort;
  FClient.ConnectTimeout := AConnectTimeoutMs;

  try
    FClient.Connect;
    FLock.Enter;
    try
      FClosing := False;
    finally
      FLock.Leave;
    end;
    FReader := TOutboundReaderThread.Create(Self);
    FWriter := TOutboundWriterThread.Create(Self);
    FLogger.Info('Net', Format('Connected to %s:%d', [AHost, APort]));
    if Assigned(FOnState) then
      FOnState(Self, True, '');
    Result := True;
  except
    on E: Exception do
    begin
      FLogger.Error('Net', Format('Connect failed %s:%d %s', [AHost, APort, E.Message]));
      Disconnect(E.Message);
    end;
  end;
end;

procedure TKrvnOutboundConnection.Disconnect(const AReason: string);
var
  LCurrentThread: TThread;
begin
  LCurrentThread := TThread.CurrentThread;
  FLock.Enter;
  try
    if FClosing then
      Exit;
    FClosing := True;
  finally
    FLock.Leave;
  end;

  try
    if FClient.Connected then
      FClient.Disconnect;
  except
  end;

  if FReader <> nil then
  begin
    FReader.Terminate;
    if FReader <> LCurrentThread then
    begin
      FReader.WaitFor;
      FreeAndNil(FReader);
    end;
  end;

  if FWriter <> nil then
  begin
    FWriter.Terminate;
    if FWriter <> LCurrentThread then
    begin
      FWriter.WaitFor;
      FreeAndNil(FWriter);
    end;
  end;
  FSendQueue.Clear;

  FLock.Enter;
  try
    FClosing := False;
  finally
    FLock.Leave;
  end;

  if Assigned(FOnState) then
    FOnState(Self, False, AReason);
end;

function TKrvnOutboundConnection.IsConnected: Boolean;
begin
  Result := FClient.Connected and (FReader <> nil) and (FWriter <> nil) and
    not FReader.Terminated and not FWriter.Terminated;
end;

procedure TKrvnOutboundConnection.SendFrame(const AFrame: TBytes);
begin
  if not IsConnected then
    Exit;
  // Keep most recent packets flowing under load (mainly video bursts).
  if not FSendQueue.Enqueue(AFrame, True) then
    FLogger.Warn('Net', 'Send queue overflow');
end;

procedure TKrvnOutboundConnection.SendPacket(AMsgType: Word; ASessionId: UInt64; AChannelId: Cardinal;
  const APayload: TBytes; AFlags: Cardinal);
var
  LFrame: TBytes;
begin
  LFrame := TKrvnPacketCodec.BuildFrame(AMsgType, AFlags, ASessionId, AChannelId, NextSeq, APayload);
  SendFrame(LFrame);
end;

procedure TKrvnOutboundConnection.SendControlJson(AMsgType: Word; const AJson: TJSONObject;
  ASessionId: UInt64);
var
  LPayload: TBytes;
begin
  if AJson = nil then
    Exit;
  LPayload := JsonToBytes(AJson);
  SendPacket(AMsgType, ASessionId, KRVN_CHANNEL_CONTROL, LPayload, 0);
end;

end.
