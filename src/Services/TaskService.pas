unit TaskService;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  Result;

{
  TaskService.pas
  ----------------
  Business logic for task operations. Responsibilities:
  - Enforce permissions via `IPermissionGuard` for all user-facing operations.
  - Delegate persistence to `IUserRepository`/`ITaskRepository` (here `ITaskRepository`).
  - Provide `System*` methods used by background jobs which bypass the security
    context intentionally; these are intended for trusted internal use only.

  Ownership / memory rules:
  - Methods that return `TList<TTask>` use TObjectList<TTask> with OwnsObjects=True;
    callers only need to free the list itself (items are auto-freed).
  - Methods returning a single `TTask` return an owned object the caller must free.

  Concurrency / safety:
  - This service relies on `ITaskRepository` and `IDatabaseManager` for thread
    safety. Background jobs should call `System*` methods to avoid security lookups
    and reduce locking interaction complexity.
}

type
  TTaskService = class(TInterfacedObject, ITaskService)
  private
    FTaskRepository: ITaskRepository;
    FPermissionGuard: IPermissionGuard;
    FSecurityContextProvider: ISecurityContextProvider;
    FLogger: ILogger;
  public
    constructor Create(ATaskRepository: ITaskRepository; APermissionGuard: IPermissionGuard;
      ASecurityContextProvider: ISecurityContextProvider; ALogger: ILogger);

    function GetMyTasks: TList<TTask>;
    function GetMyTasksFiltered(const AStatusFilter: string = ''): TList<TTask>;
    function GetMyTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
    function GetAllTasks: TList<TTask>;
    function GetAllTasksFiltered(const AStatusFilter: string = ''): TList<TTask>;
    function GetAllTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
    function GetTaskById(ATaskId: Integer): TTask;
    function CreateTask(const ATitle: string; const ADescription: string = ''): TResult<TTask>;
    function UpdateTask(ATask: TTask): TResult;
    function DeleteTask(ATaskId: Integer): TResult;
    function UpdateTaskStatus(ATaskId: Integer; AStatus: TTaskStatus): TResult;
    function GetMyTaskCount: Integer;
    function GetAllTaskCount: Integer;
    function CleanupCompletedTasks(ADaysOld: Integer): Integer;
    function SystemGetAllTasks: TList<TTask>;
    function SystemUpdateTask(ATask: TTask): TResult;
    function SystemCleanupCompletedTasks(ADaysOld: Integer): Integer;
    function SystemDeleteTask(ATaskId: Integer): TResult;
    function SystemBulkTouchUpdatedAt: Integer;

  private
    function GetCurrentSecurityContext: ISecurityContext;
  end;

implementation

{ TTaskService }

constructor TTaskService.Create(ATaskRepository: ITaskRepository; APermissionGuard: IPermissionGuard;
  ASecurityContextProvider: ISecurityContextProvider; ALogger: ILogger);
begin
  inherited Create;
  FTaskRepository := ATaskRepository;
  FPermissionGuard := APermissionGuard;
  FSecurityContextProvider := ASecurityContextProvider;
  FLogger := ALogger;
end;

function TTaskService.GetCurrentSecurityContext: ISecurityContext;
begin
  Result := FSecurityContextProvider.GetSecurityContext;
end;

function TTaskService.GetMyTasks: TList<TTask>;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('GetMyTasks: Not authenticated');
    Result := TObjectList<TTask>.Create(True);
    Exit;
  end;

  Result := FTaskRepository.GetTasksByUserId(LContext.UserId);
end;

function TTaskService.GetMyTasksFiltered(const AStatusFilter: string = ''): TList<TTask>;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('GetMyTasksFiltered: Not authenticated');
    Result := TObjectList<TTask>.Create(True);
    Exit;
  end;

  Result := FTaskRepository.GetTasksByUserIdWithFilter(LContext.UserId, AStatusFilter);
end;

