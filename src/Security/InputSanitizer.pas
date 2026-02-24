unit InputSanitizer;

interface

uses
  System.SysUtils,
  System.RegularExpressions,
  AppInterfaces,
  Result;

{
  InputSanitizer.pas
  -------------------
  Centralized input validation and sanitization for security.
  Implements IInputSanitizer interface (defined in AppInterfaces.pas).

  Provides defense-in-depth against:
  - SQL injection (parameterized queries are primary defense; this is secondary)
  - XSS (HTML/script tag stripping)
  - Invalid/malicious input patterns
  - Overly long inputs (DoS prevention)

  Design:
  - Stateless, thread-safe (no mutable state)
  - Returns TResult with descriptive error messages
  - Composable: individual validators can be combined
  - Used at the Use Case boundary before data reaches services
}

type
  /// <summary>Centralized input validation and sanitization service.
  /// Provides defense-in-depth for all user-supplied input.</summary>
  TInputSanitizer = class(TInterfacedObject, IInputSanitizer)
  private
    FLogger: ILogger;
    const
      MAX_USERNAME_LENGTH = 50;
      MAX_TITLE_LENGTH = 200;
      MAX_DESCRIPTION_LENGTH = 2000;
      MAX_PASSWORD_LENGTH = 128;
      MIN_USERNAME_LENGTH = 3;
  public
    constructor Create(ALogger: ILogger);

    /// <summary>Sanitize a string by trimming whitespace and stripping
    /// dangerous HTML/script tags. Returns the cleaned string.</summary>
    function SanitizeString(const AInput: string): string;

    /// <summary>Validate username: length, allowed characters (alphanumeric + underscore).</summary>
    function ValidateUsername(const AUsername: string): TResult;

    /// <summary>Validate task title: non-empty, max length, no dangerous content.</summary>
    function ValidateTaskTitle(const ATitle: string): TResult;

    /// <summary>Validate task description: max length, sanitize HTML.</summary>
    function ValidateTaskDescription(const ADescription: string): TResult;

    /// <summary>Validate password: non-empty, max length (DoS prevention).</summary>
    function ValidatePassword(const APassword: string): TResult;

    /// <summary>Validate a generic text field with custom max length.</summary>
    function ValidateTextField(const AValue, AFieldName: string;
      AMaxLength: Integer): TResult;
  end;

implementation

{ TInputSanitizer }

constructor TInputSanitizer.Create(ALogger: ILogger);
begin
  inherited Create;
  FLogger := ALogger;
end;

function TInputSanitizer.SanitizeString(const AInput: string): string;
begin
  // Step 1: Trim whitespace
  Result := Trim(AInput);

  // Step 2: Strip HTML/script tags (defense-in-depth)
  Result := TRegEx.Replace(Result, '<[^>]*>', '', [roIgnoreCase]);

  // Step 3: Remove null bytes (can bypass string comparisons)
  Result := StringReplace(Result, #0, '', [rfReplaceAll]);

  // Step 4: Normalize excessive whitespace
  Result := TRegEx.Replace(Result, '\s{2,}', ' ', []);
end;

function TInputSanitizer.ValidateUsername(const AUsername: string): TResult;
var
  LSanitized: string;
begin
  LSanitized := Trim(AUsername);

  if LSanitized = '' then
  begin
    Result := TResult.Failure('Username cannot be empty');
    Exit;
  end;

  if Length(LSanitized) < MIN_USERNAME_LENGTH then
  begin
    Result := TResult.Failure(Format('Username must be at least %d characters', [MIN_USERNAME_LENGTH]));
    Exit;
  end;

  if Length(LSanitized) > MAX_USERNAME_LENGTH then
  begin
    Result := TResult.Failure(Format('Username cannot exceed %d characters', [MAX_USERNAME_LENGTH]));
    Exit;
  end;

  // Only allow alphanumeric + underscore + dot
  if not TRegEx.IsMatch(LSanitized, '^[a-zA-Z0-9_.]+$') then
  begin
    FLogger.Warning('Input validation: Invalid username characters - ' + LSanitized);
    Result := TResult.Failure('Username can only contain letters, numbers, underscores, and dots');
    Exit;
  end;

  Result := TResult.Success;
end;

function TInputSanitizer.ValidateTaskTitle(const ATitle: string): TResult;
var
  LSanitized: string;
begin
  LSanitized := SanitizeString(ATitle);

  if LSanitized = '' then
  begin
    Result := TResult.Failure('Task title cannot be empty');
    Exit;
  end;

  if Length(LSanitized) > MAX_TITLE_LENGTH then
  begin
    Result := TResult.Failure(Format('Task title cannot exceed %d characters', [MAX_TITLE_LENGTH]));
    Exit;
  end;

  // Check for suspicious SQL patterns (defense-in-depth)
  if TRegEx.IsMatch(LSanitized, '(\b(DROP|DELETE|INSERT|UPDATE|ALTER|EXEC)\b.*\b(TABLE|FROM|INTO|SET)\b)',
    [roIgnoreCase]) then
  begin
    FLogger.Warning('Input validation: Suspicious SQL pattern in task title');
    Result := TResult.Failure('Task title contains invalid content');
    Exit;
  end;

  Result := TResult.Success;
end;

function TInputSanitizer.ValidateTaskDescription(const ADescription: string): TResult;
var
  LSanitized: string;
begin
  // Description is optional — empty is OK
  if ADescription = '' then
  begin
    Result := TResult.Success;
    Exit;
  end;

  LSanitized := SanitizeString(ADescription);

  if Length(LSanitized) > MAX_DESCRIPTION_LENGTH then
  begin
    Result := TResult.Failure(Format('Description cannot exceed %d characters', [MAX_DESCRIPTION_LENGTH]));
    Exit;
  end;

  Result := TResult.Success;
end;

function TInputSanitizer.ValidatePassword(const APassword: string): TResult;
begin
  if APassword = '' then
  begin
    Result := TResult.Failure('Password cannot be empty');
    Exit;
  end;

  if Length(APassword) > MAX_PASSWORD_LENGTH then
  begin
    FLogger.Warning('Input validation: Password exceeds maximum length');
    Result := TResult.Failure(Format('Password cannot exceed %d characters', [MAX_PASSWORD_LENGTH]));
    Exit;
  end;

  Result := TResult.Success;
end;

function TInputSanitizer.ValidateTextField(const AValue, AFieldName: string;
  AMaxLength: Integer): TResult;
var
  LSanitized: string;
begin
  LSanitized := SanitizeString(AValue);

  if LSanitized = '' then
  begin
    Result := TResult.Failure(AFieldName + ' cannot be empty');
    Exit;
  end;

  if Length(LSanitized) > AMaxLength then
  begin
    Result := TResult.Failure(Format('%s cannot exceed %d characters', [AFieldName, AMaxLength]));
    Exit;
  end;

  Result := TResult.Success;
end;

end.
