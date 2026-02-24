unit KRVN.Crypto;

interface

uses
  System.SysUtils;

type
  EKrvnCryptoError = class(Exception);

  TKrvnCrypto = class
  public
    class function RandomBytes(ALength: Integer): TBytes; static;
    class function PBKDF2SHA256(const APassword, ASalt: TBytes; AIterations, AKeyLen: Integer): TBytes; static;
    class function HMACSHA256(const AKey, AData: TBytes): TBytes; static;
    class function ProtectStringDpapi(const AValue: string): string; static;
    class function UnprotectStringDpapi(const AValue: string): string; static;
    class function DerivePasswordHash(const APassword: string; const ASalt: TBytes;
      AIterations: Integer): TBytes; static;
    class function BuildAuthProof(const APbkdf2Hash, ANonce: TBytes): TBytes; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Hash,
  System.NetEncoding;

type
  PKrvnDataBlob = ^TKrvnDataBlob;
  TKrvnDataBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;

function RtlGenRandom(RandomBuffer: Pointer; RandomBufferLength: Cardinal): BOOL; stdcall;
  external 'advapi32.dll' name 'SystemFunction036';
function CryptProtectData(pDataIn: PKrvnDataBlob; ppszDataDescr: Pointer; pOptionalEntropy: PKrvnDataBlob;
  pvReserved: Pointer; pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PKrvnDataBlob): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptProtectData';
function CryptUnprotectData(pDataIn: PKrvnDataBlob; ppszDataDescr: Pointer; pOptionalEntropy: PKrvnDataBlob;
  pvReserved: Pointer; pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PKrvnDataBlob): BOOL; stdcall;
  external 'crypt32.dll' name 'CryptUnprotectData';

const
  CRYPTPROTECT_UI_FORBIDDEN = $1;

function TryUnprotectDpapiBase64(const ABase64: string; out APlain: string): Boolean;
var
  LInBytes: TBytes;
  LOutBytes: TBytes;
  LInBlob: TKrvnDataBlob;
  LOutBlob: TKrvnDataBlob;
begin
  Result := False;
  APlain := '';
  if Trim(ABase64) = '' then
    Exit;
  try
    LInBytes := TNetEncoding.Base64.DecodeStringToBytes(ABase64);
  except
    Exit;
  end;
  if Length(LInBytes) = 0 then
    Exit;

  FillChar(LInBlob, SizeOf(LInBlob), 0);
  FillChar(LOutBlob, SizeOf(LOutBlob), 0);
  LInBlob.cbData := DWORD(Length(LInBytes));
  LInBlob.pbData := @LInBytes[0];
  if not CryptUnprotectData(@LInBlob, nil, nil, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @LOutBlob) then
    Exit;
  try
    if (LOutBlob.pbData = nil) or (LOutBlob.cbData = 0) then
      Exit;
    SetLength(LOutBytes, LOutBlob.cbData);
    Move(LOutBlob.pbData^, LOutBytes[0], LOutBlob.cbData);
    APlain := TEncoding.UTF8.GetString(LOutBytes);
    Result := True;
  finally
    if LOutBlob.pbData <> nil then
      LocalFree(HLOCAL(LOutBlob.pbData));
  end;
end;

class function TKrvnCrypto.RandomBytes(ALength: Integer): TBytes;
begin
  if ALength <= 0 then
    Exit(nil);
  SetLength(Result, ALength);
  if not RtlGenRandom(@Result[0], ALength) then
    raise EKrvnCryptoError.Create('RtlGenRandom failed');
end;

class function TKrvnCrypto.HMACSHA256(const AKey, AData: TBytes): TBytes;
begin
  Result := THashSHA2.GetHMACAsBytes(AData, AKey, THashSHA2.TSHA2Version.SHA256);
end;

class function TKrvnCrypto.PBKDF2SHA256(const APassword, ASalt: TBytes; AIterations,
  AKeyLen: Integer): TBytes;
var
  LHashLen: Integer;
  LBlockCount: Integer;
  LBlockIndex: Integer;
  LI: Integer;
  LPos: Integer;
  LSaltBlock: TBytes;
  LU: TBytes;
  LT: TBytes;
  LCounter: array[0..3] of Byte;
  J: Integer;
