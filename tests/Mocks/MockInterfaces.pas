unit MockInterfaces;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  Result;

{
  MockInterfaces.pas
  -------------------
  Lightweight mock/stub implementations of all application interfaces for unit
  testing. No external mocking framework required.

  Each mock stores calls for verification and allows pre-configuring return values.
  Usage: create mock, configure returns, inject into service under test, assert calls.

  Mock classes:
  - TMockLogger: captures log calls for verification
  - TMockSecurityContextProvider: configurable security context for tests
  - TMockUserRepository: in-memory user store with call tracking
  - TMockTaskRepository: in-memory task store with call tracking
  - TMockPermissionGuard: configurable permission results
  - TMockAuthenticationService: stub for auth operations
}

type
  // ==========================================================================
  // TMockLogger
  // ==========================================================================

  TMockLogger = class(TInterfacedObject, ILogger)
  private
    FMessages: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warning(const AMessage: string);
    procedure Error(const AMessage: string; AException: Exception = nil);
    procedure Fatal(const AMessage: string; AException: Exception = nil);

    /// <summary>Returns all logged messages for assertion.</summary>
    property Messages: TList<string> read FMessages;
    function HasMessage(const ASubstring: string): Boolean;
    procedure Clear;
  end;

  // ==========================================================================
  // TMockSecurityContextProvider
  // ==========================================================================

  TMockSecurityContextProvider = class(TInterfacedObject, ISecurityContextProvider)
  private
    FContext: ISecurityContext;
    FSessionTimeoutMinutes: Integer;
  public
    constructor Create;

    procedure SetSecurityContext(const AContext: ISecurityContext);
    function GetSecurityContext: ISecurityContext;
    procedure ClearSecurityContext;
    function IsAuthenticated: Boolean;
    function GetSessionTimeoutMinutes: Integer;
    procedure SetSessionTimeoutMinutes(AValue: Integer);

    /// <summary>Convenience: set up an authenticated admin context.</summary>
    procedure LoginAsAdmin(AUserId: Integer = 1; const AUsername: string = 'admin');
    /// <summary>Convenience: set up an authenticated regular user context.</summary>
    procedure LoginAsUser(AUserId: Integer = 2; const AUsername: string = 'user1');
    /// <summary>Clear context (simulate logged out state).</summary>
    procedure Logout;
  end;

  // ==========================================================================
  // TMockUserRepository
  // ==========================================================================

  TMockUserRepository = class(TInterfacedObject, IUserRepository)
  private
    FUsers: TObjectList<TUser>;
    FNextId: Integer;
    FGetUserByIdCalls: Integer;
    FGetUserByUsernameCalls: Integer;
    FCreateUserCalls: Integer;
    FUpdateUserCalls: Integer;
    FDeleteUserCalls: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    function GetUserById(AUserId: Integer): TUser;
    function GetUserByUsername(const AUsername: string): TUser;
    function CreateUser(const AUsername, APasswordHash, ASalt: string; ARole: TUserRole): TResult<TUser>;
    function UpdateUser(AUser: TUser): TResult;
    function DeleteUser(AUserId: Integer): TResult;
    function GetAllUsers: TList<TUser>;
    function GetAllUsersPaged(APageNum, APageSize: Integer): TList<TUser>;
    function GetUserCount: Integer;

    /// <summary>Seed a user into the mock store.</summary>
    procedure SeedUser(AId: Integer; const AUsername, APasswordHash, ASalt: string;
      ARole: TUserRole);

    property GetUserByIdCalls: Integer read FGetUserByIdCalls;
    property GetUserByUsernameCalls: Integer read FGetUserByUsernameCalls;
    property CreateUserCalls: Integer read FCreateUserCalls;
    property UpdateUserCalls: Integer read FUpdateUserCalls;
    property DeleteUserCalls: Integer read FDeleteUserCalls;
  end;

  // ==========================================================================
  // TMockTaskRepository
  // ==========================================================================

  TMockTaskRepository = class(TInterfacedObject, ITaskRepository)
  private
    FTasks: TObjectList<TTask>;
    FNextId: Integer;
    FCreateTaskCalls: Integer;
    FUpdateTaskCalls: Integer;
    FDeleteTaskCalls: Integer;
    FBulkTouchCalls: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    function GetTaskById(ATaskId: Integer): TTask;
    function GetTasksByUserId(AUserId: Integer): TList<TTask>;
    function GetTasksByUserIdWithFilter(AUserId: Integer; const AStatusFilter: string = ''): TList<TTask>;
    function GetTasksByUserIdPaged(AUserId: Integer; APageNum, APageSize: Integer): TList<TTask>;
    function GetAllTasks: TList<TTask>;
    function GetAllTasksWithFilter(const AStatusFilter: string = ''): TList<TTask>;
    function GetAllTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
    function GetTaskCountByUserId(AUserId: Integer): Integer;
    function GetAllTasksCount: Integer;
    function CreateTask(AUserId: Integer; const ATitle, ADescription: string): TResult<TTask>;
    function UpdateTask(ATask: TTask): TResult;
    function DeleteTask(ATaskId: Integer): TResult;
    function DeleteCompletedTasks(ADaysOld: Integer): Integer;
    function BulkTouchUpdatedAt: Integer;

    /// <summary>Seed a task into the mock store.</summary>
    procedure SeedTask(AId, AUserId: Integer; const ATitle: string;
      AStatus: TTaskStatus);

    property CreateTaskCalls: Integer read FCreateTaskCalls;
    property UpdateTaskCalls: Integer read FUpdateTaskCalls;
    property DeleteTaskCalls: Integer read FDeleteTaskCalls;
    property BulkTouchCalls: Integer read FBulkTouchCalls;
  end;

  // ==========================================================================
  // TMockPermissionGuard
  // ==========================================================================

  TMockPermissionGuard = class(TInterfacedObject, IPermissionGuard)
  private
    FAlwaysAllow: Boolean;
  public
    constructor Create(AAlwaysAllow: Boolean = True);

    function CanViewTask(ATask: TTask): TResult;
    function CanEditTask(ATask: TTask): TResult;
    function CanDeleteTask(ATask: TTask): TResult;
    function CanManageUsers: TResult;

    property AlwaysAllow: Boolean read FAlwaysAllow write FAlwaysAllow;
  end;

  // ==========================================================================
  // TMockAuthenticationService
  // ==========================================================================

  TMockAuthenticationService = class(TInterfacedObject, IAuthenticationService)
  private
    FPasswordPolicyValid: Boolean;
    FPasswordPolicyError: string;
    FSaltValue: string;
    FHashPrefix: string;
    FLoginCalls: Integer;
    FRegisterCalls: Integer;
  public
    constructor Create;

    function Login(const AUsername, APassword: string): TResult;
    function Register(const AUsername, APassword: string): TResult<TUser>;
    procedure Logout;
    function IsAuthenticated: Boolean;
    function HashPasswordKDF(const APassword, ASalt: string; AIterations: Integer = 10000): string;
    function GenerateSalt: string;
    function ValidatePasswordPolicy(const APassword: string): TResult;
    function GetCurrentUsername: string;
    function GetCurrentUserId: Integer;
    function IsCurrentUserAdmin: Boolean;

    /// <summary>Configure whether ValidatePasswordPolicy returns success.</summary>
    property PasswordPolicyValid: Boolean read FPasswordPolicyValid write FPasswordPolicyValid;
    /// <summary>Error message returned when PasswordPolicyValid is False.</summary>
    property PasswordPolicyError: string read FPasswordPolicyError write FPasswordPolicyError;
    /// <summary>Fixed salt returned by GenerateSalt.</summary>
    property SaltValue: string read FSaltValue write FSaltValue;
    /// <summary>Prefix used by HashPasswordKDF: returns HashPrefix + Password + Salt.</summary>
    property HashPrefix: string read FHashPrefix write FHashPrefix;

    property LoginCalls: Integer read FLoginCalls;
    property RegisterCalls: Integer read FRegisterCalls;
  end;

