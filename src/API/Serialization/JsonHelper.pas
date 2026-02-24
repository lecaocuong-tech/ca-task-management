unit JsonHelper;

interface

{
  JsonHelper.pas
  ---------------
  JSON serialization/deserialization utilities for the REST API layer.
  Converts between domain DTOs and TJSONObject for HTTP responses/requests.

  Design decisions:
  - Uses System.JSON (built-in, no external dependencies)
  - All methods are class functions (stateless utility class)
  - Dates are formatted as ISO 8601 strings for interoperability
  - Null/empty values are included explicitly for predictable API contracts

  Usage patterns:
  - Response: TTask -> TJSONObject via TaskToJSON
  - Request:  TJSONObject -> record via ParseCreateTaskRequest
  - Lists:    TList<TTask> -> TJSONArray via TaskListToJSON

  ISO 8601 format: "2026-02-13T14:30:00.000Z"
}

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  System.Generics.Collections,
  DomainModels,
  DTOs;

type
  TJsonHelper = class
  public
    class function DateTimeToISO(ADateTime: TDateTime): string;
    class function ISOToDateTime(const AValue: string): TDateTime;

    class function TaskToJSON(ATask: TTask): TJSONObject;
    class function TaskDTOToJSON(const ADto: TTaskDTO): TJSONObject;
    class function TaskListToJSON(ATasks: TList<TTask>): TJSONArray;
    class function TaskDTOArrayToJSON(const ADtos: TArray<TTaskDTO>): TJSONArray;

    class function UserToJSON(AUser: TUser): TJSONObject;
    class function UserDTOToJSON(const ADto: TUserDTO): TJSONObject;
    class function UserListToJSON(AUsers: TList<TUser>): TJSONArray;

    class function ParseLoginRequest(AJson: TJSONObject;
      out AUsername, APassword: string): Boolean;
    class function ParseCreateTaskRequest(AJson: TJSONObject;
      out ATitle, ADescription: string): Boolean;
    class function ParseUpdateTaskRequest(AJson: TJSONObject;
      out ATitle, ADescription: string): Boolean;
    class function ParseChangeStatusRequest(AJson: TJSONObject;
      out AStatus: TTaskStatus): Boolean;
    class function ParseCreateUserRequest(AJson: TJSONObject;
      out AUsername, APassword: string; out ARole: TUserRole): Boolean;
    class function ParseUpdateUserRequest(AJson: TJSONObject;
      out APassword: string; out ARole: TUserRole;
      out AHasPassword, AHasRole: Boolean): Boolean;

    class function SuccessResponse(AData: TJSONValue): TJSONObject;
    class function ErrorResponse(ACode: Integer; const AMessage: string): TJSONObject;
    class function PaginatedResponse(AData: TJSONArray; ATotalCount, APage, APageSize: Integer): TJSONObject;
    class function TokenResponse(const AToken, AUsername, ARole: string;
      AExpiresAt: TDateTime): TJSONObject;

    class function GetJSONString(AJson: TJSONObject; const AKey: string;
      const ADefault: string = ''): string;
    class function GetJSONInt(AJson: TJSONObject; const AKey: string;
      ADefault: Integer = 0): Integer;
    class function HasJSONKey(AJson: TJSONObject; const AKey: string): Boolean;
  end;

implementation

class function TJsonHelper.DateTimeToISO(ADateTime: TDateTime): string;
begin
  if ADateTime = 0 then
    Result := ''
  else
    Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', ADateTime);
end;

class function TJsonHelper.ISOToDateTime(const AValue: string): TDateTime;
begin
  if AValue = '' then
    Result := 0
  else
  begin
    try
      Result := ISO8601ToDate(AValue, False);
    except
      Result := 0;
    end;
  end;
end;

class function TJsonHelper.TaskToJSON(ATask: TTask): TJSONObject;
begin
  Result := TJSONObject.Create;
  if ATask = nil then Exit;
  Result.AddPair('id', TJSONNumber.Create(ATask.Id));
  Result.AddPair('userId', TJSONNumber.Create(ATask.UserId));
  Result.AddPair('title', ATask.Title);
  Result.AddPair('description', ATask.Description);
  Result.AddPair('status', StatusToString(ATask.Status));
  Result.AddPair('createdAt', DateTimeToISO(ATask.CreatedAt));
  Result.AddPair('updatedAt', DateTimeToISO(ATask.UpdatedAt));
  Result.AddPair('isCompleted', TJSONBool.Create(ATask.Status = tsDone));
