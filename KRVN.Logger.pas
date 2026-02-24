unit KRVN.Logger;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  TLogSinkEvent = procedure(const ALine: string; ALevel: Integer; const AScope: string) of object;

  TKrvnLogger = class
  private
    FLock: TCriticalSection;
    FFolder: string;
    FLevel: Integer;
    FRetentionDays: Integer;
    FOnLog: TLogSinkEvent;
    procedure WriteLine(ALevel: Integer; const AScope, AMessage: string; AConnId: Int64);
    function LevelName(ALevel: Integer): string;
    function FileNameForLevel(ALevel: Integer): string;
    procedure CleanupRetention;
    function ResolveLogFolder(const AFolder: string): string;
  public
    constructor Create(ALevel: Integer; const AFolder: string; ARetentionDays: Integer);
    destructor Destroy; override;
    procedure SetLevel(ALevel: Integer);
    procedure Log(ALevel: Integer; const AScope, AMessage: string; AConnId: Int64 = 0);
    procedure Error(const AScope, AMessage: string; AConnId: Int64 = 0);
    procedure Warn(const AScope, AMessage: string; AConnId: Int64 = 0);
    procedure Info(const AScope, AMessage: string; AConnId: Int64 = 0);
    procedure Debug(const AScope, AMessage: string; AConnId: Int64 = 0);
    property OnLog: TLogSinkEvent read FOnLog write FOnLog;
    property Level: Integer read FLevel write SetLevel;
  end;

implementation

uses
  System.IOUtils,
  System.DateUtils;

constructor TKrvnLogger.Create(ALevel: Integer; const AFolder: string; ARetentionDays: Integer);
var
  LFallback: string;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FFolder := ResolveLogFolder(AFolder);
  FLevel := ALevel;
  FRetentionDays := ARetentionDays;
  try
    ForceDirectories(FFolder);
  except
    LFallback := ResolveLogFolder(TPath.Combine(TPath.GetTempPath, 'SimpleVNC_logs'));
    if not SameText(FFolder, LFallback) then
    begin
      FFolder := LFallback;
      ForceDirectories(FFolder);
    end
    else
      raise;
  end;
  CleanupRetention;
end;

destructor TKrvnLogger.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TKrvnLogger.SetLevel(ALevel: Integer);
begin
  FLevel := ALevel;
end;

function TKrvnLogger.LevelName(ALevel: Integer): string;
begin
  case ALevel of
    1:
      Result := 'ERROR';
    2:
      Result := 'WARNING';
    3:
      Result := 'INFO';
    4:
      Result := 'DEBUG';
  else
    Result := 'NONE';
  end;
end;

function TKrvnLogger.FileNameForLevel(ALevel: Integer): string;
var
  LDatePrefix: string;
begin
  LDatePrefix := FormatDateTime('yyyy-mm-dd', Now);
  case ALevel of
    1:
      Result := TPath.Combine(FFolder, LDatePrefix + '_error.log');
    2:
      Result := TPath.Combine(FFolder, LDatePrefix + '_warning.log');
  else
    Result := TPath.Combine(FFolder, LDatePrefix + '_info.log');
  end;
end;

function TKrvnLogger.ResolveLogFolder(const AFolder: string): string;
var
  LFolder: string;
begin
  LFolder := Trim(AFolder);
  if LFolder = '' then
    LFolder := 'logs';
  if not TPath.IsPathRooted(LFolder) then
    LFolder := TPath.Combine(ExtractFilePath(ParamStr(0)), LFolder);
  Result := TPath.GetFullPath(LFolder);
end;

procedure TKrvnLogger.CleanupRetention;
var
  LFiles: TArray<string>;
  LFile: string;
  LLastWrite: TDateTime;
begin
  if FRetentionDays <= 0 then
    Exit;
  if Trim(FFolder) = '' then
    Exit;
  if not TDirectory.Exists(FFolder) then
    Exit;

  LFiles := TDirectory.GetFiles(FFolder, '*.log');
  for LFile in LFiles do
  begin
    LLastWrite := TFile.GetLastWriteTime(LFile);
    if DaysBetween(Now, LLastWrite) > FRetentionDays then
      TFile.Delete(LFile);
  end;
end;

procedure TKrvnLogger.WriteLine(ALevel: Integer; const AScope, AMessage: string; AConnId: Int64);
var
  LLine: string;
  LFileName: string;
  LConnChunk: string;
  LStream: TFileStream;
  LBytes: TBytes;
begin
  if AConnId <> 0 then
    LConnChunk := Format('[Conn:%d] ', [AConnId])
  else
    LConnChunk := '';

  LLine := Format('%s [%s] [%s] %s%s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), LevelName(ALevel), AScope, LConnChunk, AMessage]);

  if Assigned(FOnLog) then
    FOnLog(LLine, ALevel, AScope);

  LFileName := FileNameForLevel(ALevel);
  LBytes := TEncoding.UTF8.GetBytes(LLine + sLineBreak);
  if ExtractFilePath(LFileName) <> '' then
    ForceDirectories(ExtractFilePath(LFileName));
  if TFile.Exists(LFileName) then
    LStream := TFileStream.Create(LFileName, fmOpenReadWrite or fmShareDenyWrite)
  else
    LStream := TFileStream.Create(LFileName, fmCreate);
  try
    LStream.Seek(0, soFromEnd);
    LStream.WriteBuffer(LBytes[0], Length(LBytes));
  finally
    LStream.Free;
  end;
end;

procedure TKrvnLogger.Log(ALevel: Integer; const AScope, AMessage: string; AConnId: Int64);
begin
  if (ALevel <= 0) or (ALevel > FLevel) then
    Exit;

  FLock.Enter;
  try
    WriteLine(ALevel, AScope, AMessage, AConnId);
  finally
    FLock.Leave;
  end;
end;

procedure TKrvnLogger.Error(const AScope, AMessage: string; AConnId: Int64);
begin
  Log(1, AScope, AMessage, AConnId);
end;

procedure TKrvnLogger.Warn(const AScope, AMessage: string; AConnId: Int64);
begin
  Log(2, AScope, AMessage, AConnId);
end;

procedure TKrvnLogger.Info(const AScope, AMessage: string; AConnId: Int64);
begin
  Log(3, AScope, AMessage, AConnId);
end;

procedure TKrvnLogger.Debug(const AScope, AMessage: string; AConnId: Int64);
begin
  Log(4, AScope, AMessage, AConnId);
end;

end.
