unit TaskServiceTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  Result,
  TaskService,
  MockInterfaces;

{
  TaskServiceTests.pas
  --------------------
  Unit tests for TTaskService business logic. Uses mock implementations
  of ITaskRepository, IPermissionGuard, ISecurityContextProvider, and ILogger.

  Tests verify:
  - Authentication checks (unauthenticated returns empty/fails)
  - Permission enforcement (admin vs user access)
  - Task CRUD delegation to repository
  - Status transition validation via domain methods
  - System-level methods bypass security
}

type
  [TestFixture]
  TTaskServiceTests = class
  private
    FService: ITaskService;
    FMockRepo: TMockTaskRepository;
    FMockGuard: TMockPermissionGuard;
    FMockProvider: TMockSecurityContextProvider;
    FMockLogger: TMockLogger;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- GetMyTasks ---
    [Test]
    procedure GetMyTasks_NotAuthenticated_ReturnsEmptyList;
    [Test]
    procedure GetMyTasks_Authenticated_ReturnsTasks;

    // --- GetAllTasks ---
    [Test]
    procedure GetAllTasks_NotAuthenticated_ReturnsEmptyList;
    [Test]
    procedure GetAllTasks_RegularUser_ReturnsEmptyList;
    [Test]
    procedure GetAllTasks_Admin_ReturnsAllTasks;

    // --- CreateTask ---
    [Test]
    procedure CreateTask_NotAuthenticated_Fails;
    [Test]
    procedure CreateTask_EmptyTitle_Fails;
    [Test]
    procedure CreateTask_ValidInput_Succeeds;

    // --- DeleteTask ---
    [Test]
    procedure DeleteTask_NotFound_Fails;
    [Test]
    procedure DeleteTask_PermissionDenied_Fails;
    [Test]
    procedure DeleteTask_Allowed_Succeeds;

    // --- UpdateTaskStatus ---
    [Test]
    procedure UpdateTaskStatus_InvalidTransition_Fails;
    [Test]
    procedure UpdateTaskStatus_ValidTransition_Succeeds;

    // --- System methods ---
    [Test]
    procedure SystemGetAllTasks_BypassesSecurity;
    [Test]
    procedure SystemDeleteTask_BypassesSecurity;
    [Test]
    procedure SystemBulkTouchUpdatedAt_CallsRepo;

    // --- GetTaskById ---
    [Test]
    procedure GetTaskById_NotFound_ReturnsNil;
    [Test]
    procedure GetTaskById_PermissionDenied_ReturnsNil;
    [Test]
    procedure GetTaskById_Allowed_ReturnsTask;

    // --- Counts ---
    [Test]
    procedure GetMyTaskCount_NotAuthenticated_ReturnsZero;
    [Test]
    procedure GetMyTaskCount_Authenticated_ReturnsCount;
    [Test]
    procedure GetAllTaskCount_NotAdmin_ReturnsZero;
    [Test]
    procedure GetAllTaskCount_Admin_ReturnsCount;
  end;

implementation

{ TTaskServiceTests }

procedure TTaskServiceTests.Setup;
begin
  FMockRepo := TMockTaskRepository.Create;
  FMockGuard := TMockPermissionGuard.Create(True);
  FMockProvider := TMockSecurityContextProvider.Create;
  FMockLogger := TMockLogger.Create;

  FService := TTaskService.Create(
    FMockRepo,
    FMockGuard,
    FMockProvider,
    FMockLogger
  );

  // Seed some test data
  FMockRepo.SeedTask(1, 2, 'User Task 1', tsPending);
  FMockRepo.SeedTask(2, 2, 'User Task 2', tsInProgress);
  FMockRepo.SeedTask(3, 3, 'Other User Task', tsDone);
end;

procedure TTaskServiceTests.TearDown;
begin
  FService := nil;
  // Interfaces release automatically
end;

// --- GetMyTasks ---

procedure TTaskServiceTests.GetMyTasks_NotAuthenticated_ReturnsEmptyList;
var
  LTasks: TList<TTask>;
begin
  FMockProvider.Logout;
  LTasks := FService.GetMyTasks;
  try
    Assert.AreEqual(0, LTasks.Count);
  finally
    LTasks.Free;
  end;
end;

procedure TTaskServiceTests.GetMyTasks_Authenticated_ReturnsTasks;
var
  LTasks: TList<TTask>;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LTasks := FService.GetMyTasks;
  try
    Assert.AreEqual(2, LTasks.Count, 'User 2 should have 2 tasks');
  finally
    LTasks.Free;
  end;
end;

// --- GetAllTasks ---

procedure TTaskServiceTests.GetAllTasks_NotAuthenticated_ReturnsEmptyList;
var
  LTasks: TList<TTask>;
begin
  FMockProvider.Logout;
  LTasks := FService.GetAllTasks;
  try
    Assert.AreEqual(0, LTasks.Count);
  finally
    LTasks.Free;
  end;
end;

procedure TTaskServiceTests.GetAllTasks_RegularUser_ReturnsEmptyList;
var
  LTasks: TList<TTask>;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LTasks := FService.GetAllTasks;
  try
    Assert.AreEqual(0, LTasks.Count, 'Regular user should not see all tasks');
  finally
    LTasks.Free;
  end;
end;

procedure TTaskServiceTests.GetAllTasks_Admin_ReturnsAllTasks;
var
  LTasks: TList<TTask>;
begin
  FMockProvider.LoginAsAdmin(1, 'admin');
  LTasks := FService.GetAllTasks;
  try
    Assert.AreEqual(3, LTasks.Count, 'Admin should see all 3 tasks');
  finally
    LTasks.Free;
  end;
end;

// --- CreateTask ---

procedure TTaskServiceTests.CreateTask_NotAuthenticated_Fails;
var
  LResult: TResult<TTask>;
