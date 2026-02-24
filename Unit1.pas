unit Unit1;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  System.Math,
  System.IOUtils,
  System.NetEncoding,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Clipbrd,
  KRVN.Config,
  KRVN.Logger,
  KRVN.Types,
  KRVN.ServerRole,
  KRVN.ProviderRole,
  KRVN.ClientRole,
  KRVN.Crypto,
  KRVN.Json;

type
  TForm1 = class(TForm)
  private
    FConfig: TAppConfig;
    FLogger: TKrvnLogger;
    FServerRole: TServerRole;
    FProviderRole: TProviderRole;
    FClientRole: TClientRole;

    FPageControl: TPageControl;
    TsMode: TTabSheet;
    TsClient: TTabSheet;
    TsProvider: TTabSheet;
    TsServer: TTabSheet;
    TsLogs: TTabSheet;
    FStatusBar: TStatusBar;
    FUiTimer: TTimer;

    RgMode: TRadioGroup;
    BtnApplyMode: TButton;
    BtnSaveConfig: TButton;

    EdClientServerIp: TEdit;
    EdClientPort: TEdit;
    EdClientUser: TEdit;
    EdClientPass: TEdit;
    BtnClientConnect: TButton;
    BtnClientDisconnect: TButton;
    BtnConnectSelected: TButton;
    BtnOpenSessionWindow: TButton;
    LvProviders: TListView;
    EdHiddenMachine: TEdit;
    EdHiddenUser: TEdit;
    EdHiddenPass: TEdit;
    BtnConnectHidden: TButton;
    ImgRemote: TImage;
    TbQuality: TTrackBar;
    CbFps: TComboBox;
    ChkCaptureInput: TCheckBox;
    BtnSessionDisconnect: TButton;
    BtnSendClipboard: TButton;
    BtnSendFile: TButton;
    BtnSendCad: TButton;

    EdProvServerIp: TEdit;
    EdProvPort: TEdit;
    EdProvUser: TEdit;
    EdProvPass: TEdit;
    BtnProviderStart: TButton;
    BtnProviderStop: TButton;
    EdProvDisplay: TEdit;
    CbProvVisibility: TComboBox;
    CbProvAuthMode: TComboBox;
    EdProvLogin: TEdit;
    EdProvLoginPass: TEdit;
    ChkProvAutoAccept: TCheckBox;
    ChkProvAllowInput: TCheckBox;
    ChkProvAllowClipboard: TCheckBox;
    ChkProvAllowFiles: TCheckBox;
    BtnProviderEndSession: TButton;
    LblProviderStatus: TLabel;

    EdSrvBindIp: TEdit;
    EdSrvPort: TEdit;
    CbHiddenPolicy: TComboBox;
    BtnServerStart: TButton;
    BtnServerStop: TButton;
    LblServerStatus: TLabel;
    EdSrvUser: TEdit;
    EdSrvPass: TEdit;
    CbSrvRole: TComboBox;
    BtnSrvSaveUser: TButton;
    BtnSrvDeleteUser: TButton;
    LbServerUsers: TListBox;
    LbServerProviders: TListBox;
    LbServerSessions: TListBox;

    MemLogs: TMemo;
    FSessionForm: TForm;

    FRemoteWidth: Integer;
    FRemoteHeight: Integer;
    FLastFrameNo: Cardinal;
    FFrameUiBusy: Integer;
    FRemoteViews: array[0..2] of TImage;
    FRemoteViewIndex: Integer;
    FRenderMinIntervalMs: Cardinal;
    FLastRenderTick: Cardinal;
    FAdaptiveStartTick: Cardinal;
    FAdaptiveFrameCount: Integer;
    FAdaptiveApplied: Boolean;
    FUiTickCounter: Integer;
    FUiReady: Boolean;
    FShuttingDown: Boolean;

    procedure BuildUi;
    procedure BuildModeTab;
    procedure BuildClientTab;
    procedure BuildProviderTab;
    procedure BuildServerTab;
    procedure BuildLogsTab;
    procedure BuildStatusBar;
    procedure InitRoles;
    procedure LoadConfigToUi;
    procedure SaveUiToConfig;
    procedure ApplyMode;
    procedure RefreshServerLists;
    procedure RefreshServerUsersUi;
    procedure UpdateServerStatusUi;
    procedure EnsureSessionWindow;
    procedure ShowSessionWindow;
    procedure SessionWindowClose(Sender: TObject; var Action: TCloseAction);
    procedure ApplyAdaptivePreset;
    procedure LoggerLine(const ALine: string; ALevel: Integer; const AScope: string);
    function IsUiUsable: Boolean; inline;
    procedure WmUiLog(var Msg: TMessage); message WM_APP + 110;
    procedure WmUiClientStatus(var Msg: TMessage); message WM_APP + 111;
    procedure WmUiClientProviders(var Msg: TMessage); message WM_APP + 112;
    procedure WmUiClientFrame(var Msg: TMessage); message WM_APP + 113;
    procedure WmUiClientSession(var Msg: TMessage); message WM_APP + 114;
    procedure WmUiProviderStatus(var Msg: TMessage); message WM_APP + 115;
    procedure WmUiProviderSession(var Msg: TMessage); message WM_APP + 116;

    procedure UiTimerTick(Sender: TObject);
    procedure DoApplyMode(Sender: TObject);
    procedure DoSaveConfig(Sender: TObject);

    procedure DoClientConnect(Sender: TObject);
    procedure DoClientDisconnect(Sender: TObject);
    procedure DoConnectSelected(Sender: TObject);
    procedure DoProvidersDblClick(Sender: TObject);
    procedure DoConnectHidden(Sender: TObject);
    procedure DoOpenSessionWindow(Sender: TObject);
    procedure DoSessionDisconnect(Sender: TObject);
    procedure DoSendClipboard(Sender: TObject);
    procedure DoSendFile(Sender: TObject);
    procedure DoSendCad(Sender: TObject);
    procedure DoVideoSettingsChanged(Sender: TObject);

    procedure DoProviderStart(Sender: TObject);
    procedure DoProviderStop(Sender: TObject);
    procedure DoProviderEndSession(Sender: TObject);

    procedure DoServerStart(Sender: TObject);
    procedure DoServerStop(Sender: TObject);
    procedure DoServerSaveUser(Sender: TObject);
    procedure DoServerDeleteUser(Sender: TObject);

    procedure OnClientStatus(const AText: string);
    procedure OnClientProviders(const AJson: string);
    procedure OnClientFrame(ABitmap: TBitmap; AFrameNo: Cardinal);
    procedure OnClientSession(AActive: Boolean; const AMessage: string);
    procedure OnProviderStatus(const AText: string);
    procedure OnProviderSession(AActive: Boolean; const AMessage: string);

    procedure ImgRemoteMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ImgRemoteMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ImgRemoteMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    function MapImageToRemote(const AX, AY: Integer; out ARemoteX, ARemoteY: Integer): Boolean;
    function SendMouseMove(X, Y: Integer): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

type
  TUiStringData = class
  public
    Text: string;
    constructor Create(const AText: string);
  end;

  TUiSessionData = class(TUiStringData)
  public
    Active: Boolean;
    constructor Create(AActive: Boolean; const AText: string);
  end;

  TUiFrameData = class
  public
    Bitmap: TBitmap;
    FrameNo: Cardinal;
    constructor Create(ABitmap: TBitmap; AFrameNo: Cardinal);
    destructor Destroy; override;
  end;

constructor TUiStringData.Create(const AText: string);
begin
  inherited Create;
  Text := AText;
end;

constructor TUiSessionData.Create(AActive: Boolean; const AText: string);
begin
  inherited Create(AText);
  Active := AActive;
end;

constructor TUiFrameData.Create(ABitmap: TBitmap; AFrameNo: Cardinal);
begin
  inherited Create;
  Bitmap := ABitmap;
  FrameNo := AFrameNo;
end;

destructor TUiFrameData.Destroy;
begin
  Bitmap.Free;
  inherited Destroy;
end;

constructor TForm1.Create(AOwner: TComponent);
var
  LConfigPath: string;
begin
  inherited Create(AOwner);
  FUiReady := False;
  FShuttingDown := False;
  FRemoteViewIndex := 0;
  FRenderMinIntervalMs := 16;
  FLastRenderTick := 0;
  FAdaptiveStartTick := 0;
  FAdaptiveFrameCount := 0;
  FAdaptiveApplied := False;
  KeyPreview := True;
  OnKeyDown := FormKeyDown;
  OnKeyUp := FormKeyUp;
  OnMouseWheel := FormMouseWheel;

  LConfigPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'krvn.config.json');
  FConfig := TAppConfig.LoadOrCreate(LConfigPath, nil);
  FLogger := TKrvnLogger.Create(FConfig.LoggingLevel, FConfig.LoggingFolder, FConfig.LoggingRetentionDays);
  FLogger.OnLog := LoggerLine;

  BuildUi;
  InitRoles;
  LoadConfigToUi;
  if (CbFps <> nil) and (CbFps.ItemIndex < 0) and (CbFps.Items.Count > 0) then
    CbFps.ItemIndex := 0;
  FUiReady := True;
  if TbQuality <> nil then
    TbQuality.OnChange := DoVideoSettingsChanged;
  if CbFps <> nil then
    CbFps.OnChange := DoVideoSettingsChanged;
  ApplyMode;
  if FUiTimer <> nil then
    FUiTimer.Enabled := True;
end;

destructor TForm1.Destroy;
var
  LCanSaveConfig: Boolean;
begin
  LCanSaveConfig := FUiReady;
  FShuttingDown := True;
  FUiReady := False;
  if FSessionForm <> nil then
    FSessionForm.Hide;
  if FUiTimer <> nil then
    FUiTimer.Enabled := False;
  if FLogger <> nil then
    FLogger.OnLog := nil;
  if FClientRole <> nil then
  begin
    FClientRole.OnStatus := nil;
    FClientRole.OnProviders := nil;
    FClientRole.OnFrame := nil;
    FClientRole.OnSession := nil;
  end;
  if FProviderRole <> nil then
  begin
    FProviderRole.OnStatus := nil;
    FProviderRole.OnSession := nil;
  end;
  try
    TThread.RemoveQueuedEvents(nil);
  except
    // Ignore queue cleanup errors during shutdown.
  end;
  FreeAndNil(FClientRole);
  FreeAndNil(FProviderRole);
  FreeAndNil(FServerRole);
  if (FConfig <> nil) and LCanSaveConfig then
  begin
    SaveUiToConfig;
    FConfig.SaveToFile(TPath.Combine(ExtractFilePath(ParamStr(0)), 'krvn.config.json'));
  end;
  FreeAndNil(FLogger);
  FreeAndNil(FConfig);
  inherited Destroy;
