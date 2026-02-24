unit PermissionGuard;

interface

uses
  System.SysUtils,
  AppInterfaces,
  DomainModels,
  Result;

{
  PermissionGuard.pas
  -------------------
  IPermissionGuard interface is declared in AppInterfaces.pas (Dependency Inversion).
  Authorization service: checks whether the current user has permission to perform
  task operations. Enforces role-based access control:
  - Admin users can manage all users and view/edit/delete any task.
  - Regular users can only view/edit/delete their own tasks.
  - All operations require user authentication (non-nil SecurityContext).

  Security context is obtained via ISecurityContextProvider (injected),
  not through the global TSecurityContextManager singleton.
}

type
  TPermissionGuard = class(TInterfacedObject, IPermissionGuard)
  private
    FLogger: ILogger;
    FSecurityContextProvider: ISecurityContextProvider;
    function GetCurrentSecurityContext: ISecurityContext;
  public
    constructor Create(ASecurityContextProvider: ISecurityContextProvider; ALogger: ILogger);

    function CanViewTask(ATask: TTask): TResult;
    function CanEditTask(ATask: TTask): TResult;
    function CanDeleteTask(ATask: TTask): TResult;
    function CanManageUsers: TResult;
  end;

implementation

{ TPermissionGuard }

constructor TPermissionGuard.Create(ASecurityContextProvider: ISecurityContextProvider; ALogger: ILogger);
begin
  inherited Create;
  FSecurityContextProvider := ASecurityContextProvider;
  FLogger := ALogger;
end;

function TPermissionGuard.GetCurrentSecurityContext: ISecurityContext;
begin
  Result := FSecurityContextProvider.GetSecurityContext;
end;

function TPermissionGuard.CanViewTask(ATask: TTask): TResult;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('CanViewTask: Security context not found');
    Result := TResult.Failure('Not authenticated');
    Exit;
  end;

  // Admin can view all tasks
  if LContext.Role = urAdmin then
  begin
    Result := TResult.Success;
    Exit;
  end;

  // User can only view their own tasks
  if ATask.UserId = LContext.UserId then
  begin
    Result := TResult.Success;
  end
  else
  begin
    FLogger.Warning(Format('Permission denied: User %d attempted to view task %d',
      [LContext.UserId, ATask.Id]));
    Result := TResult.Failure('Permission denied: You cannot view this task');
  end;
end;

function TPermissionGuard.CanEditTask(ATask: TTask): TResult;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('CanEditTask: Security context not found');
    Result := TResult.Failure('Not authenticated');
    Exit;
  end;

  // Admin can edit all tasks
  if LContext.Role = urAdmin then
  begin
    Result := TResult.Success;
    Exit;
  end;

  // User can only edit their own tasks
  if ATask.UserId = LContext.UserId then
  begin
    Result := TResult.Success;
  end
  else
  begin
    FLogger.Warning(Format('Permission denied: User %d attempted to edit task %d',
      [LContext.UserId, ATask.Id]));
    Result := TResult.Failure('Permission denied: You cannot edit this task');
  end;
end;

function TPermissionGuard.CanDeleteTask(ATask: TTask): TResult;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('CanDeleteTask: Security context not found');
    Result := TResult.Failure('Not authenticated');
    Exit;
  end;

  // Admin can delete all tasks
  if LContext.Role = urAdmin then
  begin
    Result := TResult.Success;
    Exit;
  end;

  // User can only delete their own tasks
  if ATask.UserId = LContext.UserId then
  begin
    Result := TResult.Success;
  end
  else
  begin
    FLogger.Warning(Format('Permission denied: User %d attempted to delete task %d',
      [LContext.UserId, ATask.Id]));
    Result := TResult.Failure('Permission denied: You cannot delete this task');
  end;
end;

function TPermissionGuard.CanManageUsers: TResult;
var
  LContext: ISecurityContext;
begin
  LContext := GetCurrentSecurityContext;
  if LContext = nil then
  begin
    FLogger.Warning('CanManageUsers: Security context not found');
    Result := TResult.Failure('Not authenticated');
    Exit;
  end;

  if LContext.Role = urAdmin then
  begin
    Result := TResult.Success;
  end
  else
  begin
    FLogger.Warning(Format('Permission denied: User %d attempted to manage users',
      [LContext.UserId]));
    Result := TResult.Failure('Permission denied: Only admins can manage users');
  end;
end;

end.
