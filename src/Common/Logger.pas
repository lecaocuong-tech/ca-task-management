unit Logger;

interface

uses
  System.SysUtils,
  AppInterfaces;

{
  Logger.pas
  ----------
  ILogger interface is declared in AppInterfaces.pas (Dependency Inversion).
  This unit only contains the concrete TFileLogger implementation.
}

type
  TFileLogger = class(TInterfacedObject, ILogger)
  private
    FLogFile: string;
    FLock: TObject;
  public
    constructor Create(const ALogFile: string);
    destructor Destroy; override;

    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warning(const AMessage: string);
    procedure Error(const AMessage: string; AException: Exception = nil);
    procedure Fatal(const AMessage: string; AException: Exception = nil);

  private
    procedure WriteLog(const ALevel, AMessage: string; AException: Exception = nil);
  end;

implementation

{ TFileLogger }

constructor TFileLogger.Create(const ALogFile: string);
begin
  inherited Create;
  FLogFile := ALogFile;
  FLock := TObject.Create;
  
  // Create directory if it does not exist
  if not DirectoryExists(ExtractFilePath(ALogFile)) then
    ForceDirectories(ExtractFilePath(ALogFile));
end;

destructor TFileLogger.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TFileLogger.Debug(const AMessage: string);
begin
  WriteLog('DEBUG', AMessage);
end;

procedure TFileLogger.Info(const AMessage: string);
begin
  WriteLog('INFO', AMessage);
end;

procedure TFileLogger.Warning(const AMessage: string);
begin
  WriteLog('WARNING', AMessage);
end;

procedure TFileLogger.Error(const AMessage: string; AException: Exception = nil);
begin
  WriteLog('ERROR', AMessage, AException);
end;

procedure TFileLogger.Fatal(const AMessage: string; AException: Exception = nil);
begin
  WriteLog('FATAL', AMessage, AException);
end;

procedure TFileLogger.WriteLog(const ALevel, AMessage: string; AException: Exception = nil);
var
  LLogMessage: string;
  LFile: TextFile;
begin
  TMonitor.Enter(FLock);
  try
    LLogMessage := Format('[%s] %s - %s', [
      FormatDateTime('yyyy-mm-dd hh:nn:ss', Now),
      ALevel,
      AMessage
    ]);

    if AException <> nil then
      LLogMessage := LLogMessage + ' | ' + AException.Message;

    AssignFile(LFile, FLogFile);
    try
      if FileExists(FLogFile) then
        Append(LFile)
      else
        Rewrite(LFile);

      System.WriteLn(LFile, LLogMessage);
    finally
      CloseFile(LFile);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
