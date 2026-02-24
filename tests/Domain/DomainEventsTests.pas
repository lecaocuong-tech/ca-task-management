unit DomainEventsTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Generics.Collections,
  DomainModels,
  DomainEvents;

{
  DomainEventsTests.pas
  ----------------------
  Unit tests for domain event infrastructure and concrete event types.

  Tests verify:
  - TDomainEntity base class event collection (raise, get, clear, has)
  - TTask raises correct events on state transitions (CreateNew, MarkInProgress,
    MarkDone, Reopen, UpdateContent, ChangeStatus)
  - TUser raises events on role change
  - Event properties carry correct data (entity ID, old/new status, etc.)
  - ClearDomainEvents resets the event list
  - Multiple state changes accumulate multiple events
}

type
  // ==========================================================================
  // Domain Event Infrastructure Tests
  // ==========================================================================

  [TestFixture]
  TDomainEntityEventTests = class
  public
    [Test]
    procedure NewEntity_HasNoDomainEvents;
    [Test]
    procedure ClearDomainEvents_EmptiesList;
  end;

  // ==========================================================================
  // Task Domain Event Tests
  // ==========================================================================

  [TestFixture]
  TTaskDomainEventTests = class
  private
    FTask: TTask;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- CreateNew events ---
    [Test]
    procedure CreateNew_RaisesTaskCreatedEvent;
    [Test]
    procedure CreateNew_EventHasCorrectTitle;
    [Test]
    procedure CreateNew_EventHasCorrectUserId;

    // --- MarkInProgress events ---
    [Test]
    procedure MarkInProgress_RaisesStatusChangedEvent;
    [Test]
    procedure MarkInProgress_EventHasCorrectOldAndNewStatus;

    // --- MarkDone events ---
    [Test]
    procedure MarkDone_RaisesStatusChangedEvent;
    [Test]
    procedure MarkDone_EventHasCorrectStatuses;

    // --- Reopen events ---
    [Test]
    procedure Reopen_RaisesStatusChangedEvent;
    [Test]
    procedure Reopen_EventHasCorrectStatuses;

    // --- ChangeStatus events ---
    [Test]
    procedure ChangeStatus_ToPending_RaisesStatusChangedEvent;

    // --- UpdateContent events ---
    [Test]
    procedure UpdateContent_RaisesContentUpdatedEvent;
    [Test]
    procedure UpdateContent_EventHasNewTitle;

    // --- Multiple events accumulation ---
    [Test]
    procedure MultipleTransitions_AccumulatesEvents;
    [Test]
    procedure ClearEvents_ThenNewTransition_OnlyNewEvent;

    // --- Hydrate does NOT raise events ---
    [Test]
    procedure Hydrate_DoesNotRaiseEvents;
  end;

  // ==========================================================================
  // User Domain Event Tests
  // ==========================================================================

  [TestFixture]
  TUserDomainEventTests = class
  public
    [Test]
    procedure ChangeRole_RaisesUserRoleChangedEvent;
    [Test]
    procedure ChangeRole_EventHasCorrectRoles;
    [Test]
    procedure ChangeRole_SameRole_NoEvent;
    [Test]
    procedure Hydrate_DoesNotRaiseEvents;
  end;

  // ==========================================================================
  // Concrete Event Property Tests
  // ==========================================================================

  [TestFixture]
  TConcreteEventTests = class
  public
    [Test]
    procedure TaskCreatedEvent_HasCorrectEventName;
    [Test]
    procedure TaskStatusChangedEvent_HasCorrectEventName;
    [Test]
    procedure TaskContentUpdatedEvent_HasCorrectEventName;
    [Test]
    procedure TaskDeletedEvent_HasCorrectEventName;
    [Test]
    procedure UserCreatedEvent_HasCorrectEventName;
    [Test]
    procedure UserRoleChangedEvent_HasCorrectEventName;
    [Test]
    procedure BaseDomainEvent_SetsOccurredAt;
    [Test]
    procedure BaseDomainEvent_SetsEntityId;
  end;

implementation

