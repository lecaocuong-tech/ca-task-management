unit DomainModelsTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DomainModels;

type
  // ==========================================================================
  // TTask state machine and validation tests
  // ==========================================================================

  [TestFixture]
  TTaskDomainTests = class
  private
    FTask: TTask;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- Default values ---
    [Test]
    procedure Create_DefaultStatus_IsPending;
    [Test]
    procedure Create_DefaultUpdatedAt_IsZero;

    // --- IsValid ---
    [Test]
    procedure IsValid_ValidTask_ReturnsTrue;
    [Test]
    procedure IsValid_EmptyTitle_ReturnsFalse;
    [Test]
    procedure IsValid_ZeroUserId_ReturnsFalse;
    [Test]
    procedure IsValid_UnknownStatus_ReturnsFalse;
    [Test]
    procedure IsValid_WhitespaceTitle_ReturnsFalse;

    // --- CanTransitionTo: allowed transitions ---
    [Test]
    procedure CanTransitionTo_SameStatus_ReturnsTrue;
    [Test]
    procedure CanTransitionTo_PendingToInProgress_Allowed;
    [Test]
    procedure CanTransitionTo_PendingToDone_Allowed;
    [Test]
    procedure CanTransitionTo_InProgressToDone_Allowed;
    [Test]
    procedure CanTransitionTo_InProgressToPending_Allowed;
    [Test]
    procedure CanTransitionTo_DoneToInProgress_Allowed;

    // --- CanTransitionTo: forbidden transitions ---
    [Test]
    procedure CanTransitionTo_DoneToPending_Forbidden;
    [Test]
    procedure CanTransitionTo_AnyToUnknown_Forbidden;
    [Test]
    procedure CanTransitionTo_PendingToPending_Allowed;

    // --- MarkInProgress ---
    [Test]
    procedure MarkInProgress_FromPending_ChangesStatus;
    [Test]
    procedure MarkInProgress_SetsUpdatedAt;

    // --- MarkDone ---
    [Test]
    procedure MarkDone_FromPending_ChangesStatus;
    [Test]
    procedure MarkDone_FromInProgress_ChangesStatus;
    [Test]
    procedure MarkDone_SetsUpdatedAt;

    // --- Reopen ---
    [Test]
    procedure Reopen_FromDone_ChangesToInProgress;
    [Test]
    procedure Reopen_FromPending_RaisesException;

    // --- ChangeStatus ---
    [Test]
    procedure ChangeStatus_ToInProgress_Works;
    [Test]
    procedure ChangeStatus_ToDone_Works;

    // --- UpdateContent ---
    [Test]
    procedure UpdateContent_ChangesTitle;
    [Test]
    procedure UpdateContent_EmptyTitle_Raises;

    // --- Factory methods ---
    [Test]
    procedure CreateNew_SetsFields;
    [Test]
    procedure Hydrate_SetsAllFields;
  end;

  // ==========================================================================
  // TUser validation tests
  // ==========================================================================

  [TestFixture]
  TUserDomainTests = class
  private
    FUser: TUser;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Create_DefaultRole_IsUser;
    [Test]
    procedure IsValid_WithUsername_ReturnsTrue;
    [Test]
    procedure IsValid_EmptyUsername_ReturnsFalse;
    [Test]
    procedure IsValid_WhitespaceUsername_ReturnsFalse;
    [Test]
    procedure IsAdmin_AdminRole_ReturnsTrue;
    [Test]
    procedure IsAdmin_UserRole_ReturnsFalse;
    [Test]
    procedure RoleToString_Admin_ReturnsAdmin;
    [Test]
    procedure RoleToString_User_ReturnsUser;

    // --- Domain methods ---
    [Test]
    procedure ChangePassword_UpdatesCredential;
    [Test]
    procedure ChangeRole_UpdatesRole;

    // --- Factory methods ---
    [Test]
    procedure CreateNew_SetsFields;
    [Test]
    procedure Hydrate_SetsAllFields;

    // --- Value object ---
    [Test]
    procedure PasswordCredential_Equality;
  end;

  // ==========================================================================
  // Status/Role string converter tests
  // ==========================================================================

  [TestFixture]
  TStatusConverterTests = class
  public
    [Test]
    procedure StatusToStr_Pending_ReturnsPending;
    [Test]
    procedure StatusToStr_InProgress_ReturnsInProgress;
    [Test]
    procedure StatusToStr_Done_ReturnsDone;
    [Test]
    procedure StatusToStr_Unknown_ReturnsUnknown;
    [Test]
    procedure StrToStatus_Pending_ReturnsTsPending;
    [Test]
    procedure StrToStatus_InProgress_ReturnsTsInProgress;
    [Test]
    procedure StrToStatus_Done_ReturnsTsDone;
    [Test]
    procedure StrToStatus_Invalid_ReturnsTsUnknown;
    [Test]
    procedure UserRoleToStr_Admin;
    [Test]
    procedure UserRoleToStr_User;
    [Test]
    procedure StrToUserRole_Admin;
    [Test]
    procedure StrToUserRole_Invalid_DefaultsToUser;
  end;

