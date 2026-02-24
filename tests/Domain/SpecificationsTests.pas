unit SpecificationsTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.DateUtils,
  DomainModels,
  Specifications;

{
  SpecificationsTests.pas
  ------------------------
  Unit tests for the DDD Specification pattern implementation.

  Tests verify:
  - Individual specifications (Status, User, CompletedOlderThan)
  - Composite specifications (And, Or, Not)
  - Fluent factory API (TTaskSpecs)
  - SQL WHERE clause generation
  - Edge cases (unknown status, zero user, negative days)
}

type
  // ==========================================================================
  // Status Specification Tests
  // ==========================================================================

  [TestFixture]
  TStatusSpecTests = class
  public
    [Test]
    procedure IsSatisfiedBy_MatchingStatus_ReturnsTrue;
    [Test]
    procedure IsSatisfiedBy_NonMatchingStatus_ReturnsFalse;
    [Test]
    procedure ToSQLWhere_PendingStatus_ReturnsCorrectSQL;
    [Test]
    procedure ToSQLWhere_DoneStatus_ReturnsCorrectSQL;
  end;

  // ==========================================================================
  // User Specification Tests
  // ==========================================================================

  [TestFixture]
  TUserSpecTests = class
  public
    [Test]
    procedure IsSatisfiedBy_MatchingUser_ReturnsTrue;
    [Test]
    procedure IsSatisfiedBy_DifferentUser_ReturnsFalse;
    [Test]
    procedure ToSQLWhere_ReturnsCorrectSQL;
  end;

  // ==========================================================================
  // CompletedOlderThan Specification Tests
  // ==========================================================================

  [TestFixture]
  TCompletedOlderThanSpecTests = class
  public
    [Test]
    procedure IsSatisfiedBy_DoneAndOldEnough_ReturnsTrue;
    [Test]
    procedure IsSatisfiedBy_DoneButTooRecent_ReturnsFalse;
    [Test]
    procedure IsSatisfiedBy_NotDone_ReturnsFalse;
    [Test]
    procedure ToSQLWhere_ReturnsCorrectSQL;
  end;

  // ==========================================================================
  // Composite Specification Tests (And, Or, Not)
  // ==========================================================================

  [TestFixture]
  TCompositeSpecTests = class
  public
    // --- And ---
    [Test]
    procedure AndSpec_BothTrue_ReturnsTrue;
    [Test]
    procedure AndSpec_OneFalse_ReturnsFalse;
    [Test]
    procedure AndSpec_ToSQLWhere_CombinesWithAND;

    // --- Or ---
    [Test]
    procedure OrSpec_OneTrue_ReturnsTrue;
    [Test]
    procedure OrSpec_BothFalse_ReturnsFalse;
    [Test]
    procedure OrSpec_ToSQLWhere_CombinesWithOR;

    // --- Not ---
    [Test]
    procedure NotSpec_InvertsTrue_ReturnsFalse;
    [Test]
    procedure NotSpec_InvertsFalse_ReturnsTrue;
    [Test]
    procedure NotSpec_ToSQLWhere_WrapsWithNOT;
  end;

  // ==========================================================================
  // Fluent Factory (TTaskSpecs) Tests
  // ==========================================================================

  [TestFixture]
  TTaskSpecsFactoryTests = class
  public
    [Test]
    procedure ByStatus_ReturnsSatisfiedForMatchingTask;
    [Test]
    procedure ByUser_ReturnsSatisfiedForMatchingTask;
    [Test]
    procedure CompletedOlderThan_ReturnsSatisfiedForOldDoneTask;
    [Test]
    procedure Combine_ChainsTwoSpecs;
    [Test]
    procedure Either_ReturnsTrueIfOneMatches;
    [Test]
    procedure Negate_InvertsResult;
    [Test]
    procedure ComplexChain_StatusAndUser_Works;
  end;

implementation

{ Helper: create a task with specific properties }

function CreateTestTask(AId, AUserId: Integer; AStatus: TTaskStatus;
  AUpdatedAt: TDateTime = 0): TTask;
begin
  Result := TTask.Hydrate(AId, AUserId, 'Test Task', '', AStatus, Now, AUpdatedAt);
end;

{ TStatusSpecTests }

