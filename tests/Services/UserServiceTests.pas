unit UserServiceTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  Result,
  UserService,
  MockInterfaces;

{
  UserServiceTests.pas
  ---------------------
  Unit tests for TUserService business logic.
  Uses mock implementations for all dependencies:
  - TMockUserRepository: in-memory user store
  - TMockAuthenticationService: stub hashing/validation
  - TMockPermissionGuard: configurable allow/deny
  - TMockSecurityContextProvider: simulated auth context
  - TMockLogger: captured log messages

  Tests verify:
  - GetAllUsers returns empty when permission denied, full list when admin
  - CreateUser validates inputs, checks policy, delegates to repository
  - UpdateUser with and without password change
  - DeleteUser permission and delegation
  - GetUserById and GetUserCount permission gating
}

type
  [TestFixture]
  TUserServiceTests = class
  private
    FService: IUserService;
    FMockUserRepo: TMockUserRepository;
    FMockAuthService: TMockAuthenticationService;
    FMockGuard: TMockPermissionGuard;
    FMockProvider: TMockSecurityContextProvider;
    FMockLogger: TMockLogger;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- GetAllUsers ---
    [Test]
    procedure GetAllUsers_PermissionDenied_ReturnsEmpty;
    [Test]
    procedure GetAllUsers_Admin_ReturnsAll;

    // --- GetUserCount ---
    [Test]
    procedure GetUserCount_PermissionDenied_ReturnsZero;
    [Test]
    procedure GetUserCount_Admin_ReturnsCount;

    // --- GetUserById ---
    [Test]
    procedure GetUserById_PermissionDenied_ReturnsNil;
    [Test]
    procedure GetUserById_Admin_ReturnsUser;
    [Test]
    procedure GetUserById_NotFound_ReturnsNil;

    // --- CreateUser ---
    [Test]
    procedure CreateUser_PermissionDenied_Fails;
    [Test]
    procedure CreateUser_EmptyUsername_Fails;
    [Test]
    procedure CreateUser_EmptyPassword_Fails;
    [Test]
    procedure CreateUser_PolicyViolation_Fails;
    [Test]
    procedure CreateUser_Valid_Succeeds;
    [Test]
    procedure CreateUser_Valid_HashesPasswordWithSalt;

    // --- UpdateUser ---
    [Test]
    procedure UpdateUser_PermissionDenied_Fails;
    [Test]
    procedure UpdateUser_NilUser_Fails;
    [Test]
    procedure UpdateUser_NoPasswordChange_Succeeds;
    [Test]
    procedure UpdateUser_WithPasswordChange_UpdatesCredential;

    // --- DeleteUser ---
    [Test]
    procedure DeleteUser_PermissionDenied_Fails;
    [Test]
    procedure DeleteUser_Valid_Succeeds;
    [Test]
    procedure DeleteUser_NotFound_Fails;

    // --- GetAllUsersPaged ---
    [Test]
    procedure GetAllUsersPaged_PermissionDenied_ReturnsEmpty;
    [Test]
    procedure GetAllUsersPaged_Admin_ReturnsPage;
  end;

implementation

{ TUserServiceTests }

procedure TUserServiceTests.Setup;
begin
  FMockUserRepo := TMockUserRepository.Create;
  FMockAuthService := TMockAuthenticationService.Create;
  FMockGuard := TMockPermissionGuard.Create(True); // Allow by default
  FMockProvider := TMockSecurityContextProvider.Create;
  FMockLogger := TMockLogger.Create;

  // Seed some users
  FMockUserRepo.SeedUser(1, 'admin', 'hash_admin', 'salt1', urAdmin);
  FMockUserRepo.SeedUser(2, 'user1', 'hash_user1', 'salt2', urUser);
  FMockUserRepo.SeedUser(3, 'user2', 'hash_user2', 'salt3', urUser);

  FMockProvider.LoginAsAdmin(1, 'admin');

  FService := TUserService.Create(
    FMockUserRepo,
    FMockAuthService,
    FMockGuard,
    FMockProvider,
    FMockLogger
  );
end;

procedure TUserServiceTests.TearDown;
begin
  FService := nil;
end;

// --- GetAllUsers ---

procedure TUserServiceTests.GetAllUsers_PermissionDenied_ReturnsEmpty;
var
  LUsers: TList<TUser>;
