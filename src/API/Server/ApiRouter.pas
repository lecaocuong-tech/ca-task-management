unit ApiRouter;

interface

{
  ApiRouter.pas
  --------------
  URL routing engine for the REST API. Maps HTTP method + URL pattern
  combinations to handler procedures, with support for:

  - Path parameters:  /api/tasks/:id  -> extracts "id" from URL
  - Middleware chain:  CORS -> RateLimit -> Auth -> Handler
  - 404 handling:     Returns JSON error for unmatched routes

  Pattern matching:
  =================
  Patterns use ':param' syntax for path parameters:
    /api/tasks/:id        matches /api/tasks/42     -> id=42
    /api/tasks/:id/status matches /api/tasks/42/status -> id=42

  Route registration example:
    Router.AddRoute(hmGET, '/api/tasks', HandleGetTasks);
    Router.AddRoute(hmGET, '/api/tasks/:id', HandleGetTaskById);
    Router.AddRoute(hmPOST, '/api/tasks', HandleCreateTask);

  Middleware execution order:
    Middlewares are executed in registration order. Each middleware
    can short-circuit by not calling ANext, or pass control downstream.

  Thread safety:
    Routes are registered at startup (single-threaded), dispatch is
    thread-safe for concurrent request handling.
}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  ApiInterfaces,
  AppInterfaces;

type
  TRouteEntry = record
    Method: THttpMethod;
    Pattern: string;
    PatternSegments: TArray<string>;
    Handler: TRouteHandler;
  end;

  TApiRouter = class(TInterfacedObject, IApiRouter)
  private
    FRoutes: TList<TRouteEntry>;
    FMiddlewares: TList<IApiMiddleware>;
    FLogger: ILogger;
    function SplitPath(const APath: string): TArray<string>;
    function TryMatchRoute(const APatternSegments, AUrlSegments: TArray<string>;
      out AParams: TDictionary<string, string>): Boolean;
    procedure ExecuteMiddlewareChain(AIndex: Integer;
      const ARequest: IApiRequest; const AResponse: IApiResponse;
      AFinalHandler: TRouteHandler);
  public
    constructor Create(ALogger: ILogger);
    destructor Destroy; override;
    procedure AddRoute(AMethod: THttpMethod; const APattern: string;
      AHandler: TRouteHandler);
    procedure AddMiddleware(const AMiddleware: IApiMiddleware);
    function Dispatch(const ARequest: IApiRequest;
      const AResponse: IApiResponse): Boolean;
  end;

implementation

constructor TApiRouter.Create(ALogger: ILogger);
begin
  inherited Create;
  FLogger := ALogger;
  FRoutes := TList<TRouteEntry>.Create;
  FMiddlewares := TList<IApiMiddleware>.Create;
end;

destructor TApiRouter.Destroy;
begin
  FMiddlewares.Free;
  FRoutes.Free;
  inherited;
end;

function TApiRouter.SplitPath(const APath: string): TArray<string>;
var
  LParts: TArray<string>;
  LResult: TList<string>;
  LPart: string;
begin
  LResult := TList<string>.Create;
  try
    var LPath := APath;
    var LQPos := Pos('?', LPath);
    if LQPos > 0 then
      LPath := Copy(LPath, 1, LQPos - 1);
    LParts := LPath.Split(['/']);
    for LPart in LParts do
    begin
      if LPart <> '' then
        LResult.Add(LowerCase(LPart));
    end;
    Result := LResult.ToArray;
  finally
    LResult.Free;
  end;
end;

function TApiRouter.TryMatchRoute(const APatternSegments, AUrlSegments: TArray<string>;
  out AParams: TDictionary<string, string>): Boolean;
var
  I: Integer;
begin
  Result := False;
  AParams := TDictionary<string, string>.Create;

  if Length(APatternSegments) <> Length(AUrlSegments) then
  begin
    AParams.Free;
    AParams := nil;
    Exit;
  end;

  for I := 0 to High(APatternSegments) do
  begin
    if APatternSegments[I].StartsWith(':') then
    begin
      AParams.Add(Copy(APatternSegments[I], 2, MaxInt), AUrlSegments[I]);
    end
    else if not SameText(APatternSegments[I], AUrlSegments[I]) then
    begin
      AParams.Free;
      AParams := nil;
      Exit;
    end;
  end;

  Result := True;
end;

procedure TApiRouter.AddRoute(AMethod: THttpMethod; const APattern: string;
  AHandler: TRouteHandler);
var
  LEntry: TRouteEntry;
begin
  LEntry.Method := AMethod;
  LEntry.Pattern := APattern;
  LEntry.PatternSegments := SplitPath(APattern);
  LEntry.Handler := AHandler;
  FRoutes.Add(LEntry);
  FLogger.Debug(Format('Route registered: %s %s',
    [HttpMethodToString(AMethod), APattern]));
end;

procedure TApiRouter.AddMiddleware(const AMiddleware: IApiMiddleware);
begin
  FMiddlewares.Add(AMiddleware);
  FLogger.Debug(Format('Middleware registered: %s', [AMiddleware.Name]));
end;

procedure TApiRouter.ExecuteMiddlewareChain(AIndex: Integer;
  const ARequest: IApiRequest; const AResponse: IApiResponse;
  AFinalHandler: TRouteHandler);
begin
  if AIndex >= FMiddlewares.Count then
  begin
    AFinalHandler(ARequest, AResponse);
  end
  else
  begin
    FMiddlewares[AIndex].Process(ARequest, AResponse,
      procedure
      begin
        ExecuteMiddlewareChain(AIndex + 1, ARequest, AResponse, AFinalHandler);
      end
    );
  end;
end;

function TApiRouter.Dispatch(const ARequest: IApiRequest;
  const AResponse: IApiResponse): Boolean;
var
  LRoute: TRouteEntry;
  LUrlSegments: TArray<string>;
  LParams: TDictionary<string, string>;
  LPair: TPair<string, string>;
begin
  Result := False;
  LUrlSegments := SplitPath(ARequest.Path);

  if ARequest.Method = hmOPTIONS then
  begin
    ExecuteMiddlewareChain(0, ARequest, AResponse,
      procedure(const Req: IApiRequest; const Resp: IApiResponse)
      begin
        Resp.SetStatusCode(204);
      end);
    Result := True;
    Exit;
  end;

  for LRoute in FRoutes do
  begin
    if LRoute.Method <> ARequest.Method then
      Continue;

    if TryMatchRoute(LRoute.PatternSegments, LUrlSegments, LParams) then
    begin
      try
        if LParams <> nil then
        begin
          for LPair in LParams do
            ARequest.SetContextValue('path:' + LPair.Key, LPair.Value);
        end;
      finally
        LParams.Free;
      end;

      FLogger.Debug(Format('Dispatching: %s %s -> %s',
        [HttpMethodToString(ARequest.Method), ARequest.Path, LRoute.Pattern]));

      ExecuteMiddlewareChain(0, ARequest, AResponse, LRoute.Handler);
      Result := True;
      Exit;
    end;
  end;

  FLogger.Warning(Format('No route matched: %s %s',
    [HttpMethodToString(ARequest.Method), ARequest.Path]));
end;

end.