implementation

uses
  System.DateUtils,
  SecurityContext;

{ TMockLogger }

constructor TMockLogger.Create;
begin
  inherited Create;
  FMessages := TList<string>.Create;
end;

destructor TMockLogger.Destroy;
begin
  FMessages.Free;
  inherited;
end;

procedure TMockLogger.Debug(const AMessage: string);
begin
  FMessages.Add('[DEBUG] ' + AMessage);
end;

procedure TMockLogger.Info(const AMessage: string);
begin
  FMessages.Add('[INFO] ' + AMessage);
end;

procedure TMockLogger.Warning(const AMessage: string);
begin
  FMessages.Add('[WARN] ' + AMessage);
end;

procedure TMockLogger.Error(const AMessage: string; AException: Exception);
begin
  FMessages.Add('[ERROR] ' + AMessage);
end;

procedure TMockLogger.Fatal(const AMessage: string; AException: Exception);
begin
  FMessages.Add('[FATAL] ' + AMessage);
end;

function TMockLogger.HasMessage(const ASubstring: string): Boolean;
var
  Msg: string;
begin
  Result := False;
  for Msg in FMessages do
  begin
    if Pos(ASubstring, Msg) > 0 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure TMockLogger.Clear;
begin
  FMessages.Clear;
end;