end;

class function TJsonHelper.TaskDTOToJSON(const ADto: TTaskDTO): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(ADto.Id));
  Result.AddPair('userId', TJSONNumber.Create(ADto.UserId));
  Result.AddPair('title', ADto.Title);
  Result.AddPair('description', ADto.Description);
  Result.AddPair('status', ADto.Status);
  Result.AddPair('createdAt', DateTimeToISO(ADto.CreatedAt));
  Result.AddPair('updatedAt', DateTimeToISO(ADto.UpdatedAt));
  Result.AddPair('isCompleted', TJSONBool.Create(ADto.IsCompleted));
end;

class function TJsonHelper.TaskListToJSON(ATasks: TList<TTask>): TJSONArray;
var
  LTask: TTask;
begin
  Result := TJSONArray.Create;
  if ATasks = nil then Exit;
  for LTask in ATasks do
    Result.AddElement(TaskToJSON(LTask));
end;

class function TJsonHelper.TaskDTOArrayToJSON(const ADtos: TArray<TTaskDTO>): TJSONArray;
var
  LDto: TTaskDTO;
begin
  Result := TJSONArray.Create;
  for LDto in ADtos do
    Result.AddElement(TaskDTOToJSON(LDto));
end;

class function TJsonHelper.UserToJSON(AUser: TUser): TJSONObject;
begin
  Result := TJSONObject.Create;
  if AUser = nil then Exit;
  Result.AddPair('id', TJSONNumber.Create(AUser.Id));
  Result.AddPair('username', AUser.Username);
  Result.AddPair('role', AUser.RoleToString);
  Result.AddPair('isAdmin', TJSONBool.Create(AUser.IsAdmin));
  Result.AddPair('createdAt', DateTimeToISO(AUser.CreatedAt));
end;

class function TJsonHelper.UserDTOToJSON(const ADto: TUserDTO): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(ADto.Id));
  Result.AddPair('username', ADto.Username);
  Result.AddPair('role', ADto.Role);
  Result.AddPair('isAdmin', TJSONBool.Create(ADto.IsAdmin));
  Result.AddPair('createdAt', DateTimeToISO(ADto.CreatedAt));
end;

class function TJsonHelper.UserListToJSON(AUsers: TList<TUser>): TJSONArray;
var
  LUser: TUser;
begin
  Result := TJSONArray.Create;
  if AUsers = nil then Exit;
  for LUser in AUsers do
    Result.AddElement(UserToJSON(LUser));
end;

class function TJsonHelper.ParseLoginRequest(AJson: TJSONObject;
  out AUsername, APassword: string): Boolean;
begin
  Result := False;
  if AJson = nil then Exit;
  AUsername := GetJSONString(AJson, 'username');
  APassword := GetJSONString(AJson, 'password');
  Result := (AUsername <> '') and (APassword <> '');
end;

class function TJsonHelper.ParseCreateTaskRequest(AJson: TJSONObject;
  out ATitle, ADescription: string): Boolean;
begin
  Result := False;
  if AJson = nil then Exit;
  ATitle := GetJSONString(AJson, 'title');
  ADescription := GetJSONString(AJson, 'description');
  Result := (ATitle <> '');
end;

class function TJsonHelper.ParseUpdateTaskRequest(AJson: TJSONObject;
  out ATitle, ADescription: string): Boolean;
begin
  Result := False;
  if AJson = nil then Exit;
  ATitle := GetJSONString(AJson, 'title');
  ADescription := GetJSONString(AJson, 'description');
  Result := (ATitle <> '');
end;

class function TJsonHelper.ParseChangeStatusRequest(AJson: TJSONObject;
  out AStatus: TTaskStatus): Boolean;
var
  LStatusStr: string;
begin
  Result := False;
  if AJson = nil then Exit;
  LStatusStr := GetJSONString(AJson, 'status');
  if LStatusStr = '' then Exit;
  AStatus := StringToStatus(LStatusStr);
  Result := (AStatus <> tsUnknown);
end;

class function TJsonHelper.ParseCreateUserRequest(AJson: TJSONObject;
  out AUsername, APassword: string; out ARole: TUserRole): Boolean;
