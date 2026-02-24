unit TaskController;

interface

(*
  TaskController.pas
  -------------------
  REST API controller for task CRUD operations. All endpoints require
  authentication (Bearer token) enforced by the auth middleware.

  Endpoints:
  ==========
  GET    /api/tasks            - List tasks (own tasks, or all for Admin)
  GET    /api/tasks/:id        - Get a single task by ID
  POST   /api/tasks            - Create a new task
  PUT    /api/tasks/:id        - Update task title/description
  DELETE /api/tasks/:id        - Delete a task
  PATCH  /api/tasks/:id/status - Change task status

  Query Parameters (GET /api/tasks):
  ===================================
  ?status=Pending|InProgress|Done  - Filter by status
  ?page=1&pageSize=10             - Pagination
  ?all=true                       - Admin: get all tasks (not just own)

  Authorization:
  ==============
  - Regular users can only access their own tasks
  - Admin users can access all tasks with ?all=true
  - Permission checks are delegated to existing ITaskService

  Request/Response Examples:
  ==========================

  POST /api/tasks
  Request:  { "title": "Buy milk", "description": "2% fat" }
  Response: { "success": true, "data": { "id": 5, "title": "Buy milk", ... } }

  PATCH /api/tasks/5/status
  Request:  { "status": "InProgress" }
  Response: { "success": true, "data": { "message": "Status updated" } }
*)

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  ApiInterfaces,
  AppInterfaces,
  DomainModels,
  JsonHelper,
  Result;

