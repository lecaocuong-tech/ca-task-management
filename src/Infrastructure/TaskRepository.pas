unit TaskRepository;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Comp.Client,
  AppInterfaces,
  InfraInterfaces,
  DomainModels,
  Result;

{
  TaskRepository.pas
  ------------------
  Concrete repository responsible for Task persistence.
  ITaskRepository interface is declared in AppInterfaces.pas (Dependency Inversion).
  All SQL is parameterized and the repository uses IDatabaseManager for connection
  and lock management.

  Important rules:
  - Methods that return TList<TTask> use TObjectList<TTask> with OwnsObjects=True;
    callers only need to free the list itself (items are auto-freed).
  - Read methods use AcquireLock/ReleaseLock; write methods use transactions.
  - BulkTouchUpdatedAt uses a single SQL UPDATE for O(1) performance.
}

type
  TTaskRepository = class(TInterfacedObject, ITaskRepository)
  private
    FDatabaseManager: IDatabaseManager;
    FLogger: ILogger;
  public
    constructor Create(ADatabaseManager: IDatabaseManager; ALogger: ILogger);

    function GetTaskById(ATaskId: Integer): TTask;
    function GetTasksByUserId(AUserId: Integer): TList<TTask>;
    function GetTasksByUserIdWithFilter(AUserId: Integer; const AStatusFilter: string = ''): TList<TTask>;
    function GetTasksByUserIdPaged(AUserId: Integer; APageNum, APageSize: Integer): TList<TTask>;
    function GetAllTasks: TList<TTask>;
    function GetAllTasksWithFilter(const AStatusFilter: string = ''): TList<TTask>;
    function GetAllTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
    function GetTaskCountByUserId(AUserId: Integer): Integer;
    function GetAllTasksCount: Integer;
    function CreateTask(AUserId: Integer; const ATitle, ADescription: string): TResult<TTask>;
    function UpdateTask(ATask: TTask): TResult;
    function DeleteTask(ATaskId: Integer): TResult;
    function DeleteCompletedTasks(ADaysOld: Integer): Integer;
    function BulkTouchUpdatedAt: Integer;

  private
    // Helper: map a current dataset row into a newly created TTask instance.
    function DataSetToTask(ADataSet: TDataSet): TTask;
  end;

implementation

{ TTaskRepository }

constructor TTaskRepository.Create(ADatabaseManager: IDatabaseManager; ALogger: ILogger);
begin
  inherited Create;
  FDatabaseManager := ADatabaseManager;
  FLogger := ALogger;
end;

function TTaskRepository.DataSetToTask(ADataSet: TDataSet): TTask;
var
  LDescription: string;
  LUpdatedAt: TDateTime;
begin
  // Each call returns a newly allocated TTask; caller must free it.
  if ADataSet.FindField('Description') <> nil then
    LDescription := ADataSet.FieldByName('Description').AsString
  else
    LDescription := '';

  if not ADataSet.FieldByName('UpdatedAt').IsNull then
    LUpdatedAt := ADataSet.FieldByName('UpdatedAt').AsDateTime
  else
    LUpdatedAt := 0;

  Result := TTask.Hydrate(
    ADataSet.FieldByName('Id').AsInteger,
    ADataSet.FieldByName('UserId').AsInteger,
    ADataSet.FieldByName('Title').AsString,
    LDescription,
    StringToStatus(ADataSet.FieldByName('Status').AsString),
    ADataSet.FieldByName('CreatedAt').AsDateTime,
    LUpdatedAt
  );
end;

function TTaskRepository.GetTaskById(ATaskId: Integer): TTask;
var
  LQuery: TFDQuery;
begin
  Result := nil;
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT * FROM Tasks WHERE Id = :Id';
        LQuery.ParamByName('Id').AsInteger := ATaskId;
        LQuery.Open;
        if not LQuery.IsEmpty then
        begin
          LQuery.First;
          Result := DataSetToTask(LQuery);
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetTaskById failed', E);
        Result := nil;
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TTaskRepository.GetTasksByUserId(AUserId: Integer): TList<TTask>;
var
  LQuery: TFDQuery;