end;

procedure TForm1.BuildUi;
begin
  Caption := 'Simple VNC - KRVN';
  Width := 1060;
  Height := 680;
  Position := poScreenCenter;
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu, biMinimize];
  Constraints.MinWidth := 980;
  Constraints.MinHeight := 620;

  FPageControl := TPageControl.Create(Self);
  FPageControl.Parent := Self;
  FPageControl.Align := alClient;

  TsMode := TTabSheet.Create(Self);
  TsMode.PageControl := FPageControl;
  TsMode.Caption := 'Mode';

  TsClient := TTabSheet.Create(Self);
  TsClient.PageControl := FPageControl;
  TsClient.Caption := 'Client';

  TsProvider := TTabSheet.Create(Self);
  TsProvider.PageControl := FPageControl;
  TsProvider.Caption := 'Provider';

  TsServer := TTabSheet.Create(Self);
  TsServer.PageControl := FPageControl;
  TsServer.Caption := 'Server';

  TsLogs := TTabSheet.Create(Self);
  TsLogs.PageControl := FPageControl;
  TsLogs.Caption := 'Logs';

  BuildModeTab;
  BuildClientTab;
  BuildProviderTab;
  BuildServerTab;
  BuildLogsTab;
  BuildStatusBar;

  FUiTimer := TTimer.Create(Self);
  FUiTimer.Interval := 1000;
  FUiTimer.OnTimer := UiTimerTick;
  FUiTimer.Enabled := False;
end;

procedure TForm1.BuildModeTab;
var
  LHint: TLabel;
begin
  RgMode := TRadioGroup.Create(Self);
  RgMode.Parent := TsMode;
  RgMode.Caption := 'Startup Mode';
  RgMode.Items.Add('Client');
  RgMode.Items.Add('Server');
  RgMode.Items.Add('Provider');
  RgMode.Items.Add('Combo (Server + Provider)');
  RgMode.SetBounds(24, 24, 320, 180);

  BtnApplyMode := TButton.Create(Self);
  BtnApplyMode.Parent := TsMode;
  BtnApplyMode.Caption := 'Apply Mode';
  BtnApplyMode.SetBounds(24, 220, 140, 32);
  BtnApplyMode.OnClick := DoApplyMode;

  BtnSaveConfig := TButton.Create(Self);
  BtnSaveConfig.Parent := TsMode;
  BtnSaveConfig.Caption := 'Save Config';
  BtnSaveConfig.SetBounds(180, 220, 140, 32);
  BtnSaveConfig.OnClick := DoSaveConfig;

  LHint := TLabel.Create(Self);
  LHint.Parent := TsMode;
  LHint.Caption :=
    'One EXE supports Client / Server / Provider / Combo.' + sLineBreak +
    'Server credentials and Provider credentials are configured separately.' + sLineBreak +
    'Provider reconnects automatically with backoff.';
  LHint.SetBounds(24, 270, 620, 80);
  LHint.WordWrap := True;
end;

procedure TForm1.BuildClientTab;
var
  PRoot, PTop, PBody, PLeft, PRight, PLeftBtns: TPanel;
  GbServer, GbProviderAccess, GbProviders, GbSession: TGroupBox;
  Lbl, LHint: TLabel;
begin
  PRoot := TPanel.Create(Self);
  PRoot.Parent := TsClient;
  PRoot.Align := alClient;
  PRoot.BevelOuter := bvNone;

  PTop := TPanel.Create(Self);
  PTop.Parent := PRoot;
  PTop.Align := alTop;
  PTop.Height := 126;
  PTop.BevelOuter := bvNone;

  GbServer := TGroupBox.Create(Self);
  GbServer.Parent := PTop;
  GbServer.Align := alLeft;
  GbServer.Width := 500;
  GbServer.Caption := '1) Server Connection';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbServer;
  Lbl.Caption := 'Server IP';
  Lbl.SetBounds(10, 24, 70, 16);

  EdClientServerIp := TEdit.Create(Self);
  EdClientServerIp.Parent := GbServer;
  EdClientServerIp.SetBounds(8, 40, 130, 23);
  EdClientServerIp.TextHint := '127.0.0.1';
  EdClientServerIp.ShowHint := True;
  EdClientServerIp.Hint := 'IP or DNS name of relay server.';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbServer;
  Lbl.Caption := 'Port';
  Lbl.SetBounds(156, 24, 40, 16);

  EdClientPort := TEdit.Create(Self);
  EdClientPort.Parent := GbServer;
  EdClientPort.SetBounds(142, 40, 64, 23);
  EdClientPort.TextHint := '5590';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbServer;
  Lbl.Caption := 'Server Login';
  Lbl.SetBounds(232, 24, 90, 16);

  EdClientUser := TEdit.Create(Self);
  EdClientUser.Parent := GbServer;
  EdClientUser.SetBounds(210, 40, 132, 23);
  EdClientUser.TextHint := 'client1';
  EdClientUser.ShowHint := True;
  EdClientUser.Hint := 'Account on relay server.';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbServer;
  Lbl.Caption := 'Server Password';
  Lbl.SetBounds(378, 24, 100, 16);

  EdClientPass := TEdit.Create(Self);
  EdClientPass.Parent := GbServer;
  EdClientPass.SetBounds(346, 40, 132, 23);
  EdClientPass.PasswordChar := '*';
  EdClientPass.TextHint := 'client password';

  BtnClientConnect := TButton.Create(Self);
  BtnClientConnect.Parent := GbServer;
  BtnClientConnect.Caption := 'Connect';
  BtnClientConnect.SetBounds(8, 72, 86, 25);
  BtnClientConnect.OnClick := DoClientConnect;
  BtnClientConnect.ShowHint := True;
  BtnClientConnect.Hint := 'Connect to relay server using Server Login/Password.';

  BtnClientDisconnect := TButton.Create(Self);
  BtnClientDisconnect.Parent := GbServer;
  BtnClientDisconnect.Caption := 'Disconnect';
  BtnClientDisconnect.SetBounds(98, 72, 86, 25);
  BtnClientDisconnect.OnClick := DoClientDisconnect;

  LHint := TLabel.Create(Self);
  LHint.Parent := GbServer;
  LHint.Caption :=
    'Use server credentials here. Providers list updates automatically every second.';
  LHint.SetBounds(8, 99, 488, 22);
  LHint.WordWrap := True;

  GbProviderAccess := TGroupBox.Create(Self);
  GbProviderAccess.Parent := PTop;
  GbProviderAccess.Align := alClient;
  GbProviderAccess.Caption := '2) Provider Access';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbProviderAccess;
  Lbl.Caption := 'Provider Login';
  Lbl.SetBounds(10, 24, 90, 16);

  EdHiddenUser := TEdit.Create(Self);
  EdHiddenUser.Parent := GbProviderAccess;
  EdHiddenUser.SetBounds(8, 40, 110, 23);
  EdHiddenUser.TextHint := 'provider login';
  EdHiddenUser.ShowHint := True;
  EdHiddenUser.Hint := 'Credentials for selected/hidden provider session (if provider requires auth).';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbProviderAccess;
  Lbl.Caption := 'Provider Password';
  Lbl.SetBounds(136, 24, 100, 16);

  EdHiddenPass := TEdit.Create(Self);
  EdHiddenPass.Parent := GbProviderAccess;
  EdHiddenPass.SetBounds(122, 40, 110, 23);
  EdHiddenPass.PasswordChar := '*';
  EdHiddenPass.TextHint := 'provider password';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbProviderAccess;
  Lbl.Caption := 'Hidden machineName';
  Lbl.SetBounds(262, 24, 110, 16);

  EdHiddenMachine := TEdit.Create(Self);
  EdHiddenMachine.Parent := GbProviderAccess;
  EdHiddenMachine.SetBounds(236, 40, 120, 23);
  EdHiddenMachine.TextHint := 'PC-NAME';
  EdHiddenMachine.ShowHint := True;
  EdHiddenMachine.Hint := 'Used only for hidden provider connection.';

  BtnConnectHidden := TButton.Create(Self);
  BtnConnectHidden.Parent := GbProviderAccess;
  BtnConnectHidden.Caption := 'Connect Hidden';
  BtnConnectHidden.SetBounds(362, 39, 92, 25);
  BtnConnectHidden.OnClick := DoConnectHidden;

  BtnOpenSessionWindow := TButton.Create(Self);
  BtnOpenSessionWindow.Parent := GbProviderAccess;
  BtnOpenSessionWindow.Caption := 'Session Window';
  BtnOpenSessionWindow.SetBounds(458, 39, 92, 25);
  BtnOpenSessionWindow.OnClick := DoOpenSessionWindow;

  LHint := TLabel.Create(Self);
  LHint.Parent := GbProviderAccess;
  LHint.Caption := 'When connecting to selected provider, Provider Login/Password above are sent if filled.';
  LHint.SetBounds(8, 98, 546, 22);
  LHint.WordWrap := True;

  PBody := TPanel.Create(Self);
  PBody.Parent := PRoot;
  PBody.Align := alClient;
  PBody.BevelOuter := bvNone;

  PLeft := TPanel.Create(Self);
  PLeft.Parent := PBody;
  PLeft.Align := alLeft;
  PLeft.Width := 500;
  PLeft.BevelOuter := bvNone;

  GbProviders := TGroupBox.Create(Self);
  GbProviders.Parent := PLeft;
  GbProviders.Align := alClient;
  GbProviders.Caption := 'Available Providers';

  LvProviders := TListView.Create(Self);
  LvProviders.Parent := GbProviders;
  LvProviders.Align := alClient;
  LvProviders.ViewStyle := vsReport;
  LvProviders.ReadOnly := True;
  LvProviders.RowSelect := True;
  LvProviders.OnDblClick := DoProvidersDblClick;
  LvProviders.Columns.Add.Caption := 'ProviderKey';
  LvProviders.Columns.Add.Caption := 'Display';
  LvProviders.Columns.Add.Caption := 'Machine';
  LvProviders.Columns.Add.Caption := 'Auth';
  LvProviders.Columns.Add.Caption := 'Online';
  if LvProviders.Columns.Count >= 5 then
  begin
    LvProviders.Columns[0].Width := 90;
    LvProviders.Columns[1].Width := 110;
    LvProviders.Columns[2].Width := 95;
    LvProviders.Columns[3].Width := 75;
    LvProviders.Columns[4].Width := 60;
  end;

  PLeftBtns := TPanel.Create(Self);
  PLeftBtns.Parent := GbProviders;
  PLeftBtns.Align := alBottom;
  PLeftBtns.Height := 42;
  PLeftBtns.BevelOuter := bvNone;

  BtnConnectSelected := TButton.Create(Self);
  BtnConnectSelected.Parent := PLeftBtns;
  BtnConnectSelected.Caption := 'Connect Selected';
  BtnConnectSelected.SetBounds(8, 8, 130, 25);
  BtnConnectSelected.OnClick := DoConnectSelected;
  BtnConnectSelected.ShowHint := True;
  BtnConnectSelected.Hint := 'Connect to selected provider. Provider Login/Password are used if entered.';

  PRight := TPanel.Create(Self);
  PRight.Parent := PBody;
  PRight.Align := alClient;
  PRight.BevelOuter := bvNone;

  GbSession := TGroupBox.Create(Self);
  GbSession.Parent := PRight;
  GbSession.Align := alClient;
  GbSession.Caption := 'Session';

  LHint := TLabel.Create(Self);
  LHint.Parent := GbSession;
  LHint.Caption :=
    'Remote image is shown in a separate resizable "Remote Session" window.' + sLineBreak +
    'Use "Session Window" button or connect to provider to open it automatically.';
  LHint.SetBounds(10, 24, 460, 46);
  LHint.WordWrap := True;

  EnsureSessionWindow;
