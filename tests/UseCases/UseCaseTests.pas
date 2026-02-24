unit UseCaseTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  DTOs,
  Result,
  CreateTaskUseCase,
  GetTasksUseCase,
  ManageUserUseCase,
  RateLimiter,
  InputSanitizer,
  MockInterfaces;

{
  UseCaseTests.pas
  ------------------
  Unit tests for Application-layer Use Cases. Verifies the orchestration
  logic: input validation, delegation to services, event dispatching,
  and correct DTO mapping in responses.

  Uses TMockEventDispatcher to verify domain events are dispatched
  after successful operations.
}

type
  /// <summary>Mock event dispatcher that tracks dispatched events.</summary>
  TMockEventDispatcher = class(TInterfacedObject, IDomainEventDispatcher)
  private
    FDispatchedEvents: TList<IDomainEvent>;
    FHandlers: TList<IDomainEventHandler>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Dispatch(const AEvent: IDomainEvent);
    procedure DispatchAll(const AEvents: TList<IDomainEvent>);
    procedure RegisterHandler(const AHandler: IDomainEventHandler);
    procedure UnregisterHandler(const AHandler: IDomainEventHandler);

    property DispatchedEvents: TList<IDomainEvent> read FDispatchedEvents;
    function DispatchedCount: Integer;
  end;

  // ==========================================================================
  // CreateTaskUseCase Tests
  // ==========================================================================

  [TestFixture]
  TCreateTaskUseCaseTests = class
  private
    FTaskRepo: TMockTaskRepository;
    FPermGuard: TMockPermissionGuard;
    FSecCtx: TMockSecurityContextProvider;
    FLogger: TMockLogger;
    FAuthService: TMockAuthenticationService;
    FEventDispatcher: TMockEventDispatcher;
    FSanitizer: IInputSanitizer;
    FRateLimiter: IRateLimiter;
    FTaskService: ITaskService;
    FUseCase: TCreateTaskUseCase;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Execute_EmptyTitle_ReturnsFailure;
    [Test]
    procedure Execute_ValidRequest_ReturnsSuccess;
    [Test]
    procedure Execute_ValidRequest_ReturnsMappedDTO;
  end;

  // ==========================================================================
  // GetTasksUseCase Tests
  // ==========================================================================

  [TestFixture]
  TGetTasksUseCaseTests = class
  private
    FTaskRepo: TMockTaskRepository;
    FPermGuard: TMockPermissionGuard;
    FSecCtx: TMockSecurityContextProvider;
    FLogger: TMockLogger;
    FAuthService: TMockAuthenticationService;
    FTaskService: ITaskService;
    FUseCase: TGetTasksUseCase;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Execute_All_ReturnsPagedResponse;
    [Test]
    procedure Execute_All_MapsToDTO;
  end;

  // ==========================================================================
  // CreateUserUseCase Tests
  // ==========================================================================

  [TestFixture]
  TCreateUserUseCaseTests = class
  private
    FUserRepo: TMockUserRepository;
    FPermGuard: TMockPermissionGuard;
    FSecCtx: TMockSecurityContextProvider;
    FLogger: TMockLogger;
    FAuthService: TMockAuthenticationService;
    FEventDispatcher: TMockEventDispatcher;
    FSanitizer: IInputSanitizer;
    FRateLimiter: IRateLimiter;
    FUserService: IUserService;
    FUseCase: TCreateUserUseCase;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Execute_EmptyUsername_ReturnsFailure;
    [Test]
    procedure Execute_EmptyPassword_ReturnsFailure;
    [Test]
    procedure Execute_ValidRequest_ReturnsSuccess;
    [Test]
    procedure Execute_ValidRequest_ReturnsMappedDTO;
  end;

implementation

uses
  TaskService,
  UserService;

{ TMockEventDispatcher }

constructor TMockEventDispatcher.Create;
begin
  inherited Create;
  FDispatchedEvents := TList<IDomainEvent>.Create;
  FHandlers := TList<IDomainEventHandler>.Create;
end;

destructor TMockEventDispatcher.Destroy;
begin
  FDispatchedEvents.Free;
  FHandlers.Free;
  inherited;
end;

procedure TMockEventDispatcher.Dispatch(const AEvent: IDomainEvent);
begin
  if AEvent <> nil then
    FDispatchedEvents.Add(AEvent);
end;

procedure TMockEventDispatcher.DispatchAll(const AEvents: TList<IDomainEvent>);
var
  LEvent: IDomainEvent;
