unit PermissionGuardTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  AppInterfaces,
  DomainModels,
  Result,
  PermissionGuard,
  MockInterfaces;

{
  PermissionGuardTests.pas
  -------------------------
  Unit tests for TPermissionGuard role-based access control logic.
  Uses TMockSecurityContextProvider to simulate different user contexts.

  Tests verify:
  - Unauthenticated access is denied for all operations
  - Admin can view/edit/delete any task and manage users
  - Regular user can only view/edit/delete own tasks
  - Regular user cannot manage users
}

type
  [TestFixture]
  TPermissionGuardTests = class
  private
    FGuard: IPermissionGuard;
    FMockProvider: TMockSecurityContextProvider;
    FMockLogger: TMockLogger;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- Not authenticated ---
    [Test]
    procedure CanViewTask_NotAuthenticated_Fails;
    [Test]
    procedure CanEditTask_NotAuthenticated_Fails;
    [Test]
    procedure CanDeleteTask_NotAuthenticated_Fails;
    [Test]
    procedure CanManageUsers_NotAuthenticated_Fails;

    // --- Admin access ---
    [Test]
    procedure CanViewTask_Admin_OtherUserTask_Allowed;
    [Test]
    procedure CanEditTask_Admin_OtherUserTask_Allowed;
    [Test]
    procedure CanDeleteTask_Admin_OtherUserTask_Allowed;
    [Test]
    procedure CanManageUsers_Admin_Allowed;

    // --- User access: own tasks ---
    [Test]
    procedure CanViewTask_User_OwnTask_Allowed;
    [Test]
    procedure CanEditTask_User_OwnTask_Allowed;
    [Test]
    procedure CanDeleteTask_User_OwnTask_Allowed;

    // --- User access: other's tasks ---
    [Test]
    procedure CanViewTask_User_OtherTask_Denied;
    [Test]
    procedure CanEditTask_User_OtherTask_Denied;
    [Test]
    procedure CanDeleteTask_User_OtherTask_Denied;

    // --- User cannot manage users ---
    [Test]
    procedure CanManageUsers_User_Denied;
  end;

implementation

{ TPermissionGuardTests }

procedure TPermissionGuardTests.Setup;
begin
  FMockProvider := TMockSecurityContextProvider.Create;
  FMockLogger := TMockLogger.Create;
  FGuard := TPermissionGuard.Create(FMockProvider, FMockLogger);
end;

procedure TPermissionGuardTests.TearDown;
begin
  FGuard := nil;
end;

// --- Not authenticated ---

procedure TPermissionGuardTests.CanViewTask_NotAuthenticated_Fails;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.Logout;
  LTask := TTask.CreateNew(1, 'Test');
  try
    LResult := FGuard.CanViewTask(LTask);
    Assert.IsFalse(LResult.IsSuccess);
    Assert.AreEqual('Not authenticated', LResult.GetErrorMessage);
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanEditTask_NotAuthenticated_Fails;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.Logout;
  LTask := TTask.CreateNew(1, 'Test');
  try
    LResult := FGuard.CanEditTask(LTask);
    Assert.IsFalse(LResult.IsSuccess);
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanDeleteTask_NotAuthenticated_Fails;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.Logout;
  LTask := TTask.CreateNew(1, 'Test');
  try
    LResult := FGuard.CanDeleteTask(LTask);
    Assert.IsFalse(LResult.IsSuccess);
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanManageUsers_NotAuthenticated_Fails;
var
  LResult: TResult;
begin
  FMockProvider.Logout;
  LResult := FGuard.CanManageUsers;
  Assert.IsFalse(LResult.IsSuccess);
end;

// --- Admin access ---

procedure TPermissionGuardTests.CanViewTask_Admin_OtherUserTask_Allowed;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.LoginAsAdmin(1, 'admin');
  LTask := TTask.Hydrate(10, 99, 'Other Task', '', tsPending, Now, 0);
  try
    LResult := FGuard.CanViewTask(LTask);
    Assert.IsTrue(LResult.IsSuccess, 'Admin should view any task');
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanEditTask_Admin_OtherUserTask_Allowed;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.LoginAsAdmin(1, 'admin');
  LTask := TTask.Hydrate(10, 99, 'Other Task', '', tsPending, Now, 0);
  try
    LResult := FGuard.CanEditTask(LTask);
    Assert.IsTrue(LResult.IsSuccess, 'Admin should edit any task');
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanDeleteTask_Admin_OtherUserTask_Allowed;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.LoginAsAdmin(1, 'admin');
  LTask := TTask.Hydrate(10, 99, 'Other Task', '', tsPending, Now, 0);
  try
    LResult := FGuard.CanDeleteTask(LTask);
    Assert.IsTrue(LResult.IsSuccess, 'Admin should delete any task');
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanManageUsers_Admin_Allowed;
var
  LResult: TResult;
begin
  FMockProvider.LoginAsAdmin(1, 'admin');
  LResult := FGuard.CanManageUsers;
  Assert.IsTrue(LResult.IsSuccess, 'Admin should manage users');
end;

// --- User access: own tasks ---

procedure TPermissionGuardTests.CanViewTask_User_OwnTask_Allowed;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LTask := TTask.Hydrate(10, 2, 'My Task', '', tsPending, Now, 0);
  try
    LResult := FGuard.CanViewTask(LTask);
    Assert.IsTrue(LResult.IsSuccess, 'User should view own task');
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanEditTask_User_OwnTask_Allowed;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LTask := TTask.Hydrate(10, 2, 'My Task', '', tsPending, Now, 0);
  try
    LResult := FGuard.CanEditTask(LTask);
    Assert.IsTrue(LResult.IsSuccess, 'User should edit own task');
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanDeleteTask_User_OwnTask_Allowed;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LTask := TTask.Hydrate(10, 2, 'My Task', '', tsPending, Now, 0);
  try
    LResult := FGuard.CanDeleteTask(LTask);
    Assert.IsTrue(LResult.IsSuccess, 'User should delete own task');
  finally
    LTask.Free;
  end;
end;

// --- User access: other's tasks ---

procedure TPermissionGuardTests.CanViewTask_User_OtherTask_Denied;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LTask := TTask.Hydrate(10, 99, 'Other Task', '', tsPending, Now, 0);
  try
    LResult := FGuard.CanViewTask(LTask);
    Assert.IsFalse(LResult.IsSuccess, 'User should not view other''s task');
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanEditTask_User_OtherTask_Denied;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LTask := TTask.Hydrate(10, 99, 'Other Task', '', tsPending, Now, 0);
  try
    LResult := FGuard.CanEditTask(LTask);
    Assert.IsFalse(LResult.IsSuccess, 'User should not edit other''s task');
  finally
    LTask.Free;
  end;
end;

procedure TPermissionGuardTests.CanDeleteTask_User_OtherTask_Denied;
var
  LTask: TTask;
  LResult: TResult;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LTask := TTask.Hydrate(10, 99, 'Other Task', '', tsPending, Now, 0);
  try
    LResult := FGuard.CanDeleteTask(LTask);
    Assert.IsFalse(LResult.IsSuccess, 'User should not delete other''s task');
  finally
    LTask.Free;
  end;
end;

// --- User cannot manage users ---

procedure TPermissionGuardTests.CanManageUsers_User_Denied;
var
  LResult: TResult;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LResult := FGuard.CanManageUsers;
  Assert.IsFalse(LResult.IsSuccess, 'Regular user should not manage users');
end;

initialization
  TDUnitX.RegisterTestFixture(TPermissionGuardTests);

end.