end;

procedure TForm1.BuildProviderTab;
var
  PRoot: TPanel;
  GbServerAuth, GbProviderAuth, GbControls: TGroupBox;
  Lbl, LHint: TLabel;
begin
  PRoot := TPanel.Create(Self);
  PRoot.Parent := TsProvider;
  PRoot.Align := alClient;
  PRoot.BevelOuter := bvNone;

  GbServerAuth := TGroupBox.Create(Self);
  GbServerAuth.Parent := PRoot;
  GbServerAuth.Align := alTop;
  GbServerAuth.Height := 120;
  GbServerAuth.Caption := '1) Relay Server Credentials';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbServerAuth;
  Lbl.Caption := 'Server IP';
  Lbl.SetBounds(10, 24, 70, 16);

  EdProvServerIp := TEdit.Create(Self);
  EdProvServerIp.Parent := GbServerAuth;
  EdProvServerIp.SetBounds(10, 42, 150, 24);
  EdProvServerIp.TextHint := '127.0.0.1';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbServerAuth;
  Lbl.Caption := 'Port';
  Lbl.SetBounds(166, 24, 40, 16);

  EdProvPort := TEdit.Create(Self);
  EdProvPort.Parent := GbServerAuth;
  EdProvPort.SetBounds(166, 42, 70, 24);
  EdProvPort.TextHint := '5590';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbServerAuth;
  Lbl.Caption := 'Server Login';
  Lbl.SetBounds(242, 24, 90, 16);

  EdProvUser := TEdit.Create(Self);
  EdProvUser.Parent := GbServerAuth;
  EdProvUser.SetBounds(242, 42, 130, 24);
  EdProvUser.TextHint := 'provider1';
  EdProvUser.ShowHint := True;
  EdProvUser.Hint := 'Provider account for login to relay server (not provider session auth).';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbServerAuth;
  Lbl.Caption := 'Server Password';
  Lbl.SetBounds(378, 24, 100, 16);

  EdProvPass := TEdit.Create(Self);
  EdProvPass.Parent := GbServerAuth;
  EdProvPass.SetBounds(378, 42, 130, 24);
  EdProvPass.PasswordChar := '*';
  EdProvPass.TextHint := 'provider password';
  EdProvPass.ShowHint := True;
  EdProvPass.Hint := 'Password for provider account on relay server.';

  BtnProviderStart := TButton.Create(Self);
  BtnProviderStart.Parent := GbServerAuth;
  BtnProviderStart.Caption := 'Start Provider';
  BtnProviderStart.SetBounds(516, 40, 110, 28);
  BtnProviderStart.OnClick := DoProviderStart;

  BtnProviderStop := TButton.Create(Self);
  BtnProviderStop.Parent := GbServerAuth;
  BtnProviderStop.Caption := 'Stop Provider';
  BtnProviderStop.SetBounds(632, 40, 110, 28);
  BtnProviderStop.OnClick := DoProviderStop;

  LHint := TLabel.Create(Self);
  LHint.Parent := GbServerAuth;
  LHint.Caption := 'These credentials are used only to authenticate Provider to the relay server.';
  LHint.SetBounds(10, 76, 740, 30);
  LHint.WordWrap := True;

  GbProviderAuth := TGroupBox.Create(Self);
  GbProviderAuth.Parent := PRoot;
  GbProviderAuth.Align := alTop;
  GbProviderAuth.Height := 150;
  GbProviderAuth.Caption := '2) Provider Identity and Access';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbProviderAuth;
  Lbl.Caption := 'Display Name';
  Lbl.SetBounds(10, 24, 80, 16);

  EdProvDisplay := TEdit.Create(Self);
  EdProvDisplay.Parent := GbProviderAuth;
  EdProvDisplay.SetBounds(10, 42, 220, 24);
  EdProvDisplay.TextHint := 'Office PC';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbProviderAuth;
  Lbl.Caption := 'Visibility';
  Lbl.SetBounds(236, 24, 70, 16);

  CbProvVisibility := TComboBox.Create(Self);
  CbProvVisibility.Parent := GbProviderAuth;
  CbProvVisibility.SetBounds(236, 42, 100, 24);
  CbProvVisibility.Style := csDropDownList;
  CbProvVisibility.Items.Add('public');
  CbProvVisibility.Items.Add('hidden');

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbProviderAuth;
  Lbl.Caption := 'Provider Auth';
  Lbl.SetBounds(342, 24, 90, 16);

  CbProvAuthMode := TComboBox.Create(Self);
  CbProvAuthMode.Parent := GbProviderAuth;
  CbProvAuthMode.SetBounds(342, 42, 150, 24);
  CbProvAuthMode.Style := csDropDownList;
  CbProvAuthMode.Items.Add('none');
  CbProvAuthMode.Items.Add('login_password');
  CbProvAuthMode.ShowHint := True;
  CbProvAuthMode.Hint := 'If set to login_password, client must provide Provider Login/Password.';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbProviderAuth;
  Lbl.Caption := 'Provider Login';
  Lbl.SetBounds(498, 24, 90, 16);

  EdProvLogin := TEdit.Create(Self);
  EdProvLogin.Parent := GbProviderAuth;
  EdProvLogin.SetBounds(498, 42, 120, 24);
  EdProvLogin.TextHint := 'operator';
  EdProvLogin.ShowHint := True;
  EdProvLogin.Hint := 'Login that client must enter when connecting to this provider.';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbProviderAuth;
  Lbl.Caption := 'Provider Password';
  Lbl.SetBounds(624, 24, 100, 16);

  EdProvLoginPass := TEdit.Create(Self);
  EdProvLoginPass.Parent := GbProviderAuth;
  EdProvLoginPass.SetBounds(624, 42, 120, 24);
  EdProvLoginPass.PasswordChar := '*';
  EdProvLoginPass.TextHint := 'provider session password';
  EdProvLoginPass.ShowHint := True;
  EdProvLoginPass.Hint := 'Password that client must enter when connecting to this provider.';

  ChkProvAutoAccept := TCheckBox.Create(Self);
  ChkProvAutoAccept.Parent := GbProviderAuth;
  ChkProvAutoAccept.Caption := 'Auto accept session';
  ChkProvAutoAccept.SetBounds(10, 78, 150, 20);

  ChkProvAllowInput := TCheckBox.Create(Self);
  ChkProvAllowInput.Parent := GbProviderAuth;
  ChkProvAllowInput.Caption := 'Allow input';
  ChkProvAllowInput.SetBounds(170, 78, 120, 20);

  ChkProvAllowClipboard := TCheckBox.Create(Self);
  ChkProvAllowClipboard.Parent := GbProviderAuth;
  ChkProvAllowClipboard.Caption := 'Allow clipboard';
  ChkProvAllowClipboard.SetBounds(294, 78, 130, 20);

  ChkProvAllowFiles := TCheckBox.Create(Self);
  ChkProvAllowFiles.Parent := GbProviderAuth;
  ChkProvAllowFiles.Caption := 'Allow files';
  ChkProvAllowFiles.SetBounds(430, 78, 120, 20);

  LHint := TLabel.Create(Self);
  LHint.Parent := GbProviderAuth;
  LHint.Caption := 'Provider Login/Password are requested from client only if Provider Auth = login_password.';
  LHint.SetBounds(10, 106, 740, 30);
  LHint.WordWrap := True;

  GbControls := TGroupBox.Create(Self);
  GbControls.Parent := PRoot;
  GbControls.Align := alTop;
  GbControls.Height := 80;
  GbControls.Caption := '3) Active Session Control';

  BtnProviderEndSession := TButton.Create(Self);
  BtnProviderEndSession.Parent := GbControls;
  BtnProviderEndSession.Caption := 'End Active Session';
  BtnProviderEndSession.SetBounds(10, 30, 160, 28);
  BtnProviderEndSession.OnClick := DoProviderEndSession;

  LblProviderStatus := TLabel.Create(Self);
  LblProviderStatus.Parent := GbControls;
  LblProviderStatus.Caption := 'Provider status: stopped';
  LblProviderStatus.SetBounds(190, 34, 800, 20);
end;

procedure TForm1.BuildServerTab;
var
  PRoot, PLists, PLeft, PRight: TPanel;
  GbConfig, GbUsers, GbProviders, GbSessions: TGroupBox;
  Lbl, LHint: TLabel;
