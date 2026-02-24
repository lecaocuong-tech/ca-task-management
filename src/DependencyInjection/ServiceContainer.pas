unit ServiceContainer;

interface

uses
  System.SysUtils,
  AppInterfaces,
  InfraInterfaces,
  DomainModels,
  Logger,
  DatabaseManager,
  UserRepository,
  TaskRepository,
  SecurityContext,
  PermissionGuard,
  AuthenticationService,
  UserService,
  TaskService,
  JobManager,
  JobFactory,
  BackgroundJob,
  AutoSaveJob,
  CacheManager,
  DataSeeder,
  DomainEventDispatcher,
  RateLimiter,
  InputSanitizer;

{
  ServiceContainer.pas
  --------------------
  Composition Root: wires all concrete implementations via constructor injection.
  IServiceContainer interface is declared in AppInterfaces.pas (Dependency Inversion).
  Consumers only see abstractions; this unit holds the only references to concrete types.

  Responsibilities:
  - Wire infrastructure (DB, logger, cache)
  - Wire domain event infrastructure (dispatcher + handlers)
  - Wire security (context provider, permission guard)
  - Wire services (auth, user, task)
  - Wire background jobs (manager, factory)
  - Wire data seeder
  - Manage background job lifecycle

  IServiceContainer no longer exposes repositories directly.
  Infrastructure details are hidden behind service interfaces.
}

type
  TServiceContainer = class(TInterfacedObject, IServiceContainer)
  private
    FLogger: ILogger;
    FDatabaseManager: IDatabaseManager;
    FSecurityContextProvider: ISecurityContextProvider;
    FEventDispatcher: IDomainEventDispatcher;
    FCacheProvider: ICacheProvider;
    FRateLimiter: IRateLimiter;
    FInputSanitizer: IInputSanitizer;
    FUserRepository: IUserRepository;
    FTaskRepository: ITaskRepository;
    FAuthenticationService: IAuthenticationService;
    FUserService: IUserService;
    FTaskService: ITaskService;
    FJobManager: IJobManager;
    FJobFactory: IJobFactory;
    FAutoSaveJob: IBackgroundJob;
    FDataSeeder: IDataSeeder;
  public
    constructor Create(const ADbPath: string);
    destructor Destroy; override;

    function GetLogger: ILogger;
    function GetEventDispatcher: IDomainEventDispatcher;
    function GetCacheProvider: ICacheProvider;
    function GetRateLimiter: IRateLimiter;
    function GetInputSanitizer: IInputSanitizer;
    function GetSecurityContextProvider: ISecurityContextProvider;
    function GetAuthenticationService: IAuthenticationService;
    function GetUserService: IUserService;
    function GetTaskService: ITaskService;
    function GetJobManager: IJobManager;
    function GetJobFactory: IJobFactory;
    function GetDataSeeder: IDataSeeder;
    procedure StartBackgroundJobs;
    procedure StopBackgroundJobs;
  end;

implementation

{ TServiceContainer }

constructor TServiceContainer.Create(const ADbPath: string);
var
  LPermissionGuard: IPermissionGuard;
  LLoggingHandler: IDomainEventHandler;
  LCacheHandler: IDomainEventHandler;
