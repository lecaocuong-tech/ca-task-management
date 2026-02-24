unit SecurityContext;

interface

uses
  System.SysUtils,
  System.SyncObjs,
  AppInterfaces,
  DomainModels;

{  SecurityContext.pas
  -------------------
  Manages runtime security context for the authenticated user. Services consume
  ISecurityContextProvider (declared in AppInterfaces) via constructor injection.

  Key design decisions:
  - TSecurityContextManager implements ISecurityContextProvider for DI.
  - TSecurityContextManager uses initialization section for thread-safe singleton
    (kept for backward compatibility; new code should use ISecurityContextProvider).
  - Session timeout support: AuthenticatedAt tracks login time; IsAuthenticated
    checks whether the session has expired.
  - TCriticalSection replaces TMonitor for deterministic lifecycle management.
  - ISecurityContext is declared in AppInterfaces.pas (Dependency Inversion).

  Thread-safety: All operations are protected by TCriticalSection.
}

const
  /// Default session timeout in minutes. 0 = no timeout.
  DEFAULT_SESSION_TIMEOUT_MINUTES = 30;

type
  /// Lightweight implementation of ISecurityContext with login timestamp.
  TSecurityContext = class(TInterfacedObject, ISecurityContext)
  private
    FUserId: Integer;
    FUsername: string;
    FRole: TUserRole;
    FAuthenticatedAt: TDateTime;
  public
    constructor Create(AUserId: Integer; const AUsername: string; ARole: TUserRole);

    function GetUserId: Integer;
    function GetUsername: string;
    function GetRole: TUserRole;
    function GetAuthenticatedAt: TDateTime;
  end;

  /// Thread-safe singleton managing the current security context.
  /// Implements ISecurityContextProvider for dependency injection.
  /// Uses initialization section for guaranteed safe init (no race condition).
  /// Supports configurable session timeout.
  TSecurityContextManager = class(TInterfacedObject, ISecurityContextProvider)
  private
    class var FInstance: TSecurityContextManager;
    FSecurityContext: ISecurityContext;
    FLock: TCriticalSection;
    FSessionTimeoutMinutes: Integer;
    /// prevent ref-count destruction since we manage lifetime via init/finalization
    FRefCount: Integer;
    constructor Create;
  protected
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    class function GetInstance: TSecurityContextManager; static;

    procedure SetSecurityContext(const AContext: ISecurityContext);
    function GetSecurityContext: ISecurityContext;
    procedure ClearSecurityContext;
    function IsAuthenticated: Boolean;

    function GetSessionTimeoutMinutes: Integer;
    procedure SetSessionTimeoutMinutes(AValue: Integer);

    /// Session timeout in minutes. Set to 0 to disable timeout.
    property SessionTimeoutMinutes: Integer read GetSessionTimeoutMinutes write SetSessionTimeoutMinutes;
  end;

implementation

{ TSecurityContext }

constructor TSecurityContext.Create(AUserId: Integer; const AUsername: string; ARole: TUserRole);
begin
  inherited Create;
  FUserId := AUserId;
  FUsername := AUsername;
  FRole := ARole;
  FAuthenticatedAt := Now;
end;

function TSecurityContext.GetUserId: Integer;
begin
  Result := FUserId;
end;

function TSecurityContext.GetUsername: string;
begin
  Result := FUsername;
end;

function TSecurityContext.GetRole: TUserRole;
begin
  Result := FRole;
end;

function TSecurityContext.GetAuthenticatedAt: TDateTime;
begin
  Result := FAuthenticatedAt;
end;

{ TSecurityContextManager }

class function TSecurityContextManager.GetInstance: TSecurityContextManager;
begin
  // Thread-safe: FInstance is created in initialization section (single-threaded).
  Result := FInstance;
end;

constructor TSecurityContextManager.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FSecurityContext := nil;
  FSessionTimeoutMinutes := DEFAULT_SESSION_TIMEOUT_MINUTES;
  FRefCount := 1;  // prevent ref-count destruction
end;

function TSecurityContextManager._AddRef: Integer;
begin
  // Prevent ref-count driven destruction — lifetime managed by init/finalization
  Result := AtomicIncrement(FRefCount);
end;

function TSecurityContextManager._Release: Integer;
begin
  Result := AtomicDecrement(FRefCount);
  // Do NOT free here; finalization section handles cleanup
end;

procedure TSecurityContextManager.SetSecurityContext(const AContext: ISecurityContext);
begin
  FLock.Enter;
  try
    FSecurityContext := AContext;
  finally
    FLock.Leave;
  end;
end;

function TSecurityContextManager.GetSecurityContext: ISecurityContext;
begin
  FLock.Enter;
  try
    Result := FSecurityContext;
  finally
    FLock.Leave;
  end;
end;

procedure TSecurityContextManager.ClearSecurityContext;
begin
  FLock.Enter;
  try
    FSecurityContext := nil;
  finally
    FLock.Leave;
  end;
end;

function TSecurityContextManager.IsAuthenticated: Boolean;
var
  LElapsedMinutes: Double;
begin
  FLock.Enter;
  try
    if FSecurityContext = nil then
    begin
      Result := False;
      Exit;
    end;

    // Check session timeout
    if FSessionTimeoutMinutes > 0 then
    begin
      LElapsedMinutes := (Now - FSecurityContext.AuthenticatedAt) * 24 * 60;
      if LElapsedMinutes > FSessionTimeoutMinutes then
      begin
        // Session expired - auto-clear context
        FSecurityContext := nil;
        Result := False;
        Exit;
      end;
    end;

    Result := True;
  finally
    FLock.Leave;
  end;
end;

function TSecurityContextManager.GetSessionTimeoutMinutes: Integer;
begin
  FLock.Enter;
  try
    Result := FSessionTimeoutMinutes;
  finally
    FLock.Leave;
  end;
end;

procedure TSecurityContextManager.SetSessionTimeoutMinutes(AValue: Integer);
begin
  FLock.Enter;
  try
    FSessionTimeoutMinutes := AValue;
  finally
    FLock.Leave;
  end;
end;

initialization
  // Guaranteed single-threaded execution at unit init time.
  // Eliminates the race condition in the previous lazy-init approach.
  TSecurityContextManager.FInstance := TSecurityContextManager.Create;

finalization
  if TSecurityContextManager.FInstance <> nil then
  begin
    TSecurityContextManager.FInstance.FLock.Free;
    TSecurityContextManager.FInstance.Free;
    TSecurityContextManager.FInstance := nil;
  end;

end.