begin
  PRoot := TPanel.Create(Self);
  PRoot.Parent := TsServer;
  PRoot.Align := alClient;
  PRoot.BevelOuter := bvNone;

  GbConfig := TGroupBox.Create(Self);
  GbConfig.Parent := PRoot;
  GbConfig.Align := alTop;
  GbConfig.Height := 122;
  GbConfig.Caption := 'Server Runtime';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbConfig;
  Lbl.Caption := 'Bind IP';
  Lbl.SetBounds(10, 24, 50, 16);

  EdSrvBindIp := TEdit.Create(Self);
  EdSrvBindIp.Parent := GbConfig;
  EdSrvBindIp.SetBounds(10, 42, 150, 24);
  EdSrvBindIp.TextHint := '0.0.0.0';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbConfig;
  Lbl.Caption := 'Port';
  Lbl.SetBounds(166, 24, 40, 16);

  EdSrvPort := TEdit.Create(Self);
  EdSrvPort.Parent := GbConfig;
  EdSrvPort.SetBounds(166, 42, 80, 24);
  EdSrvPort.TextHint := '5590';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbConfig;
  Lbl.Caption := 'Hidden Resolve Policy';
  Lbl.SetBounds(252, 24, 130, 16);

  CbHiddenPolicy := TComboBox.Create(Self);
  CbHiddenPolicy.Parent := GbConfig;
  CbHiddenPolicy.SetBounds(252, 42, 130, 24);
  CbHiddenPolicy.Style := csDropDownList;
  CbHiddenPolicy.Items.Add('restricted');
  CbHiddenPolicy.Items.Add('first');
  CbHiddenPolicy.Items.Add('last');
  CbHiddenPolicy.ShowHint := True;
  CbHiddenPolicy.Hint := 'Hidden connect policy when several providers share same machineName.';

  BtnServerStart := TButton.Create(Self);
  BtnServerStart.Parent := GbConfig;
  BtnServerStart.Caption := 'Start Server';
  BtnServerStart.SetBounds(390, 40, 110, 28);
  BtnServerStart.OnClick := DoServerStart;

  BtnServerStop := TButton.Create(Self);
  BtnServerStop.Parent := GbConfig;
  BtnServerStop.Caption := 'Stop Server';
  BtnServerStop.SetBounds(506, 40, 110, 28);
  BtnServerStop.OnClick := DoServerStop;

  LblServerStatus := TLabel.Create(Self);
  LblServerStatus.Parent := GbConfig;
  LblServerStatus.Caption := 'Server state: stopped';
  LblServerStatus.SetBounds(632, 45, 260, 20);

  LHint := TLabel.Create(Self);
  LHint.Parent := GbConfig;
  LHint.Caption := 'Server credentials are managed below in "Server Users" and saved to krvn.config.json.';
  LHint.SetBounds(10, 78, 760, 30);
  LHint.WordWrap := True;

  GbUsers := TGroupBox.Create(Self);
  GbUsers.Parent := PRoot;
  GbUsers.Align := alTop;
  GbUsers.Height := 170;
  GbUsers.Caption := 'Server Users (Login/Password)';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbUsers;
  Lbl.Caption := 'Login';
  Lbl.SetBounds(10, 24, 50, 16);

  EdSrvUser := TEdit.Create(Self);
  EdSrvUser.Parent := GbUsers;
  EdSrvUser.SetBounds(10, 42, 150, 24);
  EdSrvUser.TextHint := 'client1';
  EdSrvUser.ShowHint := True;
  EdSrvUser.Hint := 'Account used by Client/Provider when connecting to relay server.';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbUsers;
  Lbl.Caption := 'Password';
  Lbl.SetBounds(166, 24, 70, 16);

  EdSrvPass := TEdit.Create(Self);
  EdSrvPass.Parent := GbUsers;
  EdSrvPass.SetBounds(166, 42, 150, 24);
  EdSrvPass.PasswordChar := '*';
  EdSrvPass.TextHint := 'new password';
  EdSrvPass.ShowHint := True;
  EdSrvPass.Hint := 'New password for selected login. Stored as PBKDF2 hash in config.';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := GbUsers;
  Lbl.Caption := 'Role';
  Lbl.SetBounds(322, 24, 40, 16);

  CbSrvRole := TComboBox.Create(Self);
  CbSrvRole.Parent := GbUsers;
  CbSrvRole.SetBounds(322, 42, 130, 24);
  CbSrvRole.Style := csDropDownList;
  CbSrvRole.Items.Add('client');
  CbSrvRole.Items.Add('provider');
  CbSrvRole.Items.Add('server-admin');
  CbSrvRole.ShowHint := True;
  CbSrvRole.Hint := 'Role to grant for this login.';
  CbSrvRole.ItemIndex := 0;

  BtnSrvSaveUser := TButton.Create(Self);
  BtnSrvSaveUser.Parent := GbUsers;
  BtnSrvSaveUser.Caption := 'Save/Update User';
  BtnSrvSaveUser.SetBounds(460, 40, 130, 28);
  BtnSrvSaveUser.OnClick := DoServerSaveUser;

  BtnSrvDeleteUser := TButton.Create(Self);
  BtnSrvDeleteUser.Parent := GbUsers;
  BtnSrvDeleteUser.Caption := 'Delete User';
  BtnSrvDeleteUser.SetBounds(596, 40, 110, 28);
  BtnSrvDeleteUser.OnClick := DoServerDeleteUser;

  LHint := TLabel.Create(Self);
  LHint.Parent := GbUsers;
  LHint.Caption := 'Client and Provider must use these server users in their "Server Login/Password" fields.';
  LHint.SetBounds(10, 72, 740, 28);
  LHint.WordWrap := True;

  LbServerUsers := TListBox.Create(Self);
  LbServerUsers.Parent := GbUsers;
  LbServerUsers.Align := alBottom;
  LbServerUsers.Height := 62;
  LbServerUsers.ShowHint := True;
  LbServerUsers.Hint := 'Configured server users and granted roles.';

  PLists := TPanel.Create(Self);
  PLists.Parent := PRoot;
  PLists.Align := alClient;
  PLists.BevelOuter := bvNone;

  PLeft := TPanel.Create(Self);
  PLeft.Parent := PLists;
  PLeft.Align := alLeft;
  PLeft.Width := 580;
  PLeft.BevelOuter := bvNone;

  GbProviders := TGroupBox.Create(Self);
  GbProviders.Parent := PLeft;
  GbProviders.Align := alClient;
  GbProviders.Caption := 'Providers (online/offline)';

  LbServerProviders := TListBox.Create(Self);
  LbServerProviders.Parent := GbProviders;
  LbServerProviders.Align := alClient;

  PRight := TPanel.Create(Self);
  PRight.Parent := PLists;
  PRight.Align := alClient;
  PRight.BevelOuter := bvNone;

  GbSessions := TGroupBox.Create(Self);
  GbSessions.Parent := PRight;
  GbSessions.Align := alClient;
  GbSessions.Caption := 'Sessions';

  LbServerSessions := TListBox.Create(Self);
  LbServerSessions.Parent := GbSessions;
  LbServerSessions.Align := alClient;
end;

procedure TForm1.BuildLogsTab;
begin
  MemLogs := TMemo.Create(Self);
  MemLogs.Parent := TsLogs;
  MemLogs.Align := alClient;
  MemLogs.ScrollBars := ssVertical;
end;

procedure TForm1.BuildStatusBar;
begin
  FStatusBar := TStatusBar.Create(Self);
  FStatusBar.Parent := Self;
  FStatusBar.Align := alBottom;
  FStatusBar.Panels.Add;
  FStatusBar.Panels.Add;
  FStatusBar.Panels.Add;
  FStatusBar.Panels.Add;
  FStatusBar.Panels[0].Width := 180; // mode
  FStatusBar.Panels[1].Width := 180; // server state
  FStatusBar.Panels[2].Width := 180; // session
  FStatusBar.Panels[3].Width := 520; // hints/state text
  FStatusBar.Panels[3].Text := 'Connect to server -> wait providers auto-update -> connect provider.';
end;

procedure TForm1.InitRoles;
begin
  FServerRole := TServerRole.Create(FConfig, FLogger);

  FProviderRole := TProviderRole.Create(FConfig, FLogger);
  FProviderRole.OnStatus := OnProviderStatus;
  FProviderRole.OnSession := OnProviderSession;

  FClientRole := TClientRole.Create(FConfig, FLogger);
  FClientRole.OnStatus := OnClientStatus;
  FClientRole.OnProviders := OnClientProviders;
  FClientRole.OnFrame := OnClientFrame;
  FClientRole.OnSession := OnClientSession;
  UpdateServerStatusUi;
end;

procedure TForm1.LoadConfigToUi;
begin
  if SameText(FConfig.Mode, 'server') then
    RgMode.ItemIndex := 1
  else if SameText(FConfig.Mode, 'provider') then
    RgMode.ItemIndex := 2
  else if SameText(FConfig.Mode, 'combo') then
    RgMode.ItemIndex := 3
  else
    RgMode.ItemIndex := 0;

  EdClientServerIp.Text := FConfig.ClientServerIp;
  EdClientPort.Text := IntToStr(FConfig.ClientServerPort);
  EdClientUser.Text := FConfig.ClientUsername;
  try
    EdClientPass.Text := TKrvnCrypto.UnprotectStringDpapi(FConfig.ClientSecret);
  except
    EdClientPass.Text := FConfig.ClientSecret;
  end;
  EdHiddenUser.Text := FConfig.ClientProviderUser;
  try
    EdHiddenPass.Text := TKrvnCrypto.UnprotectStringDpapi(FConfig.ClientProviderSecret);
  except
    EdHiddenPass.Text := FConfig.ClientProviderSecret;
  end;
  TbQuality.Position := FConfig.ProviderQuality;
  CbFps.ItemIndex := Max(0, CbFps.Items.IndexOf(IntToStr(FConfig.ProviderFps)));

  EdProvServerIp.Text := FConfig.ProviderServerIp;
  EdProvPort.Text := IntToStr(FConfig.ProviderServerPort);
  EdProvUser.Text := FConfig.ProviderServerUser;
  try
    EdProvPass.Text := TKrvnCrypto.UnprotectStringDpapi(FConfig.ProviderServerSecret);
  except
    EdProvPass.Text := FConfig.ProviderServerSecret;
  end;
  EdProvDisplay.Text := FConfig.ProviderDisplayName;
  CbProvVisibility.ItemIndex := Ord(FConfig.ProviderVisibility);
  CbProvAuthMode.ItemIndex := Max(0, CbProvAuthMode.Items.IndexOf(FConfig.ProviderAuthMode));
  EdProvLogin.Text := FConfig.ProviderUser;
  try
    EdProvLoginPass.Text := TKrvnCrypto.UnprotectStringDpapi(FConfig.ProviderSecret);
  except
    EdProvLoginPass.Text := FConfig.ProviderSecret;
  end;
  ChkProvAutoAccept.Checked := FConfig.ProviderAutoAccept;
  ChkProvAllowInput.Checked := FConfig.ProviderAllowInput;
  ChkProvAllowClipboard.Checked := FConfig.ProviderAllowClipboard;
  ChkProvAllowFiles.Checked := FConfig.ProviderAllowFiles;

  EdSrvBindIp.Text := FConfig.ServerBindIp;
  EdSrvPort.Text := IntToStr(FConfig.ServerPort);
  CbHiddenPolicy.ItemIndex := Max(0, CbHiddenPolicy.Items.IndexOf(HiddenResolvePolicyToStr(FConfig.HiddenResolvePolicy)));
  if (CbSrvRole <> nil) and (CbSrvRole.Items.Count > 0) and (CbSrvRole.ItemIndex < 0) then
    CbSrvRole.ItemIndex := 0;
  RefreshServerUsersUi;
