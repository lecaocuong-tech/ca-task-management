unit DTOsTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Generics.Collections,
  DomainModels,
  DTOs;

{
  DTOsTests.pas
  ---------------
  Unit tests for Data Transfer Objects and TDTOMapper.

  Tests verify:
  - TDTOMapper correctly maps TTask -> TTaskDTO
  - TDTOMapper correctly maps TUser -> TUserDTO
  - Array mapping produces correct count and content
  - Request DTO factory methods set fields correctly
  - TUseCaseResponse success/failure construction
  - TPagedResponse metadata calculations (TotalPages, HasNext, HasPrevious)
  - TGetTasksRequest factory methods (Paged, Filtered, All)
}

type
  [TestFixture]
  TTaskDTOMapperTests = class
  public
    [Test]
    procedure ToTaskDTO_MapsAllFields;
    [Test]
    procedure ToTaskDTO_DoneTask_IsCompleted;
    [Test]
    procedure ToTaskDTO_PendingTask_NotCompleted;
    [Test]
    procedure ToTaskDTOArray_EmptyList_ReturnsEmpty;
    [Test]
    procedure ToTaskDTOArray_MultipleItems_MapsAll;
  end;

  [TestFixture]
  TUserDTOMapperTests = class
  public
    [Test]
    procedure ToUserDTO_MapsAllFields;
    [Test]
    procedure ToUserDTO_AdminUser_IsAdmin;
    [Test]
    procedure ToUserDTO_RegularUser_NotAdmin;
    [Test]
    procedure ToUserDTOArray_MultipleItems_MapsAll;
  end;

  [TestFixture]
  TRequestDTOTests = class
  public
    [Test]
    procedure CreateTaskRequest_SetsFields;
    [Test]
    procedure UpdateTaskRequest_SetsFields;
    [Test]
    procedure ChangeTaskStatusRequest_SetsFields;
    [Test]
    procedure CreateUserRequest_SetsFields;
    [Test]
    procedure GetTasksRequest_Paged_SetsCorrectFlags;
    [Test]
    procedure GetTasksRequest_Filtered_SetsCorrectFlags;
    [Test]
    procedure GetTasksRequest_All_SetsCorrectFlags;
  end;

  [TestFixture]
  TResponseWrapperTests = class
  public
    [Test]
    procedure UseCaseResponse_Success_IsTrue;
    [Test]
    procedure UseCaseResponse_Failure_IsFalse;
    [Test]
    procedure UseCaseResponse_Failure_HasErrorMessage;
    [Test]
    procedure PagedResponse_TotalPages_Calculates;
    [Test]
    procedure PagedResponse_HasNextPage_True;
    [Test]
    procedure PagedResponse_HasNextPage_False;
    [Test]
    procedure PagedResponse_HasPreviousPage_True;
    [Test]
    procedure PagedResponse_HasPreviousPage_False;
  end;

implementation

{ TTaskDTOMapperTests }

procedure TTaskDTOMapperTests.ToTaskDTO_MapsAllFields;
var
  LTask: TTask;
  LDTO: TTaskDTO;
begin
  LTask := TTask.Hydrate(10, 5, 'My Task', 'Description', tsInProgress, EncodeDate(2026, 1, 15), EncodeDate(2026, 1, 16));
  try
    LDTO := TDTOMapper.ToTaskDTO(LTask);
    Assert.AreEqual(10, LDTO.Id);
    Assert.AreEqual(5, LDTO.UserId);
    Assert.AreEqual('My Task', LDTO.Title);
    Assert.AreEqual('Description', LDTO.Description);
    Assert.AreEqual('InProgress', LDTO.Status);
    Assert.AreEqual(Ord(tsInProgress), Ord(LDTO.StatusEnum));
  finally
    LTask.Free;
  end;
end;

procedure TTaskDTOMapperTests.ToTaskDTO_DoneTask_IsCompleted;
var
  LTask: TTask;
  LDTO: TTaskDTO;
begin
  LTask := TTask.Hydrate(1, 1, 'Done Task', '', tsDone, Now, Now);
  try
    LDTO := TDTOMapper.ToTaskDTO(LTask);
    Assert.IsTrue(LDTO.IsCompleted);
  finally
    LTask.Free;
  end;
end;

procedure TTaskDTOMapperTests.ToTaskDTO_PendingTask_NotCompleted;
var
  LTask: TTask;
  LDTO: TTaskDTO;
begin
  LTask := TTask.Hydrate(1, 1, 'Pending Task', '', tsPending, Now, 0);
  try
    LDTO := TDTOMapper.ToTaskDTO(LTask);
    Assert.IsFalse(LDTO.IsCompleted);
  finally
    LTask.Free;
  end;
