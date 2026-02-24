
unit AuthenticationService;

interface

uses
  System.SysUtils,
  System.Hash,
  System.Generics.Collections,
  System.DateUtils,
  AppInterfaces,
  DomainModels,
  Result;

{
  AuthenticationService.pas
  -------------------------
  Authentication service: handles login, logout, registration, and
  password encryption utilities. Key points:

  - Passwords are stored as salted iterations (HashPasswordKDF).
  - Legacy unsalted passwords are detected and upgraded on successful login.
  - On successful login, the service sets a global Security Context via
    TSecurityContextManager (Services read this context for authorization).
  - Business results are returned via TResult / TResult<T>.

  Public contract (IAuthenticationService):
  - Login(username,password): authenticates credentials, sets security context.
  - Register(username,password): creates user with encrypted KDF salt.
  - Logout: clears security context.
  - IsAuthenticated: utility check.
  - HashPasswordKDF/GenerateSalt: utilities used for verification/setting salt.
}

type
  TAuthenticationService = class(TInterfacedObject, IAuthenticationService)
  private
    FUserRepository: IUserRepository;
    FLogger: ILogger;
    FSecurityContextProvider: ISecurityContextProvider;
    FFailedAttempts: TDictionary<string, Integer>;
    FLockoutUntil: TDictionary<string, TDateTime>;
  public
    constructor Create(AUserRepository: IUserRepository;
      ASecurityContextProvider: ISecurityContextProvider; ALogger: ILogger);
    destructor Destroy; override;

    function Login(const AUsername, APassword: string): TResult;
    function Register(const AUsername, APassword: string): TResult<TUser>;
    procedure Logout;
    function IsAuthenticated: Boolean;

    // Session query methods - allow UI to query current user without importing SecurityContext
    function GetCurrentUsername: string;
    function GetCurrentUserId: Integer;
    function IsCurrentUserAdmin: Boolean;

    // Exposed utilities used by other services or by initial seeding code.
    function HashPasswordKDF(const APassword, ASalt: string; AIterations: Integer = 10000): string;
    function GenerateSalt: string;
    function ValidatePasswordPolicy(const APassword: string): TResult;

  private
    const
      PBKDF2_ITERATIONS = 10000;
      MIN_PASSWORD_LENGTH = 6;
      MAX_LOGIN_ATTEMPTS = 5;
      LOCKOUT_MINUTES = 5;
    // Internal verification using the same KDF method.
    function VerifyPasswordKDF(const APassword, AHash, ASalt: string; AIterations: Integer = PBKDF2_ITERATIONS): Boolean;
    /// <summary>Centralized brute-force tracking: increments failed attempt counter
    /// and triggers account lockout when threshold is reached.</summary>
    procedure TrackFailedLoginAttempt(const ALowerUser, AUsername: string);
  end;

implementation

uses
  SecurityContext;  // Only needed for TSecurityContext.Create in Login

{ TAuthenticationService }

constructor TAuthenticationService.Create(AUserRepository: IUserRepository;
  ASecurityContextProvider: ISecurityContextProvider; ALogger: ILogger);
begin
  inherited Create;
  FUserRepository := AUserRepository;
  FSecurityContextProvider := ASecurityContextProvider;
  FLogger := ALogger;
  FFailedAttempts := TDictionary<string, Integer>.Create;
  FLockoutUntil := TDictionary<string, TDateTime>.Create;
end;

destructor TAuthenticationService.Destroy;
begin
  FFailedAttempts.Free;
  FLockoutUntil.Free;
  inherited;
end;

function TAuthenticationService.HashPasswordKDF(const APassword, ASalt: string; AIterations: Integer): string;
var
  I: Integer;
  LHash: string;
begin
  // Simple iterative KDF based on SHA-256 (upgrade from single hash).
  // Start by injecting salt into password and iterate N times to slow down
  // brute-force attacks.
  LHash := THashSHA2.GetHashString(APassword + ASalt);
  for I := 1 to AIterations - 1 do
    LHash := THashSHA2.GetHashString(LHash + ASalt);
  Result := LHash;
end;

function TAuthenticationService.VerifyPasswordKDF(const APassword, AHash, ASalt: string; AIterations: Integer): Boolean;
begin
  // Verify by computing the KDF of the entered password and comparing it with stored salt
  Result := HashPasswordKDF(APassword, ASalt, AIterations) = AHash;