var
  LRoleStr: string;
begin
  Result := False;
  if AJson = nil then Exit;
  AUsername := GetJSONString(AJson, 'username');
  APassword := GetJSONString(AJson, 'password');
  LRoleStr := GetJSONString(AJson, 'role');
  if (AUsername = '') or (APassword = '') then Exit;
  if SameText(LRoleStr, 'Admin') then
    ARole := urAdmin
  else
    ARole := urUser;
  Result := True;
end;

class function TJsonHelper.ParseUpdateUserRequest(AJson: TJSONObject;
  out APassword: string; out ARole: TUserRole;
  out AHasPassword, AHasRole: Boolean): Boolean;
var
  LRoleStr: string;
begin
  Result := False;
  if AJson = nil then Exit;
  AHasPassword := HasJSONKey(AJson, 'password');
  AHasRole := HasJSONKey(AJson, 'role');
  if AHasPassword then
    APassword := GetJSONString(AJson, 'password')
  else
    APassword := '';
  if AHasRole then
  begin
    LRoleStr := GetJSONString(AJson, 'role');
    if SameText(LRoleStr, 'Admin') then
      ARole := urAdmin
    else
      ARole := urUser;
  end
  else
    ARole := urUser;
  Result := AHasPassword or AHasRole;
end;

class function TJsonHelper.SuccessResponse(AData: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('success', TJSONBool.Create(True));
  if AData <> nil then
    Result.AddPair('data', AData)
  else
    Result.AddPair('data', TJSONNull.Create);
end;

class function TJsonHelper.ErrorResponse(ACode: Integer; const AMessage: string): TJSONObject;
var
  LError: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('success', TJSONBool.Create(False));
  LError := TJSONObject.Create;
  LError.AddPair('code', TJSONNumber.Create(ACode));
  LError.AddPair('message', AMessage);
  Result.AddPair('error', LError);
end;

class function TJsonHelper.PaginatedResponse(AData: TJSONArray;
  ATotalCount, APage, APageSize: Integer): TJSONObject;
var
  LMeta: TJSONObject;
  LTotalPages: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('success', TJSONBool.Create(True));
  Result.AddPair('data', AData);
  if APageSize > 0 then
    LTotalPages := (ATotalCount + APageSize - 1) div APageSize
  else
    LTotalPages := 1;
  LMeta := TJSONObject.Create;
  LMeta.AddPair('totalCount', TJSONNumber.Create(ATotalCount));
  LMeta.AddPair('page', TJSONNumber.Create(APage));
  LMeta.AddPair('pageSize', TJSONNumber.Create(APageSize));
  LMeta.AddPair('totalPages', TJSONNumber.Create(LTotalPages));
  LMeta.AddPair('hasNextPage', TJSONBool.Create(APage < LTotalPages));
  LMeta.AddPair('hasPreviousPage', TJSONBool.Create(APage > 1));
  Result.AddPair('meta', LMeta);
end;

class function TJsonHelper.TokenResponse(const AToken, AUsername, ARole: string;
  AExpiresAt: TDateTime): TJSONObject;
var
  LData: TJSONObject;
begin
  LData := TJSONObject.Create;
  LData.AddPair('token', AToken);
  LData.AddPair('tokenType', 'Bearer');
  LData.AddPair('username', AUsername);
  LData.AddPair('role', ARole);
  LData.AddPair('expiresAt', DateTimeToISO(AExpiresAt));
  Result := SuccessResponse(LData);
end;

class function TJsonHelper.GetJSONString(AJson: TJSONObject; const AKey: string;
  const ADefault: string = ''): string;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if AJson = nil then Exit;
  LValue := AJson.GetValue(AKey);
  if (LValue <> nil) and not (LValue is TJSONNull) then
    Result := LValue.Value;
end;

class function TJsonHelper.GetJSONInt(AJson: TJSONObject; const AKey: string;
  ADefault: Integer = 0): Integer;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if AJson = nil then Exit;
  LValue := AJson.GetValue(AKey);
  if (LValue <> nil) and (LValue is TJSONNumber) then
    Result := TJSONNumber(LValue).AsInt;
end;

class function TJsonHelper.HasJSONKey(AJson: TJSONObject; const AKey: string): Boolean;
begin
  Result := (AJson <> nil) and (AJson.GetValue(AKey) <> nil);
end;

end.