begin
  FMockProvider.Logout;
  LResult := FService.CreateTask('New Task');
  Assert.IsFalse(LResult.IsSuccess);
  Assert.AreEqual('Not authenticated', LResult.GetErrorMessage);
end;

procedure TTaskServiceTests.CreateTask_EmptyTitle_Fails;
var
  LResult: TResult<TTask>;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LResult := FService.CreateTask('');
  Assert.IsFalse(LResult.IsSuccess);
  Assert.AreEqual('Title cannot be empty', LResult.GetErrorMessage);
end;

procedure TTaskServiceTests.CreateTask_ValidInput_Succeeds;
var
  LResult: TResult<TTask>;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  LResult := FService.CreateTask('Brand New Task', 'Description');
  Assert.IsTrue(LResult.IsSuccess);
  Assert.AreEqual('Brand New Task', LResult.GetValue.Title);
  Assert.AreEqual(1, FMockRepo.CreateTaskCalls);
  LResult.GetValue.Free;
end;

// --- DeleteTask ---

procedure TTaskServiceTests.DeleteTask_NotFound_Fails;
var
  LResult: TResult;
begin
  LResult := FService.DeleteTask(999);
  Assert.IsFalse(LResult.IsSuccess);
  Assert.AreEqual('Task not found', LResult.GetErrorMessage);
end;

procedure TTaskServiceTests.DeleteTask_PermissionDenied_Fails;
var
  LResult: TResult;
begin
  FMockGuard.AlwaysAllow := False;
  LResult := FService.DeleteTask(1);
  Assert.IsFalse(LResult.IsSuccess);
end;

procedure TTaskServiceTests.DeleteTask_Allowed_Succeeds;
var
  LResult: TResult;
begin
  FMockGuard.AlwaysAllow := True;
  LResult := FService.DeleteTask(1);
  Assert.IsTrue(LResult.IsSuccess);
  Assert.AreEqual(1, FMockRepo.DeleteTaskCalls);
end;

// --- UpdateTaskStatus ---

procedure TTaskServiceTests.UpdateTaskStatus_InvalidTransition_Fails;
var
  LResult: TResult;
begin
  // Task 3 is Done, cannot go to Pending directly
  FMockProvider.LoginAsAdmin(1, 'admin');
  LResult := FService.UpdateTaskStatus(3, tsPending);
  Assert.IsFalse(LResult.IsSuccess);
end;

procedure TTaskServiceTests.UpdateTaskStatus_ValidTransition_Succeeds;
var
  LResult: TResult;
begin
  // Task 1 is Pending, can go to InProgress
  FMockProvider.LoginAsAdmin(1, 'admin');
  LResult := FService.UpdateTaskStatus(1, tsInProgress);
  Assert.IsTrue(LResult.IsSuccess);
  Assert.AreEqual(1, FMockRepo.UpdateTaskCalls);
end;

// --- System methods ---

procedure TTaskServiceTests.SystemGetAllTasks_BypassesSecurity;
var
  LTasks: TList<TTask>;
begin
  // No login — system methods bypass security
  FMockProvider.Logout;
  LTasks := FService.SystemGetAllTasks;
  try
    Assert.AreEqual(3, LTasks.Count, 'SystemGetAllTasks should bypass security');
  finally
    LTasks.Free;
  end;
end;

procedure TTaskServiceTests.SystemDeleteTask_BypassesSecurity;
var
  LResult: TResult;
begin
  FMockProvider.Logout;
  LResult := FService.SystemDeleteTask(1);
  Assert.IsTrue(LResult.IsSuccess);
end;

procedure TTaskServiceTests.SystemBulkTouchUpdatedAt_CallsRepo;
var
  LCount: Integer;
begin
  LCount := FService.SystemBulkTouchUpdatedAt;
  Assert.AreEqual(1, FMockRepo.BulkTouchCalls);
end;

// --- GetTaskById ---

procedure TTaskServiceTests.GetTaskById_NotFound_ReturnsNil;
var
  LTask: TTask;
begin
  LTask := FService.GetTaskById(999);
  Assert.IsNull(LTask);
end;

procedure TTaskServiceTests.GetTaskById_PermissionDenied_ReturnsNil;
var
  LTask: TTask;
begin
  FMockGuard.AlwaysAllow := False;
  LTask := FService.GetTaskById(1);
  Assert.IsNull(LTask);
end;

procedure TTaskServiceTests.GetTaskById_Allowed_ReturnsTask;
var
  LTask: TTask;
begin
  FMockGuard.AlwaysAllow := True;
  LTask := FService.GetTaskById(1);
  try
    Assert.IsNotNull(LTask);
    Assert.AreEqual(1, LTask.Id);
    Assert.AreEqual('User Task 1', LTask.Title);
  finally
    LTask.Free;
  end;
end;

// --- Counts ---

procedure TTaskServiceTests.GetMyTaskCount_NotAuthenticated_ReturnsZero;
begin
  FMockProvider.Logout;
  Assert.AreEqual(0, FService.GetMyTaskCount);
end;

procedure TTaskServiceTests.GetMyTaskCount_Authenticated_ReturnsCount;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  Assert.AreEqual(2, FService.GetMyTaskCount);
end;

procedure TTaskServiceTests.GetAllTaskCount_NotAdmin_ReturnsZero;
begin
  FMockProvider.LoginAsUser(2, 'user1');
  Assert.AreEqual(0, FService.GetAllTaskCount);
end;

procedure TTaskServiceTests.GetAllTaskCount_Admin_ReturnsCount;
begin
  FMockProvider.LoginAsAdmin(1, 'admin');
  Assert.AreEqual(3, FService.GetAllTaskCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TTaskServiceTests);

end.
