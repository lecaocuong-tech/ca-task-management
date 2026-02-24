unit DataSeeder;

interface

uses
  System.SysUtils,
  AppInterfaces,
  DomainModels,
  Result;

{
  DataSeeder.pas
  ---------------
  Extracted from TaskManager.dpr to improve separation of concerns.
  Handles initialization of default data (admin user, test users).

  IDataSeeder interface is declared in AppInterfaces.pas.
  The seeder receives its dependencies via constructor injection,
  keeping the composition root (DPR / ServiceContainer) clean.
}

type
  /// <summary>Seeds default data into the database on first run.
  /// Creates admin and test user accounts with salted KDF passwords.</summary>
  TDataSeeder = class(TInterfacedObject, IDataSeeder)
  private
    FUserRepository: IUserRepository;
    FAuthService: IAuthenticationService;
    FLogger: ILogger;

    procedure SeedUser(const AUsername, APassword: string; ARole: TUserRole);
  public
    constructor Create(AUserRepository: IUserRepository;
      AAuthService: IAuthenticationService; ALogger: ILogger);

    /// <summary>Check and create default users if they don't exist.</summary>
    procedure SeedDefaultData;
  end;

implementation

{ TDataSeeder }

constructor TDataSeeder.Create(AUserRepository: IUserRepository;
  AAuthService: IAuthenticationService; ALogger: ILogger);
begin
  inherited Create;
  FUserRepository := AUserRepository;
  FAuthService := AAuthService;
  FLogger := ALogger;
end;

procedure TDataSeeder.SeedUser(const AUsername, APassword: string; ARole: TUserRole);
var
  LUser: TUser;
  LSalt: string;
  LPasswordHash: string;
  LResult: TResult<TUser>;
begin
  LUser := FUserRepository.GetUserByUsername(AUsername);
  if LUser <> nil then
  begin
    LUser.Free;
    Exit; // User already exists
  end;

  LSalt := FAuthService.GenerateSalt;
  LPasswordHash := FAuthService.HashPasswordKDF(APassword, LSalt, 10000);
  LResult := FUserRepository.CreateUser(AUsername, LPasswordHash, LSalt, ARole);

  if LResult.IsSuccess then
    FLogger.Info(Format('Seeder: Created default user "%s" (role: %s)',
      [AUsername, UserRoleToString(ARole)]))
  else
    FLogger.Error(Format('Seeder: Failed to create user "%s": %s',
      [AUsername, LResult.GetErrorMessage]));
end;

procedure TDataSeeder.SeedDefaultData;
begin
  try
    FLogger.Info('Seeder: Checking default data...');

    // Create admin user
    SeedUser('admin', 'Admin@2026', urAdmin);

    // Create test user
    SeedUser('user1', 'User1@2026', urUser);

    FLogger.Info('Seeder: Default data check complete');
  except
    on E: Exception do
      FLogger.Error('Seeder: Error initializing default data - ' + E.Message, E);
  end;
end;

end.