end;

function TAuthenticationService.GenerateSalt: string;
begin
  // Generate unique salt for each user using GUID
  Result := TGUID.NewGuid.ToString;
end;

procedure TAuthenticationService.TrackFailedLoginAttempt(const ALowerUser, AUsername: string);
var
  LAttempts: Integer;
begin
  if not FFailedAttempts.TryGetValue(ALowerUser, LAttempts) then
    LAttempts := 0;
  Inc(LAttempts);
  FFailedAttempts.AddOrSetValue(ALowerUser, LAttempts);
  if LAttempts >= MAX_LOGIN_ATTEMPTS then
  begin
    FLockoutUntil.AddOrSetValue(ALowerUser, IncMinute(Now, LOCKOUT_MINUTES));
    FLogger.Warning(Format('Account locked out after %d failed attempts: %s', [LAttempts, AUsername]));
  end;
end;

function TAuthenticationService.Login(const AUsername, APassword: string): TResult;
var
  LUser: TUser;
  LLockUntil: TDateTime;
  LLowerUser: string;
begin
  // Check that input is not empty
  if AUsername = '' then
  begin
    FLogger.Warning('Login attempt with empty username');
    Result := TResult.Failure('Username cannot be empty');
    Exit;
  end;

  if APassword = '' then
  begin
    FLogger.Warning('Login attempt with empty password');
    Result := TResult.Failure('Password cannot be empty');
    Exit;
  end;

  // Brute-force protection: check lockout
  LLowerUser := LowerCase(AUsername);
  if FLockoutUntil.TryGetValue(LLowerUser, LLockUntil) then
  begin
    if Now < LLockUntil then
    begin
      FLogger.Warning('Login blocked: Account locked out - ' + AUsername);
      Result := TResult.Failure(Format('Account locked. Try again in %d minutes.',
        [MinutesBetween(LLockUntil, Now) + 1]));
      Exit;
    end
    else
    begin
      // Lockout expired — reset
      FLockoutUntil.Remove(LLowerUser);
      FFailedAttempts.Remove(LLowerUser);
    end;
  end;

  // Find user in database by username
  LUser := FUserRepository.GetUserByUsername(AUsername);
  
  if LUser = nil then
  begin
    TrackFailedLoginAttempt(LLowerUser, AUsername);
    FLogger.Warning('Login failed: User not found - ' + AUsername);
    Result := TResult.Failure('Invalid username or password');
    Exit;
  end;

  // Support for legacy unsalted passwords: if salt is empty, try legacy salt then upgrade
  if (LUser.Salt = '') then
  begin
    if THashSHA2.GetHashString(APassword) <> LUser.PasswordHash then
    begin
      FLogger.Warning('Login failed: Invalid password for user - ' + AUsername);
      LUser.Free;
      TrackFailedLoginAttempt(LLowerUser, AUsername);
      Result := TResult.Failure('Invalid username or password');
      Exit;
    end
    else
    begin
      // Upgrade to salted KDF for better security
      try
        var NewSalt := GenerateSalt;
        LUser.ChangePassword(HashPasswordKDF(APassword, NewSalt), NewSalt);
        FUserRepository.UpdateUser(LUser);
        FLogger.Info('Upgraded legacy password hash for user: ' + AUsername);
      except
        on E: Exception do
          FLogger.Warning('Failed to upgrade legacy password for user: ' + AUsername + ' - ' + E.Message);
      end;
    end;
  end
  else
  begin
    // Verify password using new salted KDF
    if not VerifyPasswordKDF(APassword, LUser.PasswordHash, LUser.Salt) then
    begin
      FLogger.Warning('Login failed: Invalid password for user - ' + AUsername);
      LUser.Free;
      TrackFailedLoginAttempt(LLowerUser, AUsername);
      Result := TResult.Failure('Invalid username or password');
      Exit;
    end;
  end;

  // Successful login - reset brute-force counters
  FFailedAttempts.Remove(LLowerUser);
  FLockoutUntil.Remove(LLowerUser);

  // Successful login - create SecurityContext and store globally
  // Other Services read this to check permissions and get UserId
  FSecurityContextProvider.SetSecurityContext(
    TSecurityContext.Create(LUser.Id, LUser.Username, LUser.Role)
  );

  FLogger.Info('User logged in: ' + AUsername);
  LUser.Free;
  Result := TResult.Success;