{ TDomainEntityEventTests }

procedure TDomainEntityEventTests.NewEntity_HasNoDomainEvents;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'Test', '', tsPending, Now, 0);
  try
    Assert.IsFalse(LTask.HasDomainEvents);
    Assert.AreEqual(0, LTask.GetDomainEvents.Count);
  finally
    LTask.Free;
  end;
end;

procedure TDomainEntityEventTests.ClearDomainEvents_EmptiesList;
var
  LTask: TTask;
begin
  LTask := TTask.CreateNew(1, 'Test Title');
  try
    Assert.IsTrue(LTask.HasDomainEvents, 'Should have events after CreateNew');
    LTask.ClearDomainEvents;
    Assert.IsFalse(LTask.HasDomainEvents, 'Should have no events after clear');
    Assert.AreEqual(0, LTask.GetDomainEvents.Count);
  finally
    LTask.Free;
  end;
end;

{ TTaskDomainEventTests }

procedure TTaskDomainEventTests.Setup;
begin
  FTask := TTask.CreateNew(1, 'Test Task');
  FTask.AssignId(10);
  // Clear creation event so each test starts clean
  FTask.ClearDomainEvents;
end;

procedure TTaskDomainEventTests.TearDown;
begin
  FTask.Free;
end;

procedure TTaskDomainEventTests.CreateNew_RaisesTaskCreatedEvent;
var
  LTask: TTask;
begin
  LTask := TTask.CreateNew(5, 'New Task');
  try
    Assert.IsTrue(LTask.HasDomainEvents);
    Assert.AreEqual(1, LTask.GetDomainEvents.Count);
    Assert.AreEqual('TaskCreated', LTask.GetDomainEvents[0].EventName);
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainEventTests.CreateNew_EventHasCorrectTitle;
var
  LTask: TTask;
  LEvent: TTaskCreatedEvent;
begin
  LTask := TTask.CreateNew(5, 'My Title');
  try
    LEvent := LTask.GetDomainEvents[0] as TTaskCreatedEvent;
    Assert.AreEqual('My Title', LEvent.Title);
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainEventTests.CreateNew_EventHasCorrectUserId;
var
  LTask: TTask;
  LEvent: TTaskCreatedEvent;
begin
  LTask := TTask.CreateNew(42, 'Title');
  try
    LEvent := LTask.GetDomainEvents[0] as TTaskCreatedEvent;
    Assert.AreEqual(42, LEvent.UserId);
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainEventTests.MarkInProgress_RaisesStatusChangedEvent;
begin
  FTask.MarkInProgress;
  Assert.AreEqual(1, FTask.GetDomainEvents.Count);
  Assert.AreEqual('TaskStatusChanged', FTask.GetDomainEvents[0].EventName);
end;

procedure TTaskDomainEventTests.MarkInProgress_EventHasCorrectOldAndNewStatus;
var
  LEvent: TTaskStatusChangedEvent;
begin
  FTask.MarkInProgress;
  LEvent := FTask.GetDomainEvents[0] as TTaskStatusChangedEvent;
  Assert.AreEqual(Ord(tsPending), Ord(LEvent.OldStatus));
  Assert.AreEqual(Ord(tsInProgress), Ord(LEvent.NewStatus));
end;

procedure TTaskDomainEventTests.MarkDone_RaisesStatusChangedEvent;
begin
  FTask.MarkDone;
  Assert.AreEqual(1, FTask.GetDomainEvents.Count);
  Assert.AreEqual('TaskStatusChanged', FTask.GetDomainEvents[0].EventName);
end;

procedure TTaskDomainEventTests.MarkDone_EventHasCorrectStatuses;
var
  LEvent: TTaskStatusChangedEvent;
begin
  FTask.MarkDone;
  LEvent := FTask.GetDomainEvents[0] as TTaskStatusChangedEvent;
  Assert.AreEqual(Ord(tsPending), Ord(LEvent.OldStatus));
  Assert.AreEqual(Ord(tsDone), Ord(LEvent.NewStatus));
end;

