unit ApiMiddleware;

interface

{
  ApiMiddleware.pas
  ------------------
  Middleware implementations for the REST API pipeline.
  Middleware executes before the controller handler, allowing cross-cutting
  concerns to be applied uniformly across all endpoints.

  Execution order (configured in ApiServer):
  ==========================================
  1. TCorsMiddleware     - Handles CORS headers for browser clients
  2. TRateLimitMiddleware - Prevents abuse (token bucket algorithm)
  3. TAuthMiddleware     - Validates Bearer token, sets auth context

  Chain of Responsibility Pattern:
  ================================
  Each middleware receives (Request, Response, Next):
  - Call Next() to pass control to the next middleware (or handler)
  - Write to Response directly to short-circuit (e.g., 401 Unauthorized)
  - Both pre-processing and post-processing are possible

  Example flow for an authenticated request:
   Request -> CORS (add headers, call Next)
           -> RateLimit (check bucket, call Next)
           -> Auth (validate token, set context, call Next)
           -> Controller Handler

  Example flow for failed authentication:
   Request -> CORS (add headers, call Next)
           -> RateLimit (check bucket, call Next)
           -> Auth (token invalid, write 401, do NOT call Next)
           [Controller never executes]
}

uses
  System.SysUtils,
  System.JSON,
  ApiInterfaces,
  AppInterfaces,
  JsonHelper;

type
  TCorsMiddleware = class(TInterfacedObject, IApiMiddleware)
  private
    FAllowedOrigins: string;
    FAllowedMethods: string;
    FAllowedHeaders: string;
    FLogger: ILogger;
  public
    constructor Create(ALogger: ILogger;
      const AAllowedOrigins: string = '*';
      const AAllowedMethods: string = 'GET,POST,PUT,DELETE,PATCH,OPTIONS';
      const AAllowedHeaders: string = 'Content-Type,Authorization,Accept');
    procedure Process(const ARequest: IApiRequest; const AResponse: IApiResponse;
      ANext: TMiddlewareNext);
    function GetName: string;
  end;

  TRateLimitMiddleware = class(TInterfacedObject, IApiMiddleware)
  private
    FRateLimiter: IRateLimiter;
    FLogger: ILogger;
  public
    constructor Create(ARateLimiter: IRateLimiter; ALogger: ILogger);
    procedure Process(const ARequest: IApiRequest; const AResponse: IApiResponse;
      ANext: TMiddlewareNext);
    function GetName: string;
  end;

  TAuthMiddleware = class(TInterfacedObject, IApiMiddleware)
  private
    FTokenManager: ITokenManager;
    FLogger: ILogger;
    function IsPublicRoute(const APath: string; AMethod: THttpMethod): Boolean;
    function ExtractBearerToken(const AAuthHeader: string): string;
  public
    constructor Create(ATokenManager: ITokenManager; ALogger: ILogger);
    procedure Process(const ARequest: IApiRequest; const AResponse: IApiResponse;
      ANext: TMiddlewareNext);
    function GetName: string;
  end;

  TLoggingMiddleware = class(TInterfacedObject, IApiMiddleware)
  private
    FLogger: ILogger;
  public
    constructor Create(ALogger: ILogger);
    procedure Process(const ARequest: IApiRequest; const AResponse: IApiResponse;
      ANext: TMiddlewareNext);
    function GetName: string;
  end;

implementation

uses
  System.DateUtils;

constructor TCorsMiddleware.Create(ALogger: ILogger;
  const AAllowedOrigins, AAllowedMethods, AAllowedHeaders: string);
begin
  inherited Create;
  FLogger := ALogger;
  FAllowedOrigins := AAllowedOrigins;
  FAllowedMethods := AAllowedMethods;
  FAllowedHeaders := AAllowedHeaders;
end;

function TCorsMiddleware.GetName: string;
begin
  Result := 'CORS';
end;

procedure TCorsMiddleware.Process(const ARequest: IApiRequest;
  const AResponse: IApiResponse; ANext: TMiddlewareNext);
begin
  AResponse.SetHeader('Access-Control-Allow-Origin', FAllowedOrigins);
  AResponse.SetHeader('Access-Control-Allow-Methods', FAllowedMethods);
  AResponse.SetHeader('Access-Control-Allow-Headers', FAllowedHeaders);
  AResponse.SetHeader('Access-Control-Max-Age', '3600');

  if ARequest.Method = hmOPTIONS then
  begin
    AResponse.SetStatusCode(204);
    FLogger.Debug('CORS: Preflight request handled');
    Exit;
  end;

  ANext;
end;

constructor TRateLimitMiddleware.Create(ARateLimiter: IRateLimiter; ALogger: ILogger);
begin
  inherited Create;
  FRateLimiter := ARateLimiter;
  FLogger := ALogger;
end;

function TRateLimitMiddleware.GetName: string;
begin
  Result := 'RateLimit';
end;

procedure TRateLimitMiddleware.Process(const ARequest: IApiRequest;
  const AResponse: IApiResponse; ANext: TMiddlewareNext);