end;

function TAuthenticationService.ValidatePasswordPolicy(const APassword: string): TResult;
var
  LHasUpper, LHasLower, LHasDigit: Boolean;
  I: Integer;
begin
  if Length(APassword) < MIN_PASSWORD_LENGTH then
  begin
    Result := TResult.Failure(Format('Password must be at least %d characters long', [MIN_PASSWORD_LENGTH]));
    Exit;
  end;

  LHasUpper := False;
  LHasLower := False;
  LHasDigit := False;

  for I := 1 to Length(APassword) do
  begin
    if CharInSet(APassword[I], ['A'..'Z']) then
      LHasUpper := True
    else if CharInSet(APassword[I], ['a'..'z']) then
      LHasLower := True
    else if CharInSet(APassword[I], ['0'..'9']) then
      LHasDigit := True;
  end;

  if not (LHasUpper and LHasLower and LHasDigit) then
  begin
    Result := TResult.Failure('Password must contain at least one uppercase letter, one lowercase letter, and one digit');
    Exit;
  end;

  Result := TResult.Success;
end;

function TAuthenticationService.Register(const AUsername, APassword: string): TResult<TUser>;
var
  LResult: TResult<TUser>;
  LExistingUser: TUser;
  LSalt: string;
  LPolicyResult: TResult;
begin
  if AUsername = '' then
  begin
    FLogger.Warning('Registration attempt with empty username');
    Result := TResult<TUser>.Failure('Username cannot be empty');
    Exit;
  end;

  if APassword = '' then
  begin
    FLogger.Warning('Registration attempt with empty password');
    Result := TResult<TUser>.Failure('Password cannot be empty');
    Exit;
  end;

  // Enforce password policy
  LPolicyResult := ValidatePasswordPolicy(APassword);
  if not LPolicyResult.IsSuccess then
  begin
    FLogger.Warning('Registration failed: ' + LPolicyResult.GetErrorMessage);
    Result := TResult<TUser>.Failure(LPolicyResult.GetErrorMessage);
    Exit;
  end;

  // Check if username already exists
  LExistingUser := FUserRepository.GetUserByUsername(AUsername);
  if LExistingUser <> nil then
  begin
    FLogger.Warning('Registration failed: Username already exists - ' + AUsername);
    LExistingUser.Free;
    Result := TResult<TUser>.Failure('Username already exists');
    Exit;
  end;

  // Create new user with default User role
  // generate per-user salt and store salted KDF
  LSalt := GenerateSalt;
  LResult := FUserRepository.CreateUser(AUsername, HashPasswordKDF(APassword, LSalt), LSalt, urUser);
  
  if LResult.IsSuccess then
  begin
    FLogger.Info('User registered: ' + AUsername);
    Result := LResult;
  end
  else
  begin
    FLogger.Warning('Registration failed: ' + LResult.GetErrorMessage);
    Result := LResult;
  end;
end;

procedure TAuthenticationService.Logout;
var
  LContext: ISecurityContext;
begin
  LContext := FSecurityContextProvider.GetSecurityContext;
  if LContext <> nil then
    FLogger.Info('User logged out: ' + LContext.Username);
  
  FSecurityContextProvider.ClearSecurityContext;
end;

function TAuthenticationService.IsAuthenticated: Boolean;
begin
  Result := FSecurityContextProvider.IsAuthenticated;
end;

function TAuthenticationService.GetCurrentUsername: string;
var
  LContext: ISecurityContext;
begin
  LContext := FSecurityContextProvider.GetSecurityContext;
  if LContext <> nil then
    Result := LContext.Username
  else
    Result := '';
end;

function TAuthenticationService.GetCurrentUserId: Integer;
var
  LContext: ISecurityContext;
begin
  LContext := FSecurityContextProvider.GetSecurityContext;
  if LContext <> nil then
    Result := LContext.UserId
  else
    Result := 0;
end;

function TAuthenticationService.IsCurrentUserAdmin: Boolean;
var
  LContext: ISecurityContext;
begin
  LContext := FSecurityContextProvider.GetSecurityContext;
  Result := (LContext <> nil) and (LContext.Role = urAdmin);
end;

end.