end;

procedure TTaskDTOMapperTests.ToTaskDTOArray_EmptyList_ReturnsEmpty;
var
  LTasks: TList<TTask>;
  LDTOs: TArray<TTaskDTO>;
begin
  LTasks := TObjectList<TTask>.Create(True);
  try
    LDTOs := TDTOMapper.ToTaskDTOArray(LTasks);
    Assert.AreEqual(0, Length(LDTOs));
  finally
    LTasks.Free;
  end;
end;

procedure TTaskDTOMapperTests.ToTaskDTOArray_MultipleItems_MapsAll;
var
  LTasks: TList<TTask>;
  LDTOs: TArray<TTaskDTO>;
begin
  LTasks := TObjectList<TTask>.Create(True);
  try
    LTasks.Add(TTask.Hydrate(1, 1, 'Task A', '', tsPending, Now, 0));
    LTasks.Add(TTask.Hydrate(2, 1, 'Task B', '', tsDone, Now, Now));
    LTasks.Add(TTask.Hydrate(3, 2, 'Task C', '', tsInProgress, Now, Now));

    LDTOs := TDTOMapper.ToTaskDTOArray(LTasks);
    Assert.AreEqual(3, Length(LDTOs));
    Assert.AreEqual('Task A', LDTOs[0].Title);
    Assert.AreEqual('Task B', LDTOs[1].Title);
    Assert.AreEqual('Task C', LDTOs[2].Title);
  finally
    LTasks.Free;
  end;
end;

{ TUserDTOMapperTests }

procedure TUserDTOMapperTests.ToUserDTO_MapsAllFields;
var
  LUser: TUser;
  LDTO: TUserDTO;
begin
  LUser := TUser.Hydrate(3, 'john', 'hash', 'salt', urUser, EncodeDate(2026, 2, 1));
  try
    LDTO := TDTOMapper.ToUserDTO(LUser);
    Assert.AreEqual(3, LDTO.Id);
    Assert.AreEqual('john', LDTO.Username);
    Assert.AreEqual('User', LDTO.Role);
    Assert.AreEqual(Ord(urUser), Ord(LDTO.RoleEnum));
  finally
    LUser.Free;
  end;
end;

procedure TUserDTOMapperTests.ToUserDTO_AdminUser_IsAdmin;
var
  LUser: TUser;
  LDTO: TUserDTO;
begin
  LUser := TUser.Hydrate(1, 'admin', 'hash', 'salt', urAdmin, Now);
  try
    LDTO := TDTOMapper.ToUserDTO(LUser);
    Assert.IsTrue(LDTO.IsAdmin);
  finally
    LUser.Free;
  end;
end;

procedure TUserDTOMapperTests.ToUserDTO_RegularUser_NotAdmin;
var
  LUser: TUser;
  LDTO: TUserDTO;
begin
  LUser := TUser.Hydrate(2, 'user1', 'hash', 'salt', urUser, Now);
  try
    LDTO := TDTOMapper.ToUserDTO(LUser);
    Assert.IsFalse(LDTO.IsAdmin);
  finally
    LUser.Free;
  end;
end;

procedure TUserDTOMapperTests.ToUserDTOArray_MultipleItems_MapsAll;
var
  LUsers: TList<TUser>;
  LDTOs: TArray<TUserDTO>;
begin
  LUsers := TObjectList<TUser>.Create(True);
  try
    LUsers.Add(TUser.Hydrate(1, 'admin', 'h', 's', urAdmin, Now));
    LUsers.Add(TUser.Hydrate(2, 'user1', 'h', 's', urUser, Now));
    LDTOs := TDTOMapper.ToUserDTOArray(LUsers);
    Assert.AreEqual(2, Length(LDTOs));
    Assert.AreEqual('admin', LDTOs[0].Username);
    Assert.AreEqual('user1', LDTOs[1].Username);
  finally
    LUsers.Free;
  end;
end;

{ TRequestDTOTests }

procedure TRequestDTOTests.CreateTaskRequest_SetsFields;
var
  LReq: TCreateTaskRequest;
begin
  LReq := TCreateTaskRequest.Create('My Task', 'My Description');
  Assert.AreEqual('My Task', LReq.Title);
  Assert.AreEqual('My Description', LReq.Description);
end;

procedure TRequestDTOTests.UpdateTaskRequest_SetsFields;
var
  LReq: TUpdateTaskRequest;
