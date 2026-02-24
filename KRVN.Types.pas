unit KRVN.Types;

interface

uses
  System.SysUtils;

const
  KRVN_PROTOCOL_VERSION = 1;
  KRVN_HEADER_SIZE = 40;

  KRVN_FLAG_ENCRYPTED = $00000001;
  KRVN_FLAG_COMPRESSED = $00000002;

  KRVN_CHANNEL_CONTROL = 0;
  KRVN_CHANNEL_VIDEO = 1;
  KRVN_CHANNEL_INPUT = 2;
  KRVN_CHANNEL_CLIPBOARD = 3;
  KRVN_CHANNEL_FILES = 4;
  KRVN_CHANNEL_CHAT = 5;
  KRVN_CHANNEL_STATS = 6;

  KRVN_MSG_HELLO = 1;
  KRVN_MSG_AUTH_BEGIN = 2;
  KRVN_MSG_AUTH_CHALLENGE = 3;
  KRVN_MSG_AUTH_PROOF = 4;
  KRVN_MSG_AUTH_OK = 5;
  KRVN_MSG_AUTH_FAIL = 6;
  KRVN_MSG_PROVIDER_REGISTER = 10;
  KRVN_MSG_PROVIDER_REGISTERED = 11;
  KRVN_MSG_CLIENT_LIST_PROVIDERS = 20;
  KRVN_MSG_PROVIDERS_LIST = 21;
  KRVN_MSG_CLIENT_CONNECT_PROVIDER = 22;
  KRVN_MSG_CLIENT_CONNECT_HIDDEN = 23;
  KRVN_MSG_SESSION_OFFER = 30;
  KRVN_MSG_SESSION_ACCEPT = 31;
  KRVN_MSG_SESSION_REJECT = 32;
  KRVN_MSG_SESSION_ACTIVE = 33;
  KRVN_MSG_SESSION_CLOSE = 34;
  KRVN_MSG_VIDEO_SETTINGS = 35;
  KRVN_MSG_CH_OPEN = 36;
  KRVN_MSG_CH_CLOSE = 37;
  KRVN_MSG_CH_OPEN_ACK = 38;
  KRVN_MSG_CLIPBOARD_SET = 40;
  KRVN_MSG_FILE_OFFER = 41;
  KRVN_MSG_FILE_CHUNK = 42;
  KRVN_MSG_FILE_END = 43;
  KRVN_MSG_FILE_RESULT = 44;
  KRVN_MSG_VIDEO_FRAME = 100;
  KRVN_MSG_INPUT_EVENT = 101;
  KRVN_MSG_PING = 200;
  KRVN_MSG_PONG = 201;
  KRVN_MSG_ERROR = 255;

  KRVN_INPUT_MOUSE_MOVE = 1;
  KRVN_INPUT_MOUSE_BUTTON = 2;
  KRVN_INPUT_MOUSE_WHEEL = 3;
  KRVN_INPUT_KEY = 4;

type
  TKrvnRole = (krUnknown, krClient, krProvider, krServerAdmin);
  TKrvnVisibility = (kvPublic, kvHidden);
  THiddenResolvePolicy = (hrRestricted, hrFirst, hrLast);
  TSessionState = (ssOffering, ssActive, ssClosing, ssClosed);

  TKrvnPacketHeader = packed record
    Magic: array[0..3] of AnsiChar;
    Version: Byte;
    HeaderSize: Byte;
    MsgType: Word;
    Flags: Cardinal;
    SessionId: UInt64;
    ChannelId: Cardinal;
    Seq: Cardinal;
    PayloadLen: Cardinal;
    HeaderCrc32: Cardinal;
    PayloadCrc32: Cardinal;
  end;

  TKrvnVideoFrameMeta = packed record
    FrameNo: Cardinal;
    TimestampMs: Cardinal;
    Width: Word;
    Height: Word;
    Format: Byte;
    Quality: Byte;
    Flags: Word;
    DataLen: Cardinal;
  end;

  TKrvnInputEvent = packed record
    EventType: Byte;
    Flags: Byte;
    Reserved: Word;
    P1: Integer;
    P2: Integer;
    P3: Integer;
    P4: Integer;
  end;

function KrvnRoleToStr(const ARole: TKrvnRole): string;
function StrToKrvnRole(const AValue: string): TKrvnRole;
function KrvnVisibilityToStr(const AValue: TKrvnVisibility): string;
function StrToKrvnVisibility(const AValue: string): TKrvnVisibility;
function HiddenResolvePolicyToStr(const AValue: THiddenResolvePolicy): string;
function StrToHiddenResolvePolicy(const AValue: string): THiddenResolvePolicy;

implementation

function KrvnRoleToStr(const ARole: TKrvnRole): string;
begin
  case ARole of
    krClient:
      Result := 'client';
    krProvider:
      Result := 'provider';
    krServerAdmin:
      Result := 'server-admin';
  else
    Result := 'unknown';
  end;
end;

function StrToKrvnRole(const AValue: string): TKrvnRole;
var
  LValue: string;
begin
  LValue := Trim(LowerCase(AValue));
  if LValue = 'client' then
    Exit(krClient);
  if LValue = 'provider' then
    Exit(krProvider);
  if LValue = 'server-admin' then
    Exit(krServerAdmin);
  Result := krUnknown;
end;

function KrvnVisibilityToStr(const AValue: TKrvnVisibility): string;
begin
  case AValue of
    kvHidden:
      Result := 'hidden';
  else
    Result := 'public';
  end;
end;

function StrToKrvnVisibility(const AValue: string): TKrvnVisibility;
begin
  if Trim(LowerCase(AValue)) = 'hidden' then
    Exit(kvHidden);
  Result := kvPublic;
end;

function HiddenResolvePolicyToStr(const AValue: THiddenResolvePolicy): string;
begin
  case AValue of
    hrFirst:
      Result := 'first';
    hrLast:
      Result := 'last';
  else
    Result := 'restricted';
  end;
end;

function StrToHiddenResolvePolicy(const AValue: string): THiddenResolvePolicy;
var
  LValue: string;
begin
  LValue := Trim(LowerCase(AValue));
  if LValue = 'first' then
    Exit(hrFirst);
  if LValue = 'last' then
    Exit(hrLast);
  Result := hrRestricted;
end;

end.