implementation

{ TTaskDomainTests }

procedure TTaskDomainTests.Setup;
begin
  FTask := TTask.CreateNew(1, 'Test Task');
end;

procedure TTaskDomainTests.TearDown;
begin
  FTask.Free;
end;

// --- Default values ---

procedure TTaskDomainTests.Create_DefaultStatus_IsPending;
begin
  Assert.AreEqual(Ord(tsPending), Ord(FTask.Status));
end;

procedure TTaskDomainTests.Create_DefaultUpdatedAt_IsZero;
begin
  Assert.AreEqual(Double(0), Double(FTask.UpdatedAt), 0.0001);
end;

// --- IsValid ---

procedure TTaskDomainTests.IsValid_ValidTask_ReturnsTrue;
begin
  Assert.IsTrue(FTask.IsValid);
end;

procedure TTaskDomainTests.IsValid_EmptyTitle_ReturnsFalse;
var
  LTask: TTask;
begin
  LTask := TTask.CreateNew(1, '');
  try
    Assert.IsFalse(LTask.IsValid);
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.IsValid_ZeroUserId_ReturnsFalse;
var
  LTask: TTask;
begin
  LTask := TTask.CreateNew(0, 'Test');
  try
    Assert.IsFalse(LTask.IsValid);
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.IsValid_UnknownStatus_ReturnsFalse;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'Test', '', tsUnknown, Now, 0);
  try
    Assert.IsFalse(LTask.IsValid);
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.IsValid_WhitespaceTitle_ReturnsFalse;
var
  LTask: TTask;
begin
  LTask := TTask.CreateNew(1, '   ');
  try
    Assert.IsFalse(LTask.IsValid);
  finally
    LTask.Free;
  end;
end;

// --- CanTransitionTo: allowed ---

procedure TTaskDomainTests.CanTransitionTo_SameStatus_ReturnsTrue;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'T', '', tsInProgress, Now, 0);
  try
    Assert.IsTrue(LTask.CanTransitionTo(tsInProgress));
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.CanTransitionTo_PendingToInProgress_Allowed;
begin
  Assert.IsTrue(FTask.CanTransitionTo(tsInProgress));
end;

procedure TTaskDomainTests.CanTransitionTo_PendingToDone_Allowed;
begin
  Assert.IsTrue(FTask.CanTransitionTo(tsDone));
end;

procedure TTaskDomainTests.CanTransitionTo_InProgressToDone_Allowed;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'T', '', tsInProgress, Now, 0);
  try
    Assert.IsTrue(LTask.CanTransitionTo(tsDone));
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.CanTransitionTo_InProgressToPending_Allowed;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'T', '', tsInProgress, Now, 0);
  try
    Assert.IsTrue(LTask.CanTransitionTo(tsPending));
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.CanTransitionTo_DoneToInProgress_Allowed;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'T', '', tsDone, Now, 0);
  try
    Assert.IsTrue(LTask.CanTransitionTo(tsInProgress));
  finally
    LTask.Free;
  end;