{ TMockSecurityContextProvider }

constructor TMockSecurityContextProvider.Create;
begin
  inherited Create;
  FContext := nil;
  FSessionTimeoutMinutes := 30;
end;

procedure TMockSecurityContextProvider.SetSecurityContext(const AContext: ISecurityContext);
begin
  FContext := AContext;
end;

function TMockSecurityContextProvider.GetSecurityContext: ISecurityContext;
begin
  Result := FContext;
end;

procedure TMockSecurityContextProvider.ClearSecurityContext;
begin
  FContext := nil;
end;

function TMockSecurityContextProvider.IsAuthenticated: Boolean;
begin
  Result := FContext <> nil;
end;

function TMockSecurityContextProvider.GetSessionTimeoutMinutes: Integer;
begin
  Result := FSessionTimeoutMinutes;
end;

procedure TMockSecurityContextProvider.SetSessionTimeoutMinutes(AValue: Integer);
begin
  FSessionTimeoutMinutes := AValue;
end;

procedure TMockSecurityContextProvider.LoginAsAdmin(AUserId: Integer; const AUsername: string);
begin
  FContext := TSecurityContext.Create(AUserId, AUsername, urAdmin);
end;

procedure TMockSecurityContextProvider.LoginAsUser(AUserId: Integer; const AUsername: string);
begin
  FContext := TSecurityContext.Create(AUserId, AUsername, urUser);
end;

procedure TMockSecurityContextProvider.Logout;
begin
  FContext := nil;
end;

{ TMockUserRepository }

constructor TMockUserRepository.Create;
begin
  inherited Create;
  FUsers := TObjectList<TUser>.Create(False); // Don't own — we clone on return
  FNextId := 1;
end;

destructor TMockUserRepository.Destroy;
var
  I: Integer;
begin
  for I := 0 to FUsers.Count - 1 do
    FUsers[I].Free;
  FUsers.Free;
  inherited;
end;

procedure TMockUserRepository.SeedUser(AId: Integer; const AUsername, APasswordHash, ASalt: string;
  ARole: TUserRole);
var
  LUser: TUser;
begin
  LUser := TUser.Hydrate(AId, AUsername, APasswordHash, ASalt, ARole, Now);
  FUsers.Add(LUser);
  if AId >= FNextId then
    FNextId := AId + 1;
end;

function TMockUserRepository.GetUserById(AUserId: Integer): TUser;
var
  I: Integer;
begin
  Inc(FGetUserByIdCalls);
  Result := nil;
  for I := 0 to FUsers.Count - 1 do
  begin
    if FUsers[I].Id = AUserId then
    begin
      Result := TUser.Hydrate(FUsers[I].Id, FUsers[I].Username,
        FUsers[I].PasswordHash, FUsers[I].Salt, FUsers[I].Role, FUsers[I].CreatedAt);
      Exit;
    end;
  end;
end;

function TMockUserRepository.GetUserByUsername(const AUsername: string): TUser;
var
  I: Integer;
begin
  Inc(FGetUserByUsernameCalls);
  Result := nil;
  for I := 0 to FUsers.Count - 1 do
  begin
    if SameText(FUsers[I].Username, AUsername) then
    begin
      Result := TUser.Hydrate(FUsers[I].Id, FUsers[I].Username,
        FUsers[I].PasswordHash, FUsers[I].Salt, FUsers[I].Role, FUsers[I].CreatedAt);
      Exit;
    end;
  end;
end;

function TMockUserRepository.CreateUser(const AUsername, APasswordHash, ASalt: string;
  ARole: TUserRole): TResult<TUser>;
