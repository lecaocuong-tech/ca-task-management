unit DatabaseManager;

interface

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Option,
  FireDAC.UI.Intf,
  FireDAC.VCLUI.Wait,
  FireDAC.Stan.Error,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.DatS,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  AppInterfaces,
  InfraInterfaces;

{
  DatabaseManager.pas
  --------------------
  Centralized database helper that owns a single shared FireDAC connection.

  Responsibilities:
  - Initialize and open SQLite connection (WAL mode enabled).
  - Provide `CreateQuery` that returns TFDQuery linked to shared connection.
  - Provide transaction helper where BeginTransaction acquires monitor lock and
    Commit/Rollback releases it (lock pair model).
  - Provide AcquireLock/ReleaseLock for short read operations.
  - Run simple migrations on startup.

  Core and transaction model:
  - Write/transaction: call BeginTransaction->(use queries)->Commit/Rollback.
    BeginTransaction acquires lock; Commit/Rollback releases it.
  - Read: AcquireLock/ReleaseLock provide mutual exclusion scope for
    code that should not run concurrently with ongoing transaction.

  This design avoids creating a connection per query so transactions and
  last_insert_rowid() work predictably on the same connection.

  IDatabaseManager interface is declared in InfraInterfaces.pas (Dependency Inversion).
}

type
  TDatabaseManager = class(TInterfacedObject, IDatabaseManager)
  private
    FConnection: TFDConnection;
    FLock: TObject;      // Monitor object for synchronization
    FLogger: ILogger;
    FDbPath: string;
  public
    constructor Create(const ADbPath: string; ALogger: ILogger);
    destructor Destroy; override;

    function CreateQuery: TFDQuery;
    procedure BeginTransaction;
    procedure Commit;
    procedure Rollback;
    procedure AcquireLock;
    procedure ReleaseLock;

  private
    procedure InitializeDatabase; // Open connection and ensure tables
    procedure RunMigrations;      // Apply lightweight migrations safely
  end;

implementation

{ TDatabaseManager }

constructor TDatabaseManager.Create(const ADbPath: string; ALogger: ILogger);
begin
  inherited Create;
  FLogger := ALogger;
  FDbPath := ADbPath;

  // Note: the connection is shared across the process; queries returned by
  // CreateQuery should be created/freed by their callers but will use this
  // TFDConnection as Connection.
  FConnection := TFDConnection.Create(nil);
  FLock := TObject.Create;
  FConnection.DriverName := 'SQLite';

  FConnection.Params.Values['Database'] := ADbPath;
  FConnection.Params.Values['BusyTimeout'] := '10000';

  FConnection.TxOptions.AutoStart := False;
  FConnection.TxOptions.AutoStop := False;

  FLogger.Info('Initializing database: ' + ADbPath);
  InitializeDatabase;
end;

destructor TDatabaseManager.Destroy;
begin
  if FConnection.Connected then
    FConnection.Close;
  FConnection.Free;
  FLock.Free;
  inherited;
end;

procedure TDatabaseManager.AcquireLock;
begin
  // Acquire a simple monitor lock for short read scopes
  TMonitor.Enter(FLock);
end;

procedure TDatabaseManager.ReleaseLock;
begin
  TMonitor.Exit(FLock);
end;

function TDatabaseManager.CreateQuery: TFDQuery;
begin
  // Caller is responsible for freeing the returned TFDQuery. It uses the shared connection.
  Result := TFDQuery.Create(nil);
  Result.Connection := FConnection;
end;

procedure TDatabaseManager.BeginTransaction;
begin
  // Acquire the monitor lock for the duration of the transaction so that
  // other readers/writers coordinate correctly.
  AcquireLock;
  try
    FConnection.StartTransaction;
  except
    // If starting transaction fails, release the lock and propagate.
    ReleaseLock;
    raise;
  end;
end;

procedure TDatabaseManager.Commit;
begin
  try
    if FConnection.InTransaction then
      FConnection.Commit;
  finally
    // Always release the lock when leaving the transaction scope
    ReleaseLock;
  end;
end;