end;

// --- CanTransitionTo: forbidden ---

procedure TTaskDomainTests.CanTransitionTo_DoneToPending_Forbidden;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'T', '', tsDone, Now, 0);
  try
    Assert.IsFalse(LTask.CanTransitionTo(tsPending));
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.CanTransitionTo_AnyToUnknown_Forbidden;
begin
  Assert.IsFalse(FTask.CanTransitionTo(tsUnknown));
end;

procedure TTaskDomainTests.CanTransitionTo_PendingToPending_Allowed;
begin
  Assert.IsTrue(FTask.CanTransitionTo(tsPending));
end;

// --- MarkInProgress ---

procedure TTaskDomainTests.MarkInProgress_FromPending_ChangesStatus;
begin
  FTask.MarkInProgress;
  Assert.AreEqual(Ord(tsInProgress), Ord(FTask.Status));
end;

procedure TTaskDomainTests.MarkInProgress_SetsUpdatedAt;
var
  LBefore: TDateTime;
begin
  LBefore := Now;
  FTask.MarkInProgress;
  Assert.IsTrue(FTask.UpdatedAt >= LBefore, 'UpdatedAt should be set to current time');
end;

// --- MarkDone ---

procedure TTaskDomainTests.MarkDone_FromPending_ChangesStatus;
begin
  FTask.MarkDone;
  Assert.AreEqual(Ord(tsDone), Ord(FTask.Status));
end;

procedure TTaskDomainTests.MarkDone_FromInProgress_ChangesStatus;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'T', '', tsInProgress, Now, 0);
  try
    LTask.MarkDone;
    Assert.AreEqual(Ord(tsDone), Ord(LTask.Status));
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.MarkDone_SetsUpdatedAt;
var
  LBefore: TDateTime;
begin
  LBefore := Now;
  FTask.MarkDone;
  Assert.IsTrue(FTask.UpdatedAt >= LBefore);
end;

// --- Reopen ---

procedure TTaskDomainTests.Reopen_FromDone_ChangesToInProgress;
var
  LTask: TTask;
begin
  LTask := TTask.Hydrate(1, 1, 'T', '', tsDone, Now, 0);
  try
    LTask.Reopen;
    Assert.AreEqual(Ord(tsInProgress), Ord(LTask.Status));
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.Reopen_FromPending_RaisesException;
begin
  Assert.WillRaise(
    procedure
    begin
      FTask.Reopen;
    end,
    Exception
  );
end;

// --- ChangeStatus ---

procedure TTaskDomainTests.ChangeStatus_ToInProgress_Works;
begin
  FTask.ChangeStatus(tsInProgress);
  Assert.AreEqual(Ord(tsInProgress), Ord(FTask.Status));
end;

procedure TTaskDomainTests.ChangeStatus_ToDone_Works;
begin
  FTask.ChangeStatus(tsDone);
  Assert.AreEqual(Ord(tsDone), Ord(FTask.Status));
end;

// --- UpdateContent ---

procedure TTaskDomainTests.UpdateContent_ChangesTitle;
begin
  FTask.UpdateContent('New Title', 'New Desc');
  Assert.AreEqual('New Title', FTask.Title);
  Assert.AreEqual('New Desc', FTask.Description);
end;

procedure TTaskDomainTests.UpdateContent_EmptyTitle_Raises;
begin
  Assert.WillRaise(
    procedure
    begin
      FTask.UpdateContent('', 'desc');
    end,
    Exception
  );
end;

// --- Factory methods ---

procedure TTaskDomainTests.CreateNew_SetsFields;
var
  LTask: TTask;
begin
  LTask := TTask.CreateNew(5, 'My Task', 'My Description');
  try
    Assert.AreEqual(0, LTask.Id);
    Assert.AreEqual(5, LTask.UserId);
    Assert.AreEqual('My Task', LTask.Title);
    Assert.AreEqual('My Description', LTask.Description);
    Assert.AreEqual(Ord(tsPending), Ord(LTask.Status));
  finally
    LTask.Free;
  end;
