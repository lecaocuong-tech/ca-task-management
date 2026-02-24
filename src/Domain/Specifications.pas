unit Specifications;

interface

uses
  System.SysUtils,
  System.DateUtils,
  DomainModels;

{
  Specifications.pas
  -------------------
  Implements the Specification pattern from DDD for composable, reusable
  query predicates. Specifications encapsulate business rules for filtering
  domain entities without leaking query logic into services or repositories.

  Composition: TAndSpec, TOrSpec, TNotSpec allow building complex predicates
  from simple building blocks. TTaskSpecs provides a fluent factory API.

  Example usage:
    var Spec := TTaskSpecs.ByUser(UserId).AndSpec(TTaskSpecs.ByStatus(tsPending));
    for LTask in Tasks do
      if Spec.IsSatisfiedBy(LTask) then ...

  SQL generation: Each specification implements ToSQLWhere for push-down
  to the database layer, enabling efficient queries without fetching all data.
}

type
  /// <summary>Base specification interface for Task entities.
  /// Supports both in-memory evaluation and SQL generation.</summary>
  ITaskSpecification = interface
    ['{B2C3D4E5-F6A7-8B9C-0D1E-F2A3B4C5D6E7}']
    /// <summary>Evaluates whether the given task satisfies this specification.</summary>
    function IsSatisfiedBy(ATask: TTask): Boolean;
    /// <summary>Returns SQL WHERE clause fragment for push-down to database.
    /// Returns empty string if not applicable.</summary>
    function ToSQLWhere: string;
    /// <summary>Compose this specification with another using AND logic.</summary>
    function AndSpec(const AOther: ITaskSpecification): ITaskSpecification;
    /// <summary>Compose this specification with another using OR logic.</summary>
    function OrSpec(const AOther: ITaskSpecification): ITaskSpecification;
    /// <summary>Negate this specification.</summary>
    function NotSpec: ITaskSpecification;
  end;

  /// <summary>Abstract base providing composition methods.</summary>
  TBaseTaskSpec = class(TInterfacedObject, ITaskSpecification)
  public
    function IsSatisfiedBy(ATask: TTask): Boolean; virtual; abstract;
    function ToSQLWhere: string; virtual; abstract;
    function AndSpec(const AOther: ITaskSpecification): ITaskSpecification;
    function OrSpec(const AOther: ITaskSpecification): ITaskSpecification;
    function NotSpec: ITaskSpecification;
  end;

  /// <summary>Filters tasks by status.</summary>
  TStatusSpecification = class(TBaseTaskSpec)
  private
    FStatus: TTaskStatus;
  public
    constructor Create(AStatus: TTaskStatus);
    function IsSatisfiedBy(ATask: TTask): Boolean; override;
    function ToSQLWhere: string; override;
  end;

  /// <summary>Filters tasks owned by a specific user.</summary>
  TUserSpecification = class(TBaseTaskSpec)
  private
    FUserId: Integer;
  public
    constructor Create(AUserId: Integer);
    function IsSatisfiedBy(ATask: TTask): Boolean; override;
    function ToSQLWhere: string; override;
  end;

  /// <summary>Filters completed tasks older than N days (for cleanup).</summary>
  TCompletedOlderThanSpecification = class(TBaseTaskSpec)
  private
    FDaysOld: Integer;
  public
    constructor Create(ADaysOld: Integer);
    function IsSatisfiedBy(ATask: TTask): Boolean; override;
    function ToSQLWhere: string; override;
  end;

  /// <summary>Composite AND specification: both operands must be satisfied.</summary>
  TAndSpecification = class(TBaseTaskSpec)
  private
    FLeft: ITaskSpecification;
    FRight: ITaskSpecification;
  public
    constructor Create(const ALeft, ARight: ITaskSpecification);
    function IsSatisfiedBy(ATask: TTask): Boolean; override;
    function ToSQLWhere: string; override;
  end;

  /// <summary>Composite OR specification: either operand must be satisfied.</summary>
  TOrSpecification = class(TBaseTaskSpec)
  private
    FLeft: ITaskSpecification;
    FRight: ITaskSpecification;
  public
    constructor Create(const ALeft, ARight: ITaskSpecification);
    function IsSatisfiedBy(ATask: TTask): Boolean; override;
    function ToSQLWhere: string; override;
  end;

  /// <summary>Negation specification: inverts the inner result.</summary>
  TNotSpecification = class(TBaseTaskSpec)
  private
    FInner: ITaskSpecification;
  public
    constructor Create(const AInner: ITaskSpecification);
    function IsSatisfiedBy(ATask: TTask): Boolean; override;
    function ToSQLWhere: string; override;
  end;

  /// <summary>Fluent factory for creating and composing task specifications.
  /// Provides a declarative API for building complex query predicates.</summary>
  TTaskSpecs = class
  public
    class function ByStatus(AStatus: TTaskStatus): ITaskSpecification;
    class function ByUser(AUserId: Integer): ITaskSpecification;
    class function CompletedOlderThan(ADays: Integer): ITaskSpecification;
    class function Combine(const ALeft, ARight: ITaskSpecification): ITaskSpecification;
    class function Either(const ALeft, ARight: ITaskSpecification): ITaskSpecification;
    class function Negate(const ASpec: ITaskSpecification): ITaskSpecification;
  end;

implementation

{ TBaseTaskSpec }

