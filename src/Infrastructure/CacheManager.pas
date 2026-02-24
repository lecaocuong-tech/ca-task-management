unit CacheManager;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.SyncObjs,
  AppInterfaces;

{
  CacheManager.pas
  -----------------
  In-memory cache implementation with TTL (Time-To-Live) support.
  ICacheProvider interface is declared in AppInterfaces.pas.

  Design decisions:
  - Thread-safe via TCriticalSection (suitable for VCL + background threads)
  - TTL-based expiration: entries auto-expire after configured seconds
  - Prefix-based invalidation for grouped cache entries (e.g. 'tasks:*')
  - Lazy eviction: expired entries are cleaned on access and periodically

  Usage pattern:
    Cache.SetValue('tasks:user:5', TaskList, True, 60);  // own object, 60s TTL
    if Cache.TryGetValue('tasks:user:5', LObj) then
      LTasks := TObjectList<TTask>(LObj);
}

type
  /// <summary>Internal cache entry with expiration metadata.</summary>
  TCacheEntry = record
    Value: TObject;
    ExpiresAt: TDateTime;
    OwnsObject: Boolean;
  end;

  /// <summary>Thread-safe in-memory cache with TTL expiration.
  /// Implements ICacheProvider for dependency injection.</summary>
  TMemoryCacheProvider = class(TInterfacedObject, ICacheProvider)
  private
    FEntries: TDictionary<string, TCacheEntry>;
    FLock: TCriticalSection;
    FLogger: ILogger;
    FDefaultTTLSeconds: Integer;

    /// <summary>Remove expired entries. Must be called inside lock.</summary>
    procedure EvictExpired;
    /// <summary>Free an owned cache entry's value.</summary>
    procedure FreeEntry(const AEntry: TCacheEntry);
  public
    constructor Create(ALogger: ILogger; ADefaultTTLSeconds: Integer = 300);
    destructor Destroy; override;

    function TryGetValue(const AKey: string; out AObj: TObject): Boolean;
    procedure SetValue(const AKey: string; AObj: TObject;
      AOwnsObject: Boolean = False; ATTLSeconds: Integer = 0);
    procedure Invalidate(const AKey: string);
    procedure InvalidateByPrefix(const APrefix: string);
    procedure Clear;
    function GetEntryCount: Integer;
  end;

implementation

uses
  System.DateUtils;

{ TMemoryCacheProvider }

constructor TMemoryCacheProvider.Create(ALogger: ILogger; ADefaultTTLSeconds: Integer = 300);
begin
  inherited Create;
  FEntries := TDictionary<string, TCacheEntry>.Create;
  FLock := TCriticalSection.Create;
  FLogger := ALogger;
  FDefaultTTLSeconds := ADefaultTTLSeconds;
end;

destructor TMemoryCacheProvider.Destroy;
begin
  Clear;
  FEntries.Free;
  FLock.Free;
  inherited;
end;

procedure TMemoryCacheProvider.FreeEntry(const AEntry: TCacheEntry);
begin
  if AEntry.OwnsObject and (AEntry.Value <> nil) then
    AEntry.Value.Free;
end;

procedure TMemoryCacheProvider.EvictExpired;
var
  LKeysToRemove: TList<string>;
  LKey: string;
  LEntry: TCacheEntry;
begin
  // Must be called inside lock
  LKeysToRemove := TList<string>.Create;
  try
    for LKey in FEntries.Keys do
    begin
      LEntry := FEntries[LKey];
      if Now > LEntry.ExpiresAt then
        LKeysToRemove.Add(LKey);
    end;

    for LKey in LKeysToRemove do
    begin
      LEntry := FEntries[LKey];
      FreeEntry(LEntry);
      FEntries.Remove(LKey);
    end;

    if LKeysToRemove.Count > 0 then
      FLogger.Debug(Format('Cache: Evicted %d expired entries', [LKeysToRemove.Count]));
  finally
    LKeysToRemove.Free;
  end;
end;

function TMemoryCacheProvider.TryGetValue(const AKey: string; out AObj: TObject): Boolean;
var
  LEntry: TCacheEntry;
begin
  Result := False;
  AObj := nil;

  FLock.Enter;
  try
    if FEntries.TryGetValue(AKey, LEntry) then
    begin
      if Now > LEntry.ExpiresAt then
      begin
        // Entry expired - remove it
        FreeEntry(LEntry);
        FEntries.Remove(AKey);
        FLogger.Debug('Cache miss (expired): ' + AKey);
      end
      else
      begin
        AObj := LEntry.Value;
        Result := True;
        FLogger.Debug('Cache hit: ' + AKey);
      end;
    end
    else
      FLogger.Debug('Cache miss: ' + AKey);
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryCacheProvider.SetValue(const AKey: string; AObj: TObject;
  AOwnsObject: Boolean = False; ATTLSeconds: Integer = 0);
var
  LEntry: TCacheEntry;
  LOldEntry: TCacheEntry;
  LTTL: Integer;
begin
  LTTL := ATTLSeconds;
  if LTTL <= 0 then
    LTTL := FDefaultTTLSeconds;

  LEntry.Value := AObj;
  LEntry.ExpiresAt := IncSecond(Now, LTTL);
  LEntry.OwnsObject := AOwnsObject;

  FLock.Enter;
  try
    // Free old entry if exists and owns object
    if FEntries.TryGetValue(AKey, LOldEntry) then
      FreeEntry(LOldEntry);

    FEntries.AddOrSetValue(AKey, LEntry);

    // Periodic eviction (every 20 writes)
    if FEntries.Count mod 20 = 0 then
      EvictExpired;

    FLogger.Debug(Format('Cache set: %s (TTL: %ds)', [AKey, LTTL]));
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryCacheProvider.Invalidate(const AKey: string);
var
  LEntry: TCacheEntry;
begin
  FLock.Enter;
  try
    if FEntries.TryGetValue(AKey, LEntry) then
    begin
      FreeEntry(LEntry);
      FEntries.Remove(AKey);
      FLogger.Debug('Cache invalidated: ' + AKey);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryCacheProvider.InvalidateByPrefix(const APrefix: string);
var
  LKeysToRemove: TList<string>;
  LKey: string;
  LEntry: TCacheEntry;
begin
  FLock.Enter;
  try
    LKeysToRemove := TList<string>.Create;
    try
      for LKey in FEntries.Keys do
      begin
        if LKey.StartsWith(APrefix) then
          LKeysToRemove.Add(LKey);
      end;

      for LKey in LKeysToRemove do
      begin
        LEntry := FEntries[LKey];
        FreeEntry(LEntry);
        FEntries.Remove(LKey);
      end;

      if LKeysToRemove.Count > 0 then
        FLogger.Debug(Format('Cache: Invalidated %d entries with prefix "%s"',
          [LKeysToRemove.Count, APrefix]));
    finally
      LKeysToRemove.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMemoryCacheProvider.Clear;
var
  LEntry: TCacheEntry;
begin
  FLock.Enter;
  try
    for LEntry in FEntries.Values do
      FreeEntry(LEntry);
    FEntries.Clear;
    FLogger.Debug('Cache cleared');
  finally
    FLock.Leave;
  end;
end;

function TMemoryCacheProvider.GetEntryCount: Integer;
begin
  FLock.Enter;
  try
    Result := FEntries.Count;
  finally
    FLock.Leave;
  end;
end;

end.