end;

procedure TForm1.SaveUiToConfig;
begin
  case RgMode.ItemIndex of
    1: FConfig.Mode := 'server';
    2: FConfig.Mode := 'provider';
    3: FConfig.Mode := 'combo';
  else
    FConfig.Mode := 'client';
  end;

  FConfig.ClientServerIp := EdClientServerIp.Text;
  FConfig.ClientServerPort := StrToIntDef(EdClientPort.Text, 5590);
  FConfig.ClientUsername := EdClientUser.Text;
  try
    FConfig.ClientSecret := TKrvnCrypto.ProtectStringDpapi(EdClientPass.Text);
  except
    FConfig.ClientSecret := EdClientPass.Text;
  end;
  FConfig.ClientProviderUser := EdHiddenUser.Text;
  try
    FConfig.ClientProviderSecret := TKrvnCrypto.ProtectStringDpapi(EdHiddenPass.Text);
  except
    FConfig.ClientProviderSecret := EdHiddenPass.Text;
  end;

  FConfig.ProviderServerIp := EdProvServerIp.Text;
  FConfig.ProviderServerPort := StrToIntDef(EdProvPort.Text, 5590);
  FConfig.ProviderServerUser := EdProvUser.Text;
  try
    FConfig.ProviderServerSecret := TKrvnCrypto.ProtectStringDpapi(EdProvPass.Text);
  except
    FConfig.ProviderServerSecret := EdProvPass.Text;
  end;
  FConfig.ProviderDisplayName := EdProvDisplay.Text;
  if CbProvVisibility.ItemIndex = 1 then
    FConfig.ProviderVisibility := kvHidden
  else
    FConfig.ProviderVisibility := kvPublic;
  FConfig.ProviderAuthMode := CbProvAuthMode.Text;
  FConfig.ProviderUser := EdProvLogin.Text;
  try
    FConfig.ProviderSecret := TKrvnCrypto.ProtectStringDpapi(EdProvLoginPass.Text);
  except
    FConfig.ProviderSecret := EdProvLoginPass.Text;
  end;
  FConfig.ProviderAutoAccept := ChkProvAutoAccept.Checked;
  FConfig.ProviderAllowInput := ChkProvAllowInput.Checked;
  FConfig.ProviderAllowClipboard := ChkProvAllowClipboard.Checked;
  FConfig.ProviderAllowFiles := ChkProvAllowFiles.Checked;

  FConfig.ServerBindIp := EdSrvBindIp.Text;
  FConfig.ServerPort := StrToIntDef(EdSrvPort.Text, 5590);
  FConfig.HiddenResolvePolicy := StrToHiddenResolvePolicy(CbHiddenPolicy.Text);
end;

procedure TForm1.ApplyMode;
begin
  if FServerRole.IsRunning then
    FServerRole.Stop;
  FProviderRole.Stop;
  FClientRole.Disconnect;

  if RgMode.ItemIndex = 3 then
  begin
    // In combo mode provider must connect to local embedded server.
    FConfig.ProviderServerIp := '127.0.0.1';
    FConfig.ProviderServerPort := StrToIntDef(EdSrvPort.Text, FConfig.ServerPort);
    FConfig.ProviderVisibility := kvPublic;
    if EdProvServerIp <> nil then
      EdProvServerIp.Text := FConfig.ProviderServerIp;
    if EdProvPort <> nil then
      EdProvPort.Text := IntToStr(FConfig.ProviderServerPort);
    if CbProvVisibility <> nil then
      CbProvVisibility.ItemIndex := 0;
    if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
      FStatusBar.Panels[3].Text :=
        'Combo mode: provider is local (127.0.0.1) and visibility forced to public.';
  end;

  if RgMode.ItemIndex in [1, 3] then
    FServerRole.Start;
  if RgMode.ItemIndex in [2, 3] then
    FProviderRole.Start;
  UpdateServerStatusUi;
end;

procedure TForm1.RefreshServerLists;
var
  LArr: TArray<string>;
  LLine: string;
  LProvidersIndex: Integer;
  LSessionsIndex: Integer;
begin
  LProvidersIndex := -1;
  if LbServerProviders <> nil then
    LProvidersIndex := LbServerProviders.ItemIndex;
  LSessionsIndex := -1;
  if LbServerSessions <> nil then
    LSessionsIndex := LbServerSessions.ItemIndex;

  LbServerProviders.Items.BeginUpdate;
  try
    LbServerProviders.Clear;
    LArr := FServerRole.ProvidersSummary;
    for LLine in LArr do
      LbServerProviders.Items.Add(LLine);
    if LProvidersIndex >= LbServerProviders.Items.Count then
      LProvidersIndex := LbServerProviders.Items.Count - 1;
    LbServerProviders.ItemIndex := LProvidersIndex;
  finally
    LbServerProviders.Items.EndUpdate;
  end;

  LbServerSessions.Items.BeginUpdate;
  try
    LbServerSessions.Clear;
    LArr := FServerRole.SessionsSummary;
    for LLine in LArr do
      LbServerSessions.Items.Add(LLine);
    if LSessionsIndex >= LbServerSessions.Items.Count then
      LSessionsIndex := LbServerSessions.Items.Count - 1;
    LbServerSessions.ItemIndex := LSessionsIndex;
  finally
    LbServerSessions.Items.EndUpdate;
  end;
end;

procedure TForm1.RefreshServerUsersUi;
var
  LUser: TKrvnUser;
  I: Integer;
  LRoles: string;
  LUsersIndex: Integer;
begin
  if (LbServerUsers = nil) or (FConfig = nil) then
    Exit;

  LUsersIndex := LbServerUsers.ItemIndex;

  LbServerUsers.Items.BeginUpdate;
  try
    LbServerUsers.Clear;
    for LUser in FConfig.ServerUsers do
    begin
      LRoles := '';
      for I := 0 to Length(LUser.Roles) - 1 do
      begin
        if I > 0 then
          LRoles := LRoles + ',';
        LRoles := LRoles + LUser.Roles[I];
      end;
      if LRoles = '' then
        LRoles := 'none';
      LbServerUsers.Items.Add(LUser.Username + ' [' + LRoles + ']');
    end;
    if LUsersIndex >= LbServerUsers.Items.Count then
      LUsersIndex := LbServerUsers.Items.Count - 1;
    LbServerUsers.ItemIndex := LUsersIndex;
  finally
    LbServerUsers.Items.EndUpdate;
  end;
end;

procedure TForm1.EnsureSessionWindow;
var
  PRoot: TPanel;
  PToolbar: TPanel;
  PVideoHost: TPanel;
  Lbl: TLabel;
  I: Integer;
begin
  if FSessionForm <> nil then
    Exit;

  FSessionForm := TForm.CreateNew(Self);
  FSessionForm.Caption := 'Remote Session';
  FSessionForm.Position := poScreenCenter;
  FSessionForm.Width := 1120;
  FSessionForm.Height := 760;
  FSessionForm.BorderStyle := bsSizeable;
  FSessionForm.KeyPreview := True;
  FSessionForm.OnKeyDown := FormKeyDown;
  FSessionForm.OnKeyUp := FormKeyUp;
  FSessionForm.OnMouseWheel := FormMouseWheel;
  FSessionForm.OnClose := SessionWindowClose;

  PRoot := TPanel.Create(Self);
  PRoot.Parent := FSessionForm;
  PRoot.Align := alClient;
  PRoot.BevelOuter := bvNone;

  PToolbar := TPanel.Create(Self);
  PToolbar.Parent := PRoot;
  PToolbar.Align := alTop;
  PToolbar.Height := 54;
  PToolbar.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PToolbar;
  Lbl.Caption := 'Quality';
  Lbl.SetBounds(8, 6, 50, 16);

  TbQuality := TTrackBar.Create(Self);
  TbQuality.Parent := PToolbar;
  TbQuality.SetBounds(8, 22, 170, 26);
  TbQuality.Min := 30;
  TbQuality.Max := 90;
  TbQuality.TickStyle := tsNone;
  TbQuality.ShowHint := True;
  TbQuality.Hint := 'Higher quality means higher bandwidth usage.';
  TbQuality.OnChange := DoVideoSettingsChanged;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PToolbar;
  Lbl.Caption := 'FPS';
  Lbl.SetBounds(184, 6, 30, 16);

  CbFps := TComboBox.Create(Self);
  CbFps.Parent := PToolbar;
  CbFps.SetBounds(184, 22, 72, 23);
  CbFps.Items.Add('5');
  CbFps.Items.Add('10');
  CbFps.Items.Add('15');
  CbFps.Items.Add('30');
  CbFps.Items.Add('45');
  CbFps.Items.Add('60');
  CbFps.Items.Add('100');
  CbFps.Style := csDropDownList;
  CbFps.OnChange := DoVideoSettingsChanged;

  ChkCaptureInput := TCheckBox.Create(Self);
  ChkCaptureInput.Parent := PToolbar;
  ChkCaptureInput.Caption := 'Input capture';
  ChkCaptureInput.SetBounds(258, 24, 100, 20);
  ChkCaptureInput.Checked := True;
  ChkCaptureInput.ShowHint := True;
  ChkCaptureInput.Hint := 'Disable to observe screen without sending keyboard/mouse.';

  BtnSessionDisconnect := TButton.Create(Self);
  BtnSessionDisconnect.Parent := PToolbar;
  BtnSessionDisconnect.Caption := 'Disconnect';
  BtnSessionDisconnect.SetBounds(366, 20, 88, 26);
  BtnSessionDisconnect.OnClick := DoSessionDisconnect;

  BtnSendClipboard := TButton.Create(Self);
  BtnSendClipboard.Parent := PToolbar;
  BtnSendClipboard.Caption := 'Clipboard';
  BtnSendClipboard.SetBounds(460, 20, 90, 26);
  BtnSendClipboard.OnClick := DoSendClipboard;

  BtnSendFile := TButton.Create(Self);
  BtnSendFile.Parent := PToolbar;
  BtnSendFile.Caption := 'Send File';
  BtnSendFile.SetBounds(556, 20, 82, 26);
  BtnSendFile.OnClick := DoSendFile;

  BtnSendCad := TButton.Create(Self);
  BtnSendCad.Parent := PToolbar;
  BtnSendCad.Caption := 'Ctrl+Alt+Del';
  BtnSendCad.SetBounds(642, 20, 95, 26);
  BtnSendCad.OnClick := DoSendCad;
  BtnSendCad.ShowHint := True;
  BtnSendCad.Hint := 'Send secure attention sequence to remote session.';

  PVideoHost := TPanel.Create(Self);
  PVideoHost.Parent := PRoot;
  PVideoHost.Align := alClient;
  PVideoHost.BevelOuter := bvNone;

  for I := Low(FRemoteViews) to High(FRemoteViews) do
  begin
    FRemoteViews[I] := TImage.Create(Self);
    FRemoteViews[I].Parent := PVideoHost;
    FRemoteViews[I].Align := alClient;
    FRemoteViews[I].Stretch := True;
    FRemoteViews[I].Proportional := True;
    FRemoteViews[I].Center := True;
    FRemoteViews[I].Visible := I = 0;
    FRemoteViews[I].ShowHint := True;
    FRemoteViews[I].Hint := 'Remote screen. Resize window as needed; image scales automatically.';
    FRemoteViews[I].OnMouseMove := ImgRemoteMouseMove;
    FRemoteViews[I].OnMouseDown := ImgRemoteMouseDown;
    FRemoteViews[I].OnMouseUp := ImgRemoteMouseUp;
  end;
  FRemoteViewIndex := 0;
  ImgRemote := FRemoteViews[FRemoteViewIndex];