begin
  LReq := TUpdateTaskRequest.Create(10, 'Updated', 'Desc');
  Assert.AreEqual(10, LReq.TaskId);
  Assert.AreEqual('Updated', LReq.Title);
  Assert.AreEqual('Desc', LReq.Description);
end;

procedure TRequestDTOTests.ChangeTaskStatusRequest_SetsFields;
var
  LReq: TChangeTaskStatusRequest;
begin
  LReq := TChangeTaskStatusRequest.Create(5, tsDone);
  Assert.AreEqual(5, LReq.TaskId);
  Assert.AreEqual(Ord(tsDone), Ord(LReq.NewStatus));
end;

procedure TRequestDTOTests.CreateUserRequest_SetsFields;
var
  LReq: TCreateUserRequest;
begin
  LReq := TCreateUserRequest.Create('admin', 'Pass123', urAdmin);
  Assert.AreEqual('admin', LReq.Username);
  Assert.AreEqual('Pass123', LReq.Password);
  Assert.AreEqual(Ord(urAdmin), Ord(LReq.Role));
end;

procedure TRequestDTOTests.GetTasksRequest_Paged_SetsCorrectFlags;
var
  LReq: TGetTasksRequest;
begin
  LReq := TGetTasksRequest.Paged(2, 10);
  Assert.AreEqual(2, LReq.PageNumber);
  Assert.AreEqual(10, LReq.PageSize);
  Assert.IsTrue(LReq.UsePagination);
  Assert.IsFalse(LReq.UseFiltering);
end;

procedure TRequestDTOTests.GetTasksRequest_Filtered_SetsCorrectFlags;
var
  LReq: TGetTasksRequest;
begin
  LReq := TGetTasksRequest.Filtered('Done');
  Assert.AreEqual('Done', LReq.StatusFilter);
  Assert.IsTrue(LReq.UseFiltering);
  Assert.IsFalse(LReq.UsePagination);
end;

procedure TRequestDTOTests.GetTasksRequest_All_SetsCorrectFlags;
var
  LReq: TGetTasksRequest;
begin
  LReq := TGetTasksRequest.All;
  Assert.IsFalse(LReq.UseFiltering);
  Assert.IsFalse(LReq.UsePagination);
end;

{ TResponseWrapperTests }

procedure TResponseWrapperTests.UseCaseResponse_Success_IsTrue;
var
  LResp: TUseCaseResponse<Integer>;
begin
  LResp := TUseCaseResponse<Integer>.Success(42);
  Assert.IsTrue(LResp.IsSuccess);
  Assert.AreEqual(42, LResp.Data);
end;

procedure TResponseWrapperTests.UseCaseResponse_Failure_IsFalse;
var
  LResp: TUseCaseResponse<Integer>;
begin
  LResp := TUseCaseResponse<Integer>.Failure('Oops');
  Assert.IsFalse(LResp.IsSuccess);
end;

procedure TResponseWrapperTests.UseCaseResponse_Failure_HasErrorMessage;
var
  LResp: TUseCaseResponse<string>;
begin
  LResp := TUseCaseResponse<string>.Failure('Something went wrong');
  Assert.AreEqual('Something went wrong', LResp.ErrorMessage);
end;

procedure TResponseWrapperTests.PagedResponse_TotalPages_Calculates;
var
  LResp: TPagedResponse<Integer>;
begin
  LResp.TotalCount := 25;
  LResp.PageSize := 10;
  Assert.AreEqual(3, LResp.TotalPages); // ceil(25/10) = 3
end;

procedure TResponseWrapperTests.PagedResponse_HasNextPage_True;
var
  LResp: TPagedResponse<Integer>;
begin
  LResp.TotalCount := 25;
  LResp.PageSize := 10;
  LResp.PageNumber := 1;
  Assert.IsTrue(LResp.HasNextPage);
end;

procedure TResponseWrapperTests.PagedResponse_HasNextPage_False;
var
  LResp: TPagedResponse<Integer>;
begin
  LResp.TotalCount := 25;
  LResp.PageSize := 10;
  LResp.PageNumber := 3; // last page
  Assert.IsFalse(LResp.HasNextPage);
end;

procedure TResponseWrapperTests.PagedResponse_HasPreviousPage_True;
var
  LResp: TPagedResponse<Integer>;
begin
  LResp.PageNumber := 2;
  Assert.IsTrue(LResp.HasPreviousPage);
end;

procedure TResponseWrapperTests.PagedResponse_HasPreviousPage_False;
var
  LResp: TPagedResponse<Integer>;
begin
  LResp.PageNumber := 1;
  Assert.IsFalse(LResp.HasPreviousPage);
end;

end.
