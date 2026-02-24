unit TokenManager;

interface

{
  TokenManager.pas
  -----------------
  Session-based token management for REST API authentication.

  How it works:
  =============
  1. User calls POST /api/auth/login with username + password
  2. AuthController validates credentials via IAuthenticationService
  3. On success, TokenManager generates a unique GUID-based token
  4. Token is stored in an in-memory dictionary with user info + expiry
  5. Client includes token in subsequent requests:
       Authorization: Bearer <token>
  6. Middleware validates token via TokenManager.ValidateToken
  7. On logout, token is revoked (removed from dictionary)

  Security considerations:
  - Tokens are GUIDs (128-bit random) - not guessable
  - Tokens expire after configurable TTL (default: 60 minutes)
  - Thread-safe via TCriticalSection (API handles concurrent requests)
  - Expired tokens are cleaned up periodically

  Note: This is simpler than JWT but sufficient for learning REST in Delphi.
  For production, consider JWT with proper signing (e.g., JOSE library).
}

uses
  System.SysUtils,
  System.Generics.Collections,
  System.SyncObjs,
  System.DateUtils,
  ApiInterfaces,
  AppInterfaces;

type
  TTokenManager = class(TInterfacedObject, ITokenManager)
  private
    FTokens: TDictionary<string, TTokenInfo>;
    FLock: TCriticalSection;
    FLogger: ILogger;
    FTokenTTLMinutes: Integer;
  public
    constructor Create(ALogger: ILogger; ATokenTTLMinutes: Integer = 60);
    destructor Destroy; override;
    function CreateToken(AUserId: Integer; const AUsername, ARole: string): string;
    function ValidateToken(const AToken: string; out AInfo: TTokenInfo): Boolean;
    procedure RevokeToken(const AToken: string);
    procedure RevokeAllTokensForUser(AUserId: Integer);
    procedure CleanupExpiredTokens;
    function GetActiveTokenCount: Integer;
  end;

implementation

constructor TTokenManager.Create(ALogger: ILogger; ATokenTTLMinutes: Integer);
begin
  inherited Create;
  FLogger := ALogger;
  FTokenTTLMinutes := ATokenTTLMinutes;
  FTokens := TDictionary<string, TTokenInfo>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TTokenManager.Destroy;
begin
  FLock.Free;
  FTokens.Free;
  inherited;
end;

function TTokenManager.CreateToken(AUserId: Integer;
  const AUsername, ARole: string): string;
var
  LToken: string;
  LInfo: TTokenInfo;
begin
  LToken := TGUID.NewGuid.ToString + '-' + TGUID.NewGuid.ToString;
  LToken := StringReplace(LToken, '{', '', [rfReplaceAll]);
  LToken := StringReplace(LToken, '}', '', [rfReplaceAll]);

  LInfo.Token := LToken;
  LInfo.UserId := AUserId;
  LInfo.Username := AUsername;
  LInfo.Role := ARole;
  LInfo.CreatedAt := Now;
  LInfo.ExpiresAt := IncMinute(Now, FTokenTTLMinutes);

  FLock.Enter;
  try
    FTokens.AddOrSetValue(LToken, LInfo);
  finally
    FLock.Leave;
  end;

  FLogger.Info(Format('Token created for user "%s" (ID=%d), expires in %d minutes',
    [AUsername, AUserId, FTokenTTLMinutes]));

  Result := LToken;
end;

function TTokenManager.ValidateToken(const AToken: string;
  out AInfo: TTokenInfo): Boolean;
begin
  Result := False;
  if AToken = '' then Exit;

  FLock.Enter;
  try
    if not FTokens.TryGetValue(AToken, AInfo) then
    begin
      FLogger.Debug('Token validation failed: token not found');
      Exit;
    end;

    if Now > AInfo.ExpiresAt then
    begin
      FTokens.Remove(AToken);
      FLogger.Info(Format('Token expired for user "%s"', [AInfo.Username]));
      Exit;
    end;

    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TTokenManager.RevokeToken(const AToken: string);
var
  LInfo: TTokenInfo;
begin
  FLock.Enter;
  try
    if FTokens.TryGetValue(AToken, LInfo) then
    begin
      FTokens.Remove(AToken);
      FLogger.Info(Format('Token revoked for user "%s"', [LInfo.Username]));
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TTokenManager.RevokeAllTokensForUser(AUserId: Integer);
var
  LTokensToRemove: TList<string>;
  LPair: TPair<string, TTokenInfo>;
  LToken: string;
begin
  LTokensToRemove := TList<string>.Create;
  try
    FLock.Enter;
    try
      for LPair in FTokens do
      begin
        if LPair.Value.UserId = AUserId then
          LTokensToRemove.Add(LPair.Key);
      end;
      for LToken in LTokensToRemove do
        FTokens.Remove(LToken);
    finally
      FLock.Leave;
    end;

    if LTokensToRemove.Count > 0 then
      FLogger.Info(Format('Revoked %d tokens for user ID=%d',
        [LTokensToRemove.Count, AUserId]));
  finally
    LTokensToRemove.Free;
  end;
end;

procedure TTokenManager.CleanupExpiredTokens;
var
  LTokensToRemove: TList<string>;
  LPair: TPair<string, TTokenInfo>;
  LToken: string;
  LNow: TDateTime;
begin
  LTokensToRemove := TList<string>.Create;
  try
    LNow := Now;

    FLock.Enter;
    try
      for LPair in FTokens do
      begin
        if LNow > LPair.Value.ExpiresAt then
          LTokensToRemove.Add(LPair.Key);
      end;
      for LToken in LTokensToRemove do
        FTokens.Remove(LToken);
    finally
      FLock.Leave;
    end;

    if LTokensToRemove.Count > 0 then
      FLogger.Debug(Format('Cleaned up %d expired tokens', [LTokensToRemove.Count]));
  finally
    LTokensToRemove.Free;
  end;
end;

function TTokenManager.GetActiveTokenCount: Integer;
begin
  FLock.Enter;
  try
    Result := FTokens.Count;
  finally
    FLock.Leave;
  end;
end;

end.