procedure TTaskDomainEventTests.Reopen_RaisesStatusChangedEvent;
begin
  FTask.MarkDone;
  FTask.ClearDomainEvents;
  FTask.Reopen;
  Assert.AreEqual(1, FTask.GetDomainEvents.Count);
  Assert.AreEqual('TaskStatusChanged', FTask.GetDomainEvents[0].EventName);
end;

procedure TTaskDomainEventTests.Reopen_EventHasCorrectStatuses;
var
  LEvent: TTaskStatusChangedEvent;
begin
  FTask.MarkDone;
  FTask.ClearDomainEvents;
  FTask.Reopen;
  LEvent := FTask.GetDomainEvents[0] as TTaskStatusChangedEvent;
  Assert.AreEqual(Ord(tsDone), Ord(LEvent.OldStatus));
  Assert.AreEqual(Ord(tsInProgress), Ord(LEvent.NewStatus));
end;

procedure TTaskDomainEventTests.ChangeStatus_ToPending_RaisesStatusChangedEvent;
var
  LEvent: TTaskStatusChangedEvent;
begin
  FTask.MarkInProgress;
  FTask.ClearDomainEvents;
  FTask.ChangeStatus(tsPending);
  Assert.AreEqual(1, FTask.GetDomainEvents.Count);
  LEvent := FTask.GetDomainEvents[0] as TTaskStatusChangedEvent;
  Assert.AreEqual(Ord(tsInProgress), Ord(LEvent.OldStatus));
  Assert.AreEqual(Ord(tsPending), Ord(LEvent.NewStatus));
end;

procedure TTaskDomainEventTests.UpdateContent_RaisesContentUpdatedEvent;
begin
  FTask.UpdateContent('New Title', 'New Desc');
  Assert.AreEqual(1, FTask.GetDomainEvents.Count);
  Assert.AreEqual('TaskContentUpdated', FTask.GetDomainEvents[0].EventName);
end;

procedure TTaskDomainEventTests.UpdateContent_EventHasNewTitle;
var
  LEvent: TTaskContentUpdatedEvent;
begin
  FTask.UpdateContent('Updated Title', 'Desc');
  LEvent := FTask.GetDomainEvents[0] as TTaskContentUpdatedEvent;
  Assert.AreEqual('Updated Title', LEvent.NewTitle);
end;

procedure TTaskDomainEventTests.MultipleTransitions_AccumulatesEvents;
begin
  FTask.MarkInProgress;
  FTask.MarkDone;
  Assert.AreEqual(2, FTask.GetDomainEvents.Count);
  Assert.AreEqual('TaskStatusChanged', FTask.GetDomainEvents[0].EventName);
  Assert.AreEqual('TaskStatusChanged', FTask.GetDomainEvents[1].EventName);
end;

procedure TTaskDomainEventTests.ClearEvents_ThenNewTransition_OnlyNewEvent;
begin
  FTask.MarkInProgress;
  Assert.AreEqual(1, FTask.GetDomainEvents.Count);
  FTask.ClearDomainEvents;
  FTask.MarkDone;
  Assert.AreEqual(1, FTask.GetDomainEvents.Count);
end;

procedure TTaskDomainEventTests.Hydrate_DoesNotRaiseEvents;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'Test', '', tsInProgress, Now, 0);
  try
    Assert.IsFalse(LTask.HasDomainEvents);
  finally
    LTask.Free;
  end;
end;

{ TUserDomainEventTests }

procedure TUserDomainEventTests.ChangeRole_RaisesUserRoleChangedEvent;
var
  LUser: TUser;
begin
  LUser := TUser.CreateNew('testuser', 'hash', 'salt', urUser);
  try
    LUser.ClearDomainEvents; // Clear creation events if any
    LUser.ChangeRole(urAdmin);
    Assert.IsTrue(LUser.HasDomainEvents);
    Assert.AreEqual('UserRoleChanged', LUser.GetDomainEvents[0].EventName);
  finally
    LUser.Free;
  end;
end;