function TTaskService.GetMyTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('GetMyTasksPaged: Not authenticated');
    Result := TObjectList<TTask>.Create(True);
    Exit;
  end;

  Result := FTaskRepository.GetTasksByUserIdPaged(LContext.UserId, APageNum, APageSize);
end;

function TTaskService.GetAllTasks: TList<TTask>;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('GetAllTasks: Not authenticated');
    Result := TObjectList<TTask>.Create(True);
    Exit;
  end;

  if LContext.Role <> urAdmin then
  begin
    FLogger.Warning(Format('GetAllTasks: Permission denied for user %d', [LContext.UserId]));
    Result := TObjectList<TTask>.Create(True);
    Exit;
  end;

  Result := FTaskRepository.GetAllTasks;
end;

function TTaskService.GetAllTasksFiltered(const AStatusFilter: string = ''): TList<TTask>;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('GetAllTasksFiltered: Not authenticated');
    Result := TObjectList<TTask>.Create(True);
    Exit;
  end;

  if LContext.Role <> urAdmin then
  begin
    FLogger.Warning(Format('GetAllTasksFiltered: Permission denied for user %d', [LContext.UserId]));
    Result := TObjectList<TTask>.Create(True);
    Exit;
  end;

  Result := FTaskRepository.GetAllTasksWithFilter(AStatusFilter);
end;

function TTaskService.GetAllTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('GetAllTasksPaged: Not authenticated');
    Result := TObjectList<TTask>.Create(True);
    Exit;
  end;

  if LContext.Role <> urAdmin then
  begin
    FLogger.Warning(Format('GetAllTasksPaged: Permission denied for user %d', [LContext.UserId]));
    Result := TObjectList<TTask>.Create(True);
    Exit;
  end;

  Result := FTaskRepository.GetAllTasksPaged(APageNum, APageSize);
end;

function TTaskService.GetTaskById(ATaskId: Integer): TTask;
var
  LTask: TTask;
  LPermResult: TResult;
begin
  Result := nil;
  LTask := FTaskRepository.GetTaskById(ATaskId);
  
  if LTask = nil then
  begin
    FLogger.Warning('GetTaskById: Task not found - ' + IntToStr(ATaskId));
    Exit;
  end;

  LPermResult := FPermissionGuard.CanViewTask(LTask);
  if not LPermResult.IsSuccess then
  begin
    FLogger.Warning(LPermResult.GetErrorMessage);
    LTask.Free;
    Exit;
  end;

  Result := LTask;
end;

function TTaskService.CreateTask(const ATitle: string; const ADescription: string = ''): TResult<TTask>;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('CreateTask: Not authenticated');
    Result := TResult<TTask>.Failure('Not authenticated');
    Exit;
  end;

  if ATitle = '' then
  begin
    FLogger.Warning('CreateTask: Empty title');
    Result := TResult<TTask>.Failure('Title cannot be empty');
    Exit;
  end;

  Result := FTaskRepository.CreateTask(LContext.UserId, ATitle, ADescription);
  
  if Result.IsSuccess then
    FLogger.Info(Format('Task created: %d by user %d', [Result.GetValue.Id, LContext.UserId]))
  else
    FLogger.Error('CreateTask failed: ' + Result.GetErrorMessage);
end;

function TTaskService.UpdateTask(ATask: TTask): TResult;
var
  LPermResult: TResult;
begin
  if ATask = nil then
  begin
    FLogger.Warning('UpdateTask: Task is nil');
    Result := TResult.Failure('Task cannot be nil');
    Exit;
  end;

  LPermResult := FPermissionGuard.CanEditTask(ATask);
  if not LPermResult.IsSuccess then
  begin
    Result := LPermResult;
    Exit;
  end;

  Result := FTaskRepository.UpdateTask(ATask);
  
  if Result.IsSuccess then
    FLogger.Info(Format('Task updated: %d', [ATask.Id]))
  else
    FLogger.Error('UpdateTask failed: ' + Result.GetErrorMessage);
end;

