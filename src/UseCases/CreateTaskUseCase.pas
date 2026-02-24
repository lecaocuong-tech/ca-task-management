unit CreateTaskUseCase;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  DTOs,
  Result;

{
  CreateTaskUseCase.pas
  ----------------------
  Application-layer Use Case implementing the Create Task workflow.
  Follows Clean Architecture: Use Cases orchestrate domain logic, delegate
  to services, and dispatch domain events. They accept Request DTOs and
  return Response DTOs, forming the boundary between UI and business logic.

  Responsibilities:
  - Validate request input
  - Delegate creation to ITaskService
  - Dispatch collected domain events after successful persistence
  - Map domain entities to DTOs for the presentation layer
}

type
  /// <summary>Use case: Create a new task for the authenticated user.
  /// Accepts TCreateTaskRequest, returns TUseCaseResponse with TTaskDTO.</summary>
  TCreateTaskUseCase = class
  private
    FTaskService: ITaskService;
    FEventDispatcher: IDomainEventDispatcher;
    FSanitizer: IInputSanitizer;
    FRateLimiter: IRateLimiter;
    FLogger: ILogger;
  public
    constructor Create(ATaskService: ITaskService;
      AEventDispatcher: IDomainEventDispatcher; ASanitizer: IInputSanitizer;
      ARateLimiter: IRateLimiter; ALogger: ILogger);

    function Execute(const ARequest: TCreateTaskRequest): TUseCaseResponse<TTaskDTO>;
  end;

  /// <summary>Use case: Change a task's status (Pending -> InProgress -> Done).
  /// Validates transitions through domain logic and dispatches status change events.</summary>
  TChangeTaskStatusUseCase = class
  private
    FTaskService: ITaskService;
    FEventDispatcher: IDomainEventDispatcher;
    FLogger: ILogger;
  public
    constructor Create(ATaskService: ITaskService;
      AEventDispatcher: IDomainEventDispatcher; ALogger: ILogger);

    function Execute(const ARequest: TChangeTaskStatusRequest): TUseCaseResponse<TTaskDTO>;
  end;

  /// <summary>Use case: Update task content (title and description).
  /// Dispatches content update events after successful persistence.</summary>
  TUpdateTaskUseCase = class
  private
    FTaskService: ITaskService;
    FEventDispatcher: IDomainEventDispatcher;
    FSanitizer: IInputSanitizer;
    FLogger: ILogger;
  public
    constructor Create(ATaskService: ITaskService;
      AEventDispatcher: IDomainEventDispatcher; ASanitizer: IInputSanitizer;
      ALogger: ILogger);

    function Execute(const ARequest: TUpdateTaskRequest): TUseCaseResponse<TTaskDTO>;
  end;

  /// <summary>Use case: Delete a task by ID.
  /// Dispatches deletion events after successful removal.</summary>
  TDeleteTaskUseCase = class
  private
    FTaskService: ITaskService;
    FEventDispatcher: IDomainEventDispatcher;
    FLogger: ILogger;
  public
    constructor Create(ATaskService: ITaskService;
      AEventDispatcher: IDomainEventDispatcher; ALogger: ILogger);

    function Execute(ATaskId: Integer): TUseCaseResponse<Boolean>;
  end;

implementation

uses
  DomainEvents;

{ TCreateTaskUseCase }

constructor TCreateTaskUseCase.Create(ATaskService: ITaskService;
  AEventDispatcher: IDomainEventDispatcher; ASanitizer: IInputSanitizer;
  ARateLimiter: IRateLimiter; ALogger: ILogger);
begin
  inherited Create;
  FTaskService := ATaskService;
  FEventDispatcher := AEventDispatcher;
  FSanitizer := ASanitizer;
  FRateLimiter := ARateLimiter;
  FLogger := ALogger;
end;

function TCreateTaskUseCase.Execute(const ARequest: TCreateTaskRequest): TUseCaseResponse<TTaskDTO>;
var
  LResult: TResult<TTask>;
  LTask: TTask;
  LTaskDTO: TTaskDTO;
  LSanitizedTitle: string;
  LSanitizedDesc: string;
  LValidation: TResult;
