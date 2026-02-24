unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Grids,
  Vcl.ComCtrls,
  AppInterfaces,
  DomainModels,
  DTOs,
  Result,
  System.Generics.Collections,
  System.Math,
  System.UITypes;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    pnlTaskList: TPanel;
    pnlBottom: TPanel;
    lblWelcome: TLabel;
    btnLogout: TButton;
    btnRefresh: TButton;
    sgTasks: TStringGrid;
    pnlTaskActions: TPanel;
    edtNewTask: TEdit;
    btnAddTask: TButton;
    cmbStatus: TComboBox;
    lblStatus: TLabel;
    btnDeleteTask: TButton;
    btnUpdateStatus: TButton;
    lblNewTask: TLabel;
    progressBar: TProgressBar;
    lblJobStatus: TLabel;
    btnStartAutoCleanup: TButton;
    btnStartLongJob: TButton;
    btnCancelJob: TButton;
    btnDeleteDoneJob: TButton;
    pnlUserManagement: TPanel;
    btnManageUsers: TButton;
    cmbFilterStatus: TComboBox;
    lblFilterStatus: TLabel;
    lblPageInfo: TLabel;
    btnPrevPage: TButton;
    btnNextPage: TButton;
    procedure FormShow(Sender: TObject);
    procedure btnLogoutClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnAddTaskClick(Sender: TObject);
    procedure btnDeleteTaskClick(Sender: TObject);
    procedure btnUpdateStatusClick(Sender: TObject);
    procedure sgTasksSelectCell(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
    procedure sgTasksDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure sgTasksClick(Sender: TObject);
    procedure btnStartAutoCleanupClick(Sender: TObject);
    procedure btnStartLongJobClick(Sender: TObject);
    procedure btnCancelJobClick(Sender: TObject);
    procedure btnDeleteDoneJobClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnManageUsersClick(Sender: TObject);
    procedure cmbFilterStatusChange(Sender: TObject);
    procedure btnPrevPageClick(Sender: TObject);
    procedure btnNextPageClick(Sender: TObject);
    procedure sgTasksDblClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FTaskService: ITaskService;
    FUserService: IUserService;
    FAuthService: IAuthenticationService;
    FJobManager: IJobManager;
    FJobFactory: IJobFactory;
    FLogger: ILogger;
    FServiceContainer: IServiceContainer;
    FCurrentJob: IBackgroundJob;
    FRefreshTimer: TTimer;
    FCurrentPage: Integer;
    FPageSize: Integer;
    FTotalTasks: Integer;

    // Use Case instances (owned by this form)
    FCreateTaskUC: TObject;  // TCreateTaskUseCase
    FChangeStatusUC: TObject;  // TChangeTaskStatusUseCase
    FUpdateTaskUC: TObject;  // TUpdateTaskUseCase
    FDeleteTaskUC: TObject;  // TDeleteTaskUseCase

    procedure LoadTasks;
    procedure RefreshUI;
    procedure UpdateJobProgress(Sender: TObject);
    procedure RefreshPageInfo;
    procedure InitializeUseCases;
  public
    property TaskService: ITaskService write FTaskService;
    property UserService: IUserService write FUserService;
    property AuthService: IAuthenticationService write FAuthService;
    property JobManager: IJobManager write FJobManager;
    property JobFactory: IJobFactory write FJobFactory;
    property Logger: ILogger write FLogger;
    property ServiceContainer: IServiceContainer write FServiceContainer;
  end;

var
  frmMain: TfrmMain;

implementation

uses
  UserManagementForm,
  TaskEditForm,
  UIConstants,
  CreateTaskUseCase,
  ManageUserUseCase;

{$R *.dfm}

procedure TfrmMain.InitializeUseCases;
var
  LEventDispatcher: IDomainEventDispatcher;
  LSanitizer: IInputSanitizer;
  LRateLimiter: IRateLimiter;
begin
  // Create Use Cases from ServiceContainer dependencies
  // UI -> UseCase -> Service -> Domain (Clean Architecture boundary)
  LEventDispatcher := FServiceContainer.GetEventDispatcher;
  LSanitizer := FServiceContainer.GetInputSanitizer;
  LRateLimiter := FServiceContainer.GetRateLimiter;

  FCreateTaskUC := TCreateTaskUseCase.Create(
    FTaskService, LEventDispatcher, LSanitizer, LRateLimiter, FLogger);
  FChangeStatusUC := TChangeTaskStatusUseCase.Create(
    FTaskService, LEventDispatcher, FLogger);
  FUpdateTaskUC := TUpdateTaskUseCase.Create(
    FTaskService, LEventDispatcher, LSanitizer, FLogger);
  FDeleteTaskUC := TDeleteTaskUseCase.Create(
    FTaskService, LEventDispatcher, FLogger);
end;

procedure TfrmMain.FormShow(Sender: TObject);
var
  LUsername: string;
begin
  LUsername := FAuthService.GetCurrentUsername;
  if LUsername <> '' then
    lblWelcome.Caption := 'Welcome, ' + LUsername;

  // Initialize Use Cases from service container
  InitializeUseCases;

  // Initialize pagination
  FCurrentPage := 1;
  FPageSize := 10;

  // Setup grid headers
  sgTasks.Cells[0, 0] := '';
  sgTasks.Cells[1, 0] := 'ID';
  sgTasks.Cells[2, 0] := 'Title';
  sgTasks.Cells[3, 0] := 'Status';
  sgTasks.Cells[4, 0] := 'Created At';
  sgTasks.Cells[5, 0] := 'Delete';
  sgTasks.Cells[6, 0] := 'Edit';

  // Setup filter combo
  cmbFilterStatus.Items.Clear;
  cmbFilterStatus.Items.Add('All');
  cmbFilterStatus.Items.Add('Pending');
  cmbFilterStatus.Items.Add('InProgress');
  cmbFilterStatus.Items.Add('Done');
  cmbFilterStatus.ItemIndex := 0;

  // Setup timer for job progress updates
  FRefreshTimer := TTimer.Create(Self);
  FRefreshTimer.OnTimer := UpdateJobProgress;
  FRefreshTimer.Interval := 500;
  FRefreshTimer.Enabled := True;

  LoadTasks;
  btnManageUsers.Enabled := FAuthService.IsCurrentUserAdmin;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  if FRefreshTimer <> nil then
    FRefreshTimer.Free;

  // Free Use Case instances
  FCreateTaskUC.Free;
  FChangeStatusUC.Free;
  FUpdateTaskUC.Free;
  FDeleteTaskUC.Free;

  FJobManager.CancelAllJobs;
  FJobManager.WaitForAllJobsCompletion(5000);
end;

procedure TfrmMain.LoadTasks;
var
  LCapturedFilter: string;
  LCapturedPage: Integer;
  LCapturedPageSize: Integer;
begin
  // Capture VCL state on main thread BEFORE spawning background thread
  if cmbFilterStatus.ItemIndex > 0 then
    LCapturedFilter := cmbFilterStatus.Text
  else
    LCapturedFilter := '';
  LCapturedPage := FCurrentPage;
  LCapturedPageSize := FPageSize;

  sgTasks.RowCount := 1; // show header only while loading

  if FRefreshTimer <> nil then
    FRefreshTimer.Enabled := False;

  TThread.CreateAnonymousThread(procedure
  var
    LIsAdmin: Boolean;
    LTasksLocal: TList<TTask>;
    LTotal: Integer;
  begin
    LIsAdmin := FAuthService.IsCurrentUserAdmin;

    // Use captured filter value (thread-safe, no VCL access)
    try
      if LIsAdmin then
      begin
        LTotal := FTaskService.GetAllTaskCount;
        if LCapturedFilter <> '' then
          LTasksLocal := FTaskService.GetAllTasksFiltered(LCapturedFilter)
        else
          LTasksLocal := FTaskService.GetAllTasksPaged(LCapturedPage, LCapturedPageSize);
      end
      else
      begin
        LTotal := FTaskService.GetMyTaskCount;
        if LCapturedFilter <> '' then
          LTasksLocal := FTaskService.GetMyTasksFiltered(LCapturedFilter)
        else
          LTasksLocal := FTaskService.GetMyTasksPaged(LCapturedPage, LCapturedPageSize);
      end;
    except
      on E: Exception do
      begin
        LTasksLocal := nil;
        LTotal := 0;
        FLogger.Error('LoadTasks background error: ' + E.Message, E);
      end;
    end;

    // Update UI in main thread
    TThread.Queue(nil, procedure
    var
      I: Integer;
    begin
      try
        FTotalTasks := LTotal;

        if LTasksLocal <> nil then
        begin
          sgTasks.RowCount := LTasksLocal.Count + 1;
          for I := 0 to LTasksLocal.Count - 1 do
          begin
            sgTasks.Cells[0, I + 1] := '';
            sgTasks.Cells[1, I + 1] := IntToStr(LTasksLocal[I].Id);
            sgTasks.Cells[2, I + 1] := LTasksLocal[I].Title;
            sgTasks.Cells[3, I + 1] := StatusToString(LTasksLocal[I].Status);
            sgTasks.Cells[4, I + 1] := FormatDateTime('yyyy-mm-dd hh:nn', LTasksLocal[I].CreatedAt);
            sgTasks.Cells[5, I + 1] := 'Delete';
            sgTasks.Cells[6, I + 1] := 'Edit';
          end;
        end
        else
        begin
          sgTasks.RowCount := 1;
        end;

        RefreshPageInfo;
        lblJobStatus.Caption := 'Tasks loaded';
        lblJobStatus.Font.Color := clGreen;
      finally
        // TObjectList<TTask> with OwnsObjects=True auto-frees items
        LTasksLocal.Free;

        if FRefreshTimer <> nil then
          FRefreshTimer.Enabled := True;
      end;
    end);
  end).Start;
end;

procedure TfrmMain.RefreshUI;
begin
  LoadTasks;
end;

procedure TfrmMain.UpdateJobProgress(Sender: TObject);
begin
  if FCurrentJob <> nil then
  begin
    progressBar.Position := FCurrentJob.GetProgress;

    case FCurrentJob.GetState of
      jsRunning:
        lblJobStatus.Caption := Format('Job running... %d%%', [FCurrentJob.GetProgress]);
      jsCompleted:
      begin
        lblJobStatus.Caption := 'Job completed';
        lblJobStatus.Font.Color := clGreen;
        FCurrentJob := nil;
        progressBar.Position := 0;
      end;
      jsCancelled:
      begin
        lblJobStatus.Caption := 'Job cancelled';
        lblJobStatus.Font.Color := clRed;
        FCurrentJob := nil;
        progressBar.Position := 0;
      end;
      jsFailed:
      begin
        lblJobStatus.Caption := 'Job failed: ' + FCurrentJob.GetErrorMessage;
        lblJobStatus.Font.Color := clRed;
        FCurrentJob := nil;
        progressBar.Position := 0;
      end;
    end;
  end;
end;

procedure TfrmMain.btnRefreshClick(Sender: TObject);
begin
  RefreshUI;
end;

procedure TfrmMain.btnAddTaskClick(Sender: TObject);
var
  LRequest: TCreateTaskRequest;
  LResponse: TUseCaseResponse<TTaskDTO>;
begin
  if edtNewTask.Text = '' then
  begin
    ShowMessage('Please enter a task title');
    edtNewTask.SetFocus;
    Exit;
  end;

  // Disable refresh timer to prevent database contention
  if FRefreshTimer <> nil then
    FRefreshTimer.Enabled := False;

  try
    // Route through Use Case (sanitization + validation + domain events)
    LRequest := TCreateTaskRequest.Create(edtNewTask.Text, '');
    LResponse := TCreateTaskUseCase(FCreateTaskUC).Execute(LRequest);
    
    if LResponse.IsSuccess then
    begin
      edtNewTask.Clear;
      LoadTasks;
      ShowMessage('Task created successfully');
    end
    else
    begin
      ShowMessage('Error creating task: ' + LResponse.ErrorMessage);
    end;
  finally
    // Re-enable refresh timer
    if FRefreshTimer <> nil then
      FRefreshTimer.Enabled := True;
  end;
end;

procedure TfrmMain.sgTasksSelectCell(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
begin
  if ARow > 0 then
    cmbStatus.Text := sgTasks.Cells[3, ARow];
end;

procedure TfrmMain.sgTasksDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
var
  LCheckRect: TRect;
  LGrid: TStringGrid;
begin
  LGrid := Sender as TStringGrid;

  if ACol = 0 then
  begin
    // Clear the cell background
    if gdFixed in State then
      LGrid.Canvas.Brush.Color := LGrid.FixedColor
    else
      LGrid.Canvas.Brush.Color := LGrid.Color;
    LGrid.Canvas.FillRect(Rect);

    // Draw checkbox centered in cell
    LCheckRect.Left := Rect.Left + (Rect.Right - Rect.Left - 14) div 2;
    LCheckRect.Top := Rect.Top + (Rect.Bottom - Rect.Top - 14) div 2;
    LCheckRect.Right := LCheckRect.Left + 14;
    LCheckRect.Bottom := LCheckRect.Top + 14;

    // Draw checkbox border
    LGrid.Canvas.Pen.Color := clGray;
    LGrid.Canvas.Brush.Color := clWhite;
    LGrid.Canvas.Rectangle(LCheckRect);

    // Draw checkmark if checked
    if LGrid.Cells[ACol, ARow] = CHECK_MARK then
    begin
      LGrid.Canvas.Pen.Color := clBlack;
      LGrid.Canvas.Pen.Width := 2;
      LGrid.Canvas.MoveTo(LCheckRect.Left + 2, LCheckRect.Top + 6);
      LGrid.Canvas.LineTo(LCheckRect.Left + 5, LCheckRect.Top + 10);
      LGrid.Canvas.LineTo(LCheckRect.Left + 11, LCheckRect.Top + 2);
      LGrid.Canvas.Pen.Width := 1;
    end;
  end
  else
  begin
    // Default drawing for other columns
    if gdFixed in State then
    begin
      LGrid.Canvas.Brush.Color := LGrid.FixedColor;
      LGrid.Canvas.Font.Style := [fsBold];
    end
    else
    begin
      LGrid.Canvas.Brush.Color := LGrid.Color;
      LGrid.Canvas.Font.Style := [];
    end;
    LGrid.Canvas.FillRect(Rect);
    LGrid.Canvas.TextRect(Rect, Rect.Left + 4, Rect.Top + 2, LGrid.Cells[ACol, ARow]);
  end;
end;

procedure TfrmMain.sgTasksClick(Sender: TObject);
var
  ACol, ARow: Integer;
  P: TPoint;
  I: Integer;
  LAllChecked: Boolean;
begin
  P := sgTasks.ScreenToClient(Mouse.CursorPos);
  sgTasks.MouseToCell(P.X, P.Y, ACol, ARow);

  if ACol <> 0 then
    Exit;

  if ARow = 0 then
  begin
    // Toggle select all
    LAllChecked := True;
    for I := 1 to sgTasks.RowCount - 1 do
    begin
      if sgTasks.Cells[0, I] <> CHECK_MARK then
      begin
        LAllChecked := False;
        Break;
      end;
    end;
    for I := 1 to sgTasks.RowCount - 1 do
    begin
      if LAllChecked then
        sgTasks.Cells[0, I] := ''
      else
        sgTasks.Cells[0, I] := CHECK_MARK;
    end;
  end
  else
  begin
    // Toggle individual checkbox
    if sgTasks.Cells[0, ARow] = CHECK_MARK then
      sgTasks.Cells[0, ARow] := ''
    else
      sgTasks.Cells[0, ARow] := CHECK_MARK;
  end;
end;

procedure TfrmMain.btnUpdateStatusClick(Sender: TObject);
var
  LTaskIds: TList<Integer>;
  LTaskId: Integer;
  LRequest: TChangeTaskStatusRequest;
  LResponse: TUseCaseResponse<TTaskDTO>;
  LStatus: TTaskStatus;
  I: Integer;
  LSuccessCount, LFailCount: Integer;
begin
  case cmbStatus.ItemIndex of
    0: LStatus := tsPending;
    1: LStatus := tsInProgress;
    2: LStatus := tsDone;
  else
    LStatus := tsPending;
  end;

  LTaskIds := TList<Integer>.Create;
  try
    // Collect checked task IDs
    for I := 1 to sgTasks.RowCount - 1 do
    begin
      if sgTasks.Cells[0, I] = CHECK_MARK then
      begin
        LTaskId := StrToIntDef(sgTasks.Cells[1, I], 0);
        if LTaskId > 0 then
          LTaskIds.Add(LTaskId);
      end;
    end;

    // If none checked, use selected row
    if LTaskIds.Count = 0 then
    begin
      if sgTasks.Row <= 0 then
      begin
        ShowMessage('Please select or check tasks to update');
        Exit;
      end;
      LTaskId := StrToIntDef(sgTasks.Cells[1, sgTasks.Row], 0);
      if LTaskId = 0 then
      begin
        ShowMessage('Invalid task');
        Exit;
      end;
      LTaskIds.Add(LTaskId);
    end;

    LSuccessCount := 0;
    LFailCount := 0;
    for I := 0 to LTaskIds.Count - 1 do
    begin
      // Route through Use Case (domain events + validation)
      LRequest := TChangeTaskStatusRequest.Create(LTaskIds[I], LStatus);
      LResponse := TChangeTaskStatusUseCase(FChangeStatusUC).Execute(LRequest);
      if LResponse.IsSuccess then
        Inc(LSuccessCount)
      else
        Inc(LFailCount);
    end;

    LoadTasks;
    if LFailCount > 0 then
      ShowMessage(Format('Updated %d task(s), %d failed', [LSuccessCount, LFailCount]))
    else
      ShowMessage(Format('Status updated for %d task(s)', [LSuccessCount]));
  finally
    LTaskIds.Free;
  end;
end;

procedure TfrmMain.btnDeleteTaskClick(Sender: TObject);
var
  LTaskIds: TList<Integer>;
  LTaskId: Integer;
  LResponse: TUseCaseResponse<Boolean>;
  I: Integer;
  LSuccessCount, LFailCount: Integer;
begin
  LTaskIds := TList<Integer>.Create;
  try
    // Collect checked task IDs
    for I := 1 to sgTasks.RowCount - 1 do
    begin
      if sgTasks.Cells[0, I] = CHECK_MARK then
      begin
        LTaskId := StrToIntDef(sgTasks.Cells[1, I], 0);
        if LTaskId > 0 then
          LTaskIds.Add(LTaskId);
      end;
    end;

    // If none checked, use selected row
    if LTaskIds.Count = 0 then
    begin
      if sgTasks.Row <= 0 then
      begin
        ShowMessage('Please select or check tasks to delete');
        Exit;
      end;
      LTaskId := StrToIntDef(sgTasks.Cells[1, sgTasks.Row], 0);
      if LTaskId = 0 then
      begin
        ShowMessage('Invalid task');
        Exit;
      end;
      LTaskIds.Add(LTaskId);
    end;

    if MessageDlg(Format('Delete %d task(s)?', [LTaskIds.Count]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    if FRefreshTimer <> nil then
      FRefreshTimer.Enabled := False;

    try
      LSuccessCount := 0;
      LFailCount := 0;
      for I := 0 to LTaskIds.Count - 1 do
      begin
        // Route through Use Case (domain events)
        LResponse := TDeleteTaskUseCase(FDeleteTaskUC).Execute(LTaskIds[I]);
        if LResponse.IsSuccess then
          Inc(LSuccessCount)
        else
          Inc(LFailCount);
      end;

      LoadTasks;
      if LFailCount > 0 then
        ShowMessage(Format('Deleted %d task(s), %d failed', [LSuccessCount, LFailCount]))
      else
        ShowMessage(Format('Deleted %d task(s)', [LSuccessCount]));
    finally
      if FRefreshTimer <> nil then
        FRefreshTimer.Enabled := True;
    end;
  finally
    LTaskIds.Free;
  end;
end;

procedure TfrmMain.btnStartAutoCleanupClick(Sender: TObject);
begin
  if FCurrentJob <> nil then
  begin
    ShowMessage('A job is already running');
    Exit;
  end;

  // Run cleanup in background thread via TaskService (respects permissions)
  lblJobStatus.Caption := 'Auto cleanup job started';
  lblJobStatus.Font.Color := clBlue;
  TThread.CreateAnonymousThread(procedure
  var
    LDeleted: Integer;
  begin
    try
      LDeleted := FTaskService.CleanupCompletedTasks(30);
      TThread.Queue(nil, procedure
      begin
        lblJobStatus.Caption := Format('Cleanup completed: %d tasks removed', [LDeleted]);
        lblJobStatus.Font.Color := clGreen;
        LoadTasks;
      end);
    except
      on E: Exception do
        TThread.Queue(nil, procedure
        begin
          lblJobStatus.Caption := 'Cleanup failed: ' + E.Message;
          lblJobStatus.Font.Color := clRed;
        end);
    end;
  end).Start;
end;

procedure TfrmMain.btnStartLongJobClick(Sender: TObject);
begin
  if FCurrentJob <> nil then
  begin
    ShowMessage('A job is already running');
    Exit;
  end;

  FCurrentJob := FJobFactory.CreateLongRunningJob(5); // 5 seconds
  FJobManager.SubmitJob(FCurrentJob);
  lblJobStatus.Caption := 'Long running job started';
  lblJobStatus.Font.Color := clBlue;
end;

procedure TfrmMain.btnDeleteDoneJobClick(Sender: TObject);
begin
  if FCurrentJob <> nil then
  begin
    ShowMessage('A job is already running');
    Exit;
  end;

  FCurrentJob := FJobFactory.CreateDeleteDoneJob(procedure
  begin
    // Called on main thread after each task is deleted - refresh UI
    LoadTasks;
  end);
  FJobManager.SubmitJob(FCurrentJob);
  lblJobStatus.Caption := 'Delete Done Tasks job started';
  lblJobStatus.Font.Color := clBlue;
end;

procedure TfrmMain.btnCancelJobClick(Sender: TObject);
begin
  if FCurrentJob = nil then
  begin
    ShowMessage('No job running');
    Exit;
  end;

  FCurrentJob.Cancel;
  lblJobStatus.Caption := 'Cancel request sent...';
  lblJobStatus.Font.Color := clOlive;
end;

procedure TfrmMain.btnLogoutClick(Sender: TObject);
begin
  if MessageDlg('Are you sure you want to logout?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FJobManager.CancelAllJobs;
    FAuthService.Logout;
    ModalResult := mrRetry; // mrRetry = go back to login; distinct from mrCancel (X click = exit)
  end;
end;

procedure TfrmMain.btnManageUsersClick(Sender: TObject);
var
  LFormUserMgmt: TfrmUserManagement;
begin
  LFormUserMgmt := TfrmUserManagement.Create(nil);
  try
    LFormUserMgmt.UserService := FUserService;
    LFormUserMgmt.Logger := FLogger;
    LFormUserMgmt.ShowModal;
  finally
    LFormUserMgmt.Free;
  end;
end;

procedure TfrmMain.cmbFilterStatusChange(Sender: TObject);
begin
  FCurrentPage := 1;
  LoadTasks;
end;

procedure TfrmMain.btnPrevPageClick(Sender: TObject);
begin
  if FCurrentPage > 1 then
  begin
    Dec(FCurrentPage);
    LoadTasks;
  end;
end;

procedure TfrmMain.btnNextPageClick(Sender: TObject);
begin
  if FCurrentPage * FPageSize < FTotalTasks then
  begin
    Inc(FCurrentPage);
    LoadTasks;
  end;
end;

procedure TfrmMain.RefreshPageInfo;
var
  LStartRow: Integer;
  LEndRow: Integer;
begin
  LStartRow := (FCurrentPage - 1) * FPageSize + 1;
  LEndRow := Min(FCurrentPage * FPageSize, FTotalTasks);
  
  if FTotalTasks > 0 then
    lblPageInfo.Caption := Format('Page %d - Tasks %d to %d of %d',
      [FCurrentPage, LStartRow, LEndRow, FTotalTasks])
  else
    lblPageInfo.Caption := 'No tasks found';
  
  btnPrevPage.Enabled := FCurrentPage > 1;
  btnNextPage.Enabled := FCurrentPage * FPageSize < FTotalTasks;
end;

procedure TfrmMain.sgTasksDblClick(Sender: TObject);
var
  ACol: Integer;
  ARow: Integer;
begin
  if sgTasks.Row = 0 then
    Exit; // Don't process clicks on header row
  
  ACol := sgTasks.Col;
  ARow := sgTasks.Row;
  
  // Check if click is on Delete column (column 5)
  if ACol = 5 then
  begin
    var LDelTaskId := StrToIntDef(sgTasks.Cells[1, ARow], 0);
    if LDelTaskId > 0 then
    begin
      if MessageDlg('Delete this task?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        // Route through Use Case (domain events)
        var LDelResponse := TDeleteTaskUseCase(FDeleteTaskUC).Execute(LDelTaskId);
        if LDelResponse.IsSuccess then
          LoadTasks
        else
          ShowMessage('Error: ' + LDelResponse.ErrorMessage);
      end;
    end;
  end
  // Check if click is on Edit column (column 6)
  else if ACol = 6 then
  begin
    // Show edit modal for task - go through TaskService for permission checks
    var LTaskId := StrToIntDef(sgTasks.Cells[1, ARow], 0);
    var LTask := FTaskService.GetTaskById(LTaskId);
    if Assigned(LTask) then
    begin
      var LEditForm := TfrmTaskEdit.Create(nil);
      try
        if LEditForm.ExecuteEdit(LTask) then
        begin
          // Route through Use Case (sanitization + domain events)
          var LUpdateReq := TUpdateTaskRequest.Create(
            LTask.Id, LTask.Title, LTask.Description);
          var LUpdateResponse := TUpdateTaskUseCase(FUpdateTaskUC).Execute(LUpdateReq);
          if LUpdateResponse.IsSuccess then
            LoadTasks
          else
            ShowMessage('Error updating task: ' + LUpdateResponse.ErrorMessage);
        end;
      finally
        LEditForm.Free;
        LTask.Free;
      end;
    end;
  end;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Clicking X: just do cleanup. VCL will set ModalResult := mrCancel automatically
  // for modal forms, which the main loop treats as "exit app".
  CanClose := True;
  FJobManager.CancelAllJobs;
  FAuthService.Logout;
end;

end.
