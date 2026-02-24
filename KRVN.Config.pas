unit KRVN.Config;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  KRVN.Types,
  KRVN.Logger;

type
  TKrvnUser = class
  public
    Username: string;
    Roles: TArray<string>;
    SaltB64: string;
    HashB64: string;
    Iterations: Integer;
    function HasRole(ARole: TKrvnRole): Boolean;
  end;

  TAppConfig = class
  private
    procedure ApplyDefaults;
    procedure EnsureDefaultUsers;
  public
    Mode: string;
    LoggingLevel: Integer;
    LoggingFolder: string;
    LoggingRetentionDays: Integer;

    ServerEnabled: Boolean;
    ServerBindIp: string;
    ServerPort: Integer;
    HiddenResolvePolicy: THiddenResolvePolicy;
    ServerUsers: TObjectList<TKrvnUser>;

    ClientServerIp: string;
    ClientServerPort: Integer;
    ClientUsername: string;
    ClientSecret: string;
    ClientProviderUser: string;
    ClientProviderSecret: string;

    ProviderEnabled: Boolean;
    ProviderServerIp: string;
    ProviderServerPort: Integer;
    ProviderServerUser: string;
    ProviderServerSecret: string;
    ProviderVisibility: TKrvnVisibility;
    ProviderDisplayName: string;
    ProviderAuthMode: string;
    ProviderUser: string;
    ProviderSecret: string;
    ProviderAutoAccept: Boolean;
    ProviderAllowInput: Boolean;
    ProviderAllowClipboard: Boolean;
    ProviderAllowFiles: Boolean;
    ProviderFps: Integer;
    ProviderQuality: Integer;
    ProviderMaxWidth: Integer;
    ProviderMaxHeight: Integer;

    CryptoEnabled: Boolean;
    CryptoMode: string;
    CryptoAllowPlainDebug: Boolean;

    constructor Create;
    destructor Destroy; override;
    procedure LoadFromFile(const AFileName: string; ALogger: TKrvnLogger);
    procedure SaveToFile(const AFileName: string);
    class function LoadOrCreate(const AFileName: string; ALogger: TKrvnLogger): TAppConfig;
    function FindUser(const AUsername: string): TKrvnUser;
  end;

implementation

uses
  System.JSON,
  System.IOUtils,
  System.NetEncoding,
  KRVN.Crypto,
  KRVN.Json;

{ TKrvnUser }

function TKrvnUser.HasRole(ARole: TKrvnRole): Boolean;
var
  LRole: string;
begin
  for LRole in Roles do
    if SameText(LRole, KrvnRoleToStr(ARole)) then
      Exit(True);
  Result := False;
end;

{ TAppConfig }

constructor TAppConfig.Create;
begin
  inherited Create;
  ServerUsers := TObjectList<TKrvnUser>.Create(True);
  ApplyDefaults;
end;

destructor TAppConfig.Destroy;
begin
  ServerUsers.Free;
  inherited Destroy;
end;

procedure TAppConfig.ApplyDefaults;
begin
  Mode := 'client';
  LoggingLevel := 3;
  LoggingFolder := 'logs';
  LoggingRetentionDays := 14;

  ServerEnabled := True;
  ServerBindIp := '0.0.0.0';
  ServerPort := 5590;
  HiddenResolvePolicy := hrRestricted;

  ClientServerIp := '127.0.0.1';
  ClientServerPort := 5590;
  ClientUsername := 'client1';
  ClientSecret := '';
  ClientProviderUser := '';
  ClientProviderSecret := '';

  ProviderEnabled := True;
  ProviderServerIp := '127.0.0.1';
  ProviderServerPort := 5590;
  ProviderServerUser := 'provider1';
  ProviderServerSecret := '';
  ProviderVisibility := kvPublic;
  ProviderDisplayName := 'Provider PC';
  ProviderAuthMode := 'none';
  ProviderUser := '';
  ProviderSecret := '';
  ProviderAutoAccept := True;
  ProviderAllowInput := True;
  ProviderAllowClipboard := True;
  ProviderAllowFiles := False;
  ProviderFps := 15;
  ProviderQuality := 70;
  ProviderMaxWidth := 1920;
  ProviderMaxHeight := 1080;

  CryptoEnabled := True;
  CryptoMode := 'control-plane';
  CryptoAllowPlainDebug := False;
end;