var
  LUser: TUser;
  LReturn: TUser;
begin
  Inc(FCreateUserCalls);
  LUser := TUser.Hydrate(FNextId, AUsername, APasswordHash, ASalt, ARole, Now);
  Inc(FNextId);
  FUsers.Add(LUser);

  LReturn := TUser.Hydrate(LUser.Id, LUser.Username, LUser.PasswordHash,
    LUser.Salt, LUser.Role, LUser.CreatedAt);
  Result := TResult<TUser>.Success(LReturn);
end;

function TMockUserRepository.UpdateUser(AUser: TUser): TResult;
var
  I: Integer;
begin
  Inc(FUpdateUserCalls);
  for I := 0 to FUsers.Count - 1 do
  begin
    if FUsers[I].Id = AUser.Id then
    begin
      // Update stored user
      FUsers[I].ChangePassword(AUser.PasswordHash, AUser.Salt);
      FUsers[I].ChangeRole(AUser.Role);
      Result := TResult.Success;
      Exit;
    end;
  end;
  Result := TResult.Failure('User not found');
end;

function TMockUserRepository.DeleteUser(AUserId: Integer): TResult;
var
  I: Integer;
begin
  Inc(FDeleteUserCalls);
  for I := 0 to FUsers.Count - 1 do
  begin
    if FUsers[I].Id = AUserId then
    begin
      FUsers[I].Free;
      FUsers.Delete(I);
      Result := TResult.Success;
      Exit;
    end;
  end;
  Result := TResult.Failure('User not found');
end;

function TMockUserRepository.GetAllUsers: TList<TUser>;
var
  I: Integer;
begin
  Result := TObjectList<TUser>.Create(True);
  for I := 0 to FUsers.Count - 1 do
    Result.Add(TUser.Hydrate(FUsers[I].Id, FUsers[I].Username,
      FUsers[I].PasswordHash, FUsers[I].Salt, FUsers[I].Role, FUsers[I].CreatedAt));
end;

function TMockUserRepository.GetAllUsersPaged(APageNum, APageSize: Integer): TList<TUser>;
var
  LStart, LEnd, I: Integer;
begin
  Result := TObjectList<TUser>.Create(True);
  LStart := (APageNum - 1) * APageSize;
  LEnd := LStart + APageSize - 1;
  for I := LStart to LEnd do
  begin
    if I >= FUsers.Count then Break;
    Result.Add(TUser.Hydrate(FUsers[I].Id, FUsers[I].Username,
      FUsers[I].PasswordHash, FUsers[I].Salt, FUsers[I].Role, FUsers[I].CreatedAt));
  end;
end;

function TMockUserRepository.GetUserCount: Integer;
begin
  Result := FUsers.Count;
end;

{ TMockTaskRepository }

constructor TMockTaskRepository.Create;
begin
  inherited Create;
  FTasks := TObjectList<TTask>.Create(False);
  FNextId := 1;
end;

destructor TMockTaskRepository.Destroy;
var
  I: Integer;
begin
  for I := 0 to FTasks.Count - 1 do
    FTasks[I].Free;
  FTasks.Free;
  inherited;
end;

procedure TMockTaskRepository.SeedTask(AId, AUserId: Integer; const ATitle: string;
  AStatus: TTaskStatus);
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(AId, AUserId, ATitle, '', AStatus, Now, 0);
  FTasks.Add(LTask);
  if AId >= FNextId then
    FNextId := AId + 1;
end;

function TMockTaskRepository.GetTaskById(ATaskId: Integer): TTask;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FTasks.Count - 1 do
  begin
    if FTasks[I].Id = ATaskId then
    begin
      Result := TTask.Hydrate(FTasks[I].Id, FTasks[I].UserId, FTasks[I].Title,
        FTasks[I].Description, FTasks[I].Status, FTasks[I].CreatedAt, FTasks[I].UpdatedAt);
      Exit;
    end;
  end;
end;

function TMockTaskRepository.GetTasksByUserId(AUserId: Integer): TList<TTask>;
var
  I: Integer;
begin
  Result := TObjectList<TTask>.Create(True);
  for I := 0 to FTasks.Count - 1 do
  begin
    if FTasks[I].UserId = AUserId then
      Result.Add(TTask.Hydrate(FTasks[I].Id, FTasks[I].UserId, FTasks[I].Title,
        FTasks[I].Description, FTasks[I].Status, FTasks[I].CreatedAt, FTasks[I].UpdatedAt));
  end;