type
  TTaskController = class
  private
    FTaskService: ITaskService;
    FTokenManager: ITokenManager;
    FLogger: ILogger;
    function SetupSecurityContext(const ARequest: IApiRequest;
      const AResponse: IApiResponse): Boolean;
    function GetPathId(const ARequest: IApiRequest): Integer;
  public
    constructor Create(ATaskService: ITaskService;
      ATokenManager: ITokenManager; ALogger: ILogger);
    procedure HandleGetTasks(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleGetTaskById(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleCreateTask(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleUpdateTask(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleDeleteTask(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleChangeStatus(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure RegisterRoutes(const ARouter: IApiRouter);
  end;

implementation

constructor TTaskController.Create(ATaskService: ITaskService;
  ATokenManager: ITokenManager; ALogger: ILogger);
begin
  inherited Create;
  FTaskService := ATaskService;
  FTokenManager := ATokenManager;
  FLogger := ALogger;
end;

function TTaskController.SetupSecurityContext(const ARequest: IApiRequest;
  const AResponse: IApiResponse): Boolean;
var
  LUserId: string;
begin
  LUserId := ARequest.GetContextValue('auth:userId');
  Result := LUserId <> '';
  if not Result then
  begin
    AResponse.SetJSON(401, TJsonHelper.ErrorResponse(401, 'Authentication required'));
  end;
end;

function TTaskController.GetPathId(const ARequest: IApiRequest): Integer;
begin
  Result := StrToIntDef(ARequest.GetContextValue('path:id'), 0);
end;

procedure TTaskController.RegisterRoutes(const ARouter: IApiRouter);
begin
  ARouter.AddRoute(hmGET, '/api/tasks', HandleGetTasks);
  ARouter.AddRoute(hmGET, '/api/tasks/:id', HandleGetTaskById);
  ARouter.AddRoute(hmPOST, '/api/tasks', HandleCreateTask);
  ARouter.AddRoute(hmPUT, '/api/tasks/:id', HandleUpdateTask);
  ARouter.AddRoute(hmDELETE, '/api/tasks/:id', HandleDeleteTask);
  ARouter.AddRoute(hmPATCH, '/api/tasks/:id/status', HandleChangeStatus);
end;

procedure TTaskController.HandleGetTasks(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LTasks: TList<TTask>;
  LStatusFilter: string;
  LPage, LPageSize: Integer;
  LAll: Boolean;
  LJsonArray: TJSONArray;
  LResponseJson: TJSONObject;
  LRole: string;
begin
  FLogger.Info('API: GET /api/tasks');

  if not SetupSecurityContext(ARequest, AResponse) then Exit;

  LStatusFilter := ARequest.GetQueryParam('status');
  LPage := StrToIntDef(ARequest.GetQueryParam('page'), 0);
  LPageSize := StrToIntDef(ARequest.GetQueryParam('pageSize'), 20);
  LAll := SameText(ARequest.GetQueryParam('all'), 'true');
  LRole := ARequest.GetContextValue('auth:role');

  try
    if LAll and SameText(LRole, 'Admin') then
    begin
      if LStatusFilter <> '' then
        LTasks := FTaskService.GetAllTasksFiltered(LStatusFilter)
      else if LPage > 0 then
        LTasks := FTaskService.GetAllTasksPaged(LPage, LPageSize)
      else
        LTasks := FTaskService.GetAllTasks;
    end
    else
    begin
      if LStatusFilter <> '' then
        LTasks := FTaskService.GetMyTasksFiltered(LStatusFilter)
      else if LPage > 0 then
        LTasks := FTaskService.GetMyTasksPaged(LPage, LPageSize)
      else
        LTasks := FTaskService.GetMyTasks;
    end;

    try
      LJsonArray := TJsonHelper.TaskListToJSON(LTasks);

      if LPage > 0 then
      begin
        var LTotalCount: Integer;
        if LAll and SameText(LRole, 'Admin') then
          LTotalCount := FTaskService.GetAllTaskCount
        else
          LTotalCount := FTaskService.GetMyTaskCount;
        LResponseJson := TJsonHelper.PaginatedResponse(LJsonArray, LTotalCount,
          LPage, LPageSize);
      end
      else
      begin
        LResponseJson := TJsonHelper.SuccessResponse(LJsonArray);
      end;

      AResponse.SetJSON(200, LResponseJson);
    finally
      FreeAndNil(LTasks);
    end;
  except
    on E: Exception do
    begin
      FLogger.Error('API: GET /api/tasks failed', E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

procedure TTaskController.HandleGetTaskById(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LTaskId: Integer;
  LTask: TTask;
  LResponseJson: TJSONObject;
begin
  FLogger.Info('API: GET /api/tasks/:id');

  if not SetupSecurityContext(ARequest, AResponse) then Exit;

  LTaskId := GetPathId(ARequest);
  if LTaskId <= 0 then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid task ID');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    LTask := FTaskService.GetTaskById(LTaskId);
    if LTask = nil then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(404,
        Format('Task with ID %d not found', [LTaskId]));
      AResponse.SetJSON(404, LResponseJson);
      Exit;
    end;

    try
      LResponseJson := TJsonHelper.SuccessResponse(TJsonHelper.TaskToJSON(LTask));
      AResponse.SetJSON(200, LResponseJson);
    finally
      LTask.Free;
    end;
  except
    on E: Exception do
    begin
      FLogger.Error(Format('API: GET /api/tasks/%d failed', [LTaskId]), E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

procedure TTaskController.HandleCreateTask(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LJson: TJSONObject;
  LTitle, LDescription: string;
  LCreateResult: TResult<TTask>;
  LResponseJson: TJSONObject;
begin
  FLogger.Info('API: POST /api/tasks');

  if not SetupSecurityContext(ARequest, AResponse) then Exit;

  LJson := ARequest.GetBodyAsJSON;
  if LJson = nil then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid JSON body');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    if not TJsonHelper.ParseCreateTaskRequest(LJson, LTitle, LDescription) then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400,
        'Missing required field "title"');
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;
  finally
    LJson.Free;
  end;

  try
    LCreateResult := FTaskService.CreateTask(LTitle, LDescription);

    if not LCreateResult.IsSuccess then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400, LCreateResult.GetErrorMessage);
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;

    try
      LResponseJson := TJsonHelper.SuccessResponse(
        TJsonHelper.TaskToJSON(LCreateResult.GetValue));
      AResponse.SetJSON(201, LResponseJson);
    finally
      LCreateResult.GetValue.Free;
    end;
  except
    on E: Exception do
    begin
      FLogger.Error('API: POST /api/tasks failed', E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

procedure TTaskController.HandleUpdateTask(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LTaskId: Integer;
  LJson: TJSONObject;
  LTitle, LDescription: string;
  LTask: TTask;
  LUpdateResult: TResult;
  LResponseJson: TJSONObject;
begin
  FLogger.Info('API: PUT /api/tasks/:id');

  if not SetupSecurityContext(ARequest, AResponse) then Exit;

  LTaskId := GetPathId(ARequest);
  if LTaskId <= 0 then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid task ID');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  LJson := ARequest.GetBodyAsJSON;
  if LJson = nil then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid JSON body');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    if not TJsonHelper.ParseUpdateTaskRequest(LJson, LTitle, LDescription) then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400,
        'Missing required field "title"');
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;
  finally
    LJson.Free;
  end;

  try
    LTask := FTaskService.GetTaskById(LTaskId);
    if LTask = nil then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(404,
        Format('Task with ID %d not found', [LTaskId]));
      AResponse.SetJSON(404, LResponseJson);
      Exit;
    end;

    try
      LTask.UpdateContent(LTitle, LDescription);
      LUpdateResult := FTaskService.UpdateTask(LTask);

      if not LUpdateResult.IsSuccess then
      begin
        LResponseJson := TJsonHelper.ErrorResponse(400, LUpdateResult.GetErrorMessage);
        AResponse.SetJSON(400, LResponseJson);
        Exit;
      end;

      LResponseJson := TJsonHelper.SuccessResponse(TJsonHelper.TaskToJSON(LTask));
      AResponse.SetJSON(200, LResponseJson);
    finally
      LTask.Free;
    end;
  except
    on E: Exception do
    begin
      FLogger.Error(Format('API: PUT /api/tasks/%d failed', [LTaskId]), E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

procedure TTaskController.HandleDeleteTask(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LTaskId: Integer;
  LDeleteResult: TResult;
  LResponseJson: TJSONObject;
  LData: TJSONObject;
begin
  FLogger.Info('API: DELETE /api/tasks/:id');

  if not SetupSecurityContext(ARequest, AResponse) then Exit;

  LTaskId := GetPathId(ARequest);
  if LTaskId <= 0 then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid task ID');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    LDeleteResult := FTaskService.DeleteTask(LTaskId);

    if not LDeleteResult.IsSuccess then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400, LDeleteResult.GetErrorMessage);
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;

    LData := TJSONObject.Create;
    LData.AddPair('message', Format('Task %d deleted successfully', [LTaskId]));
    LResponseJson := TJsonHelper.SuccessResponse(LData);
    AResponse.SetJSON(200, LResponseJson);
  except
    on E: Exception do
    begin
      FLogger.Error(Format('API: DELETE /api/tasks/%d failed', [LTaskId]), E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

procedure TTaskController.HandleChangeStatus(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LTaskId: Integer;
  LJson: TJSONObject;
  LNewStatus: TTaskStatus;
  LStatusResult: TResult;
  LResponseJson: TJSONObject;
  LData: TJSONObject;
begin
  FLogger.Info('API: PATCH /api/tasks/:id/status');

  if not SetupSecurityContext(ARequest, AResponse) then Exit;

  LTaskId := GetPathId(ARequest);
  if LTaskId <= 0 then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid task ID');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  LJson := ARequest.GetBodyAsJSON;
  if LJson = nil then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid JSON body');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    if not TJsonHelper.ParseChangeStatusRequest(LJson, LNewStatus) then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400,
        'Invalid or missing "status" field. Use: Pending, InProgress, or Done');
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;
  finally
    LJson.Free;
  end;

  try
    LStatusResult := FTaskService.UpdateTaskStatus(LTaskId, LNewStatus);

    if not LStatusResult.IsSuccess then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400, LStatusResult.GetErrorMessage);
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;

    LData := TJSONObject.Create;
    LData.AddPair('message', 'Status updated successfully');
    LData.AddPair('taskId', TJSONNumber.Create(LTaskId));
    LData.AddPair('newStatus', StatusToString(LNewStatus));
    LResponseJson := TJsonHelper.SuccessResponse(LData);
    AResponse.SetJSON(200, LResponseJson);
  except
    on E: Exception do
    begin
      FLogger.Error(Format('API: PATCH /api/tasks/%d/status failed', [LTaskId]), E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

end.
