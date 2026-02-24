unit UserRepository;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Comp.Client,
  AppInterfaces,
  InfraInterfaces,
  DomainModels,
  Result;

{
  UserRepository.pas
  ------------------
  Concrete repository implementing user persistence.
  IUserRepository interface is declared in AppInterfaces.pas (Dependency Inversion).
  All public methods either return domain objects or TResult wrappers.

  Notes:
  - Methods returning TList<TUser> use TObjectList<TUser> with OwnsObjects=True;
    callers only need to free the list itself (items are auto-freed).
  - Create/Update/Delete operations run inside transactions via IDatabaseManager.
}

type
  TUserRepository = class(TInterfacedObject, IUserRepository)
  private
    FDatabaseManager: IDatabaseManager;
    FLogger: ILogger;
  public
    constructor Create(ADatabaseManager: IDatabaseManager; ALogger: ILogger);

    function GetUserById(AUserId: Integer): TUser;
    function GetUserByUsername(const AUsername: string): TUser;
    function CreateUser(const AUsername, APasswordHash, ASalt: string; ARole: TUserRole): TResult<TUser>;
    function UpdateUser(AUser: TUser): TResult;
    function DeleteUser(AUserId: Integer): TResult;
    function GetAllUsers: TList<TUser>;
    function GetAllUsersPaged(APageNum, APageSize: Integer): TList<TUser>;
    function GetUserCount: Integer;

  private
    // Map current dataset row to a newly allocated TUser instance.
    function DataSetToUser(ADataSet: TDataSet): TUser;
  end;

implementation

{ TUserRepository }

constructor TUserRepository.Create(ADatabaseManager: IDatabaseManager; ALogger: ILogger);
begin
  inherited Create;
  FDatabaseManager := ADatabaseManager;
  FLogger := ALogger;
end;

function TUserRepository.DataSetToUser(ADataSet: TDataSet): TUser;
var
  LSalt: string;
begin
  if ADataSet.FindField('Salt') <> nil then
    LSalt := ADataSet.FieldByName('Salt').AsString
  else
    LSalt := '';

  Result := TUser.Hydrate(
    ADataSet.FieldByName('Id').AsInteger,
    ADataSet.FieldByName('Username').AsString,
    ADataSet.FieldByName('PasswordHash').AsString,
    LSalt,
    StringToUserRole(ADataSet.FieldByName('Role').AsString),
    ADataSet.FieldByName('CreatedAt').AsDateTime
  );
end;

function TUserRepository.GetUserById(AUserId: Integer): TUser;
var
  LQuery: TFDQuery;
begin
  Result := nil;
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT * FROM Users WHERE Id = :Id';
        LQuery.ParamByName('Id').AsInteger := AUserId;
        LQuery.Open;
        if not LQuery.IsEmpty then
        begin
          LQuery.First;
          Result := DataSetToUser(LQuery);
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetUserById failed', E);
        Result := nil;
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TUserRepository.GetUserByUsername(const AUsername: string): TUser;
var
  LQuery: TFDQuery;
begin
  Result := nil;
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT * FROM Users WHERE Username = :Username';
        LQuery.ParamByName('Username').AsString := AUsername;
        LQuery.Open;
        if not LQuery.IsEmpty then
        begin
          LQuery.First;
          Result := DataSetToUser(LQuery);
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetUserByUsername failed', E);
        Result := nil;
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TUserRepository.CreateUser(const AUsername, APasswordHash, ASalt: string; ARole: TUserRole): TResult<TUser>;
var
  LQuery: TFDQuery;
  LUser: TUser;
begin
  // Create runs in a transaction to ensure DB consistency
  FDatabaseManager.BeginTransaction;
  try
    LQuery := FDatabaseManager.CreateQuery;
    try
      LQuery.SQL.Text := 'INSERT INTO Users (Username, PasswordHash, Salt, Role, CreatedAt) ' +
        'VALUES (:Username, :PasswordHash, :Salt, :Role, CURRENT_TIMESTAMP)';
      LQuery.ParamByName('Username').AsString := AUsername;
      LQuery.ParamByName('PasswordHash').AsString := APasswordHash;
      LQuery.ParamByName('Salt').AsString := ASalt;
      LQuery.ParamByName('Role').AsString := UserRoleToString(ARole);
      LQuery.ExecSQL;
    finally
      LQuery.Free;
    end;

    FDatabaseManager.Commit;
  except
    on E: Exception do
    begin
      FDatabaseManager.Rollback;
      FLogger.Error('CreateUser failed', E);
      Result := TResult<TUser>.Failure('Error creating user: ' + E.Message);
      Exit;
    end;
  end;

  // Post-commit: fetch created user
  LUser := GetUserByUsername(AUsername);
  if LUser <> nil then
    Result := TResult<TUser>.Success(LUser)
  else
    Result := TResult<TUser>.Failure('Cannot retrieve created user');