end;

function TMockTaskRepository.GetTasksByUserIdWithFilter(AUserId: Integer;
  const AStatusFilter: string): TList<TTask>;
var
  I: Integer;
  LStatus: TTaskStatus;
begin
  Result := TObjectList<TTask>.Create(True);
  for I := 0 to FTasks.Count - 1 do
  begin
    if FTasks[I].UserId <> AUserId then Continue;
    if AStatusFilter <> '' then
    begin
      LStatus := StringToStatus(AStatusFilter);
      if FTasks[I].Status <> LStatus then Continue;
    end;
    Result.Add(TTask.Hydrate(FTasks[I].Id, FTasks[I].UserId, FTasks[I].Title,
      FTasks[I].Description, FTasks[I].Status, FTasks[I].CreatedAt, FTasks[I].UpdatedAt));
  end;
end;

function TMockTaskRepository.GetTasksByUserIdPaged(AUserId: Integer;
  APageNum, APageSize: Integer): TList<TTask>;
var
  LAll: TList<TTask>;
  LStart, LEnd, I: Integer;
begin
  LAll := GetTasksByUserId(AUserId);
  try
    Result := TObjectList<TTask>.Create(True);
    LStart := (APageNum - 1) * APageSize;
    LEnd := LStart + APageSize - 1;
    for I := LStart to LEnd do
    begin
      if I >= LAll.Count then Break;
      Result.Add(TTask.Hydrate(LAll[I].Id, LAll[I].UserId, LAll[I].Title,
        LAll[I].Description, LAll[I].Status, LAll[I].CreatedAt, LAll[I].UpdatedAt));
    end;
  finally
    LAll.Free;
  end;
end;

function TMockTaskRepository.GetAllTasks: TList<TTask>;
var
  I: Integer;
begin
  Result := TObjectList<TTask>.Create(True);
  for I := 0 to FTasks.Count - 1 do
    Result.Add(TTask.Hydrate(FTasks[I].Id, FTasks[I].UserId, FTasks[I].Title,
      FTasks[I].Description, FTasks[I].Status, FTasks[I].CreatedAt, FTasks[I].UpdatedAt));
end;

function TMockTaskRepository.GetAllTasksWithFilter(const AStatusFilter: string): TList<TTask>;
var
  I: Integer;
  LStatus: TTaskStatus;
begin
  Result := TObjectList<TTask>.Create(True);
  for I := 0 to FTasks.Count - 1 do
  begin
    if AStatusFilter <> '' then
    begin
      LStatus := StringToStatus(AStatusFilter);
      if FTasks[I].Status <> LStatus then Continue;
    end;
    Result.Add(TTask.Hydrate(FTasks[I].Id, FTasks[I].UserId, FTasks[I].Title,
      FTasks[I].Description, FTasks[I].Status, FTasks[I].CreatedAt, FTasks[I].UpdatedAt));
  end;
end;

function TMockTaskRepository.GetAllTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
var
  LStart, LEnd, I: Integer;
begin
  Result := TObjectList<TTask>.Create(True);
  LStart := (APageNum - 1) * APageSize;
  LEnd := LStart + APageSize - 1;
  for I := LStart to LEnd do
  begin
    if I >= FTasks.Count then Break;
    Result.Add(TTask.Hydrate(FTasks[I].Id, FTasks[I].UserId, FTasks[I].Title,
      FTasks[I].Description, FTasks[I].Status, FTasks[I].CreatedAt, FTasks[I].UpdatedAt));
  end;
end;