end;

procedure TTaskDomainTests.Hydrate_SetsAllFields;
var
  LTask: TTask;
  LCreated: TDateTime;
begin
  LCreated := EncodeDate(2025, 1, 1);
  LTask := TTask.Hydrate(42, 7, 'Title', 'Desc', tsInProgress, LCreated, LCreated + 1);
  try
    Assert.AreEqual(42, LTask.Id);
    Assert.AreEqual(7, LTask.UserId);
    Assert.AreEqual('Title', LTask.Title);
    Assert.AreEqual('Desc', LTask.Description);
    Assert.AreEqual(Ord(tsInProgress), Ord(LTask.Status));
    Assert.AreEqual(Double(LCreated), Double(LTask.CreatedAt), 0.0001);
    Assert.AreEqual(Double(LCreated + 1), Double(LTask.UpdatedAt), 0.0001);
  finally
    LTask.Free;
  end;
end;

{ TUserDomainTests }

procedure TUserDomainTests.Setup;
begin
  FUser := TUser.CreateNew('testuser', 'hash', 'salt', urUser);
end;

procedure TUserDomainTests.TearDown;
begin
  FUser.Free;
end;

procedure TUserDomainTests.Create_DefaultRole_IsUser;
begin
  Assert.AreEqual(Ord(urUser), Ord(FUser.Role));
end;

procedure TUserDomainTests.IsValid_WithUsername_ReturnsTrue;
begin
  Assert.IsTrue(FUser.IsValid);
end;

procedure TUserDomainTests.IsValid_EmptyUsername_ReturnsFalse;
var
  LUser: TUser;
begin
  LUser := TUser.CreateNew('', 'hash', 'salt', urUser);
  try
    Assert.IsFalse(LUser.IsValid);
  finally
    LUser.Free;
  end;
end;

procedure TUserDomainTests.IsValid_WhitespaceUsername_ReturnsFalse;
var
  LUser: TUser;
begin
  LUser := TUser.CreateNew('   ', 'hash', 'salt', urUser);
  try
    Assert.IsFalse(LUser.IsValid);
  finally
    LUser.Free;
  end;
end;

procedure TUserDomainTests.IsAdmin_AdminRole_ReturnsTrue;
var
  LUser: TUser;
begin
  LUser := TUser.CreateNew('admin', 'hash', 'salt', urAdmin);
  try
    Assert.IsTrue(LUser.IsAdmin);
  finally
    LUser.Free;
  end;
end;

procedure TUserDomainTests.IsAdmin_UserRole_ReturnsFalse;
begin
  Assert.IsFalse(FUser.IsAdmin);
end;

procedure TUserDomainTests.RoleToString_Admin_ReturnsAdmin;
var
  LUser: TUser;
begin
  LUser := TUser.CreateNew('admin', 'hash', 'salt', urAdmin);
  try
    Assert.AreEqual('Admin', LUser.RoleToString);
  finally
    LUser.Free;
  end;
end;

procedure TUserDomainTests.RoleToString_User_ReturnsUser;
begin
  Assert.AreEqual('User', FUser.RoleToString);
end;

// --- Domain methods ---

procedure TUserDomainTests.ChangePassword_UpdatesCredential;
begin
  FUser.ChangePassword('newhash', 'newsalt');
  Assert.AreEqual('newhash', FUser.PasswordHash);
  Assert.AreEqual('newsalt', FUser.Salt);
end;

procedure TUserDomainTests.ChangeRole_UpdatesRole;
begin
  FUser.ChangeRole(urAdmin);
  Assert.AreEqual(Ord(urAdmin), Ord(FUser.Role));
end;

// --- Factory methods ---

procedure TUserDomainTests.CreateNew_SetsFields;
var
  LUser: TUser;
