unit ApiInterfaces;

interface

{
  ApiInterfaces.pas
  -----------------
  Interface declarations for the REST API layer. Follows the same Dependency
  Inversion Principle used throughout the application: all API components
  depend on abstractions, not concrete implementations.

  Architecture Overview (REST API Layer):
  ========================================

  +------------+     +-----------+     +----------------+     +------------+
  |  HTTP      | --> |  Router   | --> |  Middleware     | --> | Controller |
  |  Server    |     |  (URL     |     |  (Auth, CORS,  |     | (Business  |
  |  (Indy)    |     |   Match)  |     |   Rate Limit)  |     |  Logic)    |
  +------------+     +-----------+     +----------------+     +------------+
                                                                    |
                                                              +-----v------+
                                                              |  Services  |
                                                              |  (existing)|
                                                              +------------+

  Key Concepts:
  - IApiRequest/IApiResponse: HTTP request/response abstractions
  - IApiController: Base controller interface
  - IApiMiddleware: Middleware pipeline (chain of responsibility)
  - IApiRouter: Maps HTTP method + path to handlers
  - IApiServer: Composes all components and manages lifecycle
  - ITokenManager: Session token management for API authentication

  Flow:
  1. Client sends HTTP request
  2. Indy TIdHTTPServer receives it, wraps in IApiRequest
  3. Router matches URL pattern to controller action
  4. Middleware chain executes (CORS -> RateLimit -> Auth)
  5. Controller method executes, calls existing services
  6. Response is serialized to JSON and sent back

  Authentication: Bearer Token (session-based)
  - POST /api/auth/login returns a session token
  - Subsequent requests include: Authorization: Bearer <token>
  - Token is validated via ITokenManager
}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON;

type
  THttpMethod = (hmGET, hmPOST, hmPUT, hmDELETE, hmPATCH, hmOPTIONS, hmHEAD);

  IApiRequest = interface
    ['{A1A2A3A4-B1B2-C1C2-D1D2-E1E2E3E4E5E6}']
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
    property Method: THttpMethod read GetMethod;
    property Path: string read GetPath;
    property ContentType: string read GetContentType;
    property RemoteIP: string read GetRemoteIP;
  end;

  IApiResponse = interface
    ['{B2B3B4B5-C2C3-D2D3-E2E3-F2F3F4F5F6F7}']
    procedure SetStatusCode(ACode: Integer);
    function GetStatusCode: Integer;
    procedure SetHeader(const AName, AValue: string);
    procedure SetContentType(const AValue: string);
    procedure SetBody(const AValue: string);
    function GetBody: string;
    procedure SetJSON(AStatusCode: Integer; AJsonObj: TJSONObject);
    procedure SetError(AStatusCode: Integer; const AMessage: string);
    procedure SetSuccess(AStatusCode: Integer; AData: TJSONValue);
    property StatusCode: Integer read GetStatusCode;
    property Body: string read GetBody;
  end;

  TRouteHandler = reference to procedure(const ARequest: IApiRequest;
    const AResponse: IApiResponse);

  TMiddlewareNext = reference to procedure;

  IApiMiddleware = interface
    ['{C3C4C5C6-D3D4-E3E4-F3F4-A3A4A5A6A7A8}']
    procedure Process(const ARequest: IApiRequest; const AResponse: IApiResponse;
      ANext: TMiddlewareNext);
    function GetName: string;
    property Name: string read GetName;
  end;

  IApiRouter = interface
    ['{D4D5D6D7-E4E5-F4F5-A4A5-B4B5B6B7B8B9}']
    procedure AddRoute(AMethod: THttpMethod; const APattern: string;
      AHandler: TRouteHandler);
    procedure AddMiddleware(const AMiddleware: IApiMiddleware);
    function Dispatch(const ARequest: IApiRequest; const AResponse: IApiResponse): Boolean;
  end;

  TTokenInfo = record
    Token: string;
    UserId: Integer;
    Username: string;
    Role: string;
    CreatedAt: TDateTime;
    ExpiresAt: TDateTime;
  end;

  ITokenManager = interface
    ['{E5E6E7E8-F5F6-A5A6-B5B6-C5C6C7C8C9CA}']
    function CreateToken(AUserId: Integer; const AUsername, ARole: string): string;
    function ValidateToken(const AToken: string; out AInfo: TTokenInfo): Boolean;
    procedure RevokeToken(const AToken: string);
    procedure RevokeAllTokensForUser(AUserId: Integer);
    procedure CleanupExpiredTokens;
    function GetActiveTokenCount: Integer;
  end;

  IApiServer = interface
    ['{F6F7F8F9-A6A7-B6B7-C6C7-D6D7D8D9DADB}']
    procedure Start(APort: Integer = 8080);
    procedure Stop;
    function IsRunning: Boolean;
    function GetPort: Integer;
    property Port: Integer read GetPort;
  end;

  function HttpMethodToString(AMethod: THttpMethod): string;
  function StringToHttpMethod(const AMethod: string): THttpMethod;

implementation

function HttpMethodToString(AMethod: THttpMethod): string;
begin
  case AMethod of
    hmGET:     Result := 'GET';
    hmPOST:    Result := 'POST';
    hmPUT:     Result := 'PUT';
    hmDELETE:  Result := 'DELETE';
    hmPATCH:   Result := 'PATCH';
    hmOPTIONS: Result := 'OPTIONS';
    hmHEAD:    Result := 'HEAD';
  else
    Result := 'UNKNOWN';
  end;
end;

function StringToHttpMethod(const AMethod: string): THttpMethod;
var
  LUpper: string;
begin
  LUpper := UpperCase(AMethod);
  if LUpper = 'GET' then Result := hmGET
  else if LUpper = 'POST' then Result := hmPOST
  else if LUpper = 'PUT' then Result := hmPUT
  else if LUpper = 'DELETE' then Result := hmDELETE
  else if LUpper = 'PATCH' then Result := hmPATCH
  else if LUpper = 'OPTIONS' then Result := hmOPTIONS
  else if LUpper = 'HEAD' then Result := hmHEAD
  else Result := hmGET;
end;

end.