end;

function TUserRepository.UpdateUser(AUser: TUser): TResult;
var
  LQuery: TFDQuery;
begin
  FDatabaseManager.BeginTransaction;
  try
    LQuery := FDatabaseManager.CreateQuery;
    try
      LQuery.SQL.Text := 'UPDATE Users SET Username = :Username, PasswordHash = :PasswordHash, ' +
        'Salt = :Salt, Role = :Role WHERE Id = :Id';
      LQuery.ParamByName('Username').AsString := AUser.Username;
      LQuery.ParamByName('PasswordHash').AsString := AUser.PasswordHash;
      LQuery.ParamByName('Salt').AsString := AUser.Salt;
      LQuery.ParamByName('Role').AsString := UserRoleToString(AUser.Role);
      LQuery.ParamByName('Id').AsInteger := AUser.Id;
      LQuery.ExecSQL;
    finally
      LQuery.Free;
    end;

    FDatabaseManager.Commit;
    Result := TResult.Success;
  except
    on E: Exception do
    begin
      FDatabaseManager.Rollback;
      FLogger.Error('UpdateUser failed', E);
      Result := TResult.Failure('Error updating user: ' + E.Message);
    end;
  end;
end;

function TUserRepository.DeleteUser(AUserId: Integer): TResult;
var
  LQuery: TFDQuery;
begin
  FDatabaseManager.BeginTransaction;
  try
    LQuery := FDatabaseManager.CreateQuery;
    try
      LQuery.SQL.Text := 'DELETE FROM Users WHERE Id = :Id';
      LQuery.ParamByName('Id').AsInteger := AUserId;
      LQuery.ExecSQL;
    finally
      LQuery.Free;
    end;

    FDatabaseManager.Commit;
    Result := TResult.Success;
  except
    on E: Exception do
    begin
      FDatabaseManager.Rollback;
      FLogger.Error('DeleteUser failed', E);
      Result := TResult.Failure('Error deleting user: ' + E.Message);
    end;
  end;
end;

function TUserRepository.GetAllUsers: TList<TUser>;
var
  LQuery: TFDQuery;
begin
  Result := TObjectList<TUser>.Create(True);
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT * FROM Users ORDER BY Username';
        LQuery.Open;
        while not LQuery.Eof do
        begin
          Result.Add(DataSetToUser(LQuery));
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetAllUsers failed', E);
        Result.Free;
        Result := TObjectList<TUser>.Create(True);
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TUserRepository.GetAllUsersPaged(APageNum, APageSize: Integer): TList<TUser>;
var
  LQuery: TFDQuery;
  LOffset: Integer;
begin
  Result := TObjectList<TUser>.Create(True);
  FDatabaseManager.AcquireLock;
  try
    try
      LOffset := (APageNum - 1) * APageSize;
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT * FROM Users ORDER BY Username LIMIT :Limit OFFSET :Offset';
        LQuery.ParamByName('Limit').AsInteger := APageSize;
        LQuery.ParamByName('Offset').AsInteger := LOffset;
        LQuery.Open;
        while not LQuery.Eof do
        begin
          Result.Add(DataSetToUser(LQuery));
          LQuery.Next;
        end;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetAllUsersPaged failed', E);
        Result.Free;
        Result := TObjectList<TUser>.Create(True);
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

function TUserRepository.GetUserCount: Integer;
var
  LQuery: TFDQuery;
begin
  Result := 0;
  FDatabaseManager.AcquireLock;
  try
    try
      LQuery := FDatabaseManager.CreateQuery;
      try
        LQuery.SQL.Text := 'SELECT COUNT(*) as UserCount FROM Users';
        LQuery.Open;
        if not LQuery.IsEmpty then
          Result := LQuery.FieldByName('UserCount').AsInteger;
      finally
        LQuery.Free;
      end;
    except
      on E: Exception do
      begin
        FLogger.Error('GetUserCount failed', E);
        Result := 0;
      end;
    end;
  finally
    FDatabaseManager.ReleaseLock;
  end;
end;

end.
