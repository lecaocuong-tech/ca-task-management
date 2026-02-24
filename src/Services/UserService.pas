unit UserService;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  Result;

{
  UserService.pas
  ---------------
  Business layer for user management. Responsibilities:
  - Enforce permission checks via IPermissionGuard before performing user operations.
  - Delegate persistence to IUserRepository.
  - Use IAuthenticationService for password hashing/salt generation so hashing
    logic is centralized.

  Conventions:
  - All methods return TResult or TResult<T> for business outcomes.
  - Methods that return TList<TUser> use TObjectList<TUser> with OwnsObjects=True;
    callers only need to free the list itself (items are auto-freed).
}

type
  TUserService = class(TInterfacedObject, IUserService)
  private
    FUserRepository: IUserRepository;
    FAuthService: IAuthenticationService;
    FPermissionGuard: IPermissionGuard;
    FSecurityContextProvider: ISecurityContextProvider;
    FLogger: ILogger;
  public
    constructor Create(AUserRepository: IUserRepository;
      AAuthService: IAuthenticationService;
      APermissionGuard: IPermissionGuard;
      ASecurityContextProvider: ISecurityContextProvider;
      ALogger: ILogger);

    function GetAllUsers: TList<TUser>;
    function GetAllUsersPaged(APageNum, APageSize: Integer): TList<TUser>;
    function GetUserCount: Integer;
    function GetUserById(AUserId: Integer): TUser;
    function CreateUser(const AUsername, APassword: string; ARole: TUserRole): TResult<TUser>;
    function UpdateUser(AUser: TUser; const ANewPassword: string): TResult;
    function DeleteUser(AUserId: Integer): TResult;

  private
    // Helper: fetch the current security context (may be nil when not auth'd)
    function GetCurrentSecurityContext: ISecurityContext;
  end;

implementation

{ TUserService }

constructor TUserService.Create(AUserRepository: IUserRepository;
  AAuthService: IAuthenticationService;
  APermissionGuard: IPermissionGuard;
  ASecurityContextProvider: ISecurityContextProvider;
  ALogger: ILogger);
begin
  inherited Create;
  FUserRepository := AUserRepository;
  FAuthService := AAuthService;
  FPermissionGuard := APermissionGuard;
  FSecurityContextProvider := ASecurityContextProvider;
  FLogger := ALogger;
end;

function TUserService.GetCurrentSecurityContext: ISecurityContext;
begin
  Result := FSecurityContextProvider.GetSecurityContext;
end;

function TUserService.GetAllUsers: TList<TUser>;
var
  LPermResult: TResult;
begin
  // PermissionGuard centralizes admin checks
  LPermResult := FPermissionGuard.CanManageUsers;
  
  if not LPermResult.IsSuccess then
  begin
    FLogger.Warning(LPermResult.GetErrorMessage);
    Result := TObjectList<TUser>.Create(True);
    Exit;
  end;

  Result := FUserRepository.GetAllUsers;
  FLogger.Info(Format('GetAllUsers: %d users retrieved', [Result.Count]));
end;

function TUserService.GetAllUsersPaged(APageNum, APageSize: Integer): TList<TUser>;
var
  LPermResult: TResult;
begin
  LPermResult := FPermissionGuard.CanManageUsers;

  if not LPermResult.IsSuccess then
  begin
    FLogger.Warning(LPermResult.GetErrorMessage);
    Result := TObjectList<TUser>.Create(True);
    Exit;
  end;

  Result := FUserRepository.GetAllUsersPaged(APageNum, APageSize);
end;

function TUserService.GetUserCount: Integer;
var
  LPermResult: TResult;
begin
  LPermResult := FPermissionGuard.CanManageUsers;

  if not LPermResult.IsSuccess then
  begin
    FLogger.Warning(LPermResult.GetErrorMessage);
    Result := 0;
    Exit;
  end;

  Result := FUserRepository.GetUserCount;
end;

function TUserService.GetUserById(AUserId: Integer): TUser;
var
  LPermResult: TResult;
begin
  LPermResult := FPermissionGuard.CanManageUsers;
  
  if not LPermResult.IsSuccess then
  begin
    FLogger.Warning(LPermResult.GetErrorMessage);
    Result := nil;
    Exit;
  end;

  Result := FUserRepository.GetUserById(AUserId);
end;

function TUserService.CreateUser(const AUsername, APassword: string; ARole: TUserRole): TResult<TUser>;
var
  LPermResult: TResult;
begin
  LPermResult := FPermissionGuard.CanManageUsers;
  
  if not LPermResult.IsSuccess then
  begin
    FLogger.Warning(LPermResult.GetErrorMessage);
    Result := TResult<TUser>.Failure(LPermResult.GetErrorMessage);
    Exit;
  end;

  if AUsername = '' then
  begin
    FLogger.Warning('CreateUser: Empty username');
    Result := TResult<TUser>.Failure('Username cannot be empty');
    Exit;
  end;

  if APassword = '' then
  begin
    FLogger.Warning('CreateUser: Empty password');
    Result := TResult<TUser>.Failure('Password cannot be empty');
    Exit;
  end;

  // Enforce password policy
  var LPolicyResult := FAuthService.ValidatePasswordPolicy(APassword);
  if not LPolicyResult.IsSuccess then
  begin
    FLogger.Warning('CreateUser: ' + LPolicyResult.GetErrorMessage);
    Result := TResult<TUser>.Failure(LPolicyResult.GetErrorMessage);
    Exit;
  end;

  // Generate salt and store salted hash via AuthenticationService
  var LSalt := FAuthService.GenerateSalt;
  Result := FUserRepository.CreateUser(AUsername, FAuthService.HashPasswordKDF(APassword, LSalt), LSalt, ARole);
  
  if Result.IsSuccess then
    FLogger.Info(Format('User created: %s', [AUsername]))
  else
    FLogger.Error('CreateUser failed: ' + Result.GetErrorMessage);
end;

function TUserService.UpdateUser(AUser: TUser; const ANewPassword: string): TResult;
var
  LPermResult: TResult;
begin
  if AUser = nil then
  begin
    FLogger.Warning('UpdateUser: User is nil');
    Result := TResult.Failure('User cannot be nil');
    Exit;
  end;

  LPermResult := FPermissionGuard.CanManageUsers;
  
  if not LPermResult.IsSuccess then
  begin
    FLogger.Warning(LPermResult.GetErrorMessage);
    Result := LPermResult;
    Exit;
  end;

  if ANewPassword <> '' then
  begin
    var LSalt := FAuthService.GenerateSalt;
    AUser.ChangePassword(FAuthService.HashPasswordKDF(ANewPassword, LSalt), LSalt);
  end;

  Result := FUserRepository.UpdateUser(AUser);
  
  if Result.IsSuccess then
    FLogger.Info(Format('User updated: %s', [AUser.Username]))
  else
    FLogger.Error('UpdateUser failed: ' + Result.GetErrorMessage);
end;

function TUserService.DeleteUser(AUserId: Integer): TResult;
var
  LPermResult: TResult;
begin
  LPermResult := FPermissionGuard.CanManageUsers;
  
  if not LPermResult.IsSuccess then
  begin
    FLogger.Warning(LPermResult.GetErrorMessage);
    Result := LPermResult;
    Exit;
  end;

  Result := FUserRepository.DeleteUser(AUserId);
  
  if Result.IsSuccess then
    FLogger.Info(Format('User deleted: %d', [AUserId]))
  else
    FLogger.Error('DeleteUser failed: ' + Result.GetErrorMessage);
end;

end.
