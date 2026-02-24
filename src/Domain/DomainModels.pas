unit DomainModels;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

{
  DomainModels.pas
  -----------------
  Core domain types used throughout the application. This unit has NO dependencies
  on other project units (maintains domain layer purity). Contains:

  - IDomainEvent: base interface for domain events (declared here for DDD purity)
  - TDomainEntity: base class for all entities with domain event infrastructure

  - TUserRole: enum for user roles (Admin/User)
  - TTaskStatus: enum for task status (Pending/InProgress/Done)
  - TPasswordCredential: value object encapsulating password hash + salt
  - TUser: domain entity with encapsulated fields, role-based helpers, and
    domain methods for credential management
  - TTask: domain entity with encapsulated fields, lifecycle/validation behaviour,
    and state machine (MarkInProgress, MarkDone, Reopen)

  DDD patterns applied:
  - Private fields with public read-only properties (encapsulation)
  - Factory methods: CreateNew (business creation) and Hydrate (repository loading)
  - Domain methods enforce invariants (CanTransitionTo, ChangePassword, etc.)
  - Value object: TPasswordCredential (immutable, equality by value)
  - Domain events: entities raise events during state changes
  - Base entity class: TDomainEntity provides event infrastructure

  Public helpers: StatusToString / StringToStatus for persistence and UI display.
}

