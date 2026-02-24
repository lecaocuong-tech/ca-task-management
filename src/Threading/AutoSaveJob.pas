unit AutoSaveJob;

interface

uses
  System.SysUtils,
  System.Classes,
  AppInterfaces,
  BackgroundJob;

{
  AutoSaveJob.pas
  ---------------
  Background job that periodically touches UpdatedAt for all active tasks.
  Uses SystemBulkTouchUpdatedAt (single SQL UPDATE) instead of loading and
  updating each task individually => O(1) instead of O(n).
}

type
  TAutoSaveJob = class(TBackgroundJob)
  private
    FTaskService: ITaskService;
    FIntervalSeconds: Integer;
  public
    constructor Create(ATaskService: ITaskService; AIntervalSeconds: Integer; ALogger: ILogger);

  protected
    procedure Execute; override;
  end;

implementation

{ TAutoSaveJob }

constructor TAutoSaveJob.Create(ATaskService: ITaskService; AIntervalSeconds: Integer; ALogger: ILogger);
begin
  inherited Create(ALogger);
  FTaskService := ATaskService;
  FIntervalSeconds := AIntervalSeconds;
end;

procedure TAutoSaveJob.Execute;
var
  LTouched: Integer;
begin
  try
    FLogger.Info(Format('AutoSaveJob: Starting (interval %d seconds)', [FIntervalSeconds]));

    while not FCancelling do
    begin
      // Single SQL UPDATE instead of loading all tasks individually.
      // O(1) performance regardless of task count.
      LTouched := FTaskService.SystemBulkTouchUpdatedAt;
      FLogger.Info(Format('AutoSaveJob: Touched %d tasks', [LTouched]));

      // Sleep for interval, checking cancellation periodically
      if FCancelling then
        Break;

      FProgress := 0;
      TThread.Sleep(FIntervalSeconds * 1000);
    end;

    OnJobComplete;
  except
    on E: Exception do
    begin
      OnJobFailed('AutoSave failed: ' + E.Message);
    end;
  end;
end;

end.