begin
  Result := TObjectList<TTask>.Create(True);
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT * FROM Tasks WHERE UserId = :UserId ORDER BY CreatedAt DESC';
        LQuery.ParamByName('UserId').AsInteger := AUserId;
        LQuery.Open;
        while not LQuery.Eof do
        begin
          Result.Add(DataSetToTask(LQuery));
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetTasksByUserId failed', E);
        Result.Free;
        Result := TObjectList<TTask>.Create(True);
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TTaskRepository.GetTasksByUserIdWithFilter(AUserId: Integer; const AStatusFilter: string = ''): TList<TTask>;
var
  LQuery: TFDQuery;
begin
  Result := TObjectList<TTask>.Create(True);
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        if AStatusFilter <> '' then
        begin
          LQuery.SQL.Text := 'SELECT * FROM Tasks WHERE UserId = :UserId AND Status = :Status ORDER BY CreatedAt DESC';
          LQuery.ParamByName('UserId').AsInteger := AUserId;
          LQuery.ParamByName('Status').AsString := AStatusFilter;
        end
        else
        begin
          LQuery.SQL.Text := 'SELECT * FROM Tasks WHERE UserId = :UserId ORDER BY CreatedAt DESC';
          LQuery.ParamByName('UserId').AsInteger := AUserId;
        end;

        LQuery.Open;
        while not LQuery.Eof do
        begin
          Result.Add(DataSetToTask(LQuery));
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetTasksByUserIdWithFilter failed', E);
        Result.Free;
        Result := TObjectList<TTask>.Create(True);
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TTaskRepository.GetTasksByUserIdPaged(AUserId: Integer; APageNum, APageSize: Integer): TList<TTask>;
var
  LQuery: TFDQuery;
  LOffset: Integer;
begin
  Result := TObjectList<TTask>.Create(True);
  FDatabaseManager.AcquireLock;
  try
    try
      LOffset := (APageNum - 1) * APageSize;
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT * FROM Tasks WHERE UserId = :UserId ORDER BY CreatedAt DESC LIMIT :Limit OFFSET :Offset';
        LQuery.ParamByName('UserId').AsInteger := AUserId;
        LQuery.ParamByName('Limit').AsInteger := APageSize;
        LQuery.ParamByName('Offset').AsInteger := LOffset;
        LQuery.Open;
        while not LQuery.Eof do
        begin
          Result.Add(DataSetToTask(LQuery));
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetTasksByUserIdPaged failed', E);
        Result.Free;
        Result := TObjectList<TTask>.Create(True);
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TTaskRepository.GetAllTasks: TList<TTask>;
var
  LQuery: TFDQuery;
begin
  Result := TObjectList<TTask>.Create(True);
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT * FROM Tasks ORDER BY CreatedAt DESC';
        LQuery.Open;
        while not LQuery.Eof do
        begin
          Result.Add(DataSetToTask(LQuery));
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetAllTasks failed', E);
        Result.Free;
        Result := TObjectList<TTask>.Create(True);
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TTaskRepository.GetAllTasksWithFilter(const AStatusFilter: string = ''): TList<TTask>;
var
  LQuery: TFDQuery;
begin
  Result := TObjectList<TTask>.Create(True);
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        if AStatusFilter <> '' then
        begin
          LQuery.SQL.Text := 'SELECT * FROM Tasks WHERE Status = :Status ORDER BY CreatedAt DESC';
          LQuery.ParamByName('Status').AsString := AStatusFilter;
        end
        else
          LQuery.SQL.Text := 'SELECT * FROM Tasks ORDER BY CreatedAt DESC';

        LQuery.Open;
        while not LQuery.Eof do
        begin
          Result.Add(DataSetToTask(LQuery));
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetAllTasksWithFilter failed', E);
        Result.Free;
        Result := TObjectList<TTask>.Create(True);
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TTaskRepository.GetAllTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
var
  LQuery: TFDQuery;
  LOffset: Integer;
