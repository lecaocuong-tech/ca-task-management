unit ApiServer;

interface

{
  ApiServer.pas
  --------------
  Composition root for the REST API layer. Wires together:
  - HTTP Server (Indy-based)
  - Router (URL pattern matching)
  - Middleware pipeline (CORS -> Logging -> RateLimit -> Auth)
  - Controllers (Auth, Task, User)
  - Token Manager (session-based authentication)

  Integration with existing application:
  ======================================
  The API server reuses the existing IServiceContainer and all its services.
  No code changes to services, repositories, or domain models are needed.

  The API server runs alongside the VCL application, using Indy's built-in
  threading model. Each HTTP request is handled in a separate Indy thread.

  Security Context Bridge:
  ========================
  The VCL app uses ISecurityContextProvider (singleton) for session state.
  The API layer uses its own token-based auth (ITokenManager) instead.
  API controllers call services that may check security context.

  For API requests, we temporarily set the security context for the duration
  of the request, then clear it. This is done via a special middleware
  (TApiSecurityBridge) that maps token info to ISecurityContext.

  Lifecycle:
  ==========
  1. Create TApiServerManager with IServiceContainer
  2. Call Start(port) to begin listening
  3. Server runs in background (Indy threads)
  4. Call Stop to shut down gracefully

  Usage in TaskManager.dpr:
    var ApiMgr := TApiServerManager.Create(GServiceContainer);
    ApiMgr.Start(8080);
    // ... application runs ...
    ApiMgr.Stop;
    ApiMgr.Free;
}

uses
  System.SysUtils,
  System.JSON,
  ApiInterfaces,
  AppInterfaces,
  ApiRouter,
  HttpServer,
  ApiMiddleware,
  ApiSecurityBridge,
  TokenManager,
  AuthController,
  TaskController,
  UserController,
  JsonHelper;

type
  TApiServerManager = class
  private
    FServiceContainer: IServiceContainer;
    FTokenManager: ITokenManager;
    FRouter: IApiRouter;
    FHttpServer: THttpApiServer;
    FAuthController: TAuthController;
    FTaskController: TTaskController;
    FUserController: TUserController;
    FLogger: ILogger;
    FPort: Integer;

    procedure SetupRouter;
    procedure SetupMiddleware;
    procedure SetupControllers;
    procedure RegisterHealthEndpoint;
  public
    constructor Create(AServiceContainer: IServiceContainer);
    destructor Destroy; override;
    procedure Start(APort: Integer = 8080);
    procedure Stop;
    function IsRunning: Boolean;
    function GetTokenManager: ITokenManager;
    property Port: Integer read FPort;
  end;

implementation

constructor TApiServerManager.Create(AServiceContainer: IServiceContainer);
begin
  inherited Create;
  FServiceContainer := AServiceContainer;
  FLogger := FServiceContainer.GetLogger;
  FTokenManager := TTokenManager.Create(FLogger, 60);
  FRouter := TApiRouter.Create(FLogger);
  SetupMiddleware;
  SetupControllers;
  RegisterHealthEndpoint;
  FLogger.Info('API Server Manager initialized');
end;

destructor TApiServerManager.Destroy;
begin
  Stop;
  FTaskController.Free;
  FUserController.Free;
  FAuthController.Free;
  inherited;
end;

procedure TApiServerManager.SetupMiddleware;
var
  LCorsMiddleware: IApiMiddleware;
  LLoggingMiddleware: IApiMiddleware;
  LRateLimitMiddleware: IApiMiddleware;
  LAuthMiddleware: IApiMiddleware;
  LSecurityBridge: IApiMiddleware;
begin
  LCorsMiddleware := TCorsMiddleware.Create(FLogger);
  FRouter.AddMiddleware(LCorsMiddleware);
  LLoggingMiddleware := TLoggingMiddleware.Create(FLogger);
  FRouter.AddMiddleware(LLoggingMiddleware);
  LRateLimitMiddleware := TRateLimitMiddleware.Create(
    FServiceContainer.GetRateLimiter, FLogger);
  FRouter.AddMiddleware(LRateLimitMiddleware);
  LAuthMiddleware := TAuthMiddleware.Create(FTokenManager, FLogger);
  FRouter.AddMiddleware(LAuthMiddleware);
  LSecurityBridge := TApiSecurityBridge.Create(
    FServiceContainer.GetSecurityContextProvider, FLogger);
  FRouter.AddMiddleware(LSecurityBridge);