type
  // User role enum: Admin has full access; User has limited access.
  TUserRole = (urAdmin, urUser);

  // Task status enum: tsUnknown is fallback for unrecognized DB values.
  TTaskStatus = (tsUnknown, tsPending, tsInProgress, tsDone);

  // ==========================================================================
  // DOMAIN EVENT INFRASTRUCTURE
  // ==========================================================================

  /// <summary>Base interface for domain events. Events capture meaningful
  /// state changes in the domain that other parts of the system may react to.
  /// Declared in the domain layer to maintain DDD purity.</summary>
  IDomainEvent = interface
    ['{A1B2C3D4-E5F6-7A8B-9C0D-E1F2A3B4C5D6}']
    function GetEventName: string;
    function GetOccurredAt: TDateTime;
    function GetEntityId: Integer;
    property EventName: string read GetEventName;
    property OccurredAt: TDateTime read GetOccurredAt;
    property EntityId: Integer read GetEntityId;
  end;

  /// <summary>Base class for all domain entities. Provides domain event
  /// infrastructure: entities raise events during state changes, which are
  /// collected and dispatched after persistence by the application layer.
  /// This implements the "Collect-then-Dispatch" pattern from DDD.</summary>
  TDomainEntity = class
  private
    FDomainEvents: TList<IDomainEvent>;
  protected
    /// <summary>Record a domain event to be dispatched after persistence.</summary>
    procedure RaiseDomainEvent(const AEvent: IDomainEvent);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Returns collected domain events (read-only access).</summary>
    function GetDomainEvents: TList<IDomainEvent>;
    /// <summary>Clear domain events after they have been dispatched.</summary>
    procedure ClearDomainEvents;
    /// <summary>Returns True if there are pending domain events.</summary>
    function HasDomainEvents: Boolean;
  end;

  /// <summary>Value object encapsulating password hash and salt.
  /// Immutable after creation; compared by value.</summary>
  TPasswordCredential = record
  private
    FHash: string;
    FSalt: string;
  public
    constructor Create(const AHash, ASalt: string);
    property Hash: string read FHash;
    property Salt: string read FSalt;
    function HasSalt: Boolean;
    class function Empty: TPasswordCredential; static;
    class operator Equal(const A, B: TPasswordCredential): Boolean;
    class operator NotEqual(const A, B: TPasswordCredential): Boolean;
  end;

  /// <summary>User domain entity with encapsulated fields.
  /// Identity fields (Id, Username, CreatedAt) are read-only after creation.
  /// Credentials are changed only via domain methods.
  /// Inherits TDomainEntity for domain event support.</summary>
  TUser = class(TDomainEntity)
  private
    FId: Integer;
    FUsername: string;
    FPasswordCredential: TPasswordCredential;
    FRole: TUserRole;
    FCreatedAt: TDateTime;
  public
    /// <summary>Factory method for creating a new user (business creation).
    /// Assigns default CreatedAt=Now, Id=0 (assigned by repository).</summary>
    class function CreateNew(const AUsername, APasswordHash, ASalt: string; ARole: TUserRole): TUser;
    /// <summary>Hydration factory for repositories to reconstruct from DB data.
    /// All fields are set explicitly.</summary>
    class function Hydrate(AId: Integer; const AUsername, APasswordHash, ASalt: string;
      ARole: TUserRole; ACreatedAt: TDateTime): TUser;

    // Identity (read-only)
    property Id: Integer read FId;
    property Username: string read FUsername;
    property CreatedAt: TDateTime read FCreatedAt;

    // Credential access (read-only; mutate via domain methods)
    property PasswordHash: string read FPasswordCredential.FHash;
    property Salt: string read FPasswordCredential.FSalt;
    property Credential: TPasswordCredential read FPasswordCredential;

    // Role (read via property; change via domain method)
    property Role: TUserRole read FRole;

    /// <summary>Returns True if the user has Admin role.</summary>
    function IsAdmin: Boolean;
    /// <summary>Validates domain invariants: Username must not be empty.</summary>
    function IsValid: Boolean;
    /// <summary>Returns role as display string ('Admin' or 'User').</summary>
    function RoleToString: string;

    /// <summary>Domain method: change the user's password credential.
    /// Used by AuthenticationService for password upgrades and UserService for resets.</summary>
    procedure ChangePassword(const APasswordHash, ASalt: string);
    /// <summary>Domain method: change the user's role.</summary>
    procedure ChangeRole(ANewRole: TUserRole);
    /// <summary>Domain method: set Id after repository assigns it.</summary>
    procedure AssignId(AId: Integer);
  end;

  /// <summary>Task domain entity with encapsulated fields.
  /// State transitions enforced via domain methods (MarkInProgress, MarkDone, Reopen).
  /// Mutable content fields (Title, Description) changed via SetTitle/SetDescription.
  /// Inherits TDomainEntity for domain event support.</summary>
  TTask = class(TDomainEntity)
  private
    FId: Integer;
    FUserId: Integer;
    FTitle: string;
    FDescription: string;
    FStatus: TTaskStatus;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
  public
    /// <summary>Factory method for creating a new task (business creation).
    /// Status defaults to tsPending. CreatedAt=Now, UpdatedAt=0.</summary>
    class function CreateNew(AUserId: Integer; const ATitle: string;
      const ADescription: string = ''): TTask;
    /// <summary>Hydration factory for repositories to reconstruct from DB data.</summary>
    class function Hydrate(AId, AUserId: Integer; const ATitle, ADescription: string;
      AStatus: TTaskStatus; ACreatedAt, AUpdatedAt: TDateTime): TTask;

    // Identity (read-only)
    property Id: Integer read FId;
    property UserId: Integer read FUserId;
    property CreatedAt: TDateTime read FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt;

    // Content (read; mutate via domain methods)
    property Title: string read FTitle;
    property Description: string read FDescription;

    // Status (read-only; change via MarkInProgress/MarkDone/Reopen)
    property Status: TTaskStatus read FStatus;

    /// <summary>Validates domain invariants: Title must not be empty,
    /// UserId must be positive, Status must not be tsUnknown.</summary>
    function IsValid: Boolean;
    /// <summary>Checks whether transitioning from current Status to ANewStatus
    /// is allowed. Allowed transitions:
    ///   Pending -> InProgress, Pending -> Done,
    ///   InProgress -> Done, InProgress -> Pending,
    ///   Done -> InProgress (reopen).
    /// Forbidden: Done -> Pending (must reopen first).</summary>
    function CanTransitionTo(ANewStatus: TTaskStatus): Boolean;
    /// <summary>Transition to InProgress. Sets UpdatedAt. Raises if invalid transition.</summary>
    procedure MarkInProgress;
    /// <summary>Transition to Done. Sets UpdatedAt. Raises if invalid transition.</summary>
    procedure MarkDone;
    /// <summary>Reopen a Done task back to InProgress. Sets UpdatedAt.</summary>
    procedure Reopen;

    /// <summary>Domain method: apply a new status via the proper transition method.
    /// Validates transition and raises if invalid.</summary>
    procedure ChangeStatus(ANewStatus: TTaskStatus);
    /// <summary>Domain method: update task content (title + description). Sets UpdatedAt.</summary>
    procedure UpdateContent(const ATitle, ADescription: string);
    /// <summary>Domain method: set Id after repository assigns it.</summary>
    procedure AssignId(AId: Integer);
    /// <summary>Domain method: touch UpdatedAt timestamp (used by auto-save).</summary>
    procedure TouchUpdatedAt;
  end;

// Helper converters used by repositories / UI to persist and display status
function StatusToString(AStatus: TTaskStatus): string;
function StringToStatus(const AStatusStr: string): TTaskStatus;
/// <summary>Returns user role as string ('Admin' or 'User').</summary>
function UserRoleToString(ARole: TUserRole): string;
/// <summary>Parses string to TUserRole. Defaults to urUser.</summary>
function StringToUserRole(const ARoleStr: string): TUserRole;

implementation

uses
  DomainEvents;

