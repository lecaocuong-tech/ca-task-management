unit DTOs;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DomainModels;

{
  DTOs.pas
  ---------
  Data Transfer Objects for the boundary between Use Cases (application layer)
  and the UI (presentation layer). DTOs ensure that domain entities are never
  exposed directly to the UI, enforcing the Clean Architecture boundary.

  Benefits:
  - UI cannot accidentally mutate domain state
  - Domain model can evolve independently of UI presentation
  - Clear contract for what data crosses the boundary
  - Serializable / testable without domain dependencies

  Mapping: DomainModels -> DTOs via static TDTOMapper class.
}

type
  // ==========================================================================
  // RESPONSE DTOs (Domain -> UI direction)
  // ==========================================================================

  /// <summary>Read-only task representation for the UI layer.</summary>
  TTaskDTO = record
    Id: Integer;
    UserId: Integer;
    Title: string;
    Description: string;
    Status: string;
    StatusEnum: TTaskStatus;
    CreatedAt: TDateTime;
    UpdatedAt: TDateTime;
    IsCompleted: Boolean;
  end;

  /// <summary>Read-only user representation for the UI layer.</summary>
  TUserDTO = record
    Id: Integer;
    Username: string;
    Role: string;
    RoleEnum: TUserRole;
    IsAdmin: Boolean;
    CreatedAt: TDateTime;
  end;

  // ==========================================================================
  // REQUEST DTOs (UI -> Application direction)
  // ==========================================================================

  /// <summary>Request to create a new task.</summary>
  TCreateTaskRequest = record
    Title: string;
    Description: string;
    class function Create(const ATitle: string; const ADescription: string = ''): TCreateTaskRequest; static;
  end;

  /// <summary>Request to update an existing task's content.</summary>
  TUpdateTaskRequest = record
    TaskId: Integer;
    Title: string;
    Description: string;
    class function Create(ATaskId: Integer; const ATitle, ADescription: string): TUpdateTaskRequest; static;
  end;

  /// <summary>Request to change a task's status.</summary>
  TChangeTaskStatusRequest = record
    TaskId: Integer;
    NewStatus: TTaskStatus;
    class function Create(ATaskId: Integer; ANewStatus: TTaskStatus): TChangeTaskStatusRequest; static;
  end;

  /// <summary>Request to create a new user (admin operation).</summary>
  TCreateUserRequest = record
    Username: string;
    Password: string;
    Role: TUserRole;
    class function Create(const AUsername, APassword: string; ARole: TUserRole): TCreateUserRequest; static;
  end;

  /// <summary>Request to update an existing user.</summary>
  TUpdateUserRequest = record
    UserId: Integer;
    NewPassword: string;
    NewRole: TUserRole;
    HasPasswordChange: Boolean;
    HasRoleChange: Boolean;
  end;

  /// <summary>Request to query tasks with optional filtering and pagination.</summary>
  TGetTasksRequest = record
    StatusFilter: string;
    PageNumber: Integer;
    PageSize: Integer;
    UseFiltering: Boolean;
    UsePagination: Boolean;
    class function Paged(APageNumber, APageSize: Integer): TGetTasksRequest; static;
    class function Filtered(const AStatusFilter: string): TGetTasksRequest; static;
    class function All: TGetTasksRequest; static;
  end;

  // ==========================================================================
  // RESPONSE WRAPPERS
  // ==========================================================================

  /// <summary>Generic use case response wrapping success/failure + data.</summary>
  TUseCaseResponse<T> = record
    IsSuccess: Boolean;
    ErrorMessage: string;
    Data: T;
    class function Success(const AData: T): TUseCaseResponse<T>; static;
    class function Failure(const AErrorMessage: string): TUseCaseResponse<T>; static;
  end;

  /// <summary>Paginated list response with metadata.</summary>
  TPagedResponse<T> = record
    Items: TArray<T>;
    TotalCount: Integer;
    PageNumber: Integer;
    PageSize: Integer;
    IsSuccess: Boolean;
    ErrorMessage: string;
    function TotalPages: Integer;
    function HasNextPage: Boolean;
    function HasPreviousPage: Boolean;
  end;

  // ==========================================================================
  // DTO MAPPER
  // ==========================================================================

  /// <summary>Maps domain entities to DTOs and vice versa.
  /// Centralizes all mapping logic in one place.</summary>
  TDTOMapper = class
  public
    /// <summary>Map a TTask domain entity to a TTaskDTO.</summary>
    class function ToTaskDTO(ATask: TTask): TTaskDTO;
    /// <summary>Map a list of TTask entities to an array of TTaskDTO.</summary>
    class function ToTaskDTOArray(ATasks: TList<TTask>): TArray<TTaskDTO>;
    /// <summary>Map a TUser domain entity to a TUserDTO.</summary>
    class function ToUserDTO(AUser: TUser): TUserDTO;
    /// <summary>Map a list of TUser entities to an array of TUserDTO.</summary>
    class function ToUserDTOArray(AUsers: TList<TUser>): TArray<TUserDTO>;
  end;