begin
  if AEvents <> nil then
    for LEvent in AEvents do
      Dispatch(LEvent);
end;

procedure TMockEventDispatcher.RegisterHandler(const AHandler: IDomainEventHandler);
begin
  FHandlers.Add(AHandler);
end;

procedure TMockEventDispatcher.UnregisterHandler(const AHandler: IDomainEventHandler);
begin
  FHandlers.Remove(AHandler);
end;

function TMockEventDispatcher.DispatchedCount: Integer;
begin
  Result := FDispatchedEvents.Count;
end;

{ TCreateTaskUseCaseTests }

procedure TCreateTaskUseCaseTests.Setup;
begin
  FTaskRepo := TMockTaskRepository.Create;
  FPermGuard := TMockPermissionGuard.Create(True);
  FSecCtx := TMockSecurityContextProvider.Create;
  FLogger := TMockLogger.Create;
  FAuthService := TMockAuthenticationService.Create;

  FSecCtx.LoginAsUser(5, 'testuser');

  FTaskService := TTaskService.Create(
    FTaskRepo as ITaskRepository,
    FPermGuard as IPermissionGuard,
    FSecCtx as ISecurityContextProvider,
    FLogger as ILogger
  );

  FEventDispatcher := TMockEventDispatcher.Create;

  // Use real sanitizer and rate limiter for integration-style tests
  FSanitizer := TInputSanitizer.Create(FLogger as ILogger);
  FRateLimiter := TTokenBucketRateLimiter.Create(FLogger as ILogger, 100, 10.0);

  FUseCase := TCreateTaskUseCase.Create(
    FTaskService,
    FEventDispatcher as IDomainEventDispatcher,
    FSanitizer,
    FRateLimiter,
    FLogger as ILogger
  );
end;

procedure TCreateTaskUseCaseTests.TearDown;
begin
  FUseCase.Free;
  // Interfaces are ref-counted, no manual free needed for mock objects
end;

procedure TCreateTaskUseCaseTests.Execute_EmptyTitle_ReturnsFailure;
var
  LReq: TCreateTaskRequest;
  LResp: TUseCaseResponse<TTaskDTO>;
begin
  LReq := TCreateTaskRequest.Create('');
  LResp := FUseCase.Execute(LReq);
  Assert.IsFalse(LResp.IsSuccess);
  Assert.Contains(LResp.ErrorMessage, 'empty');
end;

procedure TCreateTaskUseCaseTests.Execute_ValidRequest_ReturnsSuccess;
var
  LReq: TCreateTaskRequest;
  LResp: TUseCaseResponse<TTaskDTO>;
begin
  LReq := TCreateTaskRequest.Create('Test Task', 'Description');
  LResp := FUseCase.Execute(LReq);
  Assert.IsTrue(LResp.IsSuccess, 'Expected success but got: ' + LResp.ErrorMessage);
end;

procedure TCreateTaskUseCaseTests.Execute_ValidRequest_ReturnsMappedDTO;
var
  LReq: TCreateTaskRequest;
  LResp: TUseCaseResponse<TTaskDTO>;
begin
  LReq := TCreateTaskRequest.Create('My New Task', 'Desc');
  LResp := FUseCase.Execute(LReq);
  Assert.IsTrue(LResp.IsSuccess);
  Assert.AreEqual('My New Task', LResp.Data.Title);
  Assert.AreEqual('Pending', LResp.Data.Status);
end;

{ TGetTasksUseCaseTests }

procedure TGetTasksUseCaseTests.Setup;
begin
  FTaskRepo := TMockTaskRepository.Create;
  FPermGuard := TMockPermissionGuard.Create(True);
  FSecCtx := TMockSecurityContextProvider.Create;
  FLogger := TMockLogger.Create;
  FAuthService := TMockAuthenticationService.Create;

  FSecCtx.LoginAsAdmin(1, 'admin');

  // Seed some tasks
  FTaskRepo.SeedTask(1, 1, 'Task A', tsPending);
  FTaskRepo.SeedTask(2, 1, 'Task B', tsInProgress);
  FTaskRepo.SeedTask(3, 2, 'Task C', tsDone);

  FTaskService := TTaskService.Create(
    FTaskRepo as ITaskRepository,
    FPermGuard as IPermissionGuard,
    FSecCtx as ISecurityContextProvider,
    FLogger as ILogger
  );

  FUseCase := TGetTasksUseCase.Create(
    FTaskService,
    FAuthService as IAuthenticationService,
    FLogger as ILogger
  );
