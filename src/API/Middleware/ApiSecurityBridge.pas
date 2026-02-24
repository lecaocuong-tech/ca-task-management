unit ApiSecurityBridge;

interface

{
  ApiSecurityBridge.pas
  ----------------------
  Bridges the API's token-based authentication with the existing service layer's
  ISecurityContextProvider (singleton).

  Problem:
  ========
  The existing services (TaskService, UserService) depend on ISecurityContextProvider
  to determine who the current authenticated user is. In the VCL app, this is set
  during login. In the API layer, we use Bearer tokens instead.

  Solution:
  =========
  This middleware runs AFTER TAuthMiddleware (which validates the token and sets
  auth:userId, auth:username, auth:role in the request context). It then:

  1. Saves the current security context (if any)
  2. Creates a temporary ISecurityContext from the token info
  3. Sets it on the security context provider
  4. Calls Next() (controller executes with correct security context)
  5. Restores the original security context

  This allows existing services to work unchanged with API requests.

  Thread Safety Note:
  ===================
  ISecurityContextProvider is a singleton shared between VCL and API threads.
  The save/restore pattern ensures minimal disruption. For production systems,
  consider using thread-local storage for the security context instead.

  Registration:
  =============
  Must be registered AFTER TAuthMiddleware in the middleware pipeline:
    1. CORS
    2. Logging
    3. RateLimit
    4. Auth           <- validates token, sets auth:* context
    5. SecurityBridge <- sets ISecurityContext from auth:* context
}

uses
  System.SysUtils,
  ApiInterfaces,
  AppInterfaces,
  DomainModels;

type
  TApiSecurityBridge = class(TInterfacedObject, IApiMiddleware)
  private
    FSecurityContextProvider: ISecurityContextProvider;
    FLogger: ILogger;
  public
    constructor Create(ASecurityContextProvider: ISecurityContextProvider;
      ALogger: ILogger);
    procedure Process(const ARequest: IApiRequest; const AResponse: IApiResponse;
      ANext: TMiddlewareNext);
    function GetName: string;
  end;

implementation

uses
  SecurityContext;

constructor TApiSecurityBridge.Create(
  ASecurityContextProvider: ISecurityContextProvider; ALogger: ILogger);
begin
  inherited Create;
  FSecurityContextProvider := ASecurityContextProvider;
  FLogger := ALogger;
end;

function TApiSecurityBridge.GetName: string;
begin
  Result := 'SecurityBridge';
end;

procedure TApiSecurityBridge.Process(const ARequest: IApiRequest;
  const AResponse: IApiResponse; ANext: TMiddlewareNext);
var
  LUserId: Integer;
  LUsername, LRole: string;
  LUserRole: TUserRole;
  LSavedContext: ISecurityContext;
  LApiContext: ISecurityContext;
begin
  LUsername := ARequest.GetContextValue('auth:username');

  if LUsername = '' then
  begin
    ANext;
    Exit;
  end;

  LUserId := StrToIntDef(ARequest.GetContextValue('auth:userId'), 0);
  LRole := ARequest.GetContextValue('auth:role');

  if SameText(LRole, 'Admin') then
    LUserRole := urAdmin
  else
    LUserRole := urUser;

  LSavedContext := FSecurityContextProvider.GetSecurityContext;
  LApiContext := TSecurityContext.Create(LUserId, LUsername, LUserRole);

  try
    FSecurityContextProvider.SetSecurityContext(LApiContext);
    FLogger.Debug(Format('SecurityBridge: Set context for user "%s" (ID=%d)',
      [LUsername, LUserId]));
    ANext;
  finally
    if LSavedContext <> nil then
      FSecurityContextProvider.SetSecurityContext(LSavedContext)
    else
      FSecurityContextProvider.ClearSecurityContext;
    FLogger.Debug('SecurityBridge: Restored previous security context');
  end;
end;

end.