begin
  // Rate limiting: prevent rapid-fire task creation
  if not FRateLimiter.TryConsume('create_task') then
  begin
    FLogger.Warning('UseCase: Rate limit exceeded for task creation');
    Result := TUseCaseResponse<TTaskDTO>.Failure('Too many requests. Please try again later.');
    Exit;
  end;

  // Sanitize input at the boundary
  LSanitizedTitle := FSanitizer.SanitizeString(ARequest.Title);
  LSanitizedDesc := FSanitizer.SanitizeString(ARequest.Description);

  // Validate sanitized input
  LValidation := FSanitizer.ValidateTaskTitle(LSanitizedTitle);
  if not LValidation.IsSuccess then
  begin
    Result := TUseCaseResponse<TTaskDTO>.Failure(LValidation.GetErrorMessage);
    Exit;
  end;

  LValidation := FSanitizer.ValidateTaskDescription(LSanitizedDesc);
  if not LValidation.IsSuccess then
  begin
    Result := TUseCaseResponse<TTaskDTO>.Failure(LValidation.GetErrorMessage);
    Exit;
  end;

  // Delegate to service layer
  LResult := FTaskService.CreateTask(LSanitizedTitle, LSanitizedDesc);

  if not LResult.IsSuccess then
  begin
    Result := TUseCaseResponse<TTaskDTO>.Failure(LResult.GetErrorMessage);
    Exit;
  end;

  LTask := LResult.GetValue;
  try
    // Dispatch any domain events raised during creation
    if LTask.HasDomainEvents then
    begin
      FEventDispatcher.DispatchAll(LTask.GetDomainEvents);
      LTask.ClearDomainEvents;
    end;

    // Map to DTO for the presentation layer
    LTaskDTO := TDTOMapper.ToTaskDTO(LTask);
    FLogger.Info(Format('UseCase: Task created - ID: %d, Title: %s', [LTaskDTO.Id, LTaskDTO.Title]));
    Result := TUseCaseResponse<TTaskDTO>.Success(LTaskDTO);
  finally
    LTask.Free;
  end;
end;

{ TChangeTaskStatusUseCase }

constructor TChangeTaskStatusUseCase.Create(ATaskService: ITaskService;
  AEventDispatcher: IDomainEventDispatcher; ALogger: ILogger);
begin
  inherited Create;
  FTaskService := ATaskService;
  FEventDispatcher := AEventDispatcher;
  FLogger := ALogger;
end;

function TChangeTaskStatusUseCase.Execute(const ARequest: TChangeTaskStatusRequest): TUseCaseResponse<TTaskDTO>;
var
  LResult: TResult;
  LTask: TTask;
  LTaskDTO: TTaskDTO;
begin
  // Delegate status change to service (validates transition + permissions)
  LResult := FTaskService.UpdateTaskStatus(ARequest.TaskId, ARequest.NewStatus);

  if not LResult.IsSuccess then
  begin
    Result := TUseCaseResponse<TTaskDTO>.Failure(LResult.GetErrorMessage);
    Exit;
  end;

  // Fetch updated task for DTO mapping
  LTask := FTaskService.GetTaskById(ARequest.TaskId);
  if LTask = nil then
  begin
    Result := TUseCaseResponse<TTaskDTO>.Failure('Task not found after status update');
    Exit;
  end;

  try
    // Dispatch domain events
    if LTask.HasDomainEvents then
    begin
      FEventDispatcher.DispatchAll(LTask.GetDomainEvents);
      LTask.ClearDomainEvents;
    end;

    LTaskDTO := TDTOMapper.ToTaskDTO(LTask);
    FLogger.Info(Format('UseCase: Task %d status changed to %s', [LTaskDTO.Id, LTaskDTO.Status]));
    Result := TUseCaseResponse<TTaskDTO>.Success(LTaskDTO);
  finally
    LTask.Free;
  end;