implementation

{ TCreateTaskRequest }

class function TCreateTaskRequest.Create(const ATitle: string; const ADescription: string = ''): TCreateTaskRequest;
begin
  Result.Title := ATitle;
  Result.Description := ADescription;
end;

{ TUpdateTaskRequest }

class function TUpdateTaskRequest.Create(ATaskId: Integer; const ATitle, ADescription: string): TUpdateTaskRequest;
begin
  Result.TaskId := ATaskId;
  Result.Title := ATitle;
  Result.Description := ADescription;
end;

{ TChangeTaskStatusRequest }

class function TChangeTaskStatusRequest.Create(ATaskId: Integer; ANewStatus: TTaskStatus): TChangeTaskStatusRequest;
begin
  Result.TaskId := ATaskId;
  Result.NewStatus := ANewStatus;
end;

{ TCreateUserRequest }

class function TCreateUserRequest.Create(const AUsername, APassword: string; ARole: TUserRole): TCreateUserRequest;
begin
  Result.Username := AUsername;
  Result.Password := APassword;
  Result.Role := ARole;
end;

{ TGetTasksRequest }

class function TGetTasksRequest.Paged(APageNumber, APageSize: Integer): TGetTasksRequest;
begin
  Result.StatusFilter := '';
  Result.PageNumber := APageNumber;
  Result.PageSize := APageSize;
  Result.UseFiltering := False;
  Result.UsePagination := True;
end;

class function TGetTasksRequest.Filtered(const AStatusFilter: string): TGetTasksRequest;
begin
  Result.StatusFilter := AStatusFilter;
  Result.PageNumber := 1;
  Result.PageSize := 0;
  Result.UseFiltering := True;
  Result.UsePagination := False;
end;

class function TGetTasksRequest.All: TGetTasksRequest;
begin
  Result.StatusFilter := '';
  Result.PageNumber := 1;
  Result.PageSize := 0;
  Result.UseFiltering := False;
  Result.UsePagination := False;
end;

{ TUseCaseResponse<T> }

class function TUseCaseResponse<T>.Success(const AData: T): TUseCaseResponse<T>;
begin
  Result.IsSuccess := True;
  Result.ErrorMessage := '';
  Result.Data := AData;
end;

class function TUseCaseResponse<T>.Failure(const AErrorMessage: string): TUseCaseResponse<T>;
begin
  Result.IsSuccess := False;
  Result.ErrorMessage := AErrorMessage;
end;

{ TPagedResponse<T> }

function TPagedResponse<T>.TotalPages: Integer;
begin
  if PageSize <= 0 then
    Result := 1
  else
    Result := (TotalCount + PageSize - 1) div PageSize;
end;

function TPagedResponse<T>.HasNextPage: Boolean;
begin
  Result := PageNumber < TotalPages;
end;

function TPagedResponse<T>.HasPreviousPage: Boolean;
begin
  Result := PageNumber > 1;
end;

{ TDTOMapper }

class function TDTOMapper.ToTaskDTO(ATask: TTask): TTaskDTO;
begin
  Result.Id := ATask.Id;
  Result.UserId := ATask.UserId;
  Result.Title := ATask.Title;
  Result.Description := ATask.Description;
  Result.Status := StatusToString(ATask.Status);
  Result.StatusEnum := ATask.Status;
  Result.CreatedAt := ATask.CreatedAt;
  Result.UpdatedAt := ATask.UpdatedAt;
  Result.IsCompleted := ATask.Status = tsDone;
end;

class function TDTOMapper.ToTaskDTOArray(ATasks: TList<TTask>): TArray<TTaskDTO>;
var
  I: Integer;
begin
  SetLength(Result, ATasks.Count);
  for I := 0 to ATasks.Count - 1 do
    Result[I] := ToTaskDTO(ATasks[I]);
end;

class function TDTOMapper.ToUserDTO(AUser: TUser): TUserDTO;
begin
  Result.Id := AUser.Id;
  Result.Username := AUser.Username;
  Result.Role := AUser.RoleToString;
  Result.RoleEnum := AUser.Role;
  Result.IsAdmin := AUser.IsAdmin;
  Result.CreatedAt := AUser.CreatedAt;
end;

class function TDTOMapper.ToUserDTOArray(AUsers: TList<TUser>): TArray<TUserDTO>;
var
  I: Integer;
begin
  SetLength(Result, AUsers.Count);
  for I := 0 to AUsers.Count - 1 do
    Result[I] := ToUserDTO(AUsers[I]);
end;

end.