function TBaseTaskSpec.AndSpec(const AOther: ITaskSpecification): ITaskSpecification;
begin
  Result := TAndSpecification.Create(Self, AOther);
end;

function TBaseTaskSpec.OrSpec(const AOther: ITaskSpecification): ITaskSpecification;
begin
  Result := TOrSpecification.Create(Self, AOther);
end;

function TBaseTaskSpec.NotSpec: ITaskSpecification;
begin
  Result := TNotSpecification.Create(Self);
end;

{ TStatusSpecification }

constructor TStatusSpecification.Create(AStatus: TTaskStatus);
begin
  inherited Create;
  FStatus := AStatus;
end;

function TStatusSpecification.IsSatisfiedBy(ATask: TTask): Boolean;
begin
  Result := ATask.Status = FStatus;
end;

function TStatusSpecification.ToSQLWhere: string;
begin
  Result := Format('Status = ''%s''', [StatusToString(FStatus)]);
end;

{ TUserSpecification }

constructor TUserSpecification.Create(AUserId: Integer);
begin
  inherited Create;
  FUserId := AUserId;
end;

function TUserSpecification.IsSatisfiedBy(ATask: TTask): Boolean;
begin
  Result := ATask.UserId = FUserId;
end;

function TUserSpecification.ToSQLWhere: string;
begin
  Result := Format('UserId = %d', [FUserId]);
end;

{ TCompletedOlderThanSpecification }

constructor TCompletedOlderThanSpecification.Create(ADaysOld: Integer);
begin
  inherited Create;
  FDaysOld := ADaysOld;
end;

function TCompletedOlderThanSpecification.IsSatisfiedBy(ATask: TTask): Boolean;
begin
  Result := (ATask.Status = tsDone) and
            (ATask.UpdatedAt > 0) and
            (DaysBetween(Now, ATask.UpdatedAt) >= FDaysOld);
end;

function TCompletedOlderThanSpecification.ToSQLWhere: string;
begin
  Result := Format('Status = ''Done'' AND UpdatedAt < datetime(''now'', ''-%d days'')', [FDaysOld]);
end;

{ TAndSpecification }

constructor TAndSpecification.Create(const ALeft, ARight: ITaskSpecification);
begin
  inherited Create;
  FLeft := ALeft;
  FRight := ARight;
end;

function TAndSpecification.IsSatisfiedBy(ATask: TTask): Boolean;
begin
  Result := FLeft.IsSatisfiedBy(ATask) and FRight.IsSatisfiedBy(ATask);
end;

function TAndSpecification.ToSQLWhere: string;
var
  LLeft, LRight: string;
begin
  LLeft := FLeft.ToSQLWhere;
  LRight := FRight.ToSQLWhere;
  if (LLeft <> '') and (LRight <> '') then
    Result := Format('(%s) AND (%s)', [LLeft, LRight])
  else if LLeft <> '' then
    Result := LLeft
  else
    Result := LRight;
end;

{ TOrSpecification }

constructor TOrSpecification.Create(const ALeft, ARight: ITaskSpecification);
begin
  inherited Create;
  FLeft := ALeft;
  FRight := ARight;
end;

function TOrSpecification.IsSatisfiedBy(ATask: TTask): Boolean;
begin
  Result := FLeft.IsSatisfiedBy(ATask) or FRight.IsSatisfiedBy(ATask);
end;

function TOrSpecification.ToSQLWhere: string;
var
  LLeft, LRight: string;
begin
  LLeft := FLeft.ToSQLWhere;
  LRight := FRight.ToSQLWhere;
  if (LLeft <> '') and (LRight <> '') then
    Result := Format('(%s) OR (%s)', [LLeft, LRight])
  else if LLeft <> '' then
    Result := LLeft
  else
    Result := LRight;
end;

{ TNotSpecification }

constructor TNotSpecification.Create(const AInner: ITaskSpecification);
begin
  inherited Create;
  FInner := AInner;
end;

function TNotSpecification.IsSatisfiedBy(ATask: TTask): Boolean;
begin
  Result := not FInner.IsSatisfiedBy(ATask);
end;

function TNotSpecification.ToSQLWhere: string;
var
  LInner: string;
begin
  LInner := FInner.ToSQLWhere;
  if LInner <> '' then
    Result := Format('NOT (%s)', [LInner])
  else
    Result := '';
end;

{ TTaskSpecs }

class function TTaskSpecs.ByStatus(AStatus: TTaskStatus): ITaskSpecification;
begin
  Result := TStatusSpecification.Create(AStatus);
end;

class function TTaskSpecs.ByUser(AUserId: Integer): ITaskSpecification;
begin
  Result := TUserSpecification.Create(AUserId);
end;

class function TTaskSpecs.CompletedOlderThan(ADays: Integer): ITaskSpecification;
begin
  Result := TCompletedOlderThanSpecification.Create(ADays);
end;

class function TTaskSpecs.Combine(const ALeft, ARight: ITaskSpecification): ITaskSpecification;
begin
  Result := TAndSpecification.Create(ALeft, ARight);
end;

class function TTaskSpecs.Either(const ALeft, ARight: ITaskSpecification): ITaskSpecification;
begin
  Result := TOrSpecification.Create(ALeft, ARight);
end;

class function TTaskSpecs.Negate(const ASpec: ITaskSpecification): ITaskSpecification;
begin
  Result := TNotSpecification.Create(ASpec);
end;

end.
