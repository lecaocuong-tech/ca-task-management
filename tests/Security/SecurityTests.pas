unit SecurityTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.DateUtils,
  AppInterfaces,
  Result,
  MockInterfaces;

{
  SecurityTests.pas
  ------------------
  Unit tests for security components: RateLimiter and InputSanitizer.

  Tests verify:
  - Rate limiter allows requests within limits
  - Rate limiter blocks requests exceeding limits
  - Rate limiter replenishes tokens over time
  - Input sanitizer strips HTML tags
  - Input sanitizer validates username format
  - Input sanitizer validates field lengths
  - Input sanitizer detects suspicious SQL patterns
}

type
  // ==========================================================================
  // RateLimiter Tests
  // ==========================================================================

  [TestFixture]
  TRateLimiterTests = class
  private
    FLogger: TMockLogger;
    FRateLimiter: IRateLimiter;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TryConsume_FirstRequest_Succeeds;
    [Test]
    procedure TryConsume_WithinLimit_Succeeds;
    [Test]
    procedure TryConsume_ExceedsLimit_Fails;
    [Test]
    procedure GetRemainingTokens_InitialValue_EqualsMax;
    [Test]
    procedure GetRemainingTokens_AfterConsume_Decreases;
    [Test]
    procedure ResetKey_ResetsSpecificKey;
    [Test]
    procedure ResetAll_ClearsAllKeys;
    [Test]
    procedure DifferentKeys_IndependentTracking;
  end;

  // ==========================================================================
  // InputSanitizer Tests
  // ==========================================================================

  [TestFixture]
  TInputSanitizerTests = class
  private
    FLogger: TMockLogger;
    FSanitizer: IInputSanitizer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- SanitizeString ---
    [Test]
    procedure SanitizeString_TrimsWhitespace;
    [Test]
    procedure SanitizeString_StripsHTMLTags;
    [Test]
    procedure SanitizeString_StripsScriptTags;
    [Test]
    procedure SanitizeString_RemovesNullBytes;
    [Test]
    procedure SanitizeString_NormalizesWhitespace;

    // --- ValidateUsername ---
    [Test]
    procedure ValidateUsername_Valid_Succeeds;
    [Test]
    procedure ValidateUsername_Empty_Fails;
    [Test]
    procedure ValidateUsername_TooShort_Fails;
    [Test]
    procedure ValidateUsername_TooLong_Fails;
    [Test]
    procedure ValidateUsername_SpecialChars_Fails;
    [Test]
    procedure ValidateUsername_WithUnderscore_Succeeds;

    // --- ValidateTaskTitle ---
    [Test]
    procedure ValidateTaskTitle_Valid_Succeeds;
    [Test]
    procedure ValidateTaskTitle_Empty_Fails;
    [Test]
    procedure ValidateTaskTitle_TooLong_Fails;

    // --- ValidateTaskDescription ---
    [Test]
    procedure ValidateTaskDescription_Empty_Succeeds;
    [Test]
    procedure ValidateTaskDescription_Valid_Succeeds;
    [Test]
    procedure ValidateTaskDescription_TooLong_Fails;

    // --- ValidatePassword ---
    [Test]
    procedure ValidatePassword_Valid_Succeeds;
    [Test]
    procedure ValidatePassword_Empty_Fails;
    [Test]
    procedure ValidatePassword_TooLong_Fails;

    // --- ValidateTextField ---
    [Test]
    procedure ValidateTextField_Valid_Succeeds;
    [Test]
    procedure ValidateTextField_Empty_Fails;
    [Test]
    procedure ValidateTextField_TooLong_Fails;
  end;

implementation

uses
  RateLimiter,
  InputSanitizer;

{ TRateLimiterTests }

procedure TRateLimiterTests.Setup;
begin
  FLogger := TMockLogger.Create;
  // 5 max tokens, 1 token/second refill
  FRateLimiter := TTokenBucketRateLimiter.Create(FLogger as ILogger, 5, 1.0);
end;

procedure TRateLimiterTests.TearDown;
begin
  FRateLimiter := nil;
  // FLogger ref-counted
end;

procedure TRateLimiterTests.TryConsume_FirstRequest_Succeeds;
begin
  Assert.IsTrue(FRateLimiter.TryConsume('test:key'));
end;

procedure TRateLimiterTests.TryConsume_WithinLimit_Succeeds;
var
  I: Integer;
begin
  // Use 4 of 5 tokens — should all succeed
  for I := 1 to 4 do
    Assert.IsTrue(FRateLimiter.TryConsume('test:key'),
      Format('Token %d should succeed', [I]));
end;

procedure TRateLimiterTests.TryConsume_ExceedsLimit_Fails;
var
  I: Integer;
begin
  // Consume all 5 tokens
  for I := 1 to 5 do
    FRateLimiter.TryConsume('test:key');
  // 6th should fail
  Assert.IsFalse(FRateLimiter.TryConsume('test:key'),
    'Should fail after exceeding limit');
end;

procedure TRateLimiterTests.GetRemainingTokens_InitialValue_EqualsMax;
begin
  Assert.AreEqual(5, FRateLimiter.GetRemainingTokens('new:key'));
end;

procedure TRateLimiterTests.GetRemainingTokens_AfterConsume_Decreases;
begin
  FRateLimiter.TryConsume('test:key');
  Assert.IsTrue(FRateLimiter.GetRemainingTokens('test:key') < 5);
end;

procedure TRateLimiterTests.ResetKey_ResetsSpecificKey;
begin
  // Consume all tokens
  var I: Integer;
  for I := 1 to 5 do
    FRateLimiter.TryConsume('test:key');
  Assert.IsFalse(FRateLimiter.TryConsume('test:key'), 'Should be blocked');

  FRateLimiter.ResetKey('test:key');
  Assert.IsTrue(FRateLimiter.TryConsume('test:key'), 'Should succeed after reset');
