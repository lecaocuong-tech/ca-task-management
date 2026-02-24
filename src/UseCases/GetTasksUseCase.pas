unit GetTasksUseCase;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  DTOs,
  Specifications,
  Result;

{
  GetTasksUseCase.pas
  --------------------
  Application-layer Use Case for querying tasks. Integrates with the
  Specification pattern to provide composable, reusable query predicates.

  Separates query orchestration (filtering, pagination, permission logic)
  from the service and repository layers, keeping each layer focused
  on its own responsibility.
}

type
  /// <summary>Use case: Get tasks for the current user with optional
  /// filtering and pagination. Returns paginated TTaskDTO array.</summary>
  TGetTasksUseCase = class
  private
    FTaskService: ITaskService;
    FAuthService: IAuthenticationService;
    FLogger: ILogger;
  public
    constructor Create(ATaskService: ITaskService;
      AAuthService: IAuthenticationService; ALogger: ILogger);

    /// <summary>Execute the query with the given request parameters.</summary>
    function Execute(const ARequest: TGetTasksRequest): TPagedResponse<TTaskDTO>;

    /// <summary>Execute a query using a Specification for in-memory filtering.
    /// Fetches all tasks and applies the specification predicate.</summary>
    function ExecuteWithSpec(const ASpec: ITaskSpecification): TUseCaseResponse<TArray<TTaskDTO>>;
  end;

  /// <summary>Use case: Get users for admin management with pagination.</summary>
  TGetUsersUseCase = class
  private
    FUserService: IUserService;
    FLogger: ILogger;
  public
    constructor Create(AUserService: IUserService; ALogger: ILogger);

    function Execute(APageNumber, APageSize: Integer): TPagedResponse<TUserDTO>;
  end;

implementation

{ TGetTasksUseCase }

constructor TGetTasksUseCase.Create(ATaskService: ITaskService;
  AAuthService: IAuthenticationService; ALogger: ILogger);
begin
  inherited Create;
  FTaskService := ATaskService;
  FAuthService := AAuthService;
  FLogger := ALogger;
end;

function TGetTasksUseCase.Execute(const ARequest: TGetTasksRequest): TPagedResponse<TTaskDTO>;
var
  LTasks: TList<TTask>;
  LIsAdmin: Boolean;
  LTotal: Integer;
begin
  Result.IsSuccess := False;
  Result.PageNumber := ARequest.PageNumber;
  Result.PageSize := ARequest.PageSize;

  LIsAdmin := FAuthService.IsCurrentUserAdmin;

  try
    // Get total count for pagination
    if LIsAdmin then
      LTotal := FTaskService.GetAllTaskCount
    else
      LTotal := FTaskService.GetMyTaskCount;

    Result.TotalCount := LTotal;

    // Fetch tasks based on request type
    if ARequest.UseFiltering and (ARequest.StatusFilter <> '') then
    begin
      if LIsAdmin then
        LTasks := FTaskService.GetAllTasksFiltered(ARequest.StatusFilter)
      else
        LTasks := FTaskService.GetMyTasksFiltered(ARequest.StatusFilter);
    end
    else if ARequest.UsePagination then
    begin
      if LIsAdmin then
        LTasks := FTaskService.GetAllTasksPaged(ARequest.PageNumber, ARequest.PageSize)
      else
        LTasks := FTaskService.GetMyTasksPaged(ARequest.PageNumber, ARequest.PageSize);
    end
    else
    begin
      if LIsAdmin then
        LTasks := FTaskService.GetAllTasks
      else
        LTasks := FTaskService.GetMyTasks;
    end;

    try
      Result.Items := TDTOMapper.ToTaskDTOArray(LTasks);
      Result.IsSuccess := True;
      FLogger.Info(Format('UseCase: Retrieved %d tasks (page %d)',
        [Length(Result.Items), ARequest.PageNumber]));
    finally
      LTasks.Free;
    end;
  except
    on E: Exception do
    begin
      Result.ErrorMessage := E.Message;
      FLogger.Error('UseCase: GetTasks failed - ' + E.Message);
    end;
  end;
end;

function TGetTasksUseCase.ExecuteWithSpec(
  const ASpec: ITaskSpecification): TUseCaseResponse<TArray<TTaskDTO>>;
var
  LAllTasks: TList<TTask>;
  LFiltered: TList<TTask>;
  LTask: TTask;
  LIsAdmin: Boolean;
  LDTOs: TArray<TTaskDTO>;
begin
  LIsAdmin := FAuthService.IsCurrentUserAdmin;

  try
    // Fetch base task list
    if LIsAdmin then
      LAllTasks := FTaskService.GetAllTasks
    else
      LAllTasks := FTaskService.GetMyTasks;

    // Apply specification filter in-memory
    LFiltered := TObjectList<TTask>.Create(False); // False = do not own objects
    try
      for LTask in LAllTasks do
      begin
        if ASpec.IsSatisfiedBy(LTask) then
          LFiltered.Add(LTask);
      end;

      LDTOs := TDTOMapper.ToTaskDTOArray(LFiltered);
      FLogger.Info(Format('UseCase: Specification filtered %d -> %d tasks',
        [LAllTasks.Count, LFiltered.Count]));
      Result := TUseCaseResponse<TArray<TTaskDTO>>.Success(LDTOs);
    finally
      LFiltered.Free;
    end;
  finally
    LAllTasks.Free;
  end;
end;

{ TGetUsersUseCase }

constructor TGetUsersUseCase.Create(AUserService: IUserService; ALogger: ILogger);
begin
  inherited Create;
  FUserService := AUserService;
  FLogger := ALogger;
end;

function TGetUsersUseCase.Execute(APageNumber, APageSize: Integer): TPagedResponse<TUserDTO>;
var
  LUsers: TList<TUser>;
begin
  Result.IsSuccess := False;
  Result.PageNumber := APageNumber;
  Result.PageSize := APageSize;

  try
    Result.TotalCount := FUserService.GetUserCount;

    if APageSize > 0 then
      LUsers := FUserService.GetAllUsersPaged(APageNumber, APageSize)
    else
      LUsers := FUserService.GetAllUsers;

    try
      Result.Items := TDTOMapper.ToUserDTOArray(LUsers);
      Result.IsSuccess := True;
      FLogger.Info(Format('UseCase: Retrieved %d users', [Length(Result.Items)]));
    finally
      LUsers.Free;
    end;
  except
    on E: Exception do
    begin
      Result.ErrorMessage := E.Message;
      FLogger.Error('UseCase: GetUsers failed - ' + E.Message);
    end;
  end;
end;

end.
