unit HttpServer;

interface

{
  HttpServer.pas
  ---------------
  HTTP server implementation using Indy's TIdHTTPServer.
  Wraps the Indy component to provide a clean API for the REST layer.

  Architecture:
  =============
  TIdHTTPServer (Indy) handles TCP/threading automatically:
  - Each request runs in a separate Indy thread
  - We wrap the Indy request/response into IApiRequest/IApiResponse
  - Dispatch to IApiRouter for routing and middleware execution

  Why Indy?
  =========
  - Ships with Delphi (no extra dependencies)
  - Battle-tested, supports concurrent connections
  - Cross-platform (Windows, Linux, macOS)

  Thread Safety:
  ==============
  Indy spawns one thread per connection. The router, middleware, and controllers
  must be thread-safe or use the services' built-in synchronization.

  Usage:
    Server := THttpApiServer.Create(Router, Logger, 8080);
    Server.Start;
    // ... (server runs in background)
    Server.Stop;
}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.SyncObjs,
  IdHTTPServer,
  IdContext,
  IdCustomHTTPServer,
  IdGlobal,
  ApiInterfaces,
  AppInterfaces,
  JsonHelper;

type
  TApiRequest = class(TInterfacedObject, IApiRequest)
  private
    FMethod: THttpMethod;
    FPath: string;
    FHeaders: TDictionary<string, string>;
    FQueryParams: TDictionary<string, string>;
    FBody: string;
    FContentType: string;
    FRemoteIP: string;
    FContext: TDictionary<string, string>;
    procedure ParseQueryParams(const AURL: string);
  public
    constructor Create(ARequestInfo: TIdHTTPRequestInfo;
      AContext: TIdContext);
    destructor Destroy; override;
    function GetMethod: THttpMethod;
    function GetPath: string;
    function GetHeader(const AName: string): string;
    function GetQueryParam(const AName: string): string;
    function GetPathParam(const AName: string): string;
    function GetBody: string;
    function GetBodyAsJSON: TJSONObject;
    function GetContentType: string;
    function GetRemoteIP: string;
    procedure SetContextValue(const AKey: string; const AValue: string);
    function GetContextValue(const AKey: string): string;
  end;

  TApiResponse = class(TInterfacedObject, IApiResponse)
  private
    FStatusCode: Integer;
    FHeaders: TDictionary<string, string>;
    FContentType: string;
    FBody: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetStatusCode(ACode: Integer);
    function GetStatusCode: Integer;
    procedure SetHeader(const AName, AValue: string);
    procedure SetContentType(const AValue: string);
    procedure SetBody(const AValue: string);
    function GetBody: string;
    procedure SetJSON(AStatusCode: Integer; AJsonObj: TJSONObject);
    procedure SetError(AStatusCode: Integer; const AMessage: string);
    procedure SetSuccess(AStatusCode: Integer; AData: TJSONValue);
    procedure ApplyToIndy(AResponseInfo: TIdHTTPResponseInfo);
  end;

  THttpApiServer = class
  private
    FIdServer: TIdHTTPServer;
    FRouter: IApiRouter;
    FLogger: ILogger;
    FPort: Integer;
    FIsRunning: Boolean;
    procedure HandleRequest(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo);
  public
    constructor Create(ARouter: IApiRouter; ALogger: ILogger; APort: Integer = 8080);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    function IsRunning: Boolean;
    property Port: Integer read FPort;
  end;

implementation

constructor TApiRequest.Create(ARequestInfo: TIdHTTPRequestInfo;
  AContext: TIdContext);
var
  LStream: TStringStream;
