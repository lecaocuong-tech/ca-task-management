program TaskManager;

uses
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Controls,
  System.SysUtils,
  LoginForm in 'src\UI\LoginForm.pas' {frmLogin},
  RegistrationForm in 'src\UI\RegistrationForm.pas' {frmRegistration},
  MainForm in 'src\UI\MainForm.pas' {frmMain},
  UserManagementForm in 'src\UI\UserManagementForm.pas' {frmUserManagement},
  UserEditForm in 'src\UI\UserEditForm.pas' {frmUserEdit},
  TaskEditForm in 'src\UI\TaskEditForm.pas' {frmTaskEdit},
  Result in 'src\Common\Result.pas',
  Logger in 'src\Common\Logger.pas',
  AppInterfaces in 'src\Interfaces\AppInterfaces.pas',
  SecurityContext in 'src\Core\SecurityContext.pas',
  DomainModels in 'src\Domain\DomainModels.pas',
  DomainEvents in 'src\Domain\DomainEvents.pas',
  Specifications in 'src\Domain\Specifications.pas',
  DatabaseManager in 'src\Infrastructure\DatabaseManager.pas',
  UserRepository in 'src\Infrastructure\UserRepository.pas',
  TaskRepository in 'src\Infrastructure\TaskRepository.pas',
  InfraInterfaces in 'src\Interfaces\InfraInterfaces.pas',
  PermissionGuard in 'src\Services\PermissionGuard.pas',
  AuthenticationService in 'src\Services\AuthenticationService.pas',
  UserService in 'src\Services\UserService.pas',
  TaskService in 'src\Services\TaskService.pas',
  BackgroundJob in 'src\Threading\BackgroundJob.pas',
  AutoCleanupJob in 'src\Threading\AutoCleanupJob.pas',
  AutoSaveJob in 'src\Threading\AutoSaveJob.pas',
  LongRunningJob in 'src\Threading\LongRunningJob.pas',
  DeleteDoneJob in 'src\Threading\DeleteDoneJob.pas',
  JobManager in 'src\Threading\JobManager.pas',
  JobFactory in 'src\Threading\JobFactory.pas',
  ServiceContainer in 'src\DependencyInjection\ServiceContainer.pas',
  CacheManager in 'src\Infrastructure\CacheManager.pas',
  DataSeeder in 'src\Infrastructure\DataSeeder.pas',
  DomainEventDispatcher in 'src\Infrastructure\DomainEventDispatcher.pas',
  DTOs in 'src\UseCases\DTOs.pas',
  CreateTaskUseCase in 'src\UseCases\CreateTaskUseCase.pas',
  GetTasksUseCase in 'src\UseCases\GetTasksUseCase.pas',
  ManageUserUseCase in 'src\UseCases\ManageUserUseCase.pas',
  UIConstants in 'src\UI\UIConstants.pas',
  RateLimiter in 'src\Security\RateLimiter.pas',
  InputSanitizer in 'src\Security\InputSanitizer.pas',
  // REST API Layer - Contracts
  ApiInterfaces in 'src\API\Contracts\ApiInterfaces.pas',
  // REST API Layer - Serialization
  JsonHelper in 'src\API\Serialization\JsonHelper.pas',
  // REST API Layer - Auth
  TokenManager in 'src\API\Auth\TokenManager.pas',
  // REST API Layer - Server
  ApiRouter in 'src\API\Server\ApiRouter.pas',
  HttpServer in 'src\API\Server\HttpServer.pas',
  // REST API Layer - Middleware
  ApiMiddleware in 'src\API\Middleware\ApiMiddleware.pas',
  ApiSecurityBridge in 'src\API\Middleware\ApiSecurityBridge.pas',
  // REST API Layer - Controllers
  AuthController in 'src\API\Controllers\AuthController.pas',
  TaskController in 'src\API\Controllers\TaskController.pas',
  UserController in 'src\API\Controllers\UserController.pas',
  // REST API Layer - Startup (Composition Root)
  ApiServer in 'src\API\Startup\ApiServer.pas';

{$R *.res}

var
  GServiceContainer: IServiceContainer;
  GApiServer: TApiServerManager;
  LMainResult: Integer;

begin
{$IFDEF MSWINDOWS}
  ReportMemoryLeaksOnShutdown := DebugHook <> 0;
{$ELSE}
  ReportMemoryLeaksOnShutdown := False;
{$ENDIF}
  
  Application.Initialize;
  Application.MainFormOnTaskbar := True;

  // Initialize Service Container
  try
    GServiceContainer := TServiceContainer.Create(
      ExtractFilePath(Application.ExeName) + 'taskmanager.db'
    );
  except
    on E: Exception do
    begin
      ShowMessage('Failed to initialize services: ' + E.Message);
      // Ensure container is nil and terminate application
      GServiceContainer := nil;
      Application.Terminate;
      Exit;
    end;
  end;

  // Initialize default data via DataSeeder (extracted for SRP)
  GServiceContainer.GetDataSeeder.SeedDefaultData;

  // Start background jobs (AutoSave, etc.)
  GServiceContainer.StartBackgroundJobs;

  // Start REST API Server on port 8080
  GApiServer := nil;
  try
    GApiServer := TApiServerManager.Create(GServiceContainer);
    GApiServer.Start(8080);
  except
    on E: Exception do
    begin
      // API server failure is non-fatal; VCL app continues
      GServiceContainer.GetLogger.Warning(
        'REST API server failed to start: ' + E.Message +
        ' - VCL application will continue without API.');
      FreeAndNil(GApiServer);
    end;
  end;

  // Main application loop - allows login retry and logout/re-login
  while True do
  begin
    // Show Login Form
    Application.CreateForm(TfrmLogin, frmLogin);
    frmLogin.AuthService := GServiceContainer.GetAuthenticationService;
    frmLogin.UserService := GServiceContainer.GetUserService;
    
    if frmLogin.ShowModal <> mrOk then
    begin
      // User clicked Exit or Cancel on login form
      frmLogin.Free;
      Break;
    end;

    // Show Main Form
    Application.CreateForm(TfrmMain, frmMain);
    frmMain.TaskService := GServiceContainer.GetTaskService;
    frmMain.UserService := GServiceContainer.GetUserService;
    frmMain.AuthService := GServiceContainer.GetAuthenticationService;
    frmMain.JobManager := GServiceContainer.GetJobManager;
    frmMain.JobFactory := GServiceContainer.GetJobFactory;
    frmMain.Logger := GServiceContainer.GetLogger;
    frmMain.ServiceContainer := GServiceContainer;

    LMainResult := frmMain.ShowModal;
    frmMain.Free;

    // mrRetry = explicit logout -> loop back to login
    // Any other result (mrCancel from X click, etc.) -> exit app
    if LMainResult <> mrRetry then
    begin
      frmLogin.Free;
      Break;
    end;

    frmLogin.Free;

    // After logout, loop back to show login form again
  end;
  
  // Cleanup
  // Stop REST API server
  if GApiServer <> nil then
  begin
    GApiServer.Stop;
    FreeAndNil(GApiServer);
  end;

  GServiceContainer.StopBackgroundJobs;
  GServiceContainer := nil;
  
  Application.Terminate;
end.
