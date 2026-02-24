unit JobFactory;

interface

uses
  System.SysUtils,
  AppInterfaces,
  BackgroundJob,
  LongRunningJob,
  DeleteDoneJob;

{
  JobFactory.pas
  ---------------
  IJobFactory interface is declared in AppInterfaces.pas (Dependency Inversion).
  This unit contains the concrete factory that creates background job instances.
  UI layer uses IJobFactory to create jobs without importing concrete job types.
}

type
  TJobFactory = class(TInterfacedObject, IJobFactory)
  private
    FTaskService: ITaskService;
    FLogger: ILogger;
  public
    constructor Create(ATaskService: ITaskService; ALogger: ILogger);

    function CreateLongRunningJob(ADurationSeconds: Integer): IBackgroundJob;
    function CreateDeleteDoneJob(AOnTaskDeleted: TProc): IBackgroundJob;
  end;

implementation

{ TJobFactory }

constructor TJobFactory.Create(ATaskService: ITaskService; ALogger: ILogger);
begin
  inherited Create;
  FTaskService := ATaskService;
  FLogger := ALogger;
end;

function TJobFactory.CreateLongRunningJob(ADurationSeconds: Integer): IBackgroundJob;
begin
  Result := TLongRunningJob.Create(ADurationSeconds, FLogger);
end;

function TJobFactory.CreateDeleteDoneJob(AOnTaskDeleted: TProc): IBackgroundJob;
var
  LJob: TDeleteDoneJob;
begin
  LJob := TDeleteDoneJob.Create(FTaskService, FLogger);
  LJob.OnTaskDeleted := AOnTaskDeleted;
  Result := LJob;
end;

end.
