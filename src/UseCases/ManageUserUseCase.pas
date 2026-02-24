unit ManageUserUseCase;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  AppInterfaces,
  DomainModels,
  DTOs,
  Result;

{
  ManageUserUseCase.pas
  ----------------------
  Application-layer Use Cases for user management operations.
  Follows the same Clean Architecture pattern as task use cases:
  - Accept Request DTOs
  - Delegate to IUserService
  - Dispatch domain events
  - Return Response DTOs
}

type
  /// <summary>Use case: Create a new user (admin only).
  /// Validates input, delegates to service, dispatches creation events.</summary>
  TCreateUserUseCase = class
  private
    FUserService: IUserService;
    FEventDispatcher: IDomainEventDispatcher;
    FSanitizer: IInputSanitizer;
    FRateLimiter: IRateLimiter;
    FLogger: ILogger;
  public
    constructor Create(AUserService: IUserService;
      AEventDispatcher: IDomainEventDispatcher; ASanitizer: IInputSanitizer;
      ARateLimiter: IRateLimiter; ALogger: ILogger);

    function Execute(const ARequest: TCreateUserRequest): TUseCaseResponse<TUserDTO>;
  end;

  /// <summary>Use case: Delete a user (admin only).</summary>
  TDeleteUserUseCase = class
  private
    FUserService: IUserService;
    FEventDispatcher: IDomainEventDispatcher;
    FLogger: ILogger;
  public
    constructor Create(AUserService: IUserService;
      AEventDispatcher: IDomainEventDispatcher; ALogger: ILogger);

    function Execute(AUserId: Integer): TUseCaseResponse<Boolean>;
  end;

implementation

uses
  DomainEvents;

{ TCreateUserUseCase }

constructor TCreateUserUseCase.Create(AUserService: IUserService;
  AEventDispatcher: IDomainEventDispatcher; ASanitizer: IInputSanitizer;
  ARateLimiter: IRateLimiter; ALogger: ILogger);
begin
  inherited Create;
  FUserService := AUserService;
  FEventDispatcher := AEventDispatcher;
  FSanitizer := ASanitizer;
  FRateLimiter := ARateLimiter;
  FLogger := ALogger;
end;

function TCreateUserUseCase.Execute(const ARequest: TCreateUserRequest): TUseCaseResponse<TUserDTO>;
var
  LResult: TResult<TUser>;
  LUser: TUser;
  LUserDTO: TUserDTO;
  LSanitizedUsername: string;
  LValidation: TResult;
begin
  // Rate limiting: prevent rapid user creation
  if not FRateLimiter.TryConsume('create_user') then
  begin
    FLogger.Warning('UseCase: Rate limit exceeded for user creation');
    Result := TUseCaseResponse<TUserDTO>.Failure('Too many requests. Please try again later.');
    Exit;
  end;

  // Sanitize and validate input at the boundary
  LSanitizedUsername := FSanitizer.SanitizeString(ARequest.Username);

  LValidation := FSanitizer.ValidateUsername(LSanitizedUsername);
  if not LValidation.IsSuccess then
  begin
    Result := TUseCaseResponse<TUserDTO>.Failure(LValidation.GetErrorMessage);
    Exit;
  end;

  LValidation := FSanitizer.ValidatePassword(ARequest.Password);
  if not LValidation.IsSuccess then
  begin
    Result := TUseCaseResponse<TUserDTO>.Failure(LValidation.GetErrorMessage);
    Exit;
  end;

  // Delegate to service layer (handles permission check, hashing, persistence)
  LResult := FUserService.CreateUser(LSanitizedUsername, ARequest.Password, ARequest.Role);

  if not LResult.IsSuccess then
  begin
    Result := TUseCaseResponse<TUserDTO>.Failure(LResult.GetErrorMessage);
    Exit;
  end;

  LUser := LResult.GetValue;
  try
    // Dispatch domain events
    if LUser.HasDomainEvents then
    begin
      FEventDispatcher.DispatchAll(LUser.GetDomainEvents);
      LUser.ClearDomainEvents;
    end;

    LUserDTO := TDTOMapper.ToUserDTO(LUser);
    FLogger.Info(Format('UseCase: User created - %s (%s)', [LUserDTO.Username, LUserDTO.Role]));
    Result := TUseCaseResponse<TUserDTO>.Success(LUserDTO);
  finally
    LUser.Free;
  end;
end;

{ TDeleteUserUseCase }

constructor TDeleteUserUseCase.Create(AUserService: IUserService;
  AEventDispatcher: IDomainEventDispatcher; ALogger: ILogger);
begin
  inherited Create;
  FUserService := AUserService;
  FEventDispatcher := AEventDispatcher;
  FLogger := ALogger;
end;

function TDeleteUserUseCase.Execute(AUserId: Integer): TUseCaseResponse<Boolean>;
var
  LResult: TResult;
begin
  LResult := FUserService.DeleteUser(AUserId);

  if not LResult.IsSuccess then
  begin
    Result := TUseCaseResponse<Boolean>.Failure(LResult.GetErrorMessage);
    Exit;
  end;

  FLogger.Info(Format('UseCase: User %d deleted', [AUserId]));
  Result := TUseCaseResponse<Boolean>.Success(True);
end;

end.
