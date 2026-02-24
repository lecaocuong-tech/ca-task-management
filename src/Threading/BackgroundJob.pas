unit BackgroundJob;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  AppInterfaces;

{
  BackgroundJob.pas
  -----------------
  TJobState and IBackgroundJob are declared in AppInterfaces.pas.
  This unit contains the abstract base class TBackgroundJob and the
  helper TBackgroundJobThread.

  Thread-safety: FState changes are protected by a dedicated TCriticalSection
  to avoid race conditions between the worker thread and UI polling.
}

type
  TBackgroundJobThread = class(TThread)
  private
    FJob: IBackgroundJob;
    FOnComplete: TNotifyEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AJob: IBackgroundJob; AOnComplete: TNotifyEvent = nil);
  end;

  TBackgroundJob = class(TInterfacedObject, IBackgroundJob)
  protected
    FState: TJobState;
    FProgress: Integer;
    FErrorMessage: string;
    FLogger: ILogger;
    FCancelling: Boolean;
    FStateLock: TCriticalSection;
  public
    constructor Create(ALogger: ILogger);
    destructor Destroy; override;

    procedure Start;
    procedure Cancel;
    function GetState: TJobState;
    function GetProgress: Integer;
    function GetErrorMessage: string;

  protected
    procedure Execute; virtual; abstract;
    procedure OnJobComplete;
    procedure OnJobFailed(const AErrorMessage: string);
  end;

implementation

{ TBackgroundJobThread }

constructor TBackgroundJobThread.Create(AJob: IBackgroundJob; AOnComplete: TNotifyEvent = nil);
begin
  inherited Create(True);
  FJob := AJob;
  FOnComplete := AOnComplete;
  FreeOnTerminate := True;
end;

procedure TBackgroundJobThread.Execute;
begin
  if Assigned(FJob) then
  begin
    (FJob as TBackgroundJob).Execute;
    
    if Assigned(FOnComplete) then
      TThread.Queue(nil, procedure
      begin
        FOnComplete(Self);
      end);
  end;
end;

{ TBackgroundJob }

constructor TBackgroundJob.Create(ALogger: ILogger);
begin
  inherited Create;
  FStateLock := TCriticalSection.Create;
  FState := jsIdle;
  FProgress := 0;
  FErrorMessage := '';
  FLogger := ALogger;
  FCancelling := False;
end;

destructor TBackgroundJob.Destroy;
begin
  FCancelling := True;
  FStateLock.Free;
  inherited;
end;

procedure TBackgroundJob.Start;
var
  LThread: TBackgroundJobThread;
begin
  FStateLock.Enter;
  try
    if FState = jsRunning then
    begin
      FLogger.Warning('Job is already running');
      Exit;
    end;

    FState := jsRunning;
    FProgress := 0;
    FErrorMessage := '';
    FCancelling := False;
  finally
    FStateLock.Leave;
  end;

  LThread := TBackgroundJobThread.Create(Self, nil);
  LThread.Start;

  FLogger.Info('Background job started');
end;

procedure TBackgroundJob.Cancel;
begin
  if FState = jsRunning then
  begin
    FCancelling := True;
    FLogger.Info('Background job cancel requested');
  end;
end;

function TBackgroundJob.GetState: TJobState;
begin
  FStateLock.Enter;
  try
    Result := FState;
  finally
    FStateLock.Leave;
  end;
end;

function TBackgroundJob.GetProgress: Integer;
begin
  Result := FProgress;
end;

function TBackgroundJob.GetErrorMessage: string;
begin
  Result := FErrorMessage;
end;

procedure TBackgroundJob.OnJobComplete;
begin
  FStateLock.Enter;
  try
    if FCancelling then
      FState := jsCancelled
    else
      FState := jsCompleted;
  finally
    FStateLock.Leave;
  end;
  FLogger.Info('Background job completed - State: ' + IntToStr(Integer(FState)));
end;

procedure TBackgroundJob.OnJobFailed(const AErrorMessage: string);
begin
  FStateLock.Enter;
  try
    FState := jsFailed;
    FErrorMessage := AErrorMessage;
  finally
    FStateLock.Leave;
  end;
  FLogger.Error('Background job failed: ' + AErrorMessage);
end;

end.
