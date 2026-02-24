unit AppInterfaces;

interface

{
  AppInterfaces.pas
  ------------------
  Central interface declarations for the entire application, implementing the
  Dependency Inversion Principle (DIP). All layers depend on these abstractions
  rather than on concrete implementation units.

  Layer mapping:
  - Common:        ILogger
  - Core:          ISecurityContext, ISecurityContextProvider
  - Domain Events: IDomainEventHandler, IDomainEventDispatcher
  - Domain:        IUserRepository, ITaskRepository (repository contracts)
  - Services:      IAuthenticationService, IPermissionGuard, ITaskService, IUserService
  - Caching:       ICacheProvider
  - Threading:     TJobState, IBackgroundJob, IJobManager, IJobFactory
  - Seeding:       IDataSeeder
  - DI Container:  IServiceContainer

  Dependencies: only DomainModels (pure domain types) and Result (outcome pattern).
  No infrastructure dependencies (no FireDAC, no VCL).
}

uses
  System.SysUtils,
  System.Generics.Collections,
  DomainModels,
  Result;

type
  // ==========================================================================
  // COMMON LAYER
  // ==========================================================================

  /// <summary>Application-wide logging abstraction.</summary>
  ILogger = interface
    ['{4A8B5C3D-1E2F-4A1B-8C7D-9E3F2A1B4C5D}']
    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warning(const AMessage: string);
    procedure Error(const AMessage: string; AException: Exception = nil);
    procedure Fatal(const AMessage: string; AException: Exception = nil);
  end;

  // ==========================================================================
  // CORE LAYER
  // ==========================================================================

  /// <summary>Read-only security context representing the authenticated user.</summary>
  ISecurityContext = interface
    ['{5B9C6D4E-2F3A-4B2C-9D8E-0F4A3B2C5D6E}']
    function GetUserId: Integer;
    function GetUsername: string;
    function GetRole: TUserRole;
    function GetAuthenticatedAt: TDateTime;

    property UserId: Integer read GetUserId;
    property Username: string read GetUsername;
    property Role: TUserRole read GetRole;
    property AuthenticatedAt: TDateTime read GetAuthenticatedAt;
  end;

  /// <summary>Injectable provider for the current security context.
  /// Replaces direct access to TSecurityContextManager singleton, enabling
  /// constructor injection and unit testing with mock contexts.</summary>
  ISecurityContextProvider = interface
    ['{9A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D}']
    procedure SetSecurityContext(const AContext: ISecurityContext);
    function GetSecurityContext: ISecurityContext;
    procedure ClearSecurityContext;
    function IsAuthenticated: Boolean;
    function GetSessionTimeoutMinutes: Integer;
    procedure SetSessionTimeoutMinutes(AValue: Integer);
  end;

  // ==========================================================================
  // DOMAIN EVENT INFRASTRUCTURE
  // ==========================================================================

  /// <summary>Handler that reacts to domain events. Implementations are
  /// registered with IDomainEventDispatcher at composition time.</summary>
  IDomainEventHandler = interface
    ['{C2D3E4F5-A6B7-8C9D-0E1F-A2B3C4D5E6F7}']
    procedure Handle(const AEvent: IDomainEvent);
    function CanHandle(const AEvent: IDomainEvent): Boolean;
  end;

  /// <summary>Dispatches domain events to registered handlers.
  /// Enables loose coupling between domain operations and cross-cutting
  /// concerns (logging, cache invalidation, notifications).</summary>
  IDomainEventDispatcher = interface
    ['{D3E4F5A6-B7C8-9D0E-1F2A-B3C4D5E6F7A8}']
    procedure Dispatch(const AEvent: IDomainEvent);
    procedure DispatchAll(const AEvents: TList<IDomainEvent>);
    procedure RegisterHandler(const AHandler: IDomainEventHandler);
    procedure UnregisterHandler(const AHandler: IDomainEventHandler);
  end;

  // ==========================================================================
  // REPOSITORY INTERFACES (Domain-layer contracts for data persistence)
  // ==========================================================================

  /// <summary>User persistence contract. All methods are pure data access
  /// with no authorization checks (those belong in Services).</summary>
  IUserRepository = interface
    ['{7D1E8F6A-4B5C-6D4E-1F6A-2B3C4D5E6F7D}']
    function GetUserById(AUserId: Integer): TUser;
    function GetUserByUsername(const AUsername: string): TUser;
    function CreateUser(const AUsername, APasswordHash, ASalt: string; ARole: TUserRole): TResult<TUser>;
    function UpdateUser(AUser: TUser): TResult;
    function DeleteUser(AUserId: Integer): TResult;
    function GetAllUsers: TList<TUser>;
    function GetAllUsersPaged(APageNum, APageSize: Integer): TList<TUser>;
    function GetUserCount: Integer;
  end;

  /// <summary>Task persistence contract. Includes bulk operations for
  /// background jobs (e.g. BulkTouchUpdatedAt for auto-save).</summary>
  ITaskRepository = interface
    ['{D47C2A9F-6E5B-4F7A-9C31-8A5E2D6F4B90}']
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
    /// <summary>Bulk-update UpdatedAt for all non-completed tasks in a single
    /// SQL statement. Returns number of rows affected. Used by AutoSaveJob.</summary>
    function BulkTouchUpdatedAt: Integer;
  end;

  // ==========================================================================
  // SERVICE INTERFACES (Business logic contracts)
  // ==========================================================================

  /// <summary>Authentication and credential management.</summary>
  IAuthenticationService = interface
    ['{0A4B1C9D-7E8F-9A0B-4C9D-5E6F7A8B9C0D}']
    function Login(const AUsername, APassword: string): TResult;
    function Register(const AUsername, APassword: string): TResult<TUser>;
    procedure Logout;
    function IsAuthenticated: Boolean;
    function HashPasswordKDF(const APassword, ASalt: string; AIterations: Integer = 10000): string;
    function GenerateSalt: string;
    /// <summary>Validate password against policy rules (min length, complexity).
    /// Returns Success if valid, Failure with descriptive message if not.</summary>
    function ValidatePasswordPolicy(const APassword: string): TResult;
    /// <summary>Returns the username of the currently authenticated user, or empty string.</summary>
    function GetCurrentUsername: string;
    /// <summary>Returns the user ID of the currently authenticated user, or 0.</summary>
    function GetCurrentUserId: Integer;
    /// <summary>Returns True if the current user has Admin role.</summary>
    function IsCurrentUserAdmin: Boolean;
  end;

  /// <summary>Role-based authorization checks.</summary>
  IPermissionGuard = interface
    ['{A12C4E90-5B7D-4F6A-9C81-3E2D7A8B4F01}']
    function CanViewTask(ATask: TTask): TResult;
    function CanEditTask(ATask: TTask): TResult;
    function CanDeleteTask(ATask: TTask): TResult;
    function CanManageUsers: TResult;
  end;

  /// <summary>Task business logic with permission enforcement.
  /// System* methods bypass security for trusted internal callers (background jobs).</summary>
  ITaskService = interface
    ['{A90C1F3E-5D2B-4E8A-9F01-2C7D6B5A8E34}']
    function GetMyTasks: TList<TTask>;
    function GetMyTasksFiltered(const AStatusFilter: string = ''): TList<TTask>;
    function GetMyTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
    function GetAllTasks: TList<TTask>;
    function GetAllTasksFiltered(const AStatusFilter: string = ''): TList<TTask>;
    function GetAllTasksPaged(APageNum, APageSize: Integer): TList<TTask>;
    function GetTaskById(ATaskId: Integer): TTask;
    function CreateTask(const ATitle: string; const ADescription: string = ''): TResult<TTask>;
    function UpdateTask(ATask: TTask): TResult;
    function DeleteTask(ATaskId: Integer): TResult;
    function UpdateTaskStatus(ATaskId: Integer; AStatus: TTaskStatus): TResult;
    function GetMyTaskCount: Integer;
    function GetAllTaskCount: Integer;
    function CleanupCompletedTasks(ADaysOld: Integer): Integer;
    // System-level methods for background jobs (no security context required)
    function SystemGetAllTasks: TList<TTask>;
    function SystemUpdateTask(ATask: TTask): TResult;
    function SystemCleanupCompletedTasks(ADaysOld: Integer): Integer;
    /// <summary>System-level delete for background jobs (no security context required).</summary>
    function SystemDeleteTask(ATaskId: Integer): TResult;
    /// <summary>Bulk-touch UpdatedAt for all non-completed tasks. Used by AutoSaveJob.
    /// Single SQL operation instead of loading and updating each task individually.</summary>
    function SystemBulkTouchUpdatedAt: Integer;
  end;

  /// <summary>User management business logic (Admin-only operations).</summary>
  IUserService = interface
    ['{F1E3D6C2-9A0B-4C2D-8E1F-A7B8C9D0E1F2}']
    function GetAllUsers: TList<TUser>;
    function GetAllUsersPaged(APageNum, APageSize: Integer): TList<TUser>;
    function GetUserCount: Integer;
    function GetUserById(AUserId: Integer): TUser;
    function CreateUser(const AUsername, APassword: string; ARole: TUserRole): TResult<TUser>;
    function UpdateUser(AUser: TUser; const ANewPassword: string): TResult;
    function DeleteUser(AUserId: Integer): TResult;
  end;

  // ==========================================================================
  // THREADING INTERFACES
  // ==========================================================================

  TJobState = (jsIdle, jsRunning, jsCompleted, jsCancelled, jsFailed);

  /// <summary>Background job abstraction with lifecycle management.</summary>
  IBackgroundJob = interface
    ['{3D7E4F2A-0B1C-2C3D-7F2A-8B9C0D1E2F3A}']
    procedure Start;
    procedure Cancel;
    function GetState: TJobState;
    function GetProgress: Integer;
    function GetErrorMessage: string;
  end;

  /// <summary>Manages background job submission and lifecycle.</summary>
  IJobManager = interface
    ['{4E8F5A3B-1A2C-3D4E-8A3B-9A0B1C2D3E4F}']
    procedure SubmitJob(AJob: IBackgroundJob);
    function GetActiveJobCount: Integer;
    procedure CancelAllJobs;
    procedure WaitForAllJobsCompletion(ATimeoutMS: Integer = 30000);
  end;

  /// <summary>Factory for creating background job instances.
  /// Decouples UI from concrete job implementations.</summary>
  IJobFactory = interface
    ['{8C1D2E3F-4A5B-6C7D-8E9F-0A1B2C3D4E5F}']
    /// <summary>Creates a long-running demo job with specified duration in seconds.</summary>
    function CreateLongRunningJob(ADurationSeconds: Integer): IBackgroundJob;
    /// <summary>Creates a job that deletes all Done tasks one by one.
    /// AOnTaskDeleted callback is invoked on the main thread after each deletion.</summary>
    function CreateDeleteDoneJob(AOnTaskDeleted: TProc): IBackgroundJob;
  end;

  // ==========================================================================
  // SECURITY INTERFACES
  // ==========================================================================

  /// <summary>Token-bucket rate limiter interface. Protects sensitive operations
  /// (login, registration, task creation) from brute-force and DoS attacks.
  /// Per-key tracking allows different limits for different operations.</summary>
  IRateLimiter = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    /// <summary>Try to consume tokens for the given key. Returns True if allowed.</summary>
    function TryConsume(const AKey: string; ATokens: Integer = 1): Boolean;
    /// <summary>Returns remaining tokens for the key (without consuming).</summary>
    function GetRemainingTokens(const AKey: string): Integer;
    /// <summary>Reset rate limit tracking for a specific key.</summary>
    procedure ResetKey(const AKey: string);
    /// <summary>Reset all rate limit tracking.</summary>
    procedure ResetAll;
  end;

  /// <summary>Input validation and sanitization interface. Provides defense-in-depth
  /// against injection attacks, XSS, and malformed input. Used at the Use Case
  /// boundary to validate all user-supplied data before it reaches services.</summary>
  IInputSanitizer = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
    function SanitizeString(const AInput: string): string;
    function ValidateUsername(const AUsername: string): TResult;
    function ValidateTaskTitle(const ATitle: string): TResult;
    function ValidateTaskDescription(const ADescription: string): TResult;
    function ValidatePassword(const APassword: string): TResult;
    function ValidateTextField(const AValue, AFieldName: string;
      AMaxLength: Integer): TResult;
  end;

  // ==========================================================================
  // CACHING INTERFACES
  // ==========================================================================

  /// <summary>Abstraction for caching layer. Enables transparent caching
  /// without coupling services to a specific cache technology.
  /// Supports TTL-based expiration and prefix-based invalidation.</summary>
  ICacheProvider = interface
    ['{E4F5A6B7-C8D9-0E1F-2A3B-C4D5E6F7A8B9}']
    function TryGetValue(const AKey: string; out AObj: TObject): Boolean;
    procedure SetValue(const AKey: string; AObj: TObject;
      AOwnsObject: Boolean = False; ATTLSeconds: Integer = 0);
    procedure Invalidate(const AKey: string);
    procedure InvalidateByPrefix(const APrefix: string);
    procedure Clear;
    function GetEntryCount: Integer;
  end;

  // ==========================================================================
  // DATA SEEDING INTERFACE
  // ==========================================================================

  /// <summary>Seeds default data into the system on first run.
  /// Extracted from composition root for testability and SRP.</summary>
  IDataSeeder = interface
    ['{F5A6B7C8-D9E0-1F2A-3B4C-D5E6F7A8B9C0}']
    procedure SeedDefaultData;
  end;

  // ==========================================================================
  // DI CONTAINER INTERFACE
  // ==========================================================================

  /// <summary>Application-level composition root interface.
  /// Exposes only service-level abstractions to consumers.
  /// Infrastructure details (repositories, database) are hidden.</summary>
  IServiceContainer = interface
    ['{5F9A6B4A-2B3C-4E5F-9B4A-0B1C2D3E4F5A}']
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

  // ==========================================================================
  // HELPER PROCEDURES (Memory management utilities)
  // ==========================================================================

  /// <summary>Safely frees a TList of TTask objects and all contained items.</summary>
procedure FreeTaskList(var AList: TList<TTask>);
  /// <summary>Safely frees a TList of TUser objects and all contained items.</summary>
procedure FreeUserList(var AList: TList<TUser>);

implementation

procedure FreeTaskList(var AList: TList<TTask>);
begin
  // TObjectList<TTask> with OwnsObjects=True auto-frees items
  if AList <> nil then
    FreeAndNil(AList);
end;

procedure FreeUserList(var AList: TList<TUser>);
begin
  // TObjectList<TUser> with OwnsObjects=True auto-frees items
  if AList <> nil then
    FreeAndNil(AList);
end;

end.