end;

procedure TApiServerManager.SetupControllers;
begin
  FAuthController := TAuthController.Create(
    FServiceContainer.GetAuthenticationService,
    FTokenManager, FLogger);
  FAuthController.RegisterRoutes(FRouter);
  FTaskController := TTaskController.Create(
    FServiceContainer.GetTaskService,
    FTokenManager, FLogger);
  FTaskController.RegisterRoutes(FRouter);
  FUserController := TUserController.Create(
    FServiceContainer.GetUserService,
    FTokenManager, FLogger);
  FUserController.RegisterRoutes(FRouter);
end;

procedure TApiServerManager.RegisterHealthEndpoint;
begin
  FRouter.AddRoute(hmGET, '/api/health',
    procedure(const ARequest: IApiRequest; const AResponse: IApiResponse)
    var
      LData: System.JSON.TJSONObject;
      LResponseJson: System.JSON.TJSONObject;
    begin
      LData := System.JSON.TJSONObject.Create;
      LData.AddPair('status', 'healthy');
      LData.AddPair('version', '1.0.0');
      LData.AddPair('timestamp', TJsonHelper.DateTimeToISO(Now));
      LData.AddPair('activeTokens',
        System.JSON.TJSONNumber.Create(FTokenManager.GetActiveTokenCount));
      LResponseJson := TJsonHelper.SuccessResponse(LData);
      AResponse.SetJSON(200, LResponseJson);
    end);
end;

procedure TApiServerManager.SetupRouter;
begin
  // Router is set up via SetupMiddleware and SetupControllers
end;

procedure TApiServerManager.Start(APort: Integer);
begin
  if (FHttpServer <> nil) and FHttpServer.IsRunning then
  begin
    FLogger.Warning('API server is already running');
    Exit;
  end;

  FPort := APort;
  FreeAndNil(FHttpServer);
  FHttpServer := THttpApiServer.Create(FRouter, FLogger, APort);
  FHttpServer.Start;

  FLogger.Info('===========================================');
  FLogger.Info(Format('  REST API server running on port %d', [APort]));
  FLogger.Info(Format('  Base URL: http://localhost:%d/api', [APort]));
  FLogger.Info('  Endpoints:');
  FLogger.Info('    GET    /api/health           - Health check');
  FLogger.Info('    POST   /api/auth/login       - Login');
  FLogger.Info('    POST   /api/auth/register    - Register');
  FLogger.Info('    POST   /api/auth/logout      - Logout');
  FLogger.Info('    GET    /api/auth/me           - Current user');
  FLogger.Info('    GET    /api/tasks             - List tasks');
  FLogger.Info('    GET    /api/tasks/:id         - Get task');
  FLogger.Info('    POST   /api/tasks             - Create task');
  FLogger.Info('    PUT    /api/tasks/:id         - Update task');
  FLogger.Info('    DELETE /api/tasks/:id         - Delete task');
  FLogger.Info('    PATCH  /api/tasks/:id/status  - Change status');
  FLogger.Info('    GET    /api/users             - List users (Admin)');
  FLogger.Info('    GET    /api/users/:id         - Get user (Admin)');
  FLogger.Info('    POST   /api/users             - Create user (Admin)');
  FLogger.Info('    PUT    /api/users/:id         - Update user (Admin)');
  FLogger.Info('    DELETE /api/users/:id         - Delete user (Admin)');
  FLogger.Info('===========================================');
end;

procedure TApiServerManager.Stop;
begin
  if FHttpServer <> nil then
  begin
    FHttpServer.Stop;
    FreeAndNil(FHttpServer);
  end;
end;

function TApiServerManager.IsRunning: Boolean;
begin
  Result := (FHttpServer <> nil) and FHttpServer.IsRunning;
end;

function TApiServerManager.GetTokenManager: ITokenManager;
begin
  Result := FTokenManager;
end;

end.
