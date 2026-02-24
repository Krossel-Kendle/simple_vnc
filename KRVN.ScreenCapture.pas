unit KRVN.ScreenCapture;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  TFrameReadyEvent = procedure(Sender: TObject; const APayload: TBytes;
    AWidth, AHeight: Integer; AFrameNo: Cardinal) of object;

  TScreenCaptureThread = class(TThread)
  private
    FLock: TCriticalSection;
    FFps: Integer;
    FQuality: Integer;
    FMaxWidth: Integer;
    FMaxHeight: Integer;
    FOnFrameReady: TFrameReadyEvent;
    procedure CaptureOneFrame(var AFrameNo: Cardinal);
  protected
    procedure Execute; override;
  public
    constructor Create(AFps, AQuality, AMaxWidth, AMaxHeight: Integer);
    destructor Destroy; override;
    procedure UpdateSettings(AFps, AQuality, AMaxWidth, AMaxHeight: Integer);
    property OnFrameReady: TFrameReadyEvent read FOnFrameReady write FOnFrameReady;
  end;

implementation

uses
  System.Math,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.Imaging.jpeg,
  KRVN.FrameCodec;

constructor TScreenCaptureThread.Create(AFps, AQuality, AMaxWidth, AMaxHeight: Integer);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FFps := EnsureRange(AFps, 1, 100);
  FQuality := AQuality;
  FMaxWidth := AMaxWidth;
  FMaxHeight := AMaxHeight;
end;

destructor TScreenCaptureThread.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TScreenCaptureThread.UpdateSettings(AFps, AQuality, AMaxWidth, AMaxHeight: Integer);
begin
  FLock.Enter;
  try
    FFps := EnsureRange(AFps, 1, 100);
    FQuality := EnsureRange(AQuality, 20, 95);
    FMaxWidth := Max(320, AMaxWidth);
    FMaxHeight := Max(240, AMaxHeight);
  finally
    FLock.Leave;
  end;
end;

procedure TScreenCaptureThread.CaptureOneFrame(var AFrameNo: Cardinal);
var
  LScreenDC: HDC;
  LScreenW, LScreenH: Integer;
  LCapW, LCapH: Integer;
  LBitmap: TBitmap;
  LJpeg: TJPEGImage;
  LMs: TMemoryStream;
  LJpegBytes: TBytes;
  LPayload: TBytes;
  LQuality: Integer;
  LFps: Integer;
  LMaxW: Integer;
  LMaxH: Integer;
begin
  FLock.Enter;
  try
    LQuality := FQuality;
    LFps := FFps;
    LMaxW := FMaxWidth;
    LMaxH := FMaxHeight;
  finally
    FLock.Leave;
  end;
  if LFps <= 0 then
    Exit;

  LScreenW := GetSystemMetrics(SM_CXSCREEN);
  LScreenH := GetSystemMetrics(SM_CYSCREEN);
  LCapW := LScreenW;
  LCapH := LScreenH;
  if (LMaxW > 0) and (LCapW > LMaxW) then
  begin
    LCapH := MulDiv(LCapH, LMaxW, LCapW);
    LCapW := LMaxW;
  end;
  if (LMaxH > 0) and (LCapH > LMaxH) then
  begin
    LCapW := MulDiv(LCapW, LMaxH, LCapH);
    LCapH := LMaxH;
  end;

  LBitmap := TBitmap.Create;
  LJpeg := TJPEGImage.Create;
  LMs := TMemoryStream.Create;
  try
    LBitmap.PixelFormat := pf24bit;
    LBitmap.SetSize(LCapW, LCapH);

    LScreenDC := GetDC(0);
    if LScreenDC = 0 then
      Exit;
    try
      if (LCapW = LScreenW) and (LCapH = LScreenH) then
        BitBlt(LBitmap.Canvas.Handle, 0, 0, LCapW, LCapH, LScreenDC, 0, 0, SRCCOPY)
      else
      begin
        // Faster downscale mode to improve effective FPS on typical office desktops.
        SetStretchBltMode(LBitmap.Canvas.Handle, COLORONCOLOR);
        StretchBlt(LBitmap.Canvas.Handle, 0, 0, LCapW, LCapH, LScreenDC, 0, 0, LScreenW, LScreenH,
          SRCCOPY);
      end;
    finally
      ReleaseDC(0, LScreenDC);
    end;

    LJpeg.Assign(LBitmap);

    LJpeg.CompressionQuality := EnsureRange(LQuality, 20, 95);
    LJpeg.Compress;
    LJpeg.SaveToStream(LMs);

    SetLength(LJpegBytes, LMs.Size);
    if LMs.Size > 0 then
    begin
      LMs.Position := 0;
      LMs.ReadBuffer(LJpegBytes[0], LMs.Size);
    end;

    Inc(AFrameNo);
    LPayload := BuildVideoFramePayload(AFrameNo, GetTickCount, LCapW, LCapH, LQuality, 0, LJpegBytes);
    if Assigned(FOnFrameReady) then
      FOnFrameReady(Self, LPayload, LCapW, LCapH, AFrameNo);
  finally
    LMs.Free;
    LJpeg.Free;
    LBitmap.Free;
  end;
end;

procedure TScreenCaptureThread.Execute;
var
  LFrameNo: Cardinal;
  LFrameMs: Cardinal;
  LTickStart: Cardinal;
  LElapsed: Cardinal;
  LSleep: Integer;
  LFps: Integer;
begin
  LFrameNo := 0;
  while not Terminated do
  begin
    FLock.Enter;
    try
      LFps := Max(1, FFps);
    finally
      FLock.Leave;
    end;
    LFrameMs := Cardinal(1000 div LFps);

    LTickStart := GetTickCount;
    CaptureOneFrame(LFrameNo);
    LElapsed := GetTickCount - LTickStart;
    LSleep := Integer(LFrameMs) - Integer(LElapsed);
    if LSleep > 0 then
      Sleep(LSleep)
    else
      Sleep(1);
  end;
end;

end.