begin
  if AIterations <= 0 then
    raise EKrvnCryptoError.Create('Iterations must be > 0');
  if AKeyLen <= 0 then
    raise EKrvnCryptoError.Create('Key length must be > 0');

  LHashLen := 32;
  LBlockCount := (AKeyLen + LHashLen - 1) div LHashLen;
  SetLength(Result, LBlockCount * LHashLen);
  LPos := 0;

  for LBlockIndex := 1 to LBlockCount do
  begin
    LCounter[0] := (LBlockIndex shr 24) and $FF;
    LCounter[1] := (LBlockIndex shr 16) and $FF;
    LCounter[2] := (LBlockIndex shr 8) and $FF;
    LCounter[3] := LBlockIndex and $FF;

    SetLength(LSaltBlock, Length(ASalt) + 4);
    if Length(ASalt) > 0 then
      Move(ASalt[0], LSaltBlock[0], Length(ASalt));
    Move(LCounter[0], LSaltBlock[Length(ASalt)], 4);

    LU := HMACSHA256(APassword, LSaltBlock);
    LT := System.Copy(LU, 0, Length(LU));

    for LI := 2 to AIterations do
    begin
      LU := HMACSHA256(APassword, LU);
      for J := 0 to High(LT) do
        LT[J] := LT[J] xor LU[J];
    end;

    Move(LT[0], Result[LPos], Length(LT));
    Inc(LPos, Length(LT));
  end;

  SetLength(Result, AKeyLen);
end;

class function TKrvnCrypto.ProtectStringDpapi(const AValue: string): string;
var
  LInBytes: TBytes;
  LOutBytes: TBytes;
  LInBlob: TKrvnDataBlob;
  LOutBlob: TKrvnDataBlob;
begin
  if AValue = '' then
    Exit('plain:');

  LInBytes := TEncoding.UTF8.GetBytes(AValue);
  if Length(LInBytes) = 0 then
    Exit('plain:');

  FillChar(LInBlob, SizeOf(LInBlob), 0);
  FillChar(LOutBlob, SizeOf(LOutBlob), 0);
  LInBlob.cbData := DWORD(Length(LInBytes));
  LInBlob.pbData := @LInBytes[0];

  if CryptProtectData(@LInBlob, nil, nil, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @LOutBlob) then
  try
    if (LOutBlob.pbData <> nil) and (LOutBlob.cbData > 0) then
    begin
      SetLength(LOutBytes, LOutBlob.cbData);
      Move(LOutBlob.pbData^, LOutBytes[0], LOutBlob.cbData);
      Exit('dpapi:' + TNetEncoding.Base64.EncodeBytesToString(LOutBytes));
    end;
  finally
    if LOutBlob.pbData <> nil then
      LocalFree(HLOCAL(LOutBlob.pbData));
  end;

  Result := 'plain:' + TNetEncoding.Base64.EncodeBytesToString(LInBytes);
end;

class function TKrvnCrypto.UnprotectStringDpapi(const AValue: string): string;
var
  LData: TBytes;
  LRaw: string;
begin
  if Trim(AValue) = '' then
    Exit('');
  LRaw := AValue;

  if SameText(Copy(LRaw, 1, 6), 'plain:') then
  begin
    Delete(LRaw, 1, 6);
    try
      LData := TNetEncoding.Base64.DecodeStringToBytes(LRaw);
      Exit(TEncoding.UTF8.GetString(LData));
    except
      Exit(AValue);
    end;
  end;

  if SameText(Copy(LRaw, 1, 6), 'dpapi:') then
  begin
    Delete(LRaw, 1, 6);
    if TryUnprotectDpapiBase64(LRaw, Result) then
      Exit;
    Exit(AValue);
  end;

  // Legacy compatibility: raw base64 DPAPI payload used by earlier builds.
  if TryUnprotectDpapiBase64(LRaw, Result) then
    Exit;

  // Fallback: interpret as raw base64 UTF-8 plaintext for old compatibility mode.
  try
    LData := TNetEncoding.Base64.DecodeStringToBytes(LRaw);
    Exit(TEncoding.UTF8.GetString(LData));
  except
    Exit(AValue);
  end;
end;

class function TKrvnCrypto.DerivePasswordHash(const APassword: string; const ASalt: TBytes;
  AIterations: Integer): TBytes;
begin
  Result := PBKDF2SHA256(TEncoding.UTF8.GetBytes(APassword), ASalt, AIterations, 32);
end;

class function TKrvnCrypto.BuildAuthProof(const APbkdf2Hash, ANonce: TBytes): TBytes;
begin
  Result := HMACSHA256(APbkdf2Hash, ANonce);
end;

end.