begin
  inherited Create;
  FHeaders := TDictionary<string, string>.Create;
  FQueryParams := TDictionary<string, string>.Create;
  FContext := TDictionary<string, string>.Create;

  FMethod := StringToHttpMethod(ARequestInfo.Command);
  FPath := ARequestInfo.Document;
  if FPath = '' then
    FPath := '/';

  ParseQueryParams(ARequestInfo.QueryParams);
  FContentType := ARequestInfo.ContentType;

  if AContext.Binding <> nil then
    FRemoteIP := AContext.Binding.PeerIP
  else
    FRemoteIP := '0.0.0.0';

  if ARequestInfo.PostStream <> nil then
  begin
    LStream := TStringStream.Create('', TEncoding.UTF8);
    try
      ARequestInfo.PostStream.Position := 0;
      LStream.CopyFrom(ARequestInfo.PostStream, 0);
      FBody := LStream.DataString;
    finally
      LStream.Free;
    end;
  end
  else
    FBody := '';

  if ARequestInfo.RawHeaders <> nil then
  begin
    FHeaders.AddOrSetValue('Authorization',
      ARequestInfo.RawHeaders.Values['Authorization']);
    FHeaders.AddOrSetValue('Content-Type', ARequestInfo.ContentType);
    FHeaders.AddOrSetValue('Accept',
      ARequestInfo.RawHeaders.Values['Accept']);
    FHeaders.AddOrSetValue('Origin',
      ARequestInfo.RawHeaders.Values['Origin']);
  end;
end;

destructor TApiRequest.Destroy;
begin
  FContext.Free;
  FQueryParams.Free;
  FHeaders.Free;
  inherited;
end;

procedure TApiRequest.ParseQueryParams(const AURL: string);
var
  LParts: TArray<string>;
  LPair: string;
  LEqPos: Integer;
begin
  if AURL = '' then Exit;
  LParts := AURL.Split(['&']);
  for LPair in LParts do
  begin
    LEqPos := Pos('=', LPair);
    if LEqPos > 0 then
      FQueryParams.AddOrSetValue(
        Copy(LPair, 1, LEqPos - 1),
        Copy(LPair, LEqPos + 1, MaxInt))
    else if LPair <> '' then
      FQueryParams.AddOrSetValue(LPair, '');
  end;
end;

function TApiRequest.GetMethod: THttpMethod;
begin
  Result := FMethod;
end;

function TApiRequest.GetPath: string;
begin
  Result := FPath;
end;

function TApiRequest.GetHeader(const AName: string): string;
begin
  if not FHeaders.TryGetValue(AName, Result) then
    Result := '';
end;

function TApiRequest.GetQueryParam(const AName: string): string;
begin
  if not FQueryParams.TryGetValue(AName, Result) then
    Result := '';
end;

function TApiRequest.GetPathParam(const AName: string): string;
begin
  Result := GetContextValue('path:' + AName);
end;

function TApiRequest.GetBody: string;
begin
  Result := FBody;
end;

function TApiRequest.GetBodyAsJSON: TJSONObject;
var
  LValue: TJSONValue;
begin
  Result := nil;
  if FBody = '' then Exit;
  try
    LValue := TJSONObject.ParseJSONValue(FBody);
    if (LValue <> nil) and (LValue is TJSONObject) then
      Result := TJSONObject(LValue)
    else
      LValue.Free;
  except
    Result := nil;
  end;
end;

function TApiRequest.GetContentType: string;
begin
  Result := FContentType;
end;

function TApiRequest.GetRemoteIP: string;
begin
  Result := FRemoteIP;
end;

procedure TApiRequest.SetContextValue(const AKey, AValue: string);
begin
  FContext.AddOrSetValue(AKey, AValue);
end;

function TApiRequest.GetContextValue(const AKey: string): string;
begin
  if not FContext.TryGetValue(AKey, Result) then
    Result := '';
end;

constructor TApiResponse.Create;
begin
  inherited Create;
  FStatusCode := 200;
  FContentType := 'application/json; charset=utf-8';
  FBody := '';
  FHeaders := TDictionary<string, string>.Create;
end;

destructor TApiResponse.Destroy;
begin
  FHeaders.Free;
  inherited;
end;

procedure TApiResponse.SetStatusCode(ACode: Integer);
begin
  FStatusCode := ACode;
end;

function TApiResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

procedure TApiResponse.SetHeader(const AName, AValue: string);
begin
  FHeaders.AddOrSetValue(AName, AValue);
end;