begin
  Result := TObjectList<TTask>.Create(True);
  FDatabaseManager.AcquireLock;
  try
    try
      LOffset := (APageNum - 1) * APageSize;
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT * FROM Tasks ORDER BY CreatedAt DESC LIMIT :Limit OFFSET :Offset';
        LQuery.ParamByName('Limit').AsInteger := APageSize;
        LQuery.ParamByName('Offset').AsInteger := LOffset;
        LQuery.Open;
        while not LQuery.Eof do
        begin
          Result.Add(DataSetToTask(LQuery));
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetAllTasksPaged failed', E);
        Result.Free;
        Result := TObjectList<TTask>.Create(True);
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TTaskRepository.GetTaskCountByUserId(AUserId: Integer): Integer;
var
  LQuery: TFDQuery;
begin
  Result := 0;
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT COUNT(*) as TaskCount FROM Tasks WHERE UserId = :UserId';
        LQuery.ParamByName('UserId').AsInteger := AUserId;
        LQuery.Open;
        if not LQuery.IsEmpty then
          Result := LQuery.FieldByName('TaskCount').AsInteger;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetTaskCountByUserId failed', E);
        Result := 0;
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TTaskRepository.GetAllTasksCount: Integer;
var
  LQuery: TFDQuery;
begin
  Result := 0;
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT COUNT(*) as TaskCount FROM Tasks';
        LQuery.Open;
        if not LQuery.IsEmpty then
          Result := LQuery.FieldByName('TaskCount').AsInteger;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetAllTasksCount failed', E);
        Result := 0;
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TTaskRepository.CreateTask(AUserId: Integer; const ATitle, ADescription: string): TResult<TTask>;
var
  LQuery: TFDQuery;
  LTask: TTask;
  LTaskId: Integer;
begin
  LTaskId := 0;
  FDatabaseManager.BeginTransaction;
  try
    LQuery := FDatabaseManager.CreateQuery;
    try
      LQuery.SQL.Text := 'INSERT INTO Tasks (UserId, Title, Description, Status, CreatedAt) ' +
        'VALUES (:UserId, :Title, :Description, :Status, CURRENT_TIMESTAMP)';
      LQuery.ParamByName('UserId').AsInteger := AUserId;
      LQuery.ParamByName('Title').AsString := ATitle;
      LQuery.ParamByName('Description').AsString := ADescription;
      LQuery.ParamByName('Status').AsString := 'Pending';
      LQuery.ExecSQL;

      // Get last inserted ID on same connection
      LQuery.SQL.Text := 'SELECT last_insert_rowid() as LastId';
      LQuery.Open;
      if not LQuery.IsEmpty and not LQuery.FieldByName('LastId').IsNull then
        LTaskId := LQuery.FieldByName('LastId').AsInteger;
      LQuery.Close;
    finally
      LQuery.Free;
    end;

    FDatabaseManager.Commit;
  except
    on E: Exception do
    begin
      FDatabaseManager.Rollback;
      FLogger.Error('CreateTask failed', E);
      Result := TResult<TTask>.Failure('Error creating task: ' + E.Message);
      Exit;
    end;
  end;

  // Post-commit: fetch created task (outside transaction)
  if LTaskId > 0 then
  begin
    LTask := GetTaskById(LTaskId);
    if Assigned(LTask) then
      Result := TResult<TTask>.Success(LTask)
    else
      Result := TResult<TTask>.Failure('Cannot retrieve created task');
  end
  else
    Result := TResult<TTask>.Failure('Cannot retrieve created task');
end;

function TTaskRepository.UpdateTask(ATask: TTask): TResult;
var
  LQuery: TFDQuery;