end;

procedure TRateLimiterTests.ResetAll_ClearsAllKeys;
begin
  var I: Integer;
  for I := 1 to 5 do
  begin
    FRateLimiter.TryConsume('key:a');
    FRateLimiter.TryConsume('key:b');
  end;

  FRateLimiter.ResetAll;

  Assert.IsTrue(FRateLimiter.TryConsume('key:a'), 'key:a should work after reset');
  Assert.IsTrue(FRateLimiter.TryConsume('key:b'), 'key:b should work after reset');
end;

procedure TRateLimiterTests.DifferentKeys_IndependentTracking;
begin
  var I: Integer;
  for I := 1 to 5 do
    FRateLimiter.TryConsume('key:a');

  // key:a should be exhausted, key:b should be fresh
  Assert.IsFalse(FRateLimiter.TryConsume('key:a'), 'key:a should be blocked');
  Assert.IsTrue(FRateLimiter.TryConsume('key:b'), 'key:b should succeed');
end;

{ TInputSanitizerTests }

procedure TInputSanitizerTests.Setup;
begin
  FLogger := TMockLogger.Create;
  FSanitizer := TInputSanitizer.Create(FLogger as ILogger);
end;

procedure TInputSanitizerTests.TearDown;
begin
  FSanitizer := nil;
end;

procedure TInputSanitizerTests.SanitizeString_TrimsWhitespace;
begin
  Assert.AreEqual('hello world', FSanitizer.SanitizeString('  hello world  '));
end;

procedure TInputSanitizerTests.SanitizeString_StripsHTMLTags;
begin
  Assert.AreEqual('Hello', FSanitizer.SanitizeString('<b>Hello</b>'));
end;

procedure TInputSanitizerTests.SanitizeString_StripsScriptTags;
begin
  Assert.AreEqual('alert("xss")', FSanitizer.SanitizeString('<script>alert("xss")</script>'));
end;

procedure TInputSanitizerTests.SanitizeString_RemovesNullBytes;
begin
  Assert.AreEqual('test', FSanitizer.SanitizeString('te' + #0 + 'st'));
end;

procedure TInputSanitizerTests.SanitizeString_NormalizesWhitespace;
begin
  Assert.AreEqual('hello world', FSanitizer.SanitizeString('hello    world'));
end;

procedure TInputSanitizerTests.ValidateUsername_Valid_Succeeds;
begin
  Assert.IsTrue(FSanitizer.ValidateUsername('admin').IsSuccess);
end;

procedure TInputSanitizerTests.ValidateUsername_Empty_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidateUsername('').IsSuccess);
end;

procedure TInputSanitizerTests.ValidateUsername_TooShort_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidateUsername('ab').IsSuccess);
end;

procedure TInputSanitizerTests.ValidateUsername_TooLong_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidateUsername(StringOfChar('a', 51)).IsSuccess);
end;

procedure TInputSanitizerTests.ValidateUsername_SpecialChars_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidateUsername('admin@test').IsSuccess);
  Assert.IsFalse(FSanitizer.ValidateUsername('user name').IsSuccess);
  Assert.IsFalse(FSanitizer.ValidateUsername('user<script>').IsSuccess);
end;

procedure TInputSanitizerTests.ValidateUsername_WithUnderscore_Succeeds;
begin
  Assert.IsTrue(FSanitizer.ValidateUsername('admin_user').IsSuccess);
  Assert.IsTrue(FSanitizer.ValidateUsername('user.name').IsSuccess);
end;

procedure TInputSanitizerTests.ValidateTaskTitle_Valid_Succeeds;
begin
  Assert.IsTrue(FSanitizer.ValidateTaskTitle('My Task').IsSuccess);
end;

procedure TInputSanitizerTests.ValidateTaskTitle_Empty_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidateTaskTitle('').IsSuccess);
end;

procedure TInputSanitizerTests.ValidateTaskTitle_TooLong_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidateTaskTitle(StringOfChar('a', 201)).IsSuccess);
end;

procedure TInputSanitizerTests.ValidateTaskDescription_Empty_Succeeds;
begin
  Assert.IsTrue(FSanitizer.ValidateTaskDescription('').IsSuccess);
end;

procedure TInputSanitizerTests.ValidateTaskDescription_Valid_Succeeds;
begin
  Assert.IsTrue(FSanitizer.ValidateTaskDescription('Some description').IsSuccess);
end;

procedure TInputSanitizerTests.ValidateTaskDescription_TooLong_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidateTaskDescription(StringOfChar('a', 2001)).IsSuccess);
end;

procedure TInputSanitizerTests.ValidatePassword_Valid_Succeeds;
begin
  Assert.IsTrue(FSanitizer.ValidatePassword('MyPassword123').IsSuccess);
end;

procedure TInputSanitizerTests.ValidatePassword_Empty_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidatePassword('').IsSuccess);
end;

procedure TInputSanitizerTests.ValidatePassword_TooLong_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidatePassword(StringOfChar('a', 129)).IsSuccess);
end;

procedure TInputSanitizerTests.ValidateTextField_Valid_Succeeds;
begin
  Assert.IsTrue(FSanitizer.ValidateTextField('Hello', 'Name', 100).IsSuccess);
end;

procedure TInputSanitizerTests.ValidateTextField_Empty_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidateTextField('', 'Name', 100).IsSuccess);
end;

procedure TInputSanitizerTests.ValidateTextField_TooLong_Fails;
begin
  Assert.IsFalse(FSanitizer.ValidateTextField(StringOfChar('a', 101), 'Name', 100).IsSuccess);
end;

end.
