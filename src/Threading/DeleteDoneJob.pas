unit DeleteDoneJob;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  BackgroundJob,
  Result;

type
  /// <summary>Background job that deletes tasks with status Done one by one,
  /// sleeping 3 seconds between each deletion. Supports cancellation.
  /// Fires OnTaskDeleted (queued to main thread) after each deletion so the
  /// UI can refresh the task list.</summary>
  TDeleteDoneJob = class(TBackgroundJob)
  private
    FTaskService: ITaskService;
    FOnTaskDeleted: TProc;
  public
    constructor Create(ATaskService: ITaskService; ALogger: ILogger);

    /// <summary>Callback invoked on the MAIN thread after each task is deleted.
    /// Set this before calling Start.</summary>
    property OnTaskDeleted: TProc read FOnTaskDeleted write FOnTaskDeleted;

  protected
    procedure Execute; override;
  end;

implementation

{ TDeleteDoneJob }

constructor TDeleteDoneJob.Create(ATaskService: ITaskService; ALogger: ILogger);
begin
  inherited Create(ALogger);
  FTaskService := ATaskService;
  FOnTaskDeleted := nil;
end;

procedure TDeleteDoneJob.Execute;
var
  LAllTasks: TList<TTask>;
  LDoneTasks: TList<Integer>;
  I: Integer;
  LDeleteResult: TResult;
  LTotal: Integer;
  LDeleted: Integer;
  LCapturedCallback: TProc;
begin
  try
    FLogger.Info('DeleteDoneJob: Starting - collecting Done tasks');

    // Capture the callback reference for thread-safe usage
    LCapturedCallback := FOnTaskDeleted;

    // Gather all tasks and filter for Done status
    LDoneTasks := TList<Integer>.Create;
    try
      LAllTasks := FTaskService.SystemGetAllTasks;
      try
        for I := 0 to LAllTasks.Count - 1 do
        begin
          if LAllTasks[I].Status = tsDone then
            LDoneTasks.Add(LAllTasks[I].Id);
        end;
      finally
        // TObjectList<TTask> with OwnsObjects=True auto-frees items
        LAllTasks.Free;
      end;

      LTotal := LDoneTasks.Count;
      FLogger.Info(Format('DeleteDoneJob: Found %d Done task(s) to delete', [LTotal]));

      if LTotal = 0 then
      begin
        FProgress := 100;
        FLogger.Info('DeleteDoneJob: No Done tasks found, nothing to do');
        OnJobComplete;
        Exit;
      end;

      LDeleted := 0;

      for I := 0 to LDoneTasks.Count - 1 do
      begin
        // Check for cancellation before each deletion
        if FCancelling then
        begin
          FLogger.Info(Format('DeleteDoneJob: Cancelled after deleting %d of %d tasks',
            [LDeleted, LTotal]));
          OnJobComplete; // will set state to jsCancelled because FCancelling = True
          Exit;
        end;

        // Wait 3 seconds before deleting (allows cancellation during wait)
        if I > 0 then
        begin
          // Split the 3-second wait into smaller chunks for responsive cancellation
          var LWaitMs := 0;
          while LWaitMs < 3000 do
          begin
            if FCancelling then
            begin
              FLogger.Info(Format('DeleteDoneJob: Cancelled during wait after deleting %d of %d tasks',
                [LDeleted, LTotal]));
              OnJobComplete;
              Exit;
            end;
            TThread.Sleep(100);
            Inc(LWaitMs, 100);
          end;
        end;

        // Delete the task
        LDeleteResult := FTaskService.SystemDeleteTask(LDoneTasks[I]);

        if LDeleteResult.IsSuccess then
        begin
          Inc(LDeleted);
          FProgress := (LDeleted * 100) div LTotal;
          FLogger.Info(Format('DeleteDoneJob: Deleted task %d (%d/%d) - Progress %d%%',
            [LDoneTasks[I], LDeleted, LTotal, FProgress]));

          // Notify the UI to refresh (queued to main thread)
          if Assigned(LCapturedCallback) then
          begin
            TThread.Queue(nil, procedure
            begin
              LCapturedCallback();
            end);
          end;
        end
        else
        begin
          FLogger.Warning(Format('DeleteDoneJob: Failed to delete task %d: %s',
            [LDoneTasks[I], LDeleteResult.GetErrorMessage]));
        end;
      end;

      FProgress := 100;
      FLogger.Info(Format('DeleteDoneJob: Completed - deleted %d of %d Done tasks',
        [LDeleted, LTotal]));
      OnJobComplete;

    finally
      LDoneTasks.Free;
    end;

  except
    on E: Exception do
    begin
      OnJobFailed('DeleteDoneJob failed: ' + E.Message);
    end;
  end;
end;

end.
