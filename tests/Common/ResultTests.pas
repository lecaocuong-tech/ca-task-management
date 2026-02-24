unit ResultTests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  Result;

type
  // ==========================================================================
  // TResult (non-generic) tests
  // ==========================================================================

  [TestFixture]
  TResultTests = class
  public
    [Test]
    procedure Success_IsSuccess_ReturnsTrue;
    [Test]
    procedure Success_ErrorMessage_IsEmpty;
    [Test]
    procedure Failure_IsSuccess_ReturnsFalse;
    [Test]
    procedure Failure_ErrorMessage_ReturnsMessage;
    [Test]
    procedure Failure_EmptyMessage_StillFails;
  end;

  // ==========================================================================
  // TResult<T> (generic) tests
  // ==========================================================================

  [TestFixture]
  TResultGenericTests = class
  public
    [Test]
    procedure Success_IsSuccess_ReturnsTrue;
    [Test]
    procedure Success_GetValue_ReturnsValue;
    [Test]
    procedure Failure_IsSuccess_ReturnsFalse;
    [Test]
    procedure Failure_ErrorMessage_ReturnsMessage;
    [Test]
    procedure Success_IntegerValue_ReturnsCorrectValue;
    [Test]
    procedure Success_StringValue_ReturnsCorrectValue;
  end;

implementation

{ TResultTests }

procedure TResultTests.Success_IsSuccess_ReturnsTrue;
var
  LResult: TResult;
begin
  LResult := TResult.Success;
  Assert.IsTrue(LResult.IsSuccess);
end;

procedure TResultTests.Success_ErrorMessage_IsEmpty;
var
  LResult: TResult;
begin
  LResult := TResult.Success;
  Assert.AreEqual('', LResult.GetErrorMessage);
end;

procedure TResultTests.Failure_IsSuccess_ReturnsFalse;
var
  LResult: TResult;
begin
  LResult := TResult.Failure('Something went wrong');
  Assert.IsFalse(LResult.IsSuccess);
end;

procedure TResultTests.Failure_ErrorMessage_ReturnsMessage;
var
  LResult: TResult;
begin
  LResult := TResult.Failure('Detailed error info');
  Assert.AreEqual('Detailed error info', LResult.GetErrorMessage);
end;

procedure TResultTests.Failure_EmptyMessage_StillFails;
var
  LResult: TResult;
begin
  LResult := TResult.Failure('');
  Assert.IsFalse(LResult.IsSuccess);
end;

{ TResultGenericTests }

procedure TResultGenericTests.Success_IsSuccess_ReturnsTrue;
var
  LResult: TResult<Integer>;
begin
  LResult := TResult<Integer>.Success(42);
  Assert.IsTrue(LResult.IsSuccess);
end;

procedure TResultGenericTests.Success_GetValue_ReturnsValue;
var
  LResult: TResult<Integer>;
begin
  LResult := TResult<Integer>.Success(42);
  Assert.AreEqual(42, LResult.GetValue);
end;

procedure TResultGenericTests.Failure_IsSuccess_ReturnsFalse;
var
  LResult: TResult<Integer>;
begin
  LResult := TResult<Integer>.Failure('Not found');
  Assert.IsFalse(LResult.IsSuccess);
end;

procedure TResultGenericTests.Failure_ErrorMessage_ReturnsMessage;
var
  LResult: TResult<Integer>;
begin
  LResult := TResult<Integer>.Failure('Not found');
  Assert.AreEqual('Not found', LResult.GetErrorMessage);
end;

procedure TResultGenericTests.Success_IntegerValue_ReturnsCorrectValue;
var
  LResult: TResult<Integer>;
begin
  LResult := TResult<Integer>.Success(99);
  Assert.AreEqual(99, LResult.GetValue);
end;

procedure TResultGenericTests.Success_StringValue_ReturnsCorrectValue;
var
  LResult: TResult<string>;
begin
  LResult := TResult<string>.Success('hello');
  Assert.AreEqual('hello', LResult.GetValue);
end;

initialization
  TDUnitX.RegisterTestFixture(TResultTests);
  TDUnitX.RegisterTestFixture(TResultGenericTests);

end.