end;

procedure TForm1.ShowSessionWindow;
begin
  EnsureSessionWindow;
  if FSessionForm <> nil then
  begin
    FSessionForm.Show;
    FSessionForm.BringToFront;
  end;
end;

procedure TForm1.SessionWindowClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caHide;
end;

procedure TForm1.ApplyAdaptivePreset;
var
  LElapsed: Cardinal;
  LMeasuredFps: Double;
  LTargetFps: Integer;
  LTargetQuality: Integer;
  LIdx: Integer;
  LProbe: Integer;
  LChosenFps: Integer;
begin
  if FAdaptiveApplied then
    Exit;
  LElapsed := GetTickCount - FAdaptiveStartTick;
  if LElapsed < 1500 then
    Exit;

  LMeasuredFps := (FAdaptiveFrameCount * 1000.0) / Max(1, Integer(LElapsed));
  if LMeasuredFps < 8 then
  begin
    LTargetFps := 10;
    LTargetQuality := 35;
  end
  else if LMeasuredFps < 16 then
  begin
    LTargetFps := 15;
    LTargetQuality := 45;
  end
  else if LMeasuredFps < 28 then
  begin
    LTargetFps := 30;
    LTargetQuality := 60;
  end
  else if LMeasuredFps < 42 then
  begin
    LTargetFps := 45;
    LTargetQuality := 70;
  end
  else if LMeasuredFps < 60 then
  begin
    LTargetFps := 60;
    LTargetQuality := 78;
  end
  else
  begin
    LTargetFps := 100;
    LTargetQuality := 82;
  end;
  LChosenFps := LTargetFps;

  if TbQuality <> nil then
    TbQuality.Position := EnsureRange(LTargetQuality, TbQuality.Min, TbQuality.Max);
  if CbFps <> nil then
  begin
    LIdx := CbFps.Items.IndexOf(IntToStr(LTargetFps));
    if (LIdx < 0) and (CbFps.Items.Count > 0) then
    begin
      LIdx := -1;
      for LProbe := CbFps.Items.Count - 1 downto 0 do
      begin
        LChosenFps := StrToIntDef(CbFps.Items[LProbe], 0);
        if (LChosenFps > 0) and (LChosenFps <= LTargetFps) then
        begin
          LIdx := LProbe;
          Break;
        end;
      end;
      if LIdx < 0 then
        LIdx := CbFps.Items.Count - 1;
    end;
    if (LIdx >= 0) and (LIdx < CbFps.Items.Count) then
    begin
      CbFps.ItemIndex := LIdx;
      LChosenFps := StrToIntDef(CbFps.Items[LIdx], 0);
    end;
  end;
  DoVideoSettingsChanged(nil);

  if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
    FStatusBar.Panels[3].Text := Format('Adaptive profile: %.1f fps -> set %dfps, quality %d, render %d ms',
      [LMeasuredFps, LChosenFps, LTargetQuality, FRenderMinIntervalMs]);
  FAdaptiveApplied := True;
end;

procedure TForm1.UpdateServerStatusUi;
var
  LServerText: string;
  LStateText: string;
  LColor: TColor;
begin
  if FServerRole <> nil then
  begin
    if FServerRole.IsRunning then
    begin
      LServerText := 'Server: started';
      LStateText := 'started';
      LColor := clGreen;
    end
    else
    begin
      LServerText := 'Server: stopped';
      LStateText := 'stopped';
      LColor := clRed;
    end;
  end
  else
  begin
    LServerText := 'Server: n/a';
    LStateText := 'n/a';
    LColor := clGray;
  end;

  if LblServerStatus <> nil then
  begin
    LblServerStatus.Caption := 'Server state: ' + LStateText;
    LblServerStatus.Font.Color := LColor;
  end;

  if BtnServerStart <> nil then
    BtnServerStart.Enabled := (FServerRole <> nil) and (not FServerRole.IsRunning);
  if BtnServerStop <> nil then
    BtnServerStop.Enabled := (FServerRole <> nil) and FServerRole.IsRunning;

  if (FStatusBar <> nil) and (FStatusBar.Panels.Count > 1) then
    FStatusBar.Panels[1].Text := LServerText;
end;

procedure TForm1.LoggerLine(const ALine: string; ALevel: Integer; const AScope: string);
var
  LData: TUiStringData;
begin
  if not IsUiUsable then
    Exit;
  LData := TUiStringData.Create(ALine);
  if (not HandleAllocated) or (not PostMessage(Handle, WM_APP + 110, WPARAM(LData), 0)) then
    LData.Free;
end;

function TForm1.IsUiUsable: Boolean;
begin
  Result := not FShuttingDown and not (csDestroying in ComponentState);
end;

procedure TForm1.WmUiLog(var Msg: TMessage);
var
  LData: TUiStringData;
begin
  LData := TUiStringData(Msg.WParam);
  try
    if (LData = nil) or not IsUiUsable or (MemLogs = nil) then
      Exit;
    MemLogs.Lines.Add(LData.Text);
    while MemLogs.Lines.Count > 200 do
      MemLogs.Lines.Delete(0);
  finally
    LData.Free;
  end;
end;

procedure TForm1.WmUiClientStatus(var Msg: TMessage);
var
  LData: TUiStringData;
begin
  LData := TUiStringData(Msg.WParam);
  try
    if (LData = nil) or not IsUiUsable or (FStatusBar = nil) or (FStatusBar.Panels.Count < 4) then
      Exit;
    FStatusBar.Panels[3].Text := 'Client: ' + LData.Text;
  finally
    LData.Free;
  end;
end;

procedure TForm1.WmUiClientProviders(var Msg: TMessage);
var
  LData: TUiStringData;
  LObj: TJSONObject;
  LArr: TJSONArray;
  I: Integer;
  LItemObj: TJSONObject;
  LItem: TListItem;
  LSelectedKey: string;
  LSelectedIndex: Integer;
  LRestored: Boolean;
begin
  LData := TUiStringData(Msg.WParam);
  try
    if (LData = nil) or not IsUiUsable or (LvProviders = nil) then
      Exit;

    LObj := TJSONObject.ParseJSONValue(LData.Text) as TJSONObject;
    if LObj = nil then
      Exit;
    try
      LSelectedKey := '';
      LSelectedIndex := -1;
      if LvProviders.Selected <> nil then
      begin
        LSelectedKey := LvProviders.Selected.Caption;
        LSelectedIndex := LvProviders.Selected.Index;
      end;

      LvProviders.Items.BeginUpdate;
      try
        LvProviders.Items.Clear;
        LArr := LObj.GetValue('providers') as TJSONArray;
        if LArr <> nil then
          for I := 0 to LArr.Count - 1 do
          begin
            LItemObj := LArr.Items[I] as TJSONObject;
            if LItemObj = nil then
              Continue;
            LItem := LvProviders.Items.Add;
            LItem.Caption := JsonGetStr(LItemObj, 'providerKey', '');
            LItem.SubItems.Add(JsonGetStr(LItemObj, 'displayName', ''));
            LItem.SubItems.Add(JsonGetStr(LItemObj, 'machineName', ''));
            LItem.SubItems.Add(JsonGetStr(LItemObj, 'authMode', ''));
            LItem.SubItems.Add(JsonGetStr(LItemObj, 'online', ''));
          end;

        LRestored := False;
        if LSelectedKey <> '' then
          for I := 0 to LvProviders.Items.Count - 1 do
            if SameText(LvProviders.Items[I].Caption, LSelectedKey) then
            begin
              LvProviders.Items[I].Selected := True;
              LvProviders.Items[I].Focused := True;
              LvProviders.Items[I].MakeVisible(False);
              LRestored := True;
              Break;
            end;

        if (not LRestored) and (LSelectedIndex >= 0) and (LSelectedIndex < LvProviders.Items.Count) then
        begin
          LvProviders.Items[LSelectedIndex].Selected := True;
          LvProviders.Items[LSelectedIndex].Focused := True;
          LvProviders.Items[LSelectedIndex].MakeVisible(False);
        end;
      finally
        LvProviders.Items.EndUpdate;
      end;
    finally
      LObj.Free;
    end;
  finally
    LData.Free;
  end;
end;

procedure TForm1.WmUiClientFrame(var Msg: TMessage);
var
  LData: TUiFrameData;
  LNowTick: Cardinal;
  LNextIndex: Integer;
  LTarget: TImage;