procedure TStatusSpecTests.IsSatisfiedBy_MatchingStatus_ReturnsTrue;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TStatusSpecification.Create(tsPending);
  LTask := CreateTestTask(1, 1, tsPending);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TStatusSpecTests.IsSatisfiedBy_NonMatchingStatus_ReturnsFalse;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TStatusSpecification.Create(tsDone);
  LTask := CreateTestTask(1, 1, tsPending);
  try
    Assert.IsFalse(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TStatusSpecTests.ToSQLWhere_PendingStatus_ReturnsCorrectSQL;
var
  LSpec: ITaskSpecification;
begin
  LSpec := TStatusSpecification.Create(tsPending);
  Assert.AreEqual('Status = ''Pending''', LSpec.ToSQLWhere);
end;

procedure TStatusSpecTests.ToSQLWhere_DoneStatus_ReturnsCorrectSQL;
var
  LSpec: ITaskSpecification;
begin
  LSpec := TStatusSpecification.Create(tsDone);
  Assert.AreEqual('Status = ''Done''', LSpec.ToSQLWhere);
end;

{ TUserSpecTests }

procedure TUserSpecTests.IsSatisfiedBy_MatchingUser_ReturnsTrue;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TUserSpecification.Create(5);
  LTask := CreateTestTask(1, 5, tsPending);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TUserSpecTests.IsSatisfiedBy_DifferentUser_ReturnsFalse;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TUserSpecification.Create(5);
  LTask := CreateTestTask(1, 99, tsPending);
  try
    Assert.IsFalse(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TUserSpecTests.ToSQLWhere_ReturnsCorrectSQL;
var
  LSpec: ITaskSpecification;
begin
  LSpec := TUserSpecification.Create(42);
  Assert.AreEqual('UserId = 42', LSpec.ToSQLWhere);
end;

{ TCompletedOlderThanSpecTests }

procedure TCompletedOlderThanSpecTests.IsSatisfiedBy_DoneAndOldEnough_ReturnsTrue;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TCompletedOlderThanSpecification.Create(7);
  // Task completed 10 days ago
  LTask := CreateTestTask(1, 1, tsDone, IncDay(Now, -10));
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TCompletedOlderThanSpecTests.IsSatisfiedBy_DoneButTooRecent_ReturnsFalse;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TCompletedOlderThanSpecification.Create(7);
  // Task completed 3 days ago
  LTask := CreateTestTask(1, 1, tsDone, IncDay(Now, -3));
  try
    Assert.IsFalse(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TCompletedOlderThanSpecTests.IsSatisfiedBy_NotDone_ReturnsFalse;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TCompletedOlderThanSpecification.Create(7);
  LTask := CreateTestTask(1, 1, tsInProgress, IncDay(Now, -10));
  try
    Assert.IsFalse(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TCompletedOlderThanSpecTests.ToSQLWhere_ReturnsCorrectSQL;
var
  LSpec: ITaskSpecification;
  LSQL: string;
begin
  LSpec := TCompletedOlderThanSpecification.Create(30);
  LSQL := LSpec.ToSQLWhere;
  Assert.Contains(LSQL, 'Status');
  Assert.Contains(LSQL, 'Done');
  Assert.Contains(LSQL, '30');
end;

{ TCompositeSpecTests }

procedure TCompositeSpecTests.AndSpec_BothTrue_ReturnsTrue;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.ByStatus(tsPending).AndSpec(TTaskSpecs.ByUser(5));
  LTask := CreateTestTask(1, 5, tsPending);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TCompositeSpecTests.AndSpec_OneFalse_ReturnsFalse;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.ByStatus(tsDone).AndSpec(TTaskSpecs.ByUser(5));
  LTask := CreateTestTask(1, 5, tsPending); // status doesn't match
  try
    Assert.IsFalse(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TCompositeSpecTests.AndSpec_ToSQLWhere_CombinesWithAND;
var
  LSpec: ITaskSpecification;
  LSQL: string;
begin
  LSpec := TTaskSpecs.ByStatus(tsPending).AndSpec(TTaskSpecs.ByUser(5));
  LSQL := LSpec.ToSQLWhere;
  Assert.Contains(LSQL, 'AND');
  Assert.Contains(LSQL, 'Pending');
  Assert.Contains(LSQL, '5');
end;

procedure TCompositeSpecTests.OrSpec_OneTrue_ReturnsTrue;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.ByStatus(tsPending).OrSpec(TTaskSpecs.ByStatus(tsDone));
  LTask := CreateTestTask(1, 1, tsPending);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TCompositeSpecTests.OrSpec_BothFalse_ReturnsFalse;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.ByStatus(tsDone).OrSpec(TTaskSpecs.ByUser(99));
  LTask := CreateTestTask(1, 1, tsPending);
  try
    Assert.IsFalse(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TCompositeSpecTests.OrSpec_ToSQLWhere_CombinesWithOR;
var
  LSpec: ITaskSpecification;
  LSQL: string;
begin
  LSpec := TTaskSpecs.ByStatus(tsPending).OrSpec(TTaskSpecs.ByStatus(tsDone));
  LSQL := LSpec.ToSQLWhere;
  Assert.Contains(LSQL, 'OR');
end;

procedure TCompositeSpecTests.NotSpec_InvertsTrue_ReturnsFalse;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.ByStatus(tsPending).NotSpec;
  LTask := CreateTestTask(1, 1, tsPending);
  try
    Assert.IsFalse(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TCompositeSpecTests.NotSpec_InvertsFalse_ReturnsTrue;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.ByStatus(tsDone).NotSpec;
  LTask := CreateTestTask(1, 1, tsPending);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TCompositeSpecTests.NotSpec_ToSQLWhere_WrapsWithNOT;
var
  LSpec: ITaskSpecification;
  LSQL: string;
begin
  LSpec := TTaskSpecs.ByStatus(tsPending).NotSpec;
  LSQL := LSpec.ToSQLWhere;
  Assert.Contains(LSQL, 'NOT');
end;

{ TTaskSpecsFactoryTests }

procedure TTaskSpecsFactoryTests.ByStatus_ReturnsSatisfiedForMatchingTask;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.ByStatus(tsInProgress);
  LTask := CreateTestTask(1, 1, tsInProgress);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TTaskSpecsFactoryTests.ByUser_ReturnsSatisfiedForMatchingTask;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.ByUser(7);
  LTask := CreateTestTask(1, 7, tsPending);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TTaskSpecsFactoryTests.CompletedOlderThan_ReturnsSatisfiedForOldDoneTask;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.CompletedOlderThan(5);
  LTask := CreateTestTask(1, 1, tsDone, IncDay(Now, -10));
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TTaskSpecsFactoryTests.Combine_ChainsTwoSpecs;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.Combine(TTaskSpecs.ByStatus(tsPending), TTaskSpecs.ByUser(3));
  LTask := CreateTestTask(1, 3, tsPending);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TTaskSpecsFactoryTests.Either_ReturnsTrueIfOneMatches;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.Either(TTaskSpecs.ByStatus(tsDone), TTaskSpecs.ByUser(3));
  LTask := CreateTestTask(1, 3, tsPending); // User matches but status doesn't
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TTaskSpecsFactoryTests.Negate_InvertsResult;
var
  LSpec: ITaskSpecification;
  LTask: TTask;
begin
  LSpec := TTaskSpecs.Negate(TTaskSpecs.ByStatus(tsDone));
  LTask := CreateTestTask(1, 1, tsPending);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LTask));
  finally
    LTask.Free;
  end;
end;

procedure TTaskSpecsFactoryTests.ComplexChain_StatusAndUser_Works;
var
  LSpec: ITaskSpecification;
  LMatch, LNoMatch: TTask;
begin
  // (Status=Pending AND User=5) OR Status=Done
  LSpec := TTaskSpecs.Either(
    TTaskSpecs.Combine(TTaskSpecs.ByStatus(tsPending), TTaskSpecs.ByUser(5)),
    TTaskSpecs.ByStatus(tsDone)
  );

  LMatch := CreateTestTask(1, 5, tsPending);
  LNoMatch := CreateTestTask(2, 99, tsInProgress);
  try
    Assert.IsTrue(LSpec.IsSatisfiedBy(LMatch), 'Pending task by user 5 should match');
    Assert.IsFalse(LSpec.IsSatisfiedBy(LNoMatch), 'InProgress task by user 99 should not match');
  finally
    LMatch.Free;
    LNoMatch.Free;
  end;
end;

end.