procedure TDatabaseManager.Rollback;
begin
  try
    if FConnection.InTransaction then
      FConnection.Rollback;
  finally
    ReleaseLock;
  end;
end;

procedure TDatabaseManager.InitializeDatabase;
var
  LRetries: Integer;
  LSuccess: Boolean;
begin
  LRetries := 0;
  LSuccess := False;

  while (LRetries < 5) and not LSuccess do
  begin
    try
      if FConnection.Connected then
        FConnection.Close;
      Sleep(100);
      FConnection.Open;
      LSuccess := True;
      FLogger.Info('Database connected successfully');
    except
      on E: Exception do
      begin
        Inc(LRetries);
        FLogger.Error(Format('Database connection attempt %d failed: %s', [LRetries, E.Message]));
        try
          if FConnection.Connected then
            FConnection.Close;
        except
          // Ignore close errors
        end;
        if LRetries < 5 then
          Sleep(LRetries * 200);
      end;
    end;
  end;

  if not LSuccess then
    raise Exception.Create('Cannot connect to database: ' + FDbPath);

  // Enable WAL mode for better concurrent read performance
  FConnection.ExecSQL('PRAGMA journal_mode=WAL');
  FConnection.ExecSQL('PRAGMA busy_timeout=10000');

  try
    // Ensure Users table exists
    if FConnection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sqlite_master WHERE type=''table'' AND name=''Users'''
    ) = 0 then
    begin
      FConnection.ExecSQL(
        'CREATE TABLE Users (' +
        '  Id INTEGER PRIMARY KEY AUTOINCREMENT,' +
        '  Username TEXT UNIQUE NOT NULL,' +
        '  PasswordHash TEXT NOT NULL,' +
        '  Salt TEXT NOT NULL DEFAULT '''',' +
        '  Role TEXT NOT NULL,' +
        '  CreatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP' +
        ')'
      );
      FLogger.Info('Created Users table');
    end;

    // Ensure Tasks table exists
    if FConnection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sqlite_master WHERE type=''table'' AND name=''Tasks'''
    ) = 0 then
    begin
      FConnection.ExecSQL(
        'CREATE TABLE Tasks (' +
        '  Id INTEGER PRIMARY KEY AUTOINCREMENT,' +
        '  UserId INTEGER NOT NULL,' +
        '  Title TEXT NOT NULL,' +
        '  Description TEXT DEFAULT '''',' +
        '  Status TEXT NOT NULL DEFAULT ''Pending'',' +
        '  CreatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,' +
        '  UpdatedAt DATETIME,' +
        '  FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE' +
        ')'
      );
      FLogger.Info('Created Tasks table');
    end;

    RunMigrations;
    FLogger.Info('Database initialization completed');
  except
    on E: Exception do
    begin
      FLogger.Error('Database initialization failed: ' + E.Message, E);
      raise;
    end;
  end;
end;

procedure TDatabaseManager.RunMigrations;
var
  LQuery: TFDQuery;
  LHasColumn: Boolean;
begin
  // Migration: Add Salt column to Users if missing. Ignore failure when already present.
  try
    FConnection.ExecSQL('ALTER TABLE Users ADD COLUMN Salt TEXT NOT NULL DEFAULT ''''');
    FLogger.Info('Migration: Added Salt column to Users');
  except
    // Column already exists - ignore
  end;

  // Migration: Add Description column to Tasks if missing
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := FConnection;
    LQuery.SQL.Text := 'PRAGMA table_info(Tasks)';
    LQuery.Open;
    LHasColumn := False;
    while not LQuery.Eof do
    begin
      if SameText(LQuery.FieldByName('name').AsString, 'Description') then
      begin
        LHasColumn := True;
        Break;
      end;
      LQuery.Next;
    end;
    LQuery.Close;

    if not LHasColumn then
    begin
      FConnection.ExecSQL('ALTER TABLE Tasks ADD COLUMN Description TEXT DEFAULT ''''');
      FLogger.Info('Migration: Added Description column to Tasks');
    end;
  finally
    LQuery.Free;
  end;
end;

end.
