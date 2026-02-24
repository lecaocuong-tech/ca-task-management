unit RateLimiter;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.SyncObjs,
  System.DateUtils,
  AppInterfaces;

{
  RateLimiter.pas
  ----------------
  Token-bucket rate limiter for protecting sensitive operations from abuse.
  Implements IRateLimiter interface (defined in AppInterfaces.pas).

  Design:
  - Per-key buckets (e.g. per-user, per-IP, per-action)
  - Configurable max tokens and refill rate
  - Thread-safe via TCriticalSection
  - Automatic token replenishment based on elapsed time
  - Lazy cleanup of expired buckets

  Usage:
    if not RateLimiter.TryConsume('login:admin') then
      raise exception 'Rate limit exceeded';

  Security benefits:
  - Prevents brute-force attacks on login
  - Limits API abuse for create/delete operations
  - Configurable per-operation thresholds
}

type
  /// <summary>Internal bucket tracking token count and last refill time.</summary>
  TTokenBucket = record
    Tokens: Double;
    LastRefillTime: TDateTime;
  end;

  /// <summary>Thread-safe token-bucket rate limiter.
  /// Tracks consumption per key and refills tokens over time.</summary>
  TTokenBucketRateLimiter = class(TInterfacedObject, IRateLimiter)
  private
    FBuckets: TDictionary<string, TTokenBucket>;
    FLock: TCriticalSection;
    FLogger: ILogger;
    FMaxTokens: Integer;
    FRefillPerSecond: Double;

    /// <summary>Refill tokens based on elapsed time since last check.</summary>
    procedure RefillBucket(var ABucket: TTokenBucket);
    /// <summary>Remove buckets that have been full and idle for > 10 minutes.</summary>
    procedure CleanupIdleBuckets;
  public
    /// <summary>Create a rate limiter with specified capacity and refill rate.
    /// AMaxTokens: maximum burst size. ARefillPerSecond: tokens added per second.</summary>
    constructor Create(ALogger: ILogger; AMaxTokens: Integer = 10;
      ARefillPerSecond: Double = 1.0);
    destructor Destroy; override;

    function TryConsume(const AKey: string; ATokens: Integer = 1): Boolean;
    function GetRemainingTokens(const AKey: string): Integer;
    procedure ResetKey(const AKey: string);
    procedure ResetAll;
  end;

implementation

{ TTokenBucketRateLimiter }

constructor TTokenBucketRateLimiter.Create(ALogger: ILogger; AMaxTokens: Integer;
  ARefillPerSecond: Double);
begin
  inherited Create;
  FBuckets := TDictionary<string, TTokenBucket>.Create;
  FLock := TCriticalSection.Create;
  FLogger := ALogger;
  FMaxTokens := AMaxTokens;
  FRefillPerSecond := ARefillPerSecond;
end;

destructor TTokenBucketRateLimiter.Destroy;
begin
  FBuckets.Free;
  FLock.Free;
  inherited;
end;

procedure TTokenBucketRateLimiter.RefillBucket(var ABucket: TTokenBucket);
var
  LElapsedSeconds: Double;
  LNewTokens: Double;
begin
  LElapsedSeconds := SecondSpan(Now, ABucket.LastRefillTime);
  if LElapsedSeconds > 0 then
  begin
    LNewTokens := LElapsedSeconds * FRefillPerSecond;
    ABucket.Tokens := ABucket.Tokens + LNewTokens;
    if ABucket.Tokens > FMaxTokens then
      ABucket.Tokens := FMaxTokens;
    ABucket.LastRefillTime := Now;
  end;
end;

procedure TTokenBucketRateLimiter.CleanupIdleBuckets;
var
  LKeysToRemove: TList<string>;
  LKey: string;
  LBucket: TTokenBucket;
begin
  // Must be called inside lock
  LKeysToRemove := TList<string>.Create;
  try
    for LKey in FBuckets.Keys do
    begin
      LBucket := FBuckets[LKey];
      // Remove buckets that are full and idle for > 10 minutes
      if (LBucket.Tokens >= FMaxTokens) and
         (MinutesBetween(Now, LBucket.LastRefillTime) > 10) then
        LKeysToRemove.Add(LKey);
    end;

    for LKey in LKeysToRemove do
      FBuckets.Remove(LKey);

    if LKeysToRemove.Count > 0 then
      FLogger.Debug(Format('RateLimiter: Cleaned up %d idle buckets', [LKeysToRemove.Count]));
  finally
    LKeysToRemove.Free;
  end;
end;

function TTokenBucketRateLimiter.TryConsume(const AKey: string; ATokens: Integer): Boolean;
var
  LBucket: TTokenBucket;
begin
  Result := False;

  FLock.Enter;
  try
    // Create bucket if not exists
    if not FBuckets.TryGetValue(AKey, LBucket) then
    begin
      LBucket.Tokens := FMaxTokens;
      LBucket.LastRefillTime := Now;
    end;

    // Refill based on elapsed time
    RefillBucket(LBucket);

    // Try to consume
    if LBucket.Tokens >= ATokens then
    begin
      LBucket.Tokens := LBucket.Tokens - ATokens;
      FBuckets.AddOrSetValue(AKey, LBucket);
      Result := True;
    end
    else
    begin
      FBuckets.AddOrSetValue(AKey, LBucket);
      FLogger.Warning(Format('RateLimiter: Rate limit exceeded for key "%s" (%.1f tokens remaining)',
        [AKey, LBucket.Tokens]));
    end;

    // Periodic cleanup
    if FBuckets.Count mod 50 = 0 then
      CleanupIdleBuckets;
  finally
    FLock.Leave;
  end;
end;

function TTokenBucketRateLimiter.GetRemainingTokens(const AKey: string): Integer;
var
  LBucket: TTokenBucket;
begin
  FLock.Enter;
  try
    if FBuckets.TryGetValue(AKey, LBucket) then
    begin
      RefillBucket(LBucket);
      FBuckets.AddOrSetValue(AKey, LBucket);
      Result := Trunc(LBucket.Tokens);
    end
    else
      Result := FMaxTokens;
  finally
    FLock.Leave;
  end;
end;

procedure TTokenBucketRateLimiter.ResetKey(const AKey: string);
begin
  FLock.Enter;
  try
    FBuckets.Remove(AKey);
  finally
    FLock.Leave;
  end;
end;

procedure TTokenBucketRateLimiter.ResetAll;
begin
  FLock.Enter;
  try
    FBuckets.Clear;
  finally
    FLock.Leave;
  end;
end;

end.
