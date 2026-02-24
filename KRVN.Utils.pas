unit KRVN.Utils;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  TBytesQueue = class
  private
    FQueue: TQueue<TBytes>;
    FLock: TCriticalSection;
    FSignal: TEvent;
    FMaxItems: Integer;
  public
    constructor Create(AMaxItems: Integer = 0);
    destructor Destroy; override;
    function Enqueue(const AData: TBytes; ADropOldestOnOverflow: Boolean = True): Boolean;
    function Dequeue(out AData: TBytes; ATimeoutMs: Cardinal = INFINITE): Boolean;
    procedure Clear;
    function Count: Integer;
  end;

function Utf8Bytes(const AValue: string): TBytes;
function Utf8String(const AValue: TBytes): string;
function BytesToHex(const AValue: TBytes): string;
function HexToBytes(const AValue: string): TBytes;
function ConstantTimeEquals(const ALeft, ARight: TBytes): Boolean;
function NowUtcIso8601: string;

implementation

uses
  System.DateUtils;

function Utf8Bytes(const AValue: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AValue);
end;

function Utf8String(const AValue: TBytes): string;
begin
  Result := TEncoding.UTF8.GetString(AValue);
end;

function BytesToHex(const AValue: TBytes): string;
const
  HEX_CHARS: array[0..15] of Char = '0123456789ABCDEF';
var
  I: Integer;
begin
  SetLength(Result, Length(AValue) * 2);
  for I := 0 to High(AValue) do
  begin
    Result[(I * 2) + 1] := HEX_CHARS[AValue[I] shr 4];
    Result[(I * 2) + 2] := HEX_CHARS[AValue[I] and $0F];
  end;
end;

function HexToBytes(const AValue: string): TBytes;
var
  I: Integer;
  LClean: string;
begin
  LClean := Trim(AValue);
  if Odd(Length(LClean)) then
    raise EArgumentException.Create('Hex length must be even');
  SetLength(Result, Length(LClean) div 2);
  for I := 0 to High(Result) do
    Result[I] := StrToInt('$' + LClean[(I * 2) + 1] + LClean[(I * 2) + 2]);
end;

function ConstantTimeEquals(const ALeft, ARight: TBytes): Boolean;
var
  I: Integer;
  LDiff: Byte;
begin
  if Length(ALeft) <> Length(ARight) then
    Exit(False);
  LDiff := 0;
  for I := 0 to High(ALeft) do
    LDiff := LDiff or (ALeft[I] xor ARight[I]);
  Result := LDiff = 0;
end;

function NowUtcIso8601: string;
begin
  Result := DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True);
end;

constructor TBytesQueue.Create(AMaxItems: Integer);
begin
  inherited Create;
  FQueue := TQueue<TBytes>.Create;
  FLock := TCriticalSection.Create;
  FSignal := TEvent.Create(nil, False, False, '');
  FMaxItems := AMaxItems;
end;

destructor TBytesQueue.Destroy;
begin
  FSignal.Free;
  FLock.Free;
  FQueue.Free;
  inherited Destroy;
end;

function TBytesQueue.Enqueue(const AData: TBytes; ADropOldestOnOverflow: Boolean): Boolean;
begin
  Result := False;
  FLock.Enter;
  try
    if (FMaxItems > 0) and (FQueue.Count >= FMaxItems) then
    begin
      if ADropOldestOnOverflow then
        FQueue.Dequeue
      else
        Exit(False);
    end;
    FQueue.Enqueue(System.Copy(AData, 0, Length(AData)));
    Result := True;
  finally
    FLock.Leave;
  end;
  FSignal.SetEvent;
end;

function TBytesQueue.Dequeue(out AData: TBytes; ATimeoutMs: Cardinal): Boolean;
begin
  SetLength(AData, 0);
  Result := False;
  if FSignal.WaitFor(ATimeoutMs) <> wrSignaled then
    Exit(False);
  FLock.Enter;
  try
    if FQueue.Count > 0 then
    begin
      AData := FQueue.Dequeue;
      Result := True;
      if FQueue.Count > 0 then
        FSignal.SetEvent;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TBytesQueue.Clear;
begin
  FLock.Enter;
  try
    FQueue.Clear;
  finally
    FLock.Leave;
  end;
end;

function TBytesQueue.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FQueue.Count;
  finally
    FLock.Leave;
  end;
end;

end.