begin
  FDatabaseManager.BeginTransaction;
  try
    LQuery := FDatabaseManager.CreateQuery;
    try
      LQuery.SQL.Text := 'UPDATE Tasks SET Title = :Title, Description = :Description, ' +
        'Status = :Status, UpdatedAt = CURRENT_TIMESTAMP WHERE Id = :Id';
      LQuery.ParamByName('Title').AsString := ATask.Title;
      LQuery.ParamByName('Description').AsString := ATask.Description;
      LQuery.ParamByName('Status').AsString := StatusToString(ATask.Status);
      LQuery.ParamByName('Id').AsInteger := ATask.Id;
      LQuery.ExecSQL;
    finally
      LQuery.Free;
    end;

    FDatabaseManager.Commit;
    Result := TResult.Success;
  except
    on E: Exception do
    begin
      FDatabaseManager.Rollback;
      FLogger.Error('UpdateTask failed', E);
      Result := TResult.Failure('Error updating task: ' + E.Message);
    end;
  end;
end;

function TTaskRepository.DeleteTask(ATaskId: Integer): TResult;
var
  LQuery: TFDQuery;
begin
  FDatabaseManager.BeginTransaction;
  try
    LQuery := FDatabaseManager.CreateQuery;
    try
      LQuery.SQL.Text := 'DELETE FROM Tasks WHERE Id = :Id';
      LQuery.ParamByName('Id').AsInteger := ATaskId;
      LQuery.ExecSQL;
    finally
      LQuery.Free;
    end;

    FDatabaseManager.Commit;
    Result := TResult.Success;
  except
    on E: Exception do
    begin
      FDatabaseManager.Rollback;
      FLogger.Error('DeleteTask failed', E);
      Result := TResult.Failure('Error deleting task: ' + E.Message);
    end;
  end;
end;

function TTaskRepository.DeleteCompletedTasks(ADaysOld: Integer): Integer;
var
  LQuery: TFDQuery;
begin
  Result := 0;
  FDatabaseManager.BeginTransaction;
  try
    LQuery := FDatabaseManager.CreateQuery;
    try
      LQuery.SQL.Text := 'DELETE FROM Tasks WHERE Status = :Status AND UpdatedAt < datetime(''now'', :DaysOffset)';
      LQuery.ParamByName('Status').AsString := 'Done';
      LQuery.ParamByName('DaysOffset').AsString := Format('-%d days', [ADaysOld]);
      LQuery.ExecSQL;
      Result := LQuery.RowsAffected;
    finally
      LQuery.Free;
    end;

    FDatabaseManager.Commit;
  except
    on E: Exception do
    begin
      FDatabaseManager.Rollback;
      FLogger.Error('DeleteCompletedTasks failed', E);
      Result := 0;
    end;
  end;
end;

function TTaskRepository.BulkTouchUpdatedAt: Integer;
var
  LQuery: TFDQuery;
begin
  // Single SQL UPDATE instead of loading all tasks and updating individually.
  // Only touches non-completed tasks (active tasks) for efficiency.
  Result := 0;
  FDatabaseManager.BeginTransaction;
  try
    LQuery := FDatabaseManager.CreateQuery;
    try
      LQuery.SQL.Text := 'UPDATE Tasks SET UpdatedAt = CURRENT_TIMESTAMP WHERE Status <> :DoneStatus';
      LQuery.ParamByName('DoneStatus').AsString := 'Done';
      LQuery.ExecSQL;
      Result := LQuery.RowsAffected;
    finally
      LQuery.Free;
    end;

    FDatabaseManager.Commit;
    FLogger.Info(Format('BulkTouchUpdatedAt: %d tasks touched', [Result]));
  except
    on E: Exception do
    begin
      FDatabaseManager.Rollback;
      FLogger.Error('BulkTouchUpdatedAt failed', E);
      Result := 0;
    end;
  end;
end;

end.
