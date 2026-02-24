unit AutoCleanupJob;

interface

uses
  System.SysUtils,
  System.Classes,
  AppInterfaces,
  BackgroundJob;

type
  TAutoCleanupJob = class(TBackgroundJob)
  private
    FTaskService: ITaskService;
    FDaysOld: Integer;
  public
    constructor Create(ATaskService: ITaskService; ADaysOld: Integer; ALogger: ILogger);

  protected
    procedure Execute; override;
  end;

implementation

{ TAutoCleanupJob }

constructor TAutoCleanupJob.Create(ATaskService: ITaskService; ADaysOld: Integer; ALogger: ILogger);
begin
  inherited Create(ALogger);
  FTaskService := ATaskService;
  FDaysOld := ADaysOld;
end;

procedure TAutoCleanupJob.Execute;
var
  LDeletedCount: Integer;
begin
  try
    FLogger.Info(Format('AutoCleanupJob: Starting cleanup of Done tasks older than %d days', [FDaysOld]));
    
    FProgress := 25;
    TThread.Sleep(500); // Simulate work

    LDeletedCount := FTaskService.SystemCleanupCompletedTasks(FDaysOld);
    
    FProgress := 100;
    FLogger.Info(Format('AutoCleanupJob: Deleted %d tasks', [LDeletedCount]));
    
    OnJobComplete;
  except
    on E: Exception do
    begin
      OnJobFailed('Cleanup failed: ' + E.Message);
    end;
  end;
end;

end.