procedure TUserDomainEventTests.ChangeRole_EventHasCorrectRoles;
var
  LUser: TUser;
  LEvent: TUserRoleChangedEvent;
begin
  LUser := TUser.CreateNew('testuser', 'hash', 'salt', urUser);
  try
    LUser.AssignId(7);
    LUser.ClearDomainEvents;
    LUser.ChangeRole(urAdmin);
    LEvent := LUser.GetDomainEvents[0] as TUserRoleChangedEvent;
    Assert.AreEqual(Ord(urUser), Ord(LEvent.OldRole));
    Assert.AreEqual(Ord(urAdmin), Ord(LEvent.NewRole));
    Assert.AreEqual(7, LEvent.EntityId);
  finally
    LUser.Free;
  end;
end;

procedure TUserDomainEventTests.ChangeRole_SameRole_NoEvent;
var
  LUser: TUser;
begin
  LUser := TUser.CreateNew('testuser', 'hash', 'salt', urAdmin);
  try
    LUser.ClearDomainEvents;
    LUser.ChangeRole(urAdmin);
    Assert.IsFalse(LUser.HasDomainEvents, 'No event when role unchanged');
  finally
    LUser.Free;
  end;
end;

procedure TUserDomainEventTests.Hydrate_DoesNotRaiseEvents;
var
  LUser: TUser;
begin
  LUser := TUser.Hydrate(1, 'user', 'hash', 'salt', urAdmin, Now);
  try
    Assert.IsFalse(LUser.HasDomainEvents);
  finally
    LUser.Free;
  end;
end;

{ TConcreteEventTests }

procedure TConcreteEventTests.TaskCreatedEvent_HasCorrectEventName;
var
  LEvent: IDomainEvent;
begin
  LEvent := TTaskCreatedEvent.Create(1, 2, 'Title');
  Assert.AreEqual('TaskCreated', LEvent.EventName);
end;

procedure TConcreteEventTests.TaskStatusChangedEvent_HasCorrectEventName;
var
  LEvent: IDomainEvent;
begin
  LEvent := TTaskStatusChangedEvent.Create(1, tsPending, tsInProgress);
  Assert.AreEqual('TaskStatusChanged', LEvent.EventName);
end;

procedure TConcreteEventTests.TaskContentUpdatedEvent_HasCorrectEventName;
var
  LEvent: IDomainEvent;
begin
  LEvent := TTaskContentUpdatedEvent.Create(1, 'New Title');
  Assert.AreEqual('TaskContentUpdated', LEvent.EventName);
end;

procedure TConcreteEventTests.TaskDeletedEvent_HasCorrectEventName;
var
  LEvent: IDomainEvent;
begin
  LEvent := TTaskDeletedEvent.Create(1);
  Assert.AreEqual('TaskDeleted', LEvent.EventName);
end;

procedure TConcreteEventTests.UserCreatedEvent_HasCorrectEventName;
var
  LEvent: IDomainEvent;
begin
  LEvent := TUserCreatedEvent.Create(1, 'admin', urAdmin);
  Assert.AreEqual('UserCreated', LEvent.EventName);
end;

procedure TConcreteEventTests.UserRoleChangedEvent_HasCorrectEventName;
var
  LEvent: IDomainEvent;
begin
  LEvent := TUserRoleChangedEvent.Create(1, urUser, urAdmin);
  Assert.AreEqual('UserRoleChanged', LEvent.EventName);
end;

procedure TConcreteEventTests.BaseDomainEvent_SetsOccurredAt;
var
  LEvent: IDomainEvent;
  LBefore: TDateTime;
begin
  LBefore := Now;
  LEvent := TTaskDeletedEvent.Create(1);
  Assert.IsTrue(LEvent.OccurredAt >= LBefore, 'OccurredAt should be >= creation time');
end;

procedure TConcreteEventTests.BaseDomainEvent_SetsEntityId;
var
  LEvent: IDomainEvent;
begin
  LEvent := TTaskDeletedEvent.Create(42);
  Assert.AreEqual(42, LEvent.EntityId);
end;

end.