begin
  FMockGuard.AlwaysAllow := False;

  LUsers := FService.GetAllUsers;
  try
    Assert.AreEqual(0, LUsers.Count);
  finally
    LUsers.Free;
  end;
end;

procedure TUserServiceTests.GetAllUsers_Admin_ReturnsAll;
var
  LUsers: TList<TUser>;
begin
  LUsers := FService.GetAllUsers;
  try
    Assert.AreEqual(3, LUsers.Count);
  finally
    LUsers.Free;
  end;
end;

// --- GetUserCount ---

procedure TUserServiceTests.GetUserCount_PermissionDenied_ReturnsZero;
begin
  FMockGuard.AlwaysAllow := False;
  Assert.AreEqual(0, FService.GetUserCount);
end;

procedure TUserServiceTests.GetUserCount_Admin_ReturnsCount;
begin
  Assert.AreEqual(3, FService.GetUserCount);
end;

// --- GetUserById ---

procedure TUserServiceTests.GetUserById_PermissionDenied_ReturnsNil;
var
  LUser: TUser;
begin
  FMockGuard.AlwaysAllow := False;
  LUser := FService.GetUserById(1);
  Assert.IsNull(LUser);
end;

procedure TUserServiceTests.GetUserById_Admin_ReturnsUser;
var
  LUser: TUser;
begin
  LUser := FService.GetUserById(1);
  try
    Assert.IsNotNull(LUser);
    Assert.AreEqual('admin', LUser.Username);
  finally
    LUser.Free;
  end;
end;

procedure TUserServiceTests.GetUserById_NotFound_ReturnsNil;
var
  LUser: TUser;
begin
  LUser := FService.GetUserById(999);
  Assert.IsNull(LUser);
end;

// --- CreateUser ---

procedure TUserServiceTests.CreateUser_PermissionDenied_Fails;
var
  LResult: TResult<TUser>;
begin
  FMockGuard.AlwaysAllow := False;
  LResult := FService.CreateUser('newuser', 'Password1!', urUser);
  Assert.IsFalse(LResult.IsSuccess);
end;

procedure TUserServiceTests.CreateUser_EmptyUsername_Fails;
var
  LResult: TResult<TUser>;
begin
  LResult := FService.CreateUser('', 'Password1!', urUser);
  Assert.IsFalse(LResult.IsSuccess);
  Assert.AreEqual('Username cannot be empty', LResult.GetErrorMessage);
end;

procedure TUserServiceTests.CreateUser_EmptyPassword_Fails;
var
  LResult: TResult<TUser>;
begin
  LResult := FService.CreateUser('newuser', '', urUser);
  Assert.IsFalse(LResult.IsSuccess);
  Assert.AreEqual('Password cannot be empty', LResult.GetErrorMessage);
end;

procedure TUserServiceTests.CreateUser_PolicyViolation_Fails;
var
  LResult: TResult<TUser>;
begin
  FMockAuthService.PasswordPolicyValid := False;
  FMockAuthService.PasswordPolicyError := 'Password too weak';

  LResult := FService.CreateUser('newuser', 'weak', urUser);
  Assert.IsFalse(LResult.IsSuccess);
  Assert.AreEqual('Password too weak', LResult.GetErrorMessage);
end;

procedure TUserServiceTests.CreateUser_Valid_Succeeds;
var
  LResult: TResult<TUser>;
begin
  LResult := FService.CreateUser('newuser', 'StrongP@ss1', urUser);
  try
    Assert.IsTrue(LResult.IsSuccess, 'CreateUser should succeed');
    Assert.IsNotNull(LResult.Value);
    Assert.AreEqual('newuser', LResult.Value.Username);
    Assert.AreEqual(1, FMockUserRepo.CreateUserCalls);
  finally
    LResult.Value.Free;
  end;
end;

procedure TUserServiceTests.CreateUser_Valid_HashesPasswordWithSalt;
var
  LResult: TResult<TUser>;
begin
  FMockAuthService.SaltValue := 'testsalt';
  FMockAuthService.HashPrefix := 'KDF_';

  LResult := FService.CreateUser('hashtest', 'MyPassword', urUser);
  try
    Assert.IsTrue(LResult.IsSuccess);
    // MockAuthService.HashPasswordKDF returns: HashPrefix + Password + Salt
    // The repo receives the hash from AuthService
    Assert.AreEqual('KDF_MyPasswordtestsalt', LResult.Value.PasswordHash);
    Assert.AreEqual('testsalt', LResult.Value.Salt);
  finally
    LResult.Value.Free;
  end;