var
  LKey: string;
  LRemaining: Integer;
  LResponseJson: TJSONObject;
begin
  LKey := 'api:' + ARequest.RemoteIP;

  if not FRateLimiter.TryConsume(LKey) then
  begin
    LRemaining := FRateLimiter.GetRemainingTokens(LKey);
    FLogger.Warning(Format('Rate limit exceeded for %s', [ARequest.RemoteIP]));
    AResponse.SetHeader('X-RateLimit-Remaining', IntToStr(LRemaining));
    AResponse.SetHeader('Retry-After', '60');
    LResponseJson := TJsonHelper.ErrorResponse(429, 'Too many requests. Please slow down.');
    AResponse.SetJSON(429, LResponseJson);
    Exit;
  end;

  LRemaining := FRateLimiter.GetRemainingTokens(LKey);
  AResponse.SetHeader('X-RateLimit-Remaining', IntToStr(LRemaining));
  ANext;
end;

constructor TAuthMiddleware.Create(ATokenManager: ITokenManager; ALogger: ILogger);
begin
  inherited Create;
  FTokenManager := ATokenManager;
  FLogger := ALogger;
end;

function TAuthMiddleware.GetName: string;
begin
  Result := 'Auth';
end;

function TAuthMiddleware.IsPublicRoute(const APath: string; AMethod: THttpMethod): Boolean;
var
  LLower: string;
begin
  LLower := LowerCase(APath);
  Result := (LLower = '/api/auth/login') or
            (LLower = '/api/auth/register') or
            (LLower = '/api/health');
end;

function TAuthMiddleware.ExtractBearerToken(const AAuthHeader: string): string;
const
  BEARER_PREFIX = 'Bearer ';
begin
  Result := '';
  if AAuthHeader.StartsWith(BEARER_PREFIX, True) then
    Result := Copy(AAuthHeader, Length(BEARER_PREFIX) + 1, MaxInt).Trim;
end;

procedure TAuthMiddleware.Process(const ARequest: IApiRequest;
  const AResponse: IApiResponse; ANext: TMiddlewareNext);
var
  LAuthHeader: string;
  LToken: string;
  LTokenInfo: TTokenInfo;
  LResponseJson: TJSONObject;
begin
  if IsPublicRoute(ARequest.Path, ARequest.Method) then
  begin
    ANext;
    Exit;
  end;

  LAuthHeader := ARequest.GetHeader('Authorization');
  if LAuthHeader = '' then
  begin
    FLogger.Debug('Auth middleware: No Authorization header');
    LResponseJson := TJsonHelper.ErrorResponse(401,
      'Authentication required. Include "Authorization: Bearer <token>" header.');
    AResponse.SetJSON(401, LResponseJson);
    Exit;
  end;

  LToken := ExtractBearerToken(LAuthHeader);
  if LToken = '' then
  begin
    FLogger.Debug('Auth middleware: Invalid Authorization format');
    LResponseJson := TJsonHelper.ErrorResponse(401,
      'Invalid authorization format. Expected: "Bearer <token>"');
    AResponse.SetJSON(401, LResponseJson);
    Exit;
  end;

  if not FTokenManager.ValidateToken(LToken, LTokenInfo) then
  begin
    FLogger.Debug('Auth middleware: Token invalid or expired');
    LResponseJson := TJsonHelper.ErrorResponse(401,
      'Token invalid or expired. Please login again.');
    AResponse.SetJSON(401, LResponseJson);
    Exit;
  end;

  ARequest.SetContextValue('auth:userId', IntToStr(LTokenInfo.UserId));
  ARequest.SetContextValue('auth:username', LTokenInfo.Username);
  ARequest.SetContextValue('auth:role', LTokenInfo.Role);
  ARequest.SetContextValue('auth:token', LToken);

  FLogger.Debug(Format('Auth middleware: Authenticated user "%s" (ID=%d, Role=%s)',
    [LTokenInfo.Username, LTokenInfo.UserId, LTokenInfo.Role]));

  ANext;
end;

constructor TLoggingMiddleware.Create(ALogger: ILogger);
begin
  inherited Create;
  FLogger := ALogger;
end;

function TLoggingMiddleware.GetName: string;
begin
  Result := 'Logging';
end;

procedure TLoggingMiddleware.Process(const ARequest: IApiRequest;
  const AResponse: IApiResponse; ANext: TMiddlewareNext);
var
  LStartTime: TDateTime;
  LElapsedMs: Int64;
begin
  LStartTime := Now;
  FLogger.Info(Format('API >> %s %s [%s]',
    [HttpMethodToString(ARequest.Method), ARequest.Path, ARequest.RemoteIP]));
  ANext;
  LElapsedMs := MilliSecondsBetween(Now, LStartTime);
  FLogger.Info(Format('API << %s %s -> %d (%dms)',
    [HttpMethodToString(ARequest.Method), ARequest.Path,
     AResponse.StatusCode, LElapsedMs]));
end;

end.
