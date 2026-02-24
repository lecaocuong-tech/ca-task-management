unit DomainEventDispatcher;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.SyncObjs,
  AppInterfaces,
  DomainModels;

{
  DomainEventDispatcher.pas
  --------------------------
  Concrete implementation of IDomainEventDispatcher. Routes domain events
  to registered handlers using an in-process publish/subscribe pattern.

  Thread-safety: Handler registration and dispatch are protected by
  TCriticalSection for safe use from background threads.

  Usage:
  1. Register handlers at composition time (ServiceContainer)
  2. After domain operations, call Dispatch or DispatchAll
  3. Handlers react to events (logging, cache invalidation, notifications, etc.)

  This enables loose coupling between domain operations and cross-cutting
  reactions without the domain layer knowing about handlers.
}

type
  /// <summary>In-process domain event dispatcher.
  /// Maintains a list of handlers and routes events to matching handlers.</summary>
  TDomainEventDispatcher = class(TInterfacedObject, IDomainEventDispatcher)
  private
    FHandlers: TList<IDomainEventHandler>;
    FLock: TCriticalSection;
    FLogger: ILogger;
  public
    constructor Create(ALogger: ILogger);
    destructor Destroy; override;

    procedure Dispatch(const AEvent: IDomainEvent);
    procedure DispatchAll(const AEvents: TList<IDomainEvent>);
    procedure RegisterHandler(const AHandler: IDomainEventHandler);
    procedure UnregisterHandler(const AHandler: IDomainEventHandler);
  end;

  /// <summary>Built-in handler that logs all domain events.
  /// Provides audit trail of domain state changes.</summary>
  TLoggingEventHandler = class(TInterfacedObject, IDomainEventHandler)
  private
    FLogger: ILogger;
  public
    constructor Create(ALogger: ILogger);
    procedure Handle(const AEvent: IDomainEvent);
    function CanHandle(const AEvent: IDomainEvent): Boolean;
  end;

  /// <summary>Handler that invalidates cache entries when domain state changes.
  /// Ensures cache consistency after mutations.</summary>
  TCacheInvalidationHandler = class(TInterfacedObject, IDomainEventHandler)
  private
    FCacheProvider: ICacheProvider;
    FLogger: ILogger;
  public
    constructor Create(ACacheProvider: ICacheProvider; ALogger: ILogger);
    procedure Handle(const AEvent: IDomainEvent);
    function CanHandle(const AEvent: IDomainEvent): Boolean;
  end;

implementation

{ TDomainEventDispatcher }

constructor TDomainEventDispatcher.Create(ALogger: ILogger);
begin
  inherited Create;
  FHandlers := TList<IDomainEventHandler>.Create;
  FLock := TCriticalSection.Create;
  FLogger := ALogger;
end;

destructor TDomainEventDispatcher.Destroy;
begin
  FHandlers.Free;
  FLock.Free;
  inherited;
end;

procedure TDomainEventDispatcher.Dispatch(const AEvent: IDomainEvent);
var
  LHandler: IDomainEventHandler;
  LHandlersCopy: TArray<IDomainEventHandler>;
  I: Integer;
begin
  if AEvent = nil then
    Exit;

  // Copy handler list under lock, then dispatch outside lock
  // to avoid holding the lock during handler execution
  FLock.Enter;
  try
    SetLength(LHandlersCopy, FHandlers.Count);
    for I := 0 to FHandlers.Count - 1 do
      LHandlersCopy[I] := FHandlers[I];
  finally
    FLock.Leave;
  end;

  for LHandler in LHandlersCopy do
  begin
    try
      if LHandler.CanHandle(AEvent) then
        LHandler.Handle(AEvent);
    except
      on E: Exception do
        FLogger.Error(Format('Event handler failed for "%s": %s',
          [AEvent.EventName, E.Message]), E);
    end;
  end;
end;

procedure TDomainEventDispatcher.DispatchAll(const AEvents: TList<IDomainEvent>);
var
  LEvent: IDomainEvent;
begin
  if AEvents = nil then
    Exit;

  for LEvent in AEvents do
    Dispatch(LEvent);
end;

procedure TDomainEventDispatcher.RegisterHandler(const AHandler: IDomainEventHandler);
begin
  FLock.Enter;
  try
    if not FHandlers.Contains(AHandler) then
    begin
      FHandlers.Add(AHandler);
      FLogger.Info(Format('Event dispatcher: Handler registered (total: %d)', [FHandlers.Count]));
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDomainEventDispatcher.UnregisterHandler(const AHandler: IDomainEventHandler);
begin
  FLock.Enter;
  try
    FHandlers.Remove(AHandler);
  finally
    FLock.Leave;
  end;
end;

{ TLoggingEventHandler }

constructor TLoggingEventHandler.Create(ALogger: ILogger);
begin
  inherited Create;
  FLogger := ALogger;
end;

function TLoggingEventHandler.CanHandle(const AEvent: IDomainEvent): Boolean;
begin
  Result := True; // Logs all events
end;

procedure TLoggingEventHandler.Handle(const AEvent: IDomainEvent);
begin
  FLogger.Info(Format('DomainEvent [%s] EntityId=%d at %s',
    [AEvent.EventName, AEvent.EntityId,
     FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', AEvent.OccurredAt)]));
end;

{ TCacheInvalidationHandler }

constructor TCacheInvalidationHandler.Create(ACacheProvider: ICacheProvider; ALogger: ILogger);
begin
  inherited Create;
  FCacheProvider := ACacheProvider;
  FLogger := ALogger;
end;

function TCacheInvalidationHandler.CanHandle(const AEvent: IDomainEvent): Boolean;
begin
  // Handle task and user mutation events
  Result := AEvent.EventName.StartsWith('Task') or AEvent.EventName.StartsWith('User');
end;

procedure TCacheInvalidationHandler.Handle(const AEvent: IDomainEvent);
begin
  if AEvent.EventName.StartsWith('Task') then
  begin
    FCacheProvider.InvalidateByPrefix('tasks:');
    FLogger.Debug('Cache invalidated for tasks due to event: ' + AEvent.EventName);
  end
  else if AEvent.EventName.StartsWith('User') then
  begin
    FCacheProvider.InvalidateByPrefix('users:');
    FLogger.Debug('Cache invalidated for users due to event: ' + AEvent.EventName);
  end;
end;

end.
