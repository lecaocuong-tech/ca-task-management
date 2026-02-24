unit DomainEvents;

interface

uses
  System.SysUtils,
  DomainModels;

{
  DomainEvents.pas
  -----------------
  Concrete domain event implementations. Each event captures a meaningful
  state change in the domain that other parts of the system may react to.

  IDomainEvent interface and TDomainEntity base class are declared in
  DomainModels.pas (domain layer purity: no outward dependencies).

  Events:
  - TTaskCreatedEvent:        raised when a new task is created
  - TTaskStatusChangedEvent:  raised on any task status transition
  - TTaskContentUpdatedEvent: raised when task title/description changes
  - TTaskDeletedEvent:        raised when a task is deleted
  - TUserCreatedEvent:        raised when a new user is created
  - TUserRoleChangedEvent:    raised when a user's role is changed
}

type
  /// <summary>Base implementation providing common event fields.</summary>
  TBaseDomainEvent = class(TInterfacedObject, IDomainEvent)
  private
    FEventName: string;
    FOccurredAt: TDateTime;
    FEntityId: Integer;
  public
    constructor Create(const AEventName: string; AEntityId: Integer);
    function GetEventName: string;
    function GetOccurredAt: TDateTime;
    function GetEntityId: Integer;
  end;

  // ==========================================================================
  // TASK EVENTS
  // ==========================================================================

  /// <summary>Raised when a new task is created via TTask.CreateNew.</summary>
  TTaskCreatedEvent = class(TBaseDomainEvent)
  private
    FUserId: Integer;
    FTitle: string;
  public
    constructor Create(ATaskId, AUserId: Integer; const ATitle: string);
    property UserId: Integer read FUserId;
    property Title: string read FTitle;
  end;

  /// <summary>Raised when a task transitions from one status to another.
  /// Captures both old and new status for auditing and reaction.</summary>
  TTaskStatusChangedEvent = class(TBaseDomainEvent)
  private
    FOldStatus: TTaskStatus;
    FNewStatus: TTaskStatus;
  public
    constructor Create(ATaskId: Integer; AOldStatus, ANewStatus: TTaskStatus);
    property OldStatus: TTaskStatus read FOldStatus;
    property NewStatus: TTaskStatus read FNewStatus;
  end;

  /// <summary>Raised when task content (title/description) is updated.</summary>
  TTaskContentUpdatedEvent = class(TBaseDomainEvent)
  private
    FNewTitle: string;
  public
    constructor Create(ATaskId: Integer; const ANewTitle: string);
    property NewTitle: string read FNewTitle;
  end;

  /// <summary>Raised when a task is deleted from the system.</summary>
  TTaskDeletedEvent = class(TBaseDomainEvent)
  public
    constructor Create(ATaskId: Integer);
  end;

  // ==========================================================================
  // USER EVENTS
  // ==========================================================================

  /// <summary>Raised when a new user account is created.</summary>
  TUserCreatedEvent = class(TBaseDomainEvent)
  private
    FUsername: string;
    FRole: TUserRole;
  public
    constructor Create(AUserId: Integer; const AUsername: string; ARole: TUserRole);
    property Username: string read FUsername;
    property Role: TUserRole read FRole;
  end;

  /// <summary>Raised when a user's role is changed.</summary>
  TUserRoleChangedEvent = class(TBaseDomainEvent)
  private
    FOldRole: TUserRole;
    FNewRole: TUserRole;
  public
    constructor Create(AUserId: Integer; AOldRole, ANewRole: TUserRole);
    property OldRole: TUserRole read FOldRole;
    property NewRole: TUserRole read FNewRole;
  end;

implementation

{ TBaseDomainEvent }

constructor TBaseDomainEvent.Create(const AEventName: string; AEntityId: Integer);
begin
  inherited Create;
  FEventName := AEventName;
  FOccurredAt := Now;
  FEntityId := AEntityId;
end;

function TBaseDomainEvent.GetEventName: string;
begin
  Result := FEventName;
end;

function TBaseDomainEvent.GetOccurredAt: TDateTime;
begin
  Result := FOccurredAt;
end;

function TBaseDomainEvent.GetEntityId: Integer;
begin
  Result := FEntityId;
end;

{ TTaskCreatedEvent }

constructor TTaskCreatedEvent.Create(ATaskId, AUserId: Integer; const ATitle: string);
begin
  inherited Create('TaskCreated', ATaskId);
  FUserId := AUserId;
  FTitle := ATitle;
end;

{ TTaskStatusChangedEvent }

constructor TTaskStatusChangedEvent.Create(ATaskId: Integer; AOldStatus, ANewStatus: TTaskStatus);
begin
  inherited Create('TaskStatusChanged', ATaskId);
  FOldStatus := AOldStatus;
  FNewStatus := ANewStatus;
end;

{ TTaskContentUpdatedEvent }

constructor TTaskContentUpdatedEvent.Create(ATaskId: Integer; const ANewTitle: string);
begin
  inherited Create('TaskContentUpdated', ATaskId);
  FNewTitle := ANewTitle;
end;

{ TTaskDeletedEvent }

constructor TTaskDeletedEvent.Create(ATaskId: Integer);
begin
  inherited Create('TaskDeleted', ATaskId);
end;

{ TUserCreatedEvent }

constructor TUserCreatedEvent.Create(AUserId: Integer; const AUsername: string; ARole: TUserRole);
begin
  inherited Create('UserCreated', AUserId);
  FUsername := AUsername;
  FRole := ARole;
end;

{ TUserRoleChangedEvent }

constructor TUserRoleChangedEvent.Create(AUserId: Integer; AOldRole, ANewRole: TUserRole);
begin
  inherited Create('UserRoleChanged', AUserId);
  FOldRole := AOldRole;
  FNewRole := ANewRole;
end;

end.