begin
  LData := TUiFrameData(Msg.WParam);
  try
    if (LData = nil) or not IsUiUsable then
      Exit;
    if ImgRemote = nil then
      EnsureSessionWindow;
    if ImgRemote = nil then
      Exit;

    if (FLastFrameNo > 100) and (LData.FrameNo < 10) then
      FLastFrameNo := 0;
    if LData.FrameNo <= FLastFrameNo then
      Exit;

    LNowTick := GetTickCount;
    if (FRenderMinIntervalMs > 0) and (LNowTick - FLastRenderTick < FRenderMinIntervalMs) then
      Exit;

    Inc(FAdaptiveFrameCount);
    ApplyAdaptivePreset;

    LNextIndex := (FRemoteViewIndex + 1) mod Length(FRemoteViews);
    LTarget := FRemoteViews[LNextIndex];
    if LTarget = nil then
      LTarget := ImgRemote;

    if (LTarget.Picture.Bitmap.Width <> LData.Bitmap.Width) or
      (LTarget.Picture.Bitmap.Height <> LData.Bitmap.Height) then
      LTarget.Picture.Bitmap.SetSize(LData.Bitmap.Width, LData.Bitmap.Height);
    LTarget.Picture.Bitmap.Canvas.Draw(0, 0, LData.Bitmap);

    if not LTarget.Visible then
      LTarget.Visible := True;
    if LTarget <> ImgRemote then
    begin
      LTarget.BringToFront;
      ImgRemote := LTarget;
      FRemoteViewIndex := LNextIndex;
    end;

    FRemoteWidth := LData.Bitmap.Width;
    FRemoteHeight := LData.Bitmap.Height;
    FLastFrameNo := LData.FrameNo;
    FLastRenderTick := LNowTick;
  finally
    TInterlocked.Exchange(FFrameUiBusy, 0);
    LData.Free;
  end;
end;

procedure TForm1.WmUiClientSession(var Msg: TMessage);
var
  LData: TUiSessionData;
  I: Integer;
begin
  LData := TUiSessionData(Msg.WParam);
  try
    if (LData = nil) or not IsUiUsable or (FStatusBar = nil) or (FStatusBar.Panels.Count < 3) then
      Exit;
    FStatusBar.Panels[2].Text := LData.Text;
    if LData.Active then
    begin
      FLastFrameNo := 0;
      FLastRenderTick := 0;
      FAdaptiveStartTick := GetTickCount;
      FAdaptiveFrameCount := 0;
      FAdaptiveApplied := False;
      FRenderMinIntervalMs := 10;
      ShowSessionWindow;
    end
    else if FSessionForm <> nil then
    begin
      FLastFrameNo := 0;
      FLastRenderTick := 0;
      TInterlocked.Exchange(FFrameUiBusy, 0);
      if ImgRemote <> nil then
        ImgRemote.Picture.Assign(nil);
      for I := Low(FRemoteViews) to High(FRemoteViews) do
        if FRemoteViews[I] <> nil then
          FRemoteViews[I].Picture.Assign(nil);
      FSessionForm.Hide;
    end;
  finally
    LData.Free;
  end;
end;

procedure TForm1.WmUiProviderStatus(var Msg: TMessage);
var
  LData: TUiStringData;
begin
  LData := TUiStringData(Msg.WParam);
  try
    if (LData = nil) or not IsUiUsable or (LblProviderStatus = nil) then
      Exit;
    LblProviderStatus.Caption := 'Provider status: ' + LData.Text;
  finally
    LData.Free;
  end;
end;

procedure TForm1.WmUiProviderSession(var Msg: TMessage);
var
  LData: TUiStringData;
begin
  LData := TUiStringData(Msg.WParam);
  try
    if (LData = nil) or not IsUiUsable or (LblProviderStatus = nil) then
      Exit;
    LblProviderStatus.Caption := 'Provider session: ' + LData.Text;
  finally
    LData.Free;
  end;
end;

procedure TForm1.UiTimerTick(Sender: TObject);
var
  LModeText: string;
begin
  if not IsUiUsable then
    Exit;
  if (FClientRole = nil) or (FServerRole = nil) or (FStatusBar = nil) or (RgMode = nil) then
    Exit;
  if FStatusBar.Panels.Count < 3 then
    Exit;
  Inc(FUiTickCounter);
  FClientRole.Tick;
  if FClientRole.Authenticated then
    FClientRole.RequestProviders;
  RefreshServerLists;
  RefreshServerUsersUi;
  LModeText := 'unknown';
  if (RgMode.ItemIndex >= 0) and (RgMode.ItemIndex < RgMode.Items.Count) then
    LModeText := RgMode.Items[RgMode.ItemIndex];
  FStatusBar.Panels[0].Text := 'Mode: ' + LModeText;
  UpdateServerStatusUi;
  FStatusBar.Panels[2].Text := 'Session: ' + UIntToStr(FClientRole.ActiveSessionId);
end;

procedure TForm1.DoApplyMode(Sender: TObject);
begin
  SaveUiToConfig;
  ApplyMode;
end;

procedure TForm1.DoSaveConfig(Sender: TObject);
begin
  SaveUiToConfig;
  FConfig.SaveToFile(TPath.Combine(ExtractFilePath(ParamStr(0)), 'krvn.config.json'));
end;

procedure TForm1.DoClientConnect(Sender: TObject);
begin
  SaveUiToConfig;
  FClientRole.Connect;
end;

procedure TForm1.DoClientDisconnect(Sender: TObject);
begin
  FClientRole.Disconnect;
end;

