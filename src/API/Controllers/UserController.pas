unit UserController;

interface

(*
  UserController.pas
  -------------------
  REST API controller for user management operations.
  All endpoints require Admin role (enforced by checking auth:role context).

  Endpoints:
  ==========
  GET    /api/users          - List all users (paginated)
  GET    /api/users/:id      - Get a single user by ID
  POST   /api/users          - Create a new user
  PUT    /api/users/:id      - Update user (password/role)
  DELETE /api/users/:id      - Delete a user

  Authorization:
  ==============
  All endpoints require Admin role. The auth middleware validates the token,
  and this controller additionally checks the role.

  Request/Response Examples:
  ==========================

  GET /api/users?page=1&pageSize=10
  Response: {
    "success": true,
    "data": [...],
    "meta": { "totalCount": 5, "page": 1, "pageSize": 10, ... }
  }

  POST /api/users
  Request:  { "username": "john", "password": "pass123", "role": "User" }
  Response: { "success": true, "data": { "id": 4, "username": "john", ... } }

  PUT /api/users/4
  Request:  { "password": "newpass", "role": "Admin" }
  Response: { "success": true, "data": { "message": "User updated" } }
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
  TUserController = class
  private
    FUserService: IUserService;
    FTokenManager: ITokenManager;
    FLogger: ILogger;
    function RequireAdmin(const ARequest: IApiRequest;
      const AResponse: IApiResponse): Boolean;
    function GetPathId(const ARequest: IApiRequest): Integer;
  public
    constructor Create(AUserService: IUserService;
      ATokenManager: ITokenManager; ALogger: ILogger);
    procedure HandleGetUsers(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleGetUserById(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleCreateUser(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleUpdateUser(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleDeleteUser(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure RegisterRoutes(const ARouter: IApiRouter);
  end;

implementation

constructor TUserController.Create(AUserService: IUserService;
  ATokenManager: ITokenManager; ALogger: ILogger);
begin
  inherited Create;
  FUserService := AUserService;
  FTokenManager := ATokenManager;
  FLogger := ALogger;
end;

function TUserController.RequireAdmin(const ARequest: IApiRequest;
  const AResponse: IApiResponse): Boolean;
var
  LRole: string;
  LResponseJson: TJSONObject;
begin
  LRole := ARequest.GetContextValue('auth:role');
  Result := SameText(LRole, 'Admin');
  if not Result then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(403,
      'Forbidden: Admin role required');
    AResponse.SetJSON(403, LResponseJson);
  end;
end;

function TUserController.GetPathId(const ARequest: IApiRequest): Integer;
begin
  Result := StrToIntDef(ARequest.GetContextValue('path:id'), 0);
end;

procedure TUserController.RegisterRoutes(const ARouter: IApiRouter);
begin
  ARouter.AddRoute(hmGET, '/api/users', HandleGetUsers);
  ARouter.AddRoute(hmGET, '/api/users/:id', HandleGetUserById);
  ARouter.AddRoute(hmPOST, '/api/users', HandleCreateUser);
  ARouter.AddRoute(hmPUT, '/api/users/:id', HandleUpdateUser);
  ARouter.AddRoute(hmDELETE, '/api/users/:id', HandleDeleteUser);
end;

procedure TUserController.HandleGetUsers(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LUsers: TList<TUser>;
  LPage, LPageSize: Integer;
  LJsonArray: TJSONArray;
  LResponseJson: TJSONObject;
begin
  FLogger.Info('API: GET /api/users');

  if not RequireAdmin(ARequest, AResponse) then Exit;

  LPage := StrToIntDef(ARequest.GetQueryParam('page'), 0);
  LPageSize := StrToIntDef(ARequest.GetQueryParam('pageSize'), 20);

  try
    if LPage > 0 then
      LUsers := FUserService.GetAllUsersPaged(LPage, LPageSize)
    else
      LUsers := FUserService.GetAllUsers;

    try
      LJsonArray := TJsonHelper.UserListToJSON(LUsers);

      if LPage > 0 then
      begin
        var LTotalCount := FUserService.GetUserCount;
        LResponseJson := TJsonHelper.PaginatedResponse(LJsonArray, LTotalCount,
          LPage, LPageSize);
      end
      else
        LResponseJson := TJsonHelper.SuccessResponse(LJsonArray);

      AResponse.SetJSON(200, LResponseJson);
    finally
      FreeAndNil(LUsers);
    end;
  except
    on E: Exception do
    begin
      FLogger.Error('API: GET /api/users failed', E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

procedure TUserController.HandleGetUserById(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LUserId: Integer;
  LUser: TUser;
  LResponseJson: TJSONObject;
begin
  FLogger.Info('API: GET /api/users/:id');

  if not RequireAdmin(ARequest, AResponse) then Exit;

  LUserId := GetPathId(ARequest);
  if LUserId <= 0 then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid user ID');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    LUser := FUserService.GetUserById(LUserId);
    if LUser = nil then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(404,
        Format('User with ID %d not found', [LUserId]));
      AResponse.SetJSON(404, LResponseJson);
      Exit;
    end;

    try
      LResponseJson := TJsonHelper.SuccessResponse(TJsonHelper.UserToJSON(LUser));
      AResponse.SetJSON(200, LResponseJson);
    finally
      LUser.Free;
    end;
  except
    on E: Exception do
    begin
      FLogger.Error(Format('API: GET /api/users/%d failed', [LUserId]), E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

procedure TUserController.HandleCreateUser(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LJson: TJSONObject;
  LUsername, LPassword: string;
  LRole: TUserRole;
  LCreateResult: TResult<TUser>;
  LResponseJson: TJSONObject;
begin
  FLogger.Info('API: POST /api/users');

  if not RequireAdmin(ARequest, AResponse) then Exit;

  LJson := ARequest.GetBodyAsJSON;
  if LJson = nil then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid JSON body');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    if not TJsonHelper.ParseCreateUserRequest(LJson, LUsername, LPassword, LRole) then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400,
        'Missing required fields: "username", "password"');
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;
  finally
    LJson.Free;
  end;

  try
    LCreateResult := FUserService.CreateUser(LUsername, LPassword, LRole);

    if not LCreateResult.IsSuccess then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400, LCreateResult.GetErrorMessage);
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;

    try
      LResponseJson := TJsonHelper.SuccessResponse(
        TJsonHelper.UserToJSON(LCreateResult.GetValue));
      AResponse.SetJSON(201, LResponseJson);
    finally
      LCreateResult.GetValue.Free;
    end;
  except
    on E: Exception do
    begin
      FLogger.Error('API: POST /api/users failed', E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

procedure TUserController.HandleUpdateUser(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LUserId: Integer;
  LJson: TJSONObject;
  LPassword: string;
  LRole: TUserRole;
  LHasPassword, LHasRole: Boolean;
  LUser: TUser;
  LUpdateResult: TResult;
  LResponseJson: TJSONObject;
  LData: TJSONObject;
begin
  FLogger.Info('API: PUT /api/users/:id');

  if not RequireAdmin(ARequest, AResponse) then Exit;

  LUserId := GetPathId(ARequest);
  if LUserId <= 0 then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid user ID');
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
    if not TJsonHelper.ParseUpdateUserRequest(LJson, LPassword, LRole,
      LHasPassword, LHasRole) then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400,
        'At least "password" or "role" must be provided');
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;
  finally
    LJson.Free;
  end;

  try
    LUser := FUserService.GetUserById(LUserId);
    if LUser = nil then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(404,
        Format('User with ID %d not found', [LUserId]));
      AResponse.SetJSON(404, LResponseJson);
      Exit;
    end;

    try
      if LHasRole then
        LUser.ChangeRole(LRole);

      if LHasPassword then
        LUpdateResult := FUserService.UpdateUser(LUser, LPassword)
      else
        LUpdateResult := FUserService.UpdateUser(LUser, '');

      if not LUpdateResult.IsSuccess then
      begin
        LResponseJson := TJsonHelper.ErrorResponse(400, LUpdateResult.GetErrorMessage);
        AResponse.SetJSON(400, LResponseJson);
        Exit;
      end;

      LData := TJSONObject.Create;
      LData.AddPair('message', Format('User %d updated successfully', [LUserId]));
      LResponseJson := TJsonHelper.SuccessResponse(LData);
      AResponse.SetJSON(200, LResponseJson);
    finally
      LUser.Free;
    end;
  except
    on E: Exception do
    begin
      FLogger.Error(Format('API: PUT /api/users/%d failed', [LUserId]), E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

procedure TUserController.HandleDeleteUser(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LUserId: Integer;
  LDeleteResult: TResult;
  LResponseJson: TJSONObject;
  LData: TJSONObject;
begin
  FLogger.Info('API: DELETE /api/users/:id');

  if not RequireAdmin(ARequest, AResponse) then Exit;

  LUserId := GetPathId(ARequest);
  if LUserId <= 0 then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid user ID');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    LDeleteResult := FUserService.DeleteUser(LUserId);

    if not LDeleteResult.IsSuccess then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400, LDeleteResult.GetErrorMessage);
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;

    FTokenManager.RevokeAllTokensForUser(LUserId);

    LData := TJSONObject.Create;
    LData.AddPair('message', Format('User %d deleted successfully', [LUserId]));
    LResponseJson := TJsonHelper.SuccessResponse(LData);
    AResponse.SetJSON(200, LResponseJson);
  except
    on E: Exception do
    begin
      FLogger.Error(Format('API: DELETE /api/users/%d failed', [LUserId]), E);
      LResponseJson := TJsonHelper.ErrorResponse(500, 'Internal server error');
      AResponse.SetJSON(500, LResponseJson);
    end;
  end;
end;

end.