{ TDomainEntity }

constructor TDomainEntity.Create;
begin
  inherited Create;
  FDomainEvents := TList<IDomainEvent>.Create;
end;

destructor TDomainEntity.Destroy;
begin
  FDomainEvents.Free;
  inherited;
end;

procedure TDomainEntity.RaiseDomainEvent(const AEvent: IDomainEvent);
begin
  FDomainEvents.Add(AEvent);
end;

function TDomainEntity.GetDomainEvents: TList<IDomainEvent>;
begin
  Result := FDomainEvents;
end;

procedure TDomainEntity.ClearDomainEvents;
begin
  FDomainEvents.Clear;
end;

function TDomainEntity.HasDomainEvents: Boolean;
begin
  Result := FDomainEvents.Count > 0;
end;

{ TPasswordCredential }

constructor TPasswordCredential.Create(const AHash, ASalt: string);
begin
  FHash := AHash;
  FSalt := ASalt;
end;

function TPasswordCredential.HasSalt: Boolean;
begin
  Result := FSalt <> '';
end;

class function TPasswordCredential.Empty: TPasswordCredential;
begin
  Result.FHash := '';
  Result.FSalt := '';
end;

class operator TPasswordCredential.Equal(const A, B: TPasswordCredential): Boolean;
begin
  Result := (A.FHash = B.FHash) and (A.FSalt = B.FSalt);
end;

class operator TPasswordCredential.NotEqual(const A, B: TPasswordCredential): Boolean;
begin
  Result := not (A = B);
end;

{ TUser }

class function TUser.CreateNew(const AUsername, APasswordHash, ASalt: string; ARole: TUserRole): TUser;
begin
  Result := TUser.Create;
  Result.FId := 0;
  Result.FUsername := AUsername;
  Result.FPasswordCredential := TPasswordCredential.Create(APasswordHash, ASalt);
  Result.FRole := ARole;
  Result.FCreatedAt := Now;
end;

class function TUser.Hydrate(AId: Integer; const AUsername, APasswordHash, ASalt: string;
  ARole: TUserRole; ACreatedAt: TDateTime): TUser;
begin
  Result := TUser.Create;
  Result.FId := AId;
  Result.FUsername := AUsername;
  Result.FPasswordCredential := TPasswordCredential.Create(APasswordHash, ASalt);
  Result.FRole := ARole;
  Result.FCreatedAt := ACreatedAt;
end;

function TUser.IsAdmin: Boolean;
begin
  Result := FRole = urAdmin;
end;

function TUser.IsValid: Boolean;
begin
  Result := Trim(FUsername) <> '';
end;

function TUser.RoleToString: string;
begin
  Result := UserRoleToString(FRole);
end;

procedure TUser.ChangePassword(const APasswordHash, ASalt: string);
begin
  FPasswordCredential := TPasswordCredential.Create(APasswordHash, ASalt);
end;

procedure TUser.ChangeRole(ANewRole: TUserRole);
var
  LOldRole: TUserRole;
begin
  LOldRole := FRole;
  FRole := ANewRole;
  if LOldRole <> ANewRole then
    RaiseDomainEvent(TUserRoleChangedEvent.Create(FId, LOldRole, ANewRole));
end;

procedure TUser.AssignId(AId: Integer);
begin
  FId := AId;
end;

{ TTask }

class function TTask.CreateNew(AUserId: Integer; const ATitle: string;
  const ADescription: string = ''): TTask;
begin
  Result := TTask.Create;
  Result.FId := 0;
  Result.FUserId := AUserId;
  Result.FTitle := ATitle;
  Result.FDescription := ADescription;
  Result.FStatus := tsPending;
  Result.FCreatedAt := Now;
  Result.FUpdatedAt := 0;
  Result.RaiseDomainEvent(TTaskCreatedEvent.Create(0, AUserId, ATitle));
end;

class function TTask.Hydrate(AId, AUserId: Integer; const ATitle, ADescription: string;
  AStatus: TTaskStatus; ACreatedAt, AUpdatedAt: TDateTime): TTask;
begin
  Result := TTask.Create;
  Result.FId := AId;
  Result.FUserId := AUserId;
  Result.FTitle := ATitle;
  Result.FDescription := ADescription;
  Result.FStatus := AStatus;
  Result.FCreatedAt := ACreatedAt;
  Result.FUpdatedAt := AUpdatedAt;
end;

function TTask.IsValid: Boolean;
begin
  Result := (Trim(FTitle) <> '') and (FUserId > 0) and (FStatus <> tsUnknown);
end;

