unit KRVN.InputInjector;

interface

uses
  KRVN.Types;

type
  TKrvnInputInjector = class
  public
    class procedure Inject(const AEvent: TKrvnInputEvent; ARemoteWidth, ARemoteHeight: Integer); static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Math;

class procedure TKrvnInputInjector.Inject(const AEvent: TKrvnInputEvent; ARemoteWidth,
  ARemoteHeight: Integer);
var
  LInput: TInput;
  LScreenWidth: Integer;
  LScreenHeight: Integer;
  LDown: Boolean;
begin
  FillChar(LInput, SizeOf(LInput), 0);
  LDown := (AEvent.Flags and 1) <> 0;
  case AEvent.EventType of
    KRVN_INPUT_MOUSE_MOVE:
      begin
        LScreenWidth := GetSystemMetrics(SM_CXSCREEN);
        LScreenHeight := GetSystemMetrics(SM_CYSCREEN);
        if ARemoteWidth <= 0 then
          ARemoteWidth := LScreenWidth;
        if ARemoteHeight <= 0 then
          ARemoteHeight := LScreenHeight;

        LInput.Itype := INPUT_MOUSE;
        LInput.mi.dwFlags := MOUSEEVENTF_MOVE or MOUSEEVENTF_ABSOLUTE;
        LInput.mi.dx := MulDiv(AEvent.P1, 65535, Max(1, ARemoteWidth - 1));
        LInput.mi.dy := MulDiv(AEvent.P2, 65535, Max(1, ARemoteHeight - 1));
        SendInput(1, LInput, SizeOf(TInput));
      end;
    KRVN_INPUT_MOUSE_BUTTON:
      begin
        LInput.Itype := INPUT_MOUSE;
        case AEvent.P1 of
          1:
            if LDown then
              LInput.mi.dwFlags := MOUSEEVENTF_LEFTDOWN
            else
              LInput.mi.dwFlags := MOUSEEVENTF_LEFTUP;
          2:
            if LDown then
              LInput.mi.dwFlags := MOUSEEVENTF_RIGHTDOWN
            else
              LInput.mi.dwFlags := MOUSEEVENTF_RIGHTUP;
          3:
            if LDown then
              LInput.mi.dwFlags := MOUSEEVENTF_MIDDLEDOWN
            else
              LInput.mi.dwFlags := MOUSEEVENTF_MIDDLEUP;
        end;
        SendInput(1, LInput, SizeOf(TInput));
      end;
    KRVN_INPUT_MOUSE_WHEEL:
      begin
        LInput.Itype := INPUT_MOUSE;
        LInput.mi.dwFlags := MOUSEEVENTF_WHEEL;
        LInput.mi.mouseData := Cardinal(AEvent.P3);
        SendInput(1, LInput, SizeOf(TInput));
      end;
    KRVN_INPUT_KEY:
      begin
        LInput.Itype := INPUT_KEYBOARD;
        LInput.ki.wVk := AEvent.P1;
        LInput.ki.wScan := AEvent.P2;
        if not LDown then
          LInput.ki.dwFlags := KEYEVENTF_KEYUP;
        SendInput(1, LInput, SizeOf(TInput));
      end;
  end;
end;

end.