procedure TForm1.DoConnectSelected(Sender: TObject);
begin
  if LvProviders.Selected <> nil then
    FClientRole.ConnectProvider(LvProviders.Selected.Caption, EdHiddenUser.Text, EdHiddenPass.Text);
  if (LvProviders.Selected = nil) and (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
    FStatusBar.Panels[3].Text := 'Client: Select a provider from list first.';
end;

procedure TForm1.DoProvidersDblClick(Sender: TObject);
begin
  DoConnectSelected(Sender);
end;

procedure TForm1.DoConnectHidden(Sender: TObject);
begin
  if Trim(EdHiddenMachine.Text) = '' then
  begin
    if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
      FStatusBar.Panels[3].Text := 'Client: Enter hidden machineName before Connect Hidden.';
    Exit;
  end;
  FClientRole.ConnectHidden(EdHiddenMachine.Text, EdHiddenUser.Text, EdHiddenPass.Text);
end;

procedure TForm1.DoOpenSessionWindow(Sender: TObject);
begin
  ShowSessionWindow;
end;

procedure TForm1.DoSessionDisconnect(Sender: TObject);
begin
  FClientRole.DisconnectSession;
end;

procedure TForm1.DoSendClipboard(Sender: TObject);
begin
  if Clipboard.HasFormat(CF_UNICODETEXT) then
    FClientRole.SendClipboardText(Clipboard.AsText);
end;

procedure TForm1.DoSendFile(Sender: TObject);
var
  LDlg: TOpenDialog;
begin
  LDlg := TOpenDialog.Create(nil);
  try
    if LDlg.Execute then
      FClientRole.SendFile(LDlg.FileName);
  finally
    LDlg.Free;
  end;
end;

procedure TForm1.DoSendCad(Sender: TObject);
var
  E: TKrvnInputEvent;

  procedure SendKey(AKey: Word; ADown: Boolean);
  begin
    FillChar(E, SizeOf(E), 0);
    E.EventType := KRVN_INPUT_KEY;
    if ADown then
      E.Flags := 1
    else
      E.Flags := 0;
    E.P1 := AKey;
    E.P2 := MapVirtualKey(AKey, 0);
    FClientRole.SendInputEvent(E);
  end;
begin
  if (FClientRole = nil) or (FClientRole.ActiveSessionId = 0) then
    Exit;
  SendKey(VK_CONTROL, True);
  SendKey(VK_MENU, True);
  SendKey(VK_DELETE, True);
  SendKey(VK_DELETE, False);
  SendKey(VK_MENU, False);
  SendKey(VK_CONTROL, False);
end;

procedure TForm1.DoVideoSettingsChanged(Sender: TObject);
var
  LFps: Integer;
begin
  if not FUiReady or FShuttingDown then
    Exit;
  if (FClientRole = nil) or (CbFps = nil) or (TbQuality = nil) then
    Exit;
  if (CbFps.ItemIndex < 0) or (CbFps.ItemIndex >= CbFps.Items.Count) then
    Exit;
  LFps := StrToIntDef(CbFps.Items[CbFps.ItemIndex], 15);
  if LFps <= 0 then
    LFps := 15;
  FRenderMinIntervalMs := Cardinal(Max(1, (1000 + LFps - 1) div LFps));
  FClientRole.SendVideoSettings(LFps, TbQuality.Position, 1.0);
end;

procedure TForm1.DoProviderStart(Sender: TObject);
begin
  SaveUiToConfig;
  FProviderRole.Start;
end;

procedure TForm1.DoProviderStop(Sender: TObject);
begin
  FProviderRole.Stop;
end;

procedure TForm1.DoProviderEndSession(Sender: TObject);
begin
  FProviderRole.DisconnectSession;
end;

procedure TForm1.DoServerStart(Sender: TObject);
begin
  SaveUiToConfig;
  FServerRole.Start;
  UpdateServerStatusUi;
end;

procedure TForm1.DoServerStop(Sender: TObject);
begin
  FServerRole.Stop;
  UpdateServerStatusUi;
end;

procedure TForm1.DoServerSaveUser(Sender: TObject);
var
  LUsername: string;
  LPassword: string;
  LRole: string;
  LUser: TKrvnUser;
  LSalt: TBytes;
  LHash: TBytes;
  I: Integer;
  LFoundRole: Boolean;
begin
  if FConfig = nil then
    Exit;

  LUsername := Trim(EdSrvUser.Text);
  LPassword := EdSrvPass.Text;
  if LUsername = '' then
  begin
    if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
      FStatusBar.Panels[3].Text := 'Server: Enter login before saving user.';
    Exit;
  end;
  if LPassword = '' then
  begin
    if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
      FStatusBar.Panels[3].Text := 'Server: Enter password before saving user.';
    Exit;
  end;

  LRole := 'client';
  if CbSrvRole <> nil then
    LRole := Trim(CbSrvRole.Text);
  if not (SameText(LRole, 'client') or SameText(LRole, 'provider') or SameText(LRole, 'server-admin')) then
    LRole := 'client';

  LUser := FConfig.FindUser(LUsername);
  if LUser = nil then
  begin
    LUser := TKrvnUser.Create;
    LUser.Username := LUsername;
    SetLength(LUser.Roles, 1);
    LUser.Roles[0] := LRole;
    FConfig.ServerUsers.Add(LUser);
  end
  else
  begin
    LFoundRole := False;
    for I := 0 to Length(LUser.Roles) - 1 do
      if SameText(LUser.Roles[I], LRole) then
      begin
        LFoundRole := True;
        Break;
      end;
    if not LFoundRole then
    begin
      I := Length(LUser.Roles);
      SetLength(LUser.Roles, I + 1);
      LUser.Roles[I] := LRole;
    end;
  end;

  LUser.Iterations := 200000;
  LSalt := TKrvnCrypto.RandomBytes(16);
  LHash := TKrvnCrypto.DerivePasswordHash(LPassword, LSalt, LUser.Iterations);
  LUser.SaltB64 := TNetEncoding.Base64.EncodeBytesToString(LSalt);
  LUser.HashB64 := TNetEncoding.Base64.EncodeBytesToString(LHash);

  FConfig.SaveToFile(TPath.Combine(ExtractFilePath(ParamStr(0)), 'krvn.config.json'));
  RefreshServerUsersUi;
  EdSrvPass.Clear;

  if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
    FStatusBar.Panels[3].Text := 'Server: user "' + LUsername + '" saved/updated.';
end;

procedure TForm1.DoServerDeleteUser(Sender: TObject);
var
  LUsername: string;
  I: Integer;
  LDeleted: Boolean;
begin
  if FConfig = nil then
    Exit;

  LUsername := Trim(EdSrvUser.Text);
  if LUsername = '' then
  begin
    if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
      FStatusBar.Panels[3].Text := 'Server: Enter login to delete user.';
    Exit;
  end;

  if SameText(LUsername, 'admin') then
  begin
    if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
      FStatusBar.Panels[3].Text := 'Server: default admin user cannot be deleted from UI.';
    Exit;
  end;

  LDeleted := False;
  for I := FConfig.ServerUsers.Count - 1 downto 0 do
    if SameText(FConfig.ServerUsers[I].Username, LUsername) then
    begin
      FConfig.ServerUsers.Delete(I);
      LDeleted := True;
      Break;
    end;

  if LDeleted then
  begin
    FConfig.SaveToFile(TPath.Combine(ExtractFilePath(ParamStr(0)), 'krvn.config.json'));
    RefreshServerUsersUi;
    if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
      FStatusBar.Panels[3].Text := 'Server: user "' + LUsername + '" deleted.';
  end
  else if (FStatusBar <> nil) and (FStatusBar.Panels.Count >= 4) then
    FStatusBar.Panels[3].Text := 'Server: user "' + LUsername + '" not found.';
end;

procedure TForm1.OnClientStatus(const AText: string);
var
  LData: TUiStringData;
begin
  if not IsUiUsable then
    Exit;
  LData := TUiStringData.Create(AText);
  if (not HandleAllocated) or (not PostMessage(Handle, WM_APP + 111, WPARAM(LData), 0)) then
    LData.Free;
end;

procedure TForm1.OnClientProviders(const AJson: string);
var
  LData: TUiStringData;
begin
  if not IsUiUsable then
    Exit;
  LData := TUiStringData.Create(AJson);
  if (not HandleAllocated) or (not PostMessage(Handle, WM_APP + 112, WPARAM(LData), 0)) then
    LData.Free;
end;

procedure TForm1.OnClientFrame(ABitmap: TBitmap; AFrameNo: Cardinal);
var
  LData: TUiFrameData;
begin
  if not IsUiUsable or (ABitmap = nil) then
  begin
    ABitmap.Free;
    Exit;
  end;
  if TInterlocked.CompareExchange(FFrameUiBusy, 1, 0) <> 0 then
  begin
    ABitmap.Free;
    Exit;
  end;
  LData := TUiFrameData.Create(ABitmap, AFrameNo);
  if (not HandleAllocated) or (not PostMessage(Handle, WM_APP + 113, WPARAM(LData), 0)) then
  begin
    LData.Free;
    TInterlocked.Exchange(FFrameUiBusy, 0);
  end;
end;

procedure TForm1.OnClientSession(AActive: Boolean; const AMessage: string);
var
  LData: TUiSessionData;
begin
  if not IsUiUsable then
    Exit;
  LData := TUiSessionData.Create(AActive, AMessage);
  if (not HandleAllocated) or (not PostMessage(Handle, WM_APP + 114, WPARAM(LData), 0)) then
    LData.Free;
end;

procedure TForm1.OnProviderStatus(const AText: string);
var
  LData: TUiStringData;
begin
  if not IsUiUsable then
    Exit;
  LData := TUiStringData.Create(AText);
  if (not HandleAllocated) or (not PostMessage(Handle, WM_APP + 115, WPARAM(LData), 0)) then
    LData.Free;
end;

procedure TForm1.OnProviderSession(AActive: Boolean; const AMessage: string);
var
  LData: TUiStringData;
begin
  if not IsUiUsable then
    Exit;
  LData := TUiStringData.Create(AMessage);
  if (not HandleAllocated) or (not PostMessage(Handle, WM_APP + 116, WPARAM(LData), 0)) then
    LData.Free;
end;

function TForm1.MapImageToRemote(const AX, AY: Integer; out ARemoteX, ARemoteY: Integer): Boolean;
var
  LViewW: Integer;
  LViewH: Integer;
  LDrawW: Integer;
  LDrawH: Integer;
  LOffX: Integer;
  LOffY: Integer;
  LX: Integer;
  LY: Integer;
  LScale: Double;
begin
  Result := False;
  ARemoteX := 0;
  ARemoteY := 0;
  if (ImgRemote = nil) or (FRemoteWidth <= 0) or (FRemoteHeight <= 0) then
    Exit;

  LViewW := Max(1, ImgRemote.Width);
  LViewH := Max(1, ImgRemote.Height);
  if ImgRemote.Proportional then
  begin
    LScale := Min(LViewW / Max(1, FRemoteWidth), LViewH / Max(1, FRemoteHeight));
    LDrawW := Max(1, Round(FRemoteWidth * LScale));
    LDrawH := Max(1, Round(FRemoteHeight * LScale));
    LOffX := (LViewW - LDrawW) div 2;
    LOffY := (LViewH - LDrawH) div 2;
  end
  else
  begin
    LDrawW := LViewW;
    LDrawH := LViewH;
    LOffX := 0;
    LOffY := 0;
  end;

  Result := (AX >= LOffX) and (AX < LOffX + LDrawW) and (AY >= LOffY) and (AY < LOffY + LDrawH);
  LX := EnsureRange(AX - LOffX, 0, LDrawW - 1);
  LY := EnsureRange(AY - LOffY, 0, LDrawH - 1);

  if LDrawW > 1 then
    ARemoteX := MulDiv(LX, Max(1, FRemoteWidth - 1), LDrawW - 1)
  else
    ARemoteX := 0;
  if LDrawH > 1 then
    ARemoteY := MulDiv(LY, Max(1, FRemoteHeight - 1), LDrawH - 1)
  else
    ARemoteY := 0;
end;

function TForm1.SendMouseMove(X, Y: Integer): Boolean;
var
  E: TKrvnInputEvent;
  LRemoteX: Integer;
  LRemoteY: Integer;
begin
  Result := False;
  if not FUiReady or FShuttingDown then
    Exit;
  if (FClientRole = nil) or (ChkCaptureInput = nil) or (ImgRemote = nil) then
    Exit;
  if (FClientRole.ActiveSessionId = 0) or (not ChkCaptureInput.Checked) then
    Exit;
  if not MapImageToRemote(X, Y, LRemoteX, LRemoteY) then
    Exit;
  FillChar(E, SizeOf(E), 0);
  E.EventType := KRVN_INPUT_MOUSE_MOVE;
  E.Flags := 1;
  E.P1 := LRemoteX;
  E.P2 := LRemoteY;
  FClientRole.SendInputEvent(E);
  Result := True;
end;

procedure TForm1.ImgRemoteMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if Sender is TImage then
    ImgRemote := TImage(Sender);
  SendMouseMove(X, Y);
end;

procedure TForm1.ImgRemoteMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  E: TKrvnInputEvent;
begin
  if (FClientRole = nil) or not FUiReady or FShuttingDown then
    Exit;
  if Sender is TImage then
    ImgRemote := TImage(Sender);
  if not SendMouseMove(X, Y) then
    Exit;
  FillChar(E, SizeOf(E), 0);
  E.EventType := KRVN_INPUT_MOUSE_BUTTON;
  E.Flags := 1;
  case Button of
    mbLeft: E.P1 := 1;
    mbRight: E.P1 := 2;
    mbMiddle: E.P1 := 3;
  end;
  FClientRole.SendInputEvent(E);
end;

procedure TForm1.ImgRemoteMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  E: TKrvnInputEvent;
begin
  if (FClientRole = nil) or not FUiReady or FShuttingDown then
    Exit;
  if Sender is TImage then
    ImgRemote := TImage(Sender);
  if not SendMouseMove(X, Y) then
    Exit;
  FillChar(E, SizeOf(E), 0);
  E.EventType := KRVN_INPUT_MOUSE_BUTTON;
  E.Flags := 0;
  case Button of
    mbLeft: E.P1 := 1;
    mbRight: E.P1 := 2;
    mbMiddle: E.P1 := 3;
  end;
  FClientRole.SendInputEvent(E);
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  E: TKrvnInputEvent;
begin
  if (FClientRole = nil) or (ChkCaptureInput = nil) or not FUiReady or FShuttingDown then
    Exit;
  if not ChkCaptureInput.Checked then
    Exit;
  FillChar(E, SizeOf(E), 0);
  E.EventType := KRVN_INPUT_KEY;
  E.Flags := 1;
  E.P1 := Key;
  E.P2 := MapVirtualKey(Key, 0);
  FClientRole.SendInputEvent(E);
end;

procedure TForm1.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  E: TKrvnInputEvent;
begin
  if (FClientRole = nil) or (ChkCaptureInput = nil) or not FUiReady or FShuttingDown then
    Exit;
  if not ChkCaptureInput.Checked then
    Exit;
  FillChar(E, SizeOf(E), 0);
  E.EventType := KRVN_INPUT_KEY;
  E.Flags := 0;
  E.P1 := Key;
  E.P2 := MapVirtualKey(Key, 0);
  FClientRole.SendInputEvent(E);
end;

procedure TForm1.FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
var
  E: TKrvnInputEvent;
begin
  if (FClientRole = nil) or (ChkCaptureInput = nil) or not FUiReady or FShuttingDown then
    Exit;
  if not ChkCaptureInput.Checked then
    Exit;
  FillChar(E, SizeOf(E), 0);
  E.EventType := KRVN_INPUT_MOUSE_WHEEL;
  E.P3 := WheelDelta;
  FClientRole.SendInputEvent(E);
  Handled := True;
end;

end.
