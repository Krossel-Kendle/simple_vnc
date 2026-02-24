unit KRVN.Json;

interface

uses
  System.SysUtils,
  System.JSON;

function JsonFromBytes(const AData: TBytes): TJSONObject;
function JsonToBytes(const AValue: TJSONObject): TBytes;
function JsonGetStr(const AObj: TJSONObject; const AName, ADefault: string): string;
function JsonGetInt(const AObj: TJSONObject; const AName: string; ADefault: Integer): Integer;
function JsonGetBool(const AObj: TJSONObject; const AName: string; ADefault: Boolean): Boolean;

implementation

uses
  KRVN.Utils;

function JsonFromBytes(const AData: TBytes): TJSONObject;
var
  LValue: TJSONValue;
begin
  LValue := TJSONObject.ParseJSONValue(Utf8String(AData));
  if (LValue = nil) or not (LValue is TJSONObject) then
  begin
    LValue.Free;
    raise EConvertError.Create('Invalid JSON payload');
  end;
  Result := TJSONObject(LValue);
end;

function JsonToBytes(const AValue: TJSONObject): TBytes;
begin
  if AValue = nil then
    Exit(nil);
  Result := Utf8Bytes(AValue.ToJSON);
end;

function JsonGetStr(const AObj: TJSONObject; const AName, ADefault: string): string;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if AObj = nil then
    Exit;
  LValue := AObj.GetValue(AName);
  if LValue <> nil then
    Result := LValue.Value;
end;

function JsonGetInt(const AObj: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if AObj = nil then
    Exit;
  LValue := AObj.GetValue(AName);
  if LValue <> nil then
    Result := StrToIntDef(LValue.Value, ADefault);
end;

function JsonGetBool(const AObj: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if AObj = nil then
    Exit;
  LValue := AObj.GetValue(AName);
  if LValue <> nil then
    Result := SameText(LValue.Value, 'true') or (LValue.Value = '1');
end;

end.
