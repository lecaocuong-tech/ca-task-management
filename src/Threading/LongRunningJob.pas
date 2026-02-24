unit LongRunningJob;

interface

uses
  System.SysUtils,
  System.Classes,
  AppInterfaces,
  BackgroundJob;

type
  TLongRunningJob = class(TBackgroundJob)
  private
    FDurationSeconds: Integer;
  public
    constructor Create(ADurationSeconds: Integer; ALogger: ILogger);

  protected
    procedure Execute; override;
  end;

implementation

{ TLongRunningJob }

constructor TLongRunningJob.Create(ADurationSeconds: Integer; ALogger: ILogger);
begin
  inherited Create(ALogger);
  FDurationSeconds := ADurationSeconds;
end;

procedure TLongRunningJob.Execute;
var
  I: Integer;
  LStepDuration: Integer;
begin
  try
    FLogger.Info(Format('LongRunningJob: Starting (duration: %d seconds)', [FDurationSeconds]));
    
    LStepDuration := FDurationSeconds * 1000 div 10; // 10 steps
    
    for I := 0 to 9 do
    begin
      if FCancelling then
      begin
        FLogger.Info('LongRunningJob: Cancel requested, stopping');
        Exit;
      end;

      TThread.Sleep(LStepDuration);
      FProgress := (I + 1) * 10;
      FLogger.Info(Format('LongRunningJob: Progress %d%%', [FProgress]));
    end;

    FLogger.Info('LongRunningJob: Completed');
    OnJobComplete;
  except
    on E: Exception do
    begin
      OnJobFailed('Job execution failed: ' + E.Message);
    end;
  end;
end;

end.
