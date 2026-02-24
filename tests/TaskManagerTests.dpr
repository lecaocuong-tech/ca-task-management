program TaskManagerTests;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ENDIF}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  // Domain & Common
  DomainModels in '..\src\Domain\DomainModels.pas',
  DomainEvents in '..\src\Domain\DomainEvents.pas',
  Specifications in '..\src\Domain\Specifications.pas',
  Result in '..\src\Common\Result.pas',
  Logger in '..\src\Common\Logger.pas',
  // Core
  SecurityContext in '..\src\Core\SecurityContext.pas',
  // Interfaces
  AppInterfaces in '..\src\Interfaces\AppInterfaces.pas',
  // UseCases & DTOs
  DTOs in '..\src\UseCases\DTOs.pas',
  CreateTaskUseCase in '..\src\UseCases\CreateTaskUseCase.pas',
  GetTasksUseCase in '..\src\UseCases\GetTasksUseCase.pas',
  ManageUserUseCase in '..\src\UseCases\ManageUserUseCase.pas',
  // Security
  RateLimiter in '..\src\Security\RateLimiter.pas',
  InputSanitizer in '..\src\Security\InputSanitizer.pas',
  // Services under test
  PermissionGuard in '..\src\Services\PermissionGuard.pas',
  TaskService in '..\src\Services\TaskService.pas',
  UserService in '..\src\Services\UserService.pas',
  // Mocks
  MockInterfaces in 'Mocks\MockInterfaces.pas',
  // Test fixtures - Original
  DomainModelsTests in 'Domain\DomainModelsTests.pas',
  ResultTests in 'Common\ResultTests.pas',
  TaskServiceTests in 'Services\TaskServiceTests.pas',
  PermissionGuardTests in 'Services\PermissionGuardTests.pas',
  UserServiceTests in 'Services\UserServiceTests.pas',
  // Test fixtures - New (Domain Events, Specifications, DTOs, UseCases, Security)
  DomainEventsTests in 'Domain\DomainEventsTests.pas',
  SpecificationsTests in 'Domain\SpecificationsTests.pas',
  DTOsTests in 'UseCases\DTOsTests.pas',
  UseCaseTests in 'UseCases\UseCaseTests.pas',
  SecurityTests in 'Security\SecurityTests.pas';

{$IFNDEF TESTINSIGHT}
var
  LRunner: ITestRunner;
  LResults: IRunResults;
  LLogger: ITestLogger;
  LNUnitLogger: ITestLogger;
begin
  try
    TDUnitX.CheckCommandLine;
    LRunner := TDUnitX.CreateRunner;
    LRunner.UseRTTI := True;
    LRunner.FailsOnNoAsserts := False;

    LLogger := TDUnitXConsoleLogger.Create(True);
    LRunner.AddLogger(LLogger);

    LNUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    LRunner.AddLogger(LNUnitLogger);

    LResults := LRunner.Execute;

    if not LResults.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$ELSE}
begin
  TestInsight.DUnitX.RunRegisteredTests;
{$ENDIF}
end.