begin
  inherited Create;

  // Logger
  FLogger := TFileLogger.Create(ExtractFilePath(ADbPath) + 'log.txt');

  // Database
  FDatabaseManager := TDatabaseManager.Create(ADbPath, FLogger);

  // Security Context Provider (injectable, replaces direct singleton access)
  FSecurityContextProvider := TSecurityContextManager.GetInstance;

  // Caching
  FCacheProvider := TMemoryCacheProvider.Create(FLogger, 300); // 5 min default TTL

  // Security: Rate Limiter (10 tokens max, 1 token/second refill)
  FRateLimiter := TTokenBucketRateLimiter.Create(FLogger, 10, 1.0);

  // Security: Input Sanitizer
  FInputSanitizer := TInputSanitizer.Create(FLogger);

  // Domain Event Dispatcher + Handlers
  FEventDispatcher := DomainEventDispatcher.TDomainEventDispatcher.Create(FLogger);
  LLoggingHandler := TLoggingEventHandler.Create(FLogger);
  LCacheHandler := TCacheInvalidationHandler.Create(FCacheProvider, FLogger);
  FEventDispatcher.RegisterHandler(LLoggingHandler);
  FEventDispatcher.RegisterHandler(LCacheHandler);

  // Repositories
  FUserRepository := TUserRepository.Create(FDatabaseManager, FLogger);
  FTaskRepository := TTaskRepository.Create(FDatabaseManager, FLogger);

  // Services
  FAuthenticationService := TAuthenticationService.Create(FUserRepository, FSecurityContextProvider, FLogger);

  // Permission Guard (receives security context provider for DI)
  LPermissionGuard := TPermissionGuard.Create(FSecurityContextProvider, FLogger);

  FUserService := TUserService.Create(FUserRepository, FAuthenticationService, LPermissionGuard, FSecurityContextProvider, FLogger);
  FTaskService := TTaskService.Create(FTaskRepository, LPermissionGuard, FSecurityContextProvider, FLogger);

  // Data Seeder
  FDataSeeder := TDataSeeder.Create(FUserRepository, FAuthenticationService, FLogger);

  // Job Manager
  FJobManager := TJobManager.Create(FLogger);

  // Background jobs (created but not started - call StartBackgroundJobs explicitly)
  FAutoSaveJob := TAutoSaveJob.Create(FTaskService, 300, FLogger); // 300 seconds = 5 minutes

  // Job Factory
  FJobFactory := TJobFactory.Create(FTaskService, FLogger);

  FLogger.Info('Service container initialized (with event dispatcher, cache, security, data seeder)');
end;

destructor TServiceContainer.Destroy;
begin
  FLogger.Info('Service container shutting down');

  StopBackgroundJobs;
  FAutoSaveJob := nil;
  FDataSeeder := nil;
  FJobFactory := nil;
  FJobManager := nil;
  FTaskService := nil;
  FUserService := nil;
  FAuthenticationService := nil;
  FTaskRepository := nil;
  FUserRepository := nil;
  FEventDispatcher := nil;
  FCacheProvider := nil;
  FRateLimiter := nil;
  FInputSanitizer := nil;
  FSecurityContextProvider := nil;
  FDatabaseManager := nil;
  FLogger := nil;

  inherited;
end;

procedure TServiceContainer.StartBackgroundJobs;
begin
  if Assigned(FAutoSaveJob) and Assigned(FJobManager) then
  begin
    FJobManager.SubmitJob(FAutoSaveJob);
    FLogger.Info('Background jobs started');
  end;
end;

procedure TServiceContainer.StopBackgroundJobs;
begin
  if Assigned(FJobManager) then
  begin
    FJobManager.CancelAllJobs;
    FLogger.Info('Background jobs stopped');
  end;
end;

function TServiceContainer.GetLogger: ILogger;
begin
  Result := FLogger;
end;

function TServiceContainer.GetEventDispatcher: IDomainEventDispatcher;
begin
  Result := FEventDispatcher;
end;

function TServiceContainer.GetCacheProvider: ICacheProvider;
begin
  Result := FCacheProvider;
end;

function TServiceContainer.GetRateLimiter: IRateLimiter;
begin
  Result := FRateLimiter;
end;

function TServiceContainer.GetInputSanitizer: IInputSanitizer;
begin
  Result := FInputSanitizer;
end;

function TServiceContainer.GetSecurityContextProvider: ISecurityContextProvider;
begin
  Result := FSecurityContextProvider;
end;

function TServiceContainer.GetAuthenticationService: IAuthenticationService;
begin
  Result := FAuthenticationService;
end;

function TServiceContainer.GetUserService: IUserService;
begin
  Result := FUserService;
end;

function TServiceContainer.GetTaskService: ITaskService;
begin
  Result := FTaskService;
end;

function TServiceContainer.GetJobManager: IJobManager;
begin
  Result := FJobManager;
end;

function TServiceContainer.GetJobFactory: IJobFactory;
begin
  Result := FJobFactory;
end;

function TServiceContainer.GetDataSeeder: IDataSeeder;
begin
  Result := FDataSeeder;
end;

end.