function TTaskService.DeleteTask(ATaskId: Integer): TResult;
var
  LTask: TTask;
  LPermResult: TResult;
begin
  LTask := FTaskRepository.GetTaskById(ATaskId);
  
  if LTask = nil then
  begin
    FLogger.Warning('DeleteTask: Task not found - ' + IntToStr(ATaskId));
    Result := TResult.Failure('Task not found');
    Exit;
  end;

  LPermResult := FPermissionGuard.CanDeleteTask(LTask);
  if not LPermResult.IsSuccess then
  begin
    LTask.Free;
    Result := LPermResult;
    Exit;
  end;

  Result := FTaskRepository.DeleteTask(ATaskId);
  
  if Result.IsSuccess then
    FLogger.Info(Format('Task deleted: %d', [ATaskId]))
  else
    FLogger.Error('DeleteTask failed: ' + Result.GetErrorMessage);

  LTask.Free;
end;

function TTaskService.UpdateTaskStatus(ATaskId: Integer; AStatus: TTaskStatus): TResult;
var
  LTask: TTask;
begin
  LTask := GetTaskById(ATaskId);
  
  if LTask = nil then
  begin
    Result := TResult.Failure('Task not found or permission denied');
    Exit;
  end;

  // Validate status transition using domain logic
  if not LTask.CanTransitionTo(AStatus) then
  begin
    FLogger.Warning(Format('Invalid status transition: Task %d from %s to %s',
      [ATaskId, StatusToString(LTask.Status), StatusToString(AStatus)]));
    Result := TResult.Failure(Format('Cannot transition from %s to %s',
      [StatusToString(LTask.Status), StatusToString(AStatus)]));
    LTask.Free;
    Exit;
  end;

  LTask.ChangeStatus(AStatus);
  
  Result := UpdateTask(LTask);
  LTask.Free;
end;

function TTaskService.GetMyTaskCount: Integer;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    Result := 0;
    Exit;
  end;

  Result := FTaskRepository.GetTaskCountByUserId(LContext.UserId);
end;

function TTaskService.GetAllTaskCount: Integer;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    Result := 0;
    Exit;
  end;

  if LContext.Role <> urAdmin then
  begin
    Result := 0;
    Exit;
  end;

  Result := FTaskRepository.GetAllTasksCount;
end;

function TTaskService.CleanupCompletedTasks(ADaysOld: Integer): Integer;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('CleanupCompletedTasks: Not authenticated');
    Result := 0;
    Exit;
  end;

  if LContext.Role <> urAdmin then
  begin
    FLogger.Warning(Format('CleanupCompletedTasks: Permission denied for user %d', [LContext.UserId]));
    Result := 0;
    Exit;
  end;

  Result := FTaskRepository.DeleteCompletedTasks(ADaysOld);
  FLogger.Info(Format('Cleaned up %d completed tasks older than %d days', [Result, ADaysOld]));
end;

function TTaskService.SystemGetAllTasks: TList<TTask>;
begin
  Result := FTaskRepository.GetAllTasks;
end;

function TTaskService.SystemUpdateTask(ATask: TTask): TResult;
begin
  Result := FTaskRepository.UpdateTask(ATask);
end;

function TTaskService.SystemCleanupCompletedTasks(ADaysOld: Integer): Integer;
begin
  Result := FTaskRepository.DeleteCompletedTasks(ADaysOld);
  FLogger.Info(Format('System cleanup: Deleted %d completed tasks older than %d days', [Result, ADaysOld]));
end;

function TTaskService.SystemDeleteTask(ATaskId: Integer): TResult;
begin
  Result := FTaskRepository.DeleteTask(ATaskId);
  if Result.IsSuccess then
    FLogger.Info(Format('System delete task: %d', [ATaskId]))
  else
    FLogger.Error('SystemDeleteTask failed: ' + Result.GetErrorMessage);
end;

function TTaskService.SystemBulkTouchUpdatedAt: Integer;
begin
  Result := FTaskRepository.BulkTouchUpdatedAt;
end;

end.