begin
  LUser := TUser.CreateNew('john', 'myhash', 'mysalt', urAdmin);
  try
    Assert.AreEqual(0, LUser.Id);
    Assert.AreEqual('john', LUser.Username);
    Assert.AreEqual('myhash', LUser.PasswordHash);
    Assert.AreEqual('mysalt', LUser.Salt);
    Assert.AreEqual(Ord(urAdmin), Ord(LUser.Role));
  finally
    LUser.Free;
  end;
end;

procedure TUserDomainTests.Hydrate_SetsAllFields;
var
  LUser: TUser;
  LCreated: TDateTime;
begin
  LCreated := EncodeDate(2025, 6, 15);
  LUser := TUser.Hydrate(99, 'jane', 'hash2', 'salt2', urAdmin, LCreated);
  try
    Assert.AreEqual(99, LUser.Id);
    Assert.AreEqual('jane', LUser.Username);
    Assert.AreEqual('hash2', LUser.PasswordHash);
    Assert.AreEqual('salt2', LUser.Salt);
    Assert.AreEqual(Ord(urAdmin), Ord(LUser.Role));
    Assert.AreEqual(Double(LCreated), Double(LUser.CreatedAt), 0.0001);
  finally
    LUser.Free;
  end;
end;

// --- Value object ---

procedure TUserDomainTests.PasswordCredential_Equality;
var
  A, B: TPasswordCredential;
begin
  A := TPasswordCredential.Create('hash1', 'salt1');
  B := TPasswordCredential.Create('hash1', 'salt1');
  Assert.IsTrue(A = B, 'Same hash+salt should be equal');

  B := TPasswordCredential.Create('hash2', 'salt1');
  Assert.IsTrue(A <> B, 'Different hash should not be equal');
end;

{ TStatusConverterTests }

procedure TStatusConverterTests.StatusToStr_Pending_ReturnsPending;
begin
  Assert.AreEqual('Pending', StatusToString(tsPending));
end;

procedure TStatusConverterTests.StatusToStr_InProgress_ReturnsInProgress;
begin
  Assert.AreEqual('InProgress', StatusToString(tsInProgress));
end;

procedure TStatusConverterTests.StatusToStr_Done_ReturnsDone;
begin
  Assert.AreEqual('Done', StatusToString(tsDone));
end;

procedure TStatusConverterTests.StatusToStr_Unknown_ReturnsUnknown;
begin
  Assert.AreEqual('Unknown', StatusToString(tsUnknown));
end;

procedure TStatusConverterTests.StrToStatus_Pending_ReturnsTsPending;
begin
  Assert.AreEqual(Ord(tsPending), Ord(StringToStatus('Pending')));
end;

procedure TStatusConverterTests.StrToStatus_InProgress_ReturnsTsInProgress;
begin
  Assert.AreEqual(Ord(tsInProgress), Ord(StringToStatus('InProgress')));
end;

procedure TStatusConverterTests.StrToStatus_Done_ReturnsTsDone;
begin
  Assert.AreEqual(Ord(tsDone), Ord(StringToStatus('Done')));
end;

procedure TStatusConverterTests.StrToStatus_Invalid_ReturnsTsUnknown;
begin
  Assert.AreEqual(Ord(tsUnknown), Ord(StringToStatus('garbage')));
end;

procedure TStatusConverterTests.UserRoleToStr_Admin;
begin
  Assert.AreEqual('Admin', UserRoleToString(urAdmin));
end;

procedure TStatusConverterTests.UserRoleToStr_User;
begin
  Assert.AreEqual('User', UserRoleToString(urUser));
end;

procedure TStatusConverterTests.StrToUserRole_Admin;
begin
  Assert.AreEqual(Ord(urAdmin), Ord(StringToUserRole('Admin')));
end;

procedure TStatusConverterTests.StrToUserRole_Invalid_DefaultsToUser;
begin
  Assert.AreEqual(Ord(urUser), Ord(StringToUserRole('InvalidRole')));
end;

initialization
  TDUnitX.RegisterTestFixture(TTaskDomainTests);
  TDUnitX.RegisterTestFixture(TUserDomainTests);
  TDUnitX.RegisterTestFixture(TStatusConverterTests);

end.