procedure TApiResponse.SetContentType(const AValue: string);
begin
  FContentType := AValue;
end;

procedure TApiResponse.SetBody(const AValue: string);
begin
  FBody := AValue;
end;

function TApiResponse.GetBody: string;
begin
  Result := FBody;
end;

procedure TApiResponse.SetJSON(AStatusCode: Integer; AJsonObj: TJSONObject);
begin
  FStatusCode := AStatusCode;
  FContentType := 'application/json; charset=utf-8';
  if AJsonObj <> nil then
  begin
    FBody := AJsonObj.ToJSON;
    AJsonObj.Free;
  end
  else
    FBody := '{}';
end;

procedure TApiResponse.SetError(AStatusCode: Integer; const AMessage: string);
var
  LJson: TJSONObject;
begin
  LJson := TJsonHelper.ErrorResponse(AStatusCode, AMessage);
  SetJSON(AStatusCode, LJson);
end;

procedure TApiResponse.SetSuccess(AStatusCode: Integer; AData: TJSONValue);
var
  LJson: TJSONObject;
begin
  LJson := TJsonHelper.SuccessResponse(AData);
  SetJSON(AStatusCode, LJson);
end;

procedure TApiResponse.ApplyToIndy(AResponseInfo: TIdHTTPResponseInfo);
var
  LPair: TPair<string, string>;
begin
  AResponseInfo.ResponseNo := FStatusCode;
  AResponseInfo.ContentType := FContentType;
  AResponseInfo.ContentText := FBody;
  AResponseInfo.CharSet := 'utf-8';
  for LPair in FHeaders do
    AResponseInfo.CustomHeaders.AddValue(LPair.Key, LPair.Value);
end;

constructor THttpApiServer.Create(ARouter: IApiRouter; ALogger: ILogger;
  APort: Integer);
begin
  inherited Create;
  FRouter := ARouter;
  FLogger := ALogger;
  FPort := APort;
  FIsRunning := False;
  FIdServer := TIdHTTPServer.Create(nil);
  FIdServer.DefaultPort := APort;
  FIdServer.OnCommandGet := HandleRequest;
  FIdServer.OnCommandOther := HandleRequest;
end;

destructor THttpApiServer.Destroy;
begin
  Stop;
  FIdServer.Free;
  inherited;
end;

procedure THttpApiServer.HandleRequest(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  LRequest: IApiRequest;
  LResponse: IApiResponse;
  LInternalResponse: TApiResponse;
begin
  LRequest := TApiRequest.Create(ARequestInfo, AContext);
  LInternalResponse := TApiResponse.Create;
  LResponse := LInternalResponse;

  try
    if not FRouter.Dispatch(LRequest, LResponse) then
    begin
      LResponse.SetError(404, Format('Not Found: %s %s',
        [HttpMethodToString(LRequest.Method), LRequest.Path]));
    end;
  except
    on E: Exception do
    begin
      FLogger.Error('Unhandled API exception: ' + E.Message, E);
      LResponse.SetError(500, 'Internal server error');
    end;
  end;

  LInternalResponse.ApplyToIndy(AResponseInfo);
end;

procedure THttpApiServer.Start;
begin
  if FIsRunning then Exit;
  try
    FIdServer.Active := True;
    FIsRunning := True;
    FLogger.Info(Format('REST API server started on port %d', [FPort]));
    FLogger.Info(Format('Base URL: http://localhost:%d/api', [FPort]));
  except
    on E: Exception do
    begin
      FIsRunning := False;
      FLogger.Error(Format('Failed to start API server on port %d: %s',
        [FPort, E.Message]), E);
      raise;
    end;
  end;
end;

procedure THttpApiServer.Stop;
begin
  if not FIsRunning then Exit;
  try
    FIdServer.Active := False;
    FIsRunning := False;
    FLogger.Info('REST API server stopped');
  except
    on E: Exception do
      FLogger.Error('Error stopping API server: ' + E.Message, E);
  end;
end;

function THttpApiServer.IsRunning: Boolean;
begin
  Result := FIsRunning;
end;

end.