end;

{ TUpdateTaskUseCase }

constructor TUpdateTaskUseCase.Create(ATaskService: ITaskService;
  AEventDispatcher: IDomainEventDispatcher; ASanitizer: IInputSanitizer;
  ALogger: ILogger);
begin
  inherited Create;
  FTaskService := ATaskService;
  FEventDispatcher := AEventDispatcher;
  FSanitizer := ASanitizer;
  FLogger := ALogger;
end;

function TUpdateTaskUseCase.Execute(const ARequest: TUpdateTaskRequest): TUseCaseResponse<TTaskDTO>;
var
  LTask: TTask;
  LResult: TResult;
  LTaskDTO: TTaskDTO;
  LSanitizedTitle: string;
  LSanitizedDesc: string;
  LValidation: TResult;
begin
  // Sanitize input at the boundary
  LSanitizedTitle := FSanitizer.SanitizeString(ARequest.Title);
  LSanitizedDesc := FSanitizer.SanitizeString(ARequest.Description);

  // Validate sanitized input
  LValidation := FSanitizer.ValidateTaskTitle(LSanitizedTitle);
  if not LValidation.IsSuccess then
  begin
    Result := TUseCaseResponse<TTaskDTO>.Failure(LValidation.GetErrorMessage);
    Exit;
  end;

  LValidation := FSanitizer.ValidateTaskDescription(LSanitizedDesc);
  if not LValidation.IsSuccess then
  begin
    Result := TUseCaseResponse<TTaskDTO>.Failure(LValidation.GetErrorMessage);
    Exit;
  end;

  // Fetch task (service enforces permission check)
  LTask := FTaskService.GetTaskById(ARequest.TaskId);
  if LTask = nil then
  begin
    Result := TUseCaseResponse<TTaskDTO>.Failure('Task not found or permission denied');
    Exit;
  end;

  try
    // Apply content update via domain method (validates invariants)
    try
      LTask.UpdateContent(LSanitizedTitle, LSanitizedDesc);
    except
      on E: Exception do
      begin
        Result := TUseCaseResponse<TTaskDTO>.Failure(E.Message);
        Exit;
      end;
    end;

    // Persist via service
    LResult := FTaskService.UpdateTask(LTask);
    if not LResult.IsSuccess then
    begin
      Result := TUseCaseResponse<TTaskDTO>.Failure(LResult.GetErrorMessage);
      Exit;
    end;

    // Dispatch domain events
    if LTask.HasDomainEvents then
    begin
      FEventDispatcher.DispatchAll(LTask.GetDomainEvents);
      LTask.ClearDomainEvents;
    end;

    LTaskDTO := TDTOMapper.ToTaskDTO(LTask);
    FLogger.Info(Format('UseCase: Task %d content updated', [LTaskDTO.Id]));
    Result := TUseCaseResponse<TTaskDTO>.Success(LTaskDTO);
  finally
    LTask.Free;
  end;
end;

{ TDeleteTaskUseCase }

constructor TDeleteTaskUseCase.Create(ATaskService: ITaskService;
  AEventDispatcher: IDomainEventDispatcher; ALogger: ILogger);
begin
  inherited Create;
  FTaskService := ATaskService;
  FEventDispatcher := AEventDispatcher;
  FLogger := ALogger;
end;

function TDeleteTaskUseCase.Execute(ATaskId: Integer): TUseCaseResponse<Boolean>;
var
  LResult: TResult;
begin
  LResult := FTaskService.DeleteTask(ATaskId);

  if not LResult.IsSuccess then
  begin
    Result := TUseCaseResponse<Boolean>.Failure(LResult.GetErrorMessage);
    Exit;
  end;

  // Dispatch deletion event
  FEventDispatcher.Dispatch(TTaskDeletedEvent.Create(ATaskId));

  FLogger.Info(Format('UseCase: Task %d deleted', [ATaskId]));
  Result := TUseCaseResponse<Boolean>.Success(True);
end;

end.
