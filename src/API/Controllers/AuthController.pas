unit AuthController;

interface

(*
  AuthController.pas
  -------------------
  REST API controller for authentication operations.

  Endpoints:
  ==========
  POST /api/auth/login     - Authenticate user, returns Bearer token
  POST /api/auth/register  - Register new user account
  POST /api/auth/logout    - Revoke current session token
  GET  /api/auth/me        - Get current authenticated user info

  Request/Response Examples:
  ==========================

  POST /api/auth/login
  Request:  { "username": "admin", "password": "admin123" }
  Response: {
    "success": true,
    "data": {
      "token": "ABC-DEF-...",
      "tokenType": "Bearer",
      "username": "admin",
      "role": "Admin",
      "expiresAt": "2026-02-13T15:30:00.000Z"
    }
  }

  POST /api/auth/register
  Request:  { "username": "newuser", "password": "pass123" }
  Response: {
    "success": true,
    "data": { "id": 3, "username": "newuser", "role": "User", ... }
  }

  POST /api/auth/logout
  Headers:  Authorization: Bearer <token>
  Response: { "success": true, "data": { "message": "Logged out successfully" } }

  GET /api/auth/me
  Headers:  Authorization: Bearer <token>
  Response: {
    "success": true,
    "data": { "userId": 1, "username": "admin", "role": "Admin" }
  }
*)

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  Result,
  ApiInterfaces,
  AppInterfaces,
  DomainModels,
  JsonHelper;

type
  TAuthController = class
  private
    FAuthService: IAuthenticationService;
    FTokenManager: ITokenManager;
    FLogger: ILogger;
  public
    constructor Create(AAuthService: IAuthenticationService;
      ATokenManager: ITokenManager; ALogger: ILogger);
    procedure HandleLogin(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleRegister(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleLogout(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure HandleGetMe(const ARequest: IApiRequest; const AResponse: IApiResponse);
    procedure RegisterRoutes(const ARouter: IApiRouter);
  end;

implementation

constructor TAuthController.Create(AAuthService: IAuthenticationService;
  ATokenManager: ITokenManager; ALogger: ILogger);
begin
  inherited Create;
  FAuthService := AAuthService;
  FTokenManager := ATokenManager;
  FLogger := ALogger;
end;

procedure TAuthController.RegisterRoutes(const ARouter: IApiRouter);
begin
  ARouter.AddRoute(hmPOST, '/api/auth/login', HandleLogin);
  ARouter.AddRoute(hmPOST, '/api/auth/register', HandleRegister);
  ARouter.AddRoute(hmPOST, '/api/auth/logout', HandleLogout);
  ARouter.AddRoute(hmGET, '/api/auth/me', HandleGetMe);
end;

procedure TAuthController.HandleLogin(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LJson: TJSONObject;
  LUsername, LPassword: string;
  LLoginResult: Result.TResult;
  LToken: string;
  LRoleStr: string;
  LResponseJson: TJSONObject;
begin
  FLogger.Info('API: POST /api/auth/login');

  LJson := ARequest.GetBodyAsJSON;
  if LJson = nil then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid JSON body');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    if not TJsonHelper.ParseLoginRequest(LJson, LUsername, LPassword) then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400, 'Missing "username" or "password" field');
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;
  finally
    LJson.Free;
  end;

  LLoginResult := FAuthService.Login(LUsername, LPassword);

  if not LLoginResult.IsSuccess then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(401, LLoginResult.GetErrorMessage);
    AResponse.SetJSON(401, LResponseJson);
    FAuthService.Logout;
    Exit;
  end;

  if FAuthService.IsCurrentUserAdmin then
    LRoleStr := 'Admin'
  else
    LRoleStr := 'User';

  LToken := FTokenManager.CreateToken(
    FAuthService.GetCurrentUserId,
    FAuthService.GetCurrentUsername,
    LRoleStr
  );

  FAuthService.Logout;

  LResponseJson := TJsonHelper.TokenResponse(LToken, LUsername, LRoleStr,
    IncMinute(Now, 60));
  AResponse.SetJSON(200, LResponseJson);
end;

procedure TAuthController.HandleRegister(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LJson: TJSONObject;
  LUsername, LPassword: string;
  LRegResult: Result.TResult<TUser>;
  LResponseJson: TJSONObject;
begin
  FLogger.Info('API: POST /api/auth/register');

  LJson := ARequest.GetBodyAsJSON;
  if LJson = nil then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, 'Invalid JSON body');
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    if not TJsonHelper.ParseLoginRequest(LJson, LUsername, LPassword) then
    begin
      LResponseJson := TJsonHelper.ErrorResponse(400,
        'Missing "username" or "password" field');
      AResponse.SetJSON(400, LResponseJson);
      Exit;
    end;
  finally
    LJson.Free;
  end;

  LRegResult := FAuthService.Register(LUsername, LPassword);

  if not LRegResult.IsSuccess then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(400, LRegResult.GetErrorMessage);
    AResponse.SetJSON(400, LResponseJson);
    Exit;
  end;

  try
    LResponseJson := TJsonHelper.SuccessResponse(
      TJsonHelper.UserToJSON(LRegResult.GetValue));
    AResponse.SetJSON(201, LResponseJson);
  finally
    LRegResult.GetValue.Free;
  end;
end;

procedure TAuthController.HandleLogout(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LToken: string;
  LResponseJson: TJSONObject;
  LData: TJSONObject;
begin
  FLogger.Info('API: POST /api/auth/logout');

  LToken := ARequest.GetContextValue('auth:token');
  if LToken <> '' then
    FTokenManager.RevokeToken(LToken);

  LData := TJSONObject.Create;
  LData.AddPair('message', 'Logged out successfully');
  LResponseJson := TJsonHelper.SuccessResponse(LData);
  AResponse.SetJSON(200, LResponseJson);
end;

procedure TAuthController.HandleGetMe(const ARequest: IApiRequest;
  const AResponse: IApiResponse);
var
  LUserId, LUsername, LRole: string;
  LData: TJSONObject;
  LResponseJson: TJSONObject;
begin
  FLogger.Info('API: GET /api/auth/me');

  LUserId := ARequest.GetContextValue('auth:userId');
  LUsername := ARequest.GetContextValue('auth:username');
  LRole := ARequest.GetContextValue('auth:role');

  if LUserId = '' then
  begin
    LResponseJson := TJsonHelper.ErrorResponse(401, 'Not authenticated');
    AResponse.SetJSON(401, LResponseJson);
    Exit;
  end;

  LData := TJSONObject.Create;
  LData.AddPair('userId', TJSONNumber.Create(StrToIntDef(LUserId, 0)));
  LData.AddPair('username', LUsername);
  LData.AddPair('role', LRole);
  LResponseJson := TJsonHelper.SuccessResponse(LData);
  AResponse.SetJSON(200, LResponseJson);
end;

end.