procedure TAppConfig.EnsureDefaultUsers;
  procedure AddUser(const AUsername, APassword: string; const ARoles: array of string);
  var
    LUser: TKrvnUser;
    LSalt: TBytes;
    LHash: TBytes;
    I: Integer;
  begin
    if FindUser(AUsername) <> nil then
      Exit;
    LUser := TKrvnUser.Create;
    LUser.Username := AUsername;
    SetLength(LUser.Roles, Length(ARoles));
    for I := 0 to High(ARoles) do
      LUser.Roles[I] := ARoles[I];
    LUser.Iterations := 200000;
    LSalt := TKrvnCrypto.RandomBytes(16);
    LHash := TKrvnCrypto.DerivePasswordHash(APassword, LSalt, LUser.Iterations);
    LUser.SaltB64 := TNetEncoding.Base64.EncodeBytesToString(LSalt);
    LUser.HashB64 := TNetEncoding.Base64.EncodeBytesToString(LHash);
    ServerUsers.Add(LUser);
  end;
begin
  AddUser('admin', 'admin123', ['server-admin', 'client', 'provider']);
  AddUser('client1', 'client123', ['client']);
  AddUser('provider1', 'provider123', ['provider']);
  if Trim(ClientSecret) = '' then
    ClientSecret := TKrvnCrypto.ProtectStringDpapi('client123');
  if Trim(ProviderServerSecret) = '' then
    ProviderServerSecret := TKrvnCrypto.ProtectStringDpapi('provider123');
end;

class function TAppConfig.LoadOrCreate(const AFileName: string; ALogger: TKrvnLogger): TAppConfig;
begin
  Result := TAppConfig.Create;
  if TFile.Exists(AFileName) then
    Result.LoadFromFile(AFileName, ALogger)
  else
  begin
    Result.EnsureDefaultUsers;
    Result.SaveToFile(AFileName);
    if ALogger <> nil then
      ALogger.Info('Config', 'Created default config: ' + AFileName);
  end;
end;

function TAppConfig.FindUser(const AUsername: string): TKrvnUser;
var
  LUser: TKrvnUser;
begin
  for LUser in ServerUsers do
    if SameText(LUser.Username, AUsername) then
      Exit(LUser);
  Result := nil;
end;

procedure TAppConfig.LoadFromFile(const AFileName: string; ALogger: TKrvnLogger);
var
  LJson: TJSONObject;
  LUsers: TJSONArray;
  IUser: Integer;
  LUserObj: TJSONObject;
  LUser: TKrvnUser;
  LRolesArr: TJSONArray;
  IRole: Integer;
  LRoles: TArray<string>;
  LNode: TJSONObject;