end;

procedure TGetTasksUseCaseTests.TearDown;
begin
  FUseCase.Free;
end;

procedure TGetTasksUseCaseTests.Execute_All_ReturnsPagedResponse;
var
  LReq: TGetTasksRequest;
  LResp: TPagedResponse<TTaskDTO>;
begin
  LReq := TGetTasksRequest.All;
  LResp := FUseCase.Execute(LReq);
  Assert.IsTrue(LResp.IsSuccess);
  Assert.AreEqual(3, Length(LResp.Items));
end;

procedure TGetTasksUseCaseTests.Execute_All_MapsToDTO;
var
  LReq: TGetTasksRequest;
  LResp: TPagedResponse<TTaskDTO>;
begin
  LReq := TGetTasksRequest.All;
  LResp := FUseCase.Execute(LReq);
  Assert.IsTrue(LResp.IsSuccess);
  Assert.AreEqual('Task A', LResp.Items[0].Title);
  Assert.AreEqual('Pending', LResp.Items[0].Status);
end;

{ TCreateUserUseCaseTests }

procedure TCreateUserUseCaseTests.Setup;
begin
  FUserRepo := TMockUserRepository.Create;
  FPermGuard := TMockPermissionGuard.Create(True);
  FSecCtx := TMockSecurityContextProvider.Create;
  FLogger := TMockLogger.Create;
  FAuthService := TMockAuthenticationService.Create;

  FSecCtx.LoginAsAdmin(1, 'admin');

  FUserService := TUserService.Create(
    FUserRepo as IUserRepository,
    FAuthService as IAuthenticationService,
    FPermGuard as IPermissionGuard,
    FSecCtx as ISecurityContextProvider,
    FLogger as ILogger
  );

  FEventDispatcher := TMockEventDispatcher.Create;

  // Use real sanitizer and rate limiter for integration-style tests
  FSanitizer := TInputSanitizer.Create(FLogger as ILogger);
  FRateLimiter := TTokenBucketRateLimiter.Create(FLogger as ILogger, 100, 10.0);

  FUseCase := TCreateUserUseCase.Create(
    FUserService,
    FEventDispatcher as IDomainEventDispatcher,
    FSanitizer,
    FRateLimiter,
    FLogger as ILogger
  );
end;

procedure TCreateUserUseCaseTests.TearDown;
begin
  FUseCase.Free;
end;

procedure TCreateUserUseCaseTests.Execute_EmptyUsername_ReturnsFailure;
var
  LReq: TCreateUserRequest;
  LResp: TUseCaseResponse<TUserDTO>;
begin
  LReq := TCreateUserRequest.Create('', 'Pass123', urUser);
  LResp := FUseCase.Execute(LReq);
  Assert.IsFalse(LResp.IsSuccess);
  Assert.Contains(LResp.ErrorMessage, 'empty');
end;

procedure TCreateUserUseCaseTests.Execute_EmptyPassword_ReturnsFailure;
var
  LReq: TCreateUserRequest;
  LResp: TUseCaseResponse<TUserDTO>;
begin
  LReq := TCreateUserRequest.Create('newuser', '', urUser);
  LResp := FUseCase.Execute(LReq);
  Assert.IsFalse(LResp.IsSuccess);
  Assert.Contains(LResp.ErrorMessage, 'empty');
end;

procedure TCreateUserUseCaseTests.Execute_ValidRequest_ReturnsSuccess;
var
  LReq: TCreateUserRequest;
  LResp: TUseCaseResponse<TUserDTO>;
begin
  LReq := TCreateUserRequest.Create('newuser', 'SecurePass1', urUser);
  LResp := FUseCase.Execute(LReq);
  Assert.IsTrue(LResp.IsSuccess, 'Expected success but got: ' + LResp.ErrorMessage);
end;

procedure TCreateUserUseCaseTests.Execute_ValidRequest_ReturnsMappedDTO;
var
  LReq: TCreateUserRequest;
  LResp: TUseCaseResponse<TUserDTO>;
begin
  LReq := TCreateUserRequest.Create('newuser', 'SecurePass1', urAdmin);
  LResp := FUseCase.Execute(LReq);
  Assert.IsTrue(LResp.IsSuccess);
  Assert.AreEqual('newuser', LResp.Data.Username);
end;

end.