end;

// --- UpdateUser ---

procedure TUserServiceTests.UpdateUser_PermissionDenied_Fails;
var
  LUser: TUser;
  LResult: TResult;
begin
  FMockGuard.AlwaysAllow := False;
  LUser := TUser.Hydrate(2, 'user1', 'hash', 'salt', urUser, Now);
  try
    LResult := FService.UpdateUser(LUser, '');
    Assert.IsFalse(LResult.IsSuccess);
  finally
    LUser.Free;
  end;
end;

procedure TUserServiceTests.UpdateUser_NilUser_Fails;
var
  LResult: TResult;
begin
  LResult := FService.UpdateUser(nil, '');
  Assert.IsFalse(LResult.IsSuccess);
  Assert.AreEqual('User cannot be nil', LResult.GetErrorMessage);
end;

procedure TUserServiceTests.UpdateUser_NoPasswordChange_Succeeds;
var
  LUser: TUser;
  LResult: TResult;
begin
  LUser := TUser.Hydrate(2, 'user1', 'hash_user1', 'salt2', urUser, Now);
  try
    LResult := FService.UpdateUser(LUser, '');
    Assert.IsTrue(LResult.IsSuccess, 'UpdateUser without password change should succeed');
    Assert.AreEqual(1, FMockUserRepo.UpdateUserCalls);
    // Password should remain unchanged
    Assert.AreEqual('hash_user1', LUser.PasswordHash);
  finally
    LUser.Free;
  end;
end;

procedure TUserServiceTests.UpdateUser_WithPasswordChange_UpdatesCredential;
var
  LUser: TUser;
  LResult: TResult;
begin
  FMockAuthService.SaltValue := 'newsalt';
  FMockAuthService.HashPrefix := 'KDF_';

  LUser := TUser.Hydrate(2, 'user1', 'old_hash', 'old_salt', urUser, Now);
  try
    LResult := FService.UpdateUser(LUser, 'NewPass123');
    Assert.IsTrue(LResult.IsSuccess, 'UpdateUser with password should succeed');
    // ChangePassword should have been called via domain method
    Assert.AreEqual('KDF_NewPass123newsalt', LUser.PasswordHash);
    Assert.AreEqual('newsalt', LUser.Salt);
  finally
    LUser.Free;
  end;
end;

// --- DeleteUser ---

procedure TUserServiceTests.DeleteUser_PermissionDenied_Fails;
var
  LResult: TResult;
begin
  FMockGuard.AlwaysAllow := False;
  LResult := FService.DeleteUser(2);
  Assert.IsFalse(LResult.IsSuccess);
end;

procedure TUserServiceTests.DeleteUser_Valid_Succeeds;
var
  LResult: TResult;
begin
  LResult := FService.DeleteUser(2);
  Assert.IsTrue(LResult.IsSuccess, 'DeleteUser should succeed for existing user');
  Assert.AreEqual(1, FMockUserRepo.DeleteUserCalls);
end;

procedure TUserServiceTests.DeleteUser_NotFound_Fails;
var
  LResult: TResult;
begin
  LResult := FService.DeleteUser(999);
  Assert.IsFalse(LResult.IsSuccess, 'DeleteUser should fail for non-existent user');
end;

// --- GetAllUsersPaged ---

procedure TUserServiceTests.GetAllUsersPaged_PermissionDenied_ReturnsEmpty;
var
  LUsers: TList<TUser>;
begin
  FMockGuard.AlwaysAllow := False;
  LUsers := FService.GetAllUsersPaged(1, 10);
  try
    Assert.AreEqual(0, LUsers.Count);
  finally
    LUsers.Free;
  end;
end;

procedure TUserServiceTests.GetAllUsersPaged_Admin_ReturnsPage;
var
  LUsers: TList<TUser>;
begin
  LUsers := FService.GetAllUsersPaged(1, 2);
  try
    Assert.AreEqual(2, LUsers.Count, 'Should return page of 2 users');
  finally
    LUsers.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUserServiceTests);

end.