begin
  ApplyDefaults;
  LJson := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName, TEncoding.UTF8)) as TJSONObject;
  if LJson = nil then
    raise EConvertError.Create('Invalid config JSON');
  try
    Mode := JsonGetStr(LJson, 'mode', Mode);

    LNode := LJson.GetValue('logging') as TJSONObject;
    if LNode <> nil then
    begin
      LoggingLevel := JsonGetInt(LNode, 'level', LoggingLevel);
      LoggingFolder := JsonGetStr(LNode, 'folder', LoggingFolder);
      LoggingRetentionDays := JsonGetInt(LNode, 'retentionDays', LoggingRetentionDays);
      if Trim(LoggingFolder) = '' then
        LoggingFolder := 'logs';
      if LoggingRetentionDays < 0 then
        LoggingRetentionDays := 14;
    end;

    LNode := LJson.GetValue('server') as TJSONObject;
    if LNode <> nil then
    begin
      ServerEnabled := JsonGetBool(LNode, 'enabled', ServerEnabled);
      ServerBindIp := JsonGetStr(LNode, 'bindIp', ServerBindIp);
      ServerPort := JsonGetInt(LNode, 'port', ServerPort);
      HiddenResolvePolicy := StrToHiddenResolvePolicy(JsonGetStr(LNode, 'hiddenResolvePolicy',
        HiddenResolvePolicyToStr(HiddenResolvePolicy)));
      ServerUsers.Clear;
      LUsers := LNode.GetValue('users') as TJSONArray;
      if LUsers <> nil then
      begin
        for IUser := 0 to LUsers.Count - 1 do
        begin
          LUserObj := LUsers.Items[IUser] as TJSONObject;
          if LUserObj = nil then
            Continue;
          LUser := TKrvnUser.Create;
          LUser.Username := JsonGetStr(LUserObj, 'username', '');
          LUser.SaltB64 := JsonGetStr(LUserObj, 'salt', '');
          LUser.HashB64 := JsonGetStr(LUserObj, 'hash', '');
          LUser.Iterations := JsonGetInt(LUserObj, 'iterations', 200000);

          LRolesArr := LUserObj.GetValue('roles') as TJSONArray;
          SetLength(LRoles, 0);
          if LRolesArr <> nil then
          begin
            SetLength(LRoles, LRolesArr.Count);
            for IRole := 0 to LRolesArr.Count - 1 do
              LRoles[IRole] := LRolesArr.Items[IRole].Value;
          end;
          LUser.Roles := LRoles;
          ServerUsers.Add(LUser);
        end;
      end;
    end;

    LNode := LJson.GetValue('client') as TJSONObject;
    if LNode <> nil then
    begin
      ClientServerIp := JsonGetStr(LNode, 'serverIp', ClientServerIp);
      ClientServerPort := JsonGetInt(LNode, 'serverPort', ClientServerPort);
      ClientUsername := JsonGetStr(LNode, 'username', ClientUsername);
      ClientSecret := JsonGetStr(LNode, 'secret', ClientSecret);
      ClientProviderUser := JsonGetStr(LNode, 'providerUser', ClientProviderUser);
      ClientProviderSecret := JsonGetStr(LNode, 'providerSecret', ClientProviderSecret);
    end;

    LNode := LJson.GetValue('provider') as TJSONObject;
    if LNode <> nil then
    begin
      ProviderEnabled := JsonGetBool(LNode, 'enabled', ProviderEnabled);
      ProviderServerIp := JsonGetStr(LNode, 'serverIp', ProviderServerIp);
      ProviderServerPort := JsonGetInt(LNode, 'serverPort', ProviderServerPort);
      ProviderServerUser := JsonGetStr(LNode, 'serverUser', ProviderServerUser);
      ProviderServerSecret := JsonGetStr(LNode, 'serverSecret', ProviderServerSecret);
      ProviderVisibility := StrToKrvnVisibility(JsonGetStr(LNode, 'visibility',
        KrvnVisibilityToStr(ProviderVisibility)));
      ProviderDisplayName := JsonGetStr(LNode, 'displayName', ProviderDisplayName);
      ProviderAuthMode := JsonGetStr(LNode, 'authMode', ProviderAuthMode);
      ProviderUser := JsonGetStr(LNode, 'providerUser', ProviderUser);
      ProviderSecret := JsonGetStr(LNode, 'providerSecret', ProviderSecret);
      ProviderAutoAccept := JsonGetBool(LNode, 'autoAccept', ProviderAutoAccept);
      ProviderAllowInput := JsonGetBool(LNode, 'allowInput', ProviderAllowInput);
      ProviderAllowClipboard := JsonGetBool(LNode, 'allowClipboard', ProviderAllowClipboard);
      ProviderAllowFiles := JsonGetBool(LNode, 'allowFiles', ProviderAllowFiles);
      LNode := LNode.GetValue('video') as TJSONObject;
      if LNode <> nil then
      begin
        ProviderFps := JsonGetInt(LNode, 'fps', ProviderFps);
        ProviderQuality := JsonGetInt(LNode, 'quality', ProviderQuality);
        ProviderMaxWidth := JsonGetInt(LNode, 'maxWidth', ProviderMaxWidth);
        ProviderMaxHeight := JsonGetInt(LNode, 'maxHeight', ProviderMaxHeight);
      end;
    end;

    LNode := LJson.GetValue('crypto') as TJSONObject;
    if LNode <> nil then
    begin
      CryptoEnabled := JsonGetBool(LNode, 'enabled', CryptoEnabled);
      CryptoMode := JsonGetStr(LNode, 'mode', CryptoMode);
      CryptoAllowPlainDebug := JsonGetBool(LNode, 'allowPlainDebug', CryptoAllowPlainDebug);
    end;

    EnsureDefaultUsers;
  finally
    LJson.Free;
  end;

  if ALogger <> nil then
    ALogger.Info('Config', 'Loaded config: ' + AFileName);
end;

