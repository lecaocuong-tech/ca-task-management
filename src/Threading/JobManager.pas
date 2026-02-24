unit JobManager;

interface

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  AppInterfaces;

{
  JobManager.pas
  --------------
  IJobManager interface is declared in AppInterfaces.pas (Dependency Inversion).
  Manages the lifecycle of background jobs: submission, cancellation, and
  waiting for completion with timeout.
}

type
  TJobManager = class(TInterfacedObject, IJobManager)
  private
    FJobList: TList<IBackgroundJob>;
    FLock: TObject;
    FLogger: ILogger;
  public
    constructor Create(ALogger: ILogger);
    destructor Destroy; override;

    procedure SubmitJob(AJob: IBackgroundJob);
    function GetActiveJobCount: Integer;
    procedure CancelAllJobs;
    procedure WaitForAllJobsCompletion(ATimeoutMS: Integer = 30000);

  private
    procedure RemoveCompletedJobs;
  end;

implementation

{ TJobManager }

constructor TJobManager.Create(ALogger: ILogger);
begin
  inherited Create;
  FJobList := TList<IBackgroundJob>.Create;
  FLock := TObject.Create;
  FLogger := ALogger;
end;

destructor TJobManager.Destroy;
begin
  CancelAllJobs;
  RemoveCompletedJobs;
  FJobList.Free;
  FLock.Free;
  inherited;
end;

procedure TJobManager.SubmitJob(AJob: IBackgroundJob);
begin
  TMonitor.Enter(FLock);
  try
    FJobList.Add(AJob);
    AJob.Start;
    FLogger.Info(Format('Job submitted. Active jobs: %d', [FJobList.Count]));
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TJobManager.GetActiveJobCount: Integer;
begin
  TMonitor.Enter(FLock);
  try
    RemoveCompletedJobs;
    Result := FJobList.Count;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TJobManager.CancelAllJobs;
var
  I: Integer;
begin
  TMonitor.Enter(FLock);
  try
    for I := 0 to FJobList.Count - 1 do
    begin
      if FJobList[I].GetState = jsRunning then
      begin
        FJobList[I].Cancel;
        FLogger.Info(Format('Job cancelled. Job index: %d', [I]));
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TJobManager.WaitForAllJobsCompletion(ATimeoutMS: Integer = 30000);
var
  LStartTime: TDateTime;
  LElapsedTime: Integer;
begin
  LStartTime := Now;
  
  while True do
  begin
    TMonitor.Enter(FLock);
    try
      RemoveCompletedJobs;
      if FJobList.Count = 0 then
      begin
        FLogger.Info('All jobs completed');
        Exit;
      end;
    finally
      TMonitor.Exit(FLock);
    end;

    LElapsedTime := MilliSecondsBetween(LStartTime, Now);
    if LElapsedTime >= ATimeoutMS then
    begin
      FLogger.Warning(Format('WaitForAllJobsCompletion timeout (%d ms)', [ATimeoutMS]));
      Exit;
    end;

    TThread.Sleep(100);
  end;
end;

procedure TJobManager.RemoveCompletedJobs;
var
  I: Integer;
begin
  for I := FJobList.Count - 1 downto 0 do
  begin
    case FJobList[I].GetState of
      jsCompleted, jsCancelled, jsFailed:
      begin
        FJobList.Delete(I);
      end;
    end;
  end;
end;

end.
