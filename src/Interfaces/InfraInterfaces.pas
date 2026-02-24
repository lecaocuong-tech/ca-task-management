unit InfraInterfaces;

interface

{
  InfraInterfaces.pas
  --------------------
  Infrastructure-level interface declarations. Separated from AppInterfaces.pas
  because IDatabaseManager depends on FireDAC types (TFDQuery), which would
  violate AppInterfaces' policy of no infrastructure dependencies.

  Only infrastructure implementations (repositories, DatabaseManager) should
  depend on this unit. Services and UI should not reference it.
}

uses
  FireDAC.Comp.Client;

type
  /// <summary>Database connection and transaction management abstraction.
  /// Owns a shared FireDAC connection; provides query creation and
  /// paired lock/transaction helpers for thread-safe data access.</summary>
  IDatabaseManager = interface
    ['{6C0D7E5F-3A4B-5C3D-0E5F-1A2B3C4D5E6F}']
    /// <summary>Create a TFDQuery using the shared connection. Caller owns the returned query.</summary>
    function CreateQuery: TFDQuery;
    /// <summary>Begin a transaction and acquire the internal lock.
    /// Must be followed by Commit or Rollback (which release the lock).</summary>
    procedure BeginTransaction;
    /// <summary>Commit the active transaction and release the lock.</summary>
    procedure Commit;
    /// <summary>Rollback the active transaction and release the lock.</summary>
    procedure Rollback;
    /// <summary>Acquire a lightweight lock for read scopes that must not
    /// overlap with an active transaction. Must be paired with ReleaseLock.</summary>
    procedure AcquireLock;
    /// <summary>Release the lightweight read lock.</summary>
    procedure ReleaseLock;
  end;

implementation

end.