procedure TAppConfig.SaveToFile(const AFileName: string);
var
  LJson: TJSONObject;
  LNode: TJSONObject;
  LVideo: TJSONObject;
  LUsers: TJSONArray;
  LUser: TKrvnUser;
  LUserObj: TJSONObject;
  LRoles: TJSONArray;
  LRole: string;
begin
  EnsureDefaultUsers;

  LJson := TJSONObject.Create;
  try
    LJson.AddPair('mode', Mode);

    LNode := TJSONObject.Create;
    LNode.AddPair('level', TJSONNumber.Create(LoggingLevel));
    LNode.AddPair('folder', LoggingFolder);
    LNode.AddPair('retentionDays', TJSONNumber.Create(LoggingRetentionDays));
    LJson.AddPair('logging', LNode);

    LNode := TJSONObject.Create;
    LNode.AddPair('enabled', TJSONBool.Create(ServerEnabled));
    LNode.AddPair('bindIp', ServerBindIp);
    LNode.AddPair('port', TJSONNumber.Create(ServerPort));
    LNode.AddPair('hiddenResolvePolicy', HiddenResolvePolicyToStr(HiddenResolvePolicy));

    LUsers := TJSONArray.Create;
    for LUser in ServerUsers do
    begin
      LUserObj := TJSONObject.Create;
      LUserObj.AddPair('username', LUser.Username);
      LRoles := TJSONArray.Create;
      for LRole in LUser.Roles do
        LRoles.Add(LRole);
      LUserObj.AddPair('roles', LRoles);
      LUserObj.AddPair('salt', LUser.SaltB64);
      LUserObj.AddPair('hash', LUser.HashB64);
      LUserObj.AddPair('iterations', TJSONNumber.Create(LUser.Iterations));
      LUsers.Add(LUserObj);
    end;
    LNode.AddPair('users', LUsers);
    LJson.AddPair('server', LNode);

    LNode := TJSONObject.Create;
    LNode.AddPair('serverIp', ClientServerIp);
    LNode.AddPair('serverPort', TJSONNumber.Create(ClientServerPort));
    LNode.AddPair('username', ClientUsername);
    LNode.AddPair('secret', ClientSecret);
    LNode.AddPair('providerUser', ClientProviderUser);
    LNode.AddPair('providerSecret', ClientProviderSecret);
    LJson.AddPair('client', LNode);

    LNode := TJSONObject.Create;
    LNode.AddPair('enabled', TJSONBool.Create(ProviderEnabled));
    LNode.AddPair('serverIp', ProviderServerIp);
    LNode.AddPair('serverPort', TJSONNumber.Create(ProviderServerPort));
    LNode.AddPair('serverUser', ProviderServerUser);
    LNode.AddPair('serverSecret', ProviderServerSecret);
    LNode.AddPair('visibility', KrvnVisibilityToStr(ProviderVisibility));
    LNode.AddPair('displayName', ProviderDisplayName);
    LNode.AddPair('authMode', ProviderAuthMode);
    LNode.AddPair('providerUser', ProviderUser);
    LNode.AddPair('providerSecret', ProviderSecret);
    LNode.AddPair('autoAccept', TJSONBool.Create(ProviderAutoAccept));
    LNode.AddPair('allowInput', TJSONBool.Create(ProviderAllowInput));
    LNode.AddPair('allowClipboard', TJSONBool.Create(ProviderAllowClipboard));
    LNode.AddPair('allowFiles', TJSONBool.Create(ProviderAllowFiles));
    LVideo := TJSONObject.Create;
    LVideo.AddPair('fps', TJSONNumber.Create(ProviderFps));
    LVideo.AddPair('quality', TJSONNumber.Create(ProviderQuality));
    LVideo.AddPair('maxWidth', TJSONNumber.Create(ProviderMaxWidth));
    LVideo.AddPair('maxHeight', TJSONNumber.Create(ProviderMaxHeight));
    LNode.AddPair('video', LVideo);
    LJson.AddPair('provider', LNode);

    LNode := TJSONObject.Create;
    LNode.AddPair('enabled', TJSONBool.Create(CryptoEnabled));
    LNode.AddPair('mode', CryptoMode);
    LNode.AddPair('allowPlainDebug', TJSONBool.Create(CryptoAllowPlainDebug));
    LJson.AddPair('crypto', LNode);

    TFile.WriteAllText(AFileName, LJson.Format, TEncoding.UTF8);
  finally
    LJson.Free;
  end;
end;

end.