function TMockTaskRepository.GetTaskCountByUserId(AUserId: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FTasks.Count - 1 do
    if FTasks[I].UserId = AUserId then
      Inc(Result);
end;

function TMockTaskRepository.GetAllTasksCount: Integer;
begin
  Result := FTasks.Count;
end;

function TMockTaskRepository.CreateTask(AUserId: Integer;
  const ATitle, ADescription: string): TResult<TTask>;
var
  LTask, LReturn: TTask;
begin
  Inc(FCreateTaskCalls);
  LTask := TTask.Hydrate(FNextId, AUserId, ATitle, ADescription, tsPending, Now, 0);
  Inc(FNextId);
  FTasks.Add(LTask);

  LReturn := TTask.Hydrate(LTask.Id, LTask.UserId, LTask.Title,
    LTask.Description, LTask.Status, LTask.CreatedAt, LTask.UpdatedAt);
  Result := TResult<TTask>.Success(LReturn);
end;

function TMockTaskRepository.UpdateTask(ATask: TTask): TResult;
begin
  Inc(FUpdateTaskCalls);
  Result := TResult.Success;
end;

function TMockTaskRepository.DeleteTask(ATaskId: Integer): TResult;
var
  I: Integer;
begin
  Inc(FDeleteTaskCalls);
  for I := 0 to FTasks.Count - 1 do
  begin
    if FTasks[I].Id = ATaskId then
    begin
      FTasks[I].Free;
      FTasks.Delete(I);
      Result := TResult.Success;
      Exit;
    end;
  end;
  Result := TResult.Failure('Task not found');
end;

function TMockTaskRepository.DeleteCompletedTasks(ADaysOld: Integer): Integer;
begin
  Result := 0;
end;

function TMockTaskRepository.BulkTouchUpdatedAt: Integer;
begin
  Inc(FBulkTouchCalls);
  Result := FTasks.Count;
end;

{ TMockPermissionGuard }

constructor TMockPermissionGuard.Create(AAlwaysAllow: Boolean);
begin
  inherited Create;
  FAlwaysAllow := AAlwaysAllow;
end;

function TMockPermissionGuard.CanViewTask(ATask: TTask): TResult;
begin
  if FAlwaysAllow then
    Result := TResult.Success
  else
    Result := TResult.Failure('Permission denied');
end;

function TMockPermissionGuard.CanEditTask(ATask: TTask): TResult;
begin
  if FAlwaysAllow then
    Result := TResult.Success
  else
    Result := TResult.Failure('Permission denied');
end;

function TMockPermissionGuard.CanDeleteTask(ATask: TTask): TResult;
begin
  if FAlwaysAllow then
    Result := TResult.Success
  else
    Result := TResult.Failure('Permission denied');
end;

function TMockPermissionGuard.CanManageUsers: TResult;
begin
  if FAlwaysAllow then
    Result := TResult.Success
  else
    Result := TResult.Failure('Permission denied: Only admins can manage users');
end;

{ TMockAuthenticationService }

constructor TMockAuthenticationService.Create;
begin
  inherited Create;
  FPasswordPolicyValid := True;
  FPasswordPolicyError := 'Password does not meet policy requirements';
  FSaltValue := 'mocksalt';
  FHashPrefix := 'hashed_';
  FLoginCalls := 0;
  FRegisterCalls := 0;
end;

function TMockAuthenticationService.Login(const AUsername, APassword: string): TResult;
begin
  Inc(FLoginCalls);
  Result := TResult.Success;
end;

function TMockAuthenticationService.Register(const AUsername, APassword: string): TResult<TUser>;
var
  LUser: TUser;
begin
  Inc(FRegisterCalls);
  LUser := TUser.CreateNew(AUsername, HashPasswordKDF(APassword, GenerateSalt), GenerateSalt, urUser);
  LUser.AssignId(1);
  Result := TResult<TUser>.Success(LUser);
end;

procedure TMockAuthenticationService.Logout;
begin
  // no-op
end;

function TMockAuthenticationService.IsAuthenticated: Boolean;
begin
  Result := False;
end;

function TMockAuthenticationService.HashPasswordKDF(const APassword, ASalt: string;
  AIterations: Integer): string;
begin
  Result := FHashPrefix + APassword + ASalt;
end;

function TMockAuthenticationService.GenerateSalt: string;
begin
  Result := FSaltValue;
end;

function TMockAuthenticationService.ValidatePasswordPolicy(const APassword: string): TResult;
begin
  if FPasswordPolicyValid then
    Result := TResult.Success
  else
    Result := TResult.Failure(FPasswordPolicyError);
end;

function TMockAuthenticationService.GetCurrentUsername: string;
begin
  Result := '';
end;

function TMockAuthenticationService.GetCurrentUserId: Integer;
begin
  Result := 0;
end;

function TMockAuthenticationService.IsCurrentUserAdmin: Boolean;
begin
  Result := False;
end;

end.
