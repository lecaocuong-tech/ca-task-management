unit Result;

interface

type
  TResult<T> = record
  private
    FSuccess: Boolean;
    FErrorMessage: string;
    FValue: T;
  public
    class function Success(AValue: T): TResult<T>; static;
    class function Failure(const AErrorMessage: string): TResult<T>; static;

    function IsSuccess: Boolean;
    function GetValue: T;
    function GetErrorMessage: string;
  end;

  TResult = record
  private
    FSuccess: Boolean;
    FErrorMessage: string;
  public
    class function Success: TResult; static;
    class function Failure(const AErrorMessage: string): TResult; static;

    function IsSuccess: Boolean;
    function GetErrorMessage: string;
  end;

implementation

{ TResult<T> }

class function TResult<T>.Success(AValue: T): TResult<T>;
begin
  Result.FSuccess := True;
  Result.FErrorMessage := '';
  Result.FValue := AValue;
end;

class function TResult<T>.Failure(const AErrorMessage: string): TResult<T>;
begin
  Result.FSuccess := False;
  Result.FErrorMessage := AErrorMessage;
end;


function TResult<T>.IsSuccess: Boolean;
begin
  Result := FSuccess;
end;

function TResult<T>.GetValue: T;
begin
  Result := FValue;
end;

function TResult<T>.GetErrorMessage: string;
begin
  Result := FErrorMessage;
end;

{ TResult }

class function TResult.Success: TResult;
begin
  Result.FSuccess := True;
  Result.FErrorMessage := '';
end;

class function TResult.Failure(const AErrorMessage: string): TResult;
begin
  Result.FSuccess := False;
  Result.FErrorMessage := AErrorMessage;
end;

function TResult.IsSuccess: Boolean;
begin
  Result := FSuccess;
end;

function TResult.GetErrorMessage: string;
begin
  Result := FErrorMessage;
end;

end.