function TTask.CanTransitionTo(ANewStatus: TTaskStatus): Boolean;
begin
  // Same status is always allowed (no-op transition)
  if ANewStatus = FStatus then
  begin
    Result := True;
    Exit;
  end;

  // Unknown is never a valid target
  if ANewStatus = tsUnknown then
  begin
    Result := False;
    Exit;
  end;

  case FStatus of
    tsPending:
      // Pending -> InProgress or Done
      Result := ANewStatus in [tsInProgress, tsDone];
    tsInProgress:
      // InProgress -> Done or back to Pending
      Result := ANewStatus in [tsDone, tsPending];
    tsDone:
      // Done -> InProgress (reopen only; cannot go directly back to Pending)
      Result := ANewStatus = tsInProgress;
  else
    Result := False;
  end;
end;

procedure TTask.MarkInProgress;
var
  LOldStatus: TTaskStatus;
begin
  if not CanTransitionTo(tsInProgress) then
    raise Exception.CreateFmt('Cannot transition from %s to InProgress',
      [StatusToString(FStatus)]);
  LOldStatus := FStatus;
  FStatus := tsInProgress;
  FUpdatedAt := Now;
  RaiseDomainEvent(TTaskStatusChangedEvent.Create(FId, LOldStatus, tsInProgress));
end;

procedure TTask.MarkDone;
var
  LOldStatus: TTaskStatus;
begin
  if not CanTransitionTo(tsDone) then
    raise Exception.CreateFmt('Cannot transition from %s to Done',
      [StatusToString(FStatus)]);
  LOldStatus := FStatus;
  FStatus := tsDone;
  FUpdatedAt := Now;
  RaiseDomainEvent(TTaskStatusChangedEvent.Create(FId, LOldStatus, tsDone));
end;

procedure TTask.Reopen;
var
  LOldStatus: TTaskStatus;
begin
  if not CanTransitionTo(tsInProgress) then
    raise Exception.CreateFmt('Cannot reopen task from %s status',
      [StatusToString(FStatus)]);
  LOldStatus := FStatus;
  FStatus := tsInProgress;
  FUpdatedAt := Now;
  RaiseDomainEvent(TTaskStatusChangedEvent.Create(FId, LOldStatus, tsInProgress));
end;

procedure TTask.ChangeStatus(ANewStatus: TTaskStatus);
var
  LOldStatus: TTaskStatus;
begin
  if ANewStatus = FStatus then
    Exit;  // No-op

  case ANewStatus of
    tsInProgress:
      if FStatus = tsDone then
        Reopen
      else
        MarkInProgress;
    tsDone:
      MarkDone;
    tsPending:
      begin
        if not CanTransitionTo(tsPending) then
          raise Exception.CreateFmt('Cannot transition from %s to Pending',
            [StatusToString(FStatus)]);
        LOldStatus := FStatus;
        FStatus := tsPending;
        FUpdatedAt := Now;
        RaiseDomainEvent(TTaskStatusChangedEvent.Create(FId, LOldStatus, tsPending));
      end;
  else
    raise Exception.CreateFmt('Cannot transition to %s', [StatusToString(ANewStatus)]);
  end;
end;

procedure TTask.UpdateContent(const ATitle, ADescription: string);
begin
  if Trim(ATitle) = '' then
    raise Exception.Create('Task title cannot be empty');
  FTitle := ATitle;
  FDescription := ADescription;
  FUpdatedAt := Now;
  RaiseDomainEvent(TTaskContentUpdatedEvent.Create(FId, ATitle));
end;

procedure TTask.AssignId(AId: Integer);
begin
  FId := AId;
end;

procedure TTask.TouchUpdatedAt;
begin
  FUpdatedAt := Now;
end;

function StatusToString(AStatus: TTaskStatus): string;
begin
  // Maps enum to stable string tokens for DB storage and UI display.
  case AStatus of
    tsPending: Result := 'Pending';
    tsInProgress: Result := 'InProgress';
    tsDone: Result := 'Done';
  else
    Result := 'Unknown';
  end;
end;

function StringToStatus(const AStatusStr: string): TTaskStatus;
begin
  // Reverse conversion: string from DB or UI back to enum.
  if AStatusStr = 'Pending' then
    Result := tsPending
  else if AStatusStr = 'InProgress' then
    Result := tsInProgress
  else if AStatusStr = 'Done' then
    Result := tsDone
  else
    Result := tsUnknown;
end;

function UserRoleToString(ARole: TUserRole): string;
begin
  case ARole of
    urAdmin: Result := 'Admin';
    urUser: Result := 'User';
  else
    Result := 'User';
  end;
end;

function StringToUserRole(const ARoleStr: string): TUserRole;
begin
  if ARoleStr = 'Admin' then
    Result := urAdmin
  else
    Result := urUser;
end;

end.
