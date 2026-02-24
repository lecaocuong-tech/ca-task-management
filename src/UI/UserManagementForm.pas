unit UserManagementForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Grids,
  System.Generics.Collections,
  System.Math,
  System.UITypes,
  AppInterfaces,
  DomainModels,
  Result;

type
  TfrmUserManagement = class(TForm)
    pnlTop: TPanel;
    lblTitle: TLabel;
    pnlContent: TPanel;
    sgUsers: TStringGrid;
    pnlActions: TPanel;
    btnAdd: TButton;
    btnEdit: TButton;
    btnDelete: TButton;
    btnClose: TButton;
    lblPageInfo: TLabel;
    btnPrevPage: TButton;
    btnNextPage: TButton;
    procedure FormShow(Sender: TObject);
    procedure btnAddClick(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure sgUsersSelectCell(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
    procedure sgUsersDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure sgUsersClick(Sender: TObject);
    procedure btnPrevPageClick(Sender: TObject);
    procedure btnNextPageClick(Sender: TObject);
    procedure sgUsersDblClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FUserService: IUserService;
    FLogger: ILogger;
    FPageSize: Integer;
    FCurrentPage: Integer;
    FTotalUsers: Integer;
    procedure SetUserService(AService: IUserService);
    procedure SetLogger(ALogger: ILogger);
    procedure LoadUsersPage;
    procedure RefreshPageInfo;
    procedure SetupGrid;
  public
    property UserService: IUserService write SetUserService;
    property Logger: ILogger write SetLogger;
  end;

var
  frmUserManagement: TfrmUserManagement;

implementation

uses
  UserEditForm,
  UIConstants;

{$R *.dfm}

procedure TfrmUserManagement.SetUserService(AService: IUserService);
begin
  FUserService := AService;
end;

procedure TfrmUserManagement.SetLogger(ALogger: ILogger);
begin
  FLogger := ALogger;
end;

procedure TfrmUserManagement.FormShow(Sender: TObject);
begin
  FPageSize := 10;
  FCurrentPage := 1;
  FTotalUsers := FUserService.GetUserCount;
  
  SetupGrid;
  LoadUsersPage;
end;

procedure TfrmUserManagement.SetupGrid;
begin
  sgUsers.ColCount := 7;
  sgUsers.RowCount := 2;
  sgUsers.FixedRows := 1;
  sgUsers.Cells[0, 0] := '';
  sgUsers.Cells[1, 0] := 'ID';
  sgUsers.Cells[2, 0] := 'Username';
  sgUsers.Cells[3, 0] := 'Role';
  sgUsers.Cells[4, 0] := 'Created At';
  sgUsers.Cells[5, 0] := 'Delete';
  sgUsers.Cells[6, 0] := 'Edit';
  
  sgUsers.ColWidths[0] := 40;
  sgUsers.ColWidths[1] := 40;
  sgUsers.ColWidths[2] := 150;
  sgUsers.ColWidths[3] := 80;
  sgUsers.ColWidths[4] := 150;
  sgUsers.ColWidths[5] := 80;
  sgUsers.ColWidths[6] := 80;
end;

procedure TfrmUserManagement.LoadUsersPage;
var
  LUsers: TList<TUser>;
  I: Integer;
begin
  FTotalUsers := FUserService.GetUserCount;
  LUsers := FUserService.GetAllUsersPaged(FCurrentPage, FPageSize);
  
  sgUsers.RowCount := 1;
  
  if LUsers = nil then
    Exit;

  try
    if LUsers.Count = 0 then
    begin
      lblPageInfo.Caption := 'No users found';
      Exit;
    end;

    sgUsers.RowCount := LUsers.Count + 1;
    for I := 0 to LUsers.Count - 1 do
    begin
      sgUsers.Cells[0, I + 1] := '';
      sgUsers.Cells[1, I + 1] := IntToStr(LUsers[I].Id);
      sgUsers.Cells[2, I + 1] := LUsers[I].Username;
      sgUsers.Cells[3, I + 1] := LUsers[I].RoleToString;
      sgUsers.Cells[4, I + 1] := FormatDateTime('yyyy-mm-dd hh:nn', LUsers[I].CreatedAt);
      sgUsers.Cells[5, I + 1] := 'Delete';
      sgUsers.Cells[6, I + 1] := 'Edit';
    end;
    
    RefreshPageInfo;
  finally
    // TObjectList<TUser> with OwnsObjects=True auto-frees items
    LUsers.Free;
  end;
end;

procedure TfrmUserManagement.RefreshPageInfo;
var
  LStartRow: Integer;
  LEndRow: Integer;
begin
  LStartRow := (FCurrentPage - 1) * FPageSize + 1;
  LEndRow := Min(FCurrentPage * FPageSize, FTotalUsers);
  
  lblPageInfo.Caption := Format('Page %d - Users %d to %d of %d',
    [FCurrentPage, LStartRow, LEndRow, FTotalUsers]);
  
  btnPrevPage.Enabled := FCurrentPage > 1;
  btnNextPage.Enabled := FCurrentPage * FPageSize < FTotalUsers;
end;

procedure TfrmUserManagement.btnAddClick(Sender: TObject);
var
  LFormEdit: TfrmUserEdit;
begin
  LFormEdit := TfrmUserEdit.Create(nil);
  try
    LFormEdit.UserService := FUserService;
    LFormEdit.Logger := FLogger;
    LFormEdit.IsNewUser := True;
    LFormEdit.ShowModal;
    LoadUsersPage;
  finally
    LFormEdit.Free;
  end;
end;

procedure TfrmUserManagement.btnEditClick(Sender: TObject);
var
  LFormEdit: TfrmUserEdit;
  LUserId: Integer;
  LUser: TUser;
begin
  if sgUsers.Row <= 0 then
  begin
    ShowMessage('Please select a user');
    Exit;
  end;

  LUserId := StrToIntDef(sgUsers.Cells[1, sgUsers.Row], 0);
  if LUserId = 0 then
  begin
    ShowMessage('Invalid user');
    Exit;
  end;

  LUser := FUserService.GetUserById(LUserId);
  if LUser = nil then
  begin
    ShowMessage('User not found');
    Exit;
  end;

  LFormEdit := TfrmUserEdit.Create(nil);
  try
    LFormEdit.UserService := FUserService;
    LFormEdit.Logger := FLogger;
    LFormEdit.IsNewUser := False;
    LFormEdit.User := LUser;
    LFormEdit.ShowModal;
    LoadUsersPage;
  finally
    LFormEdit.Free;
    LUser.Free;
  end;
end;

procedure TfrmUserManagement.btnDeleteClick(Sender: TObject);
var
  LUserIds: TList<Integer>;
  LUserId: Integer;
  LResult: TResult;
  I: Integer;
  LSuccessCount, LFailCount: Integer;
begin
  LUserIds := TList<Integer>.Create;
  try
    // Collect checked user IDs
    for I := 1 to sgUsers.RowCount - 1 do
    begin
      if sgUsers.Cells[0, I] = CHECK_MARK then
      begin
        LUserId := StrToIntDef(sgUsers.Cells[1, I], 0);
        if LUserId > 0 then
          LUserIds.Add(LUserId);
      end;
    end;

    // If none checked, use selected row
    if LUserIds.Count = 0 then
    begin
      if sgUsers.Row <= 0 then
      begin
        ShowMessage('Please select or check users to delete');
        Exit;
      end;
      LUserId := StrToIntDef(sgUsers.Cells[1, sgUsers.Row], 0);
      if LUserId = 0 then
      begin
        ShowMessage('Invalid user');
        Exit;
      end;
      LUserIds.Add(LUserId);
    end;

    if MessageDlg(Format('Delete %d user(s)?', [LUserIds.Count]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;

    LSuccessCount := 0;
    LFailCount := 0;
    for I := 0 to LUserIds.Count - 1 do
    begin
      LResult := FUserService.DeleteUser(LUserIds[I]);
      if LResult.IsSuccess then
        Inc(LSuccessCount)
      else
        Inc(LFailCount);
    end;

    LoadUsersPage;
    if LFailCount > 0 then
      ShowMessage(Format('Deleted %d user(s), %d failed', [LSuccessCount, LFailCount]))
    else
      ShowMessage(Format('Deleted %d user(s)', [LSuccessCount]));
  finally
    LUserIds.Free;
  end;
end;

procedure TfrmUserManagement.btnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmUserManagement.sgUsersSelectCell(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
begin
  // User selected a cell - enable edit and delete buttons
  btnEdit.Enabled := ARow > 0;
  btnDelete.Enabled := ARow > 0;
end;

procedure TfrmUserManagement.sgUsersDrawCell(Sender: TObject; ACol, ARow: Integer;
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

procedure TfrmUserManagement.btnPrevPageClick(Sender: TObject);
begin
  if FCurrentPage > 1 then
  begin
    Dec(FCurrentPage);
    LoadUsersPage;
  end;
end;

procedure TfrmUserManagement.btnNextPageClick(Sender: TObject);
begin
  if FCurrentPage * FPageSize < FTotalUsers then
  begin
    Inc(FCurrentPage);
    LoadUsersPage;
  end;
end;

procedure TfrmUserManagement.sgUsersClick(Sender: TObject);
var
  ACol, ARow: Integer;
  P: TPoint;
  I: Integer;
  LAllChecked: Boolean;
begin
  P := sgUsers.ScreenToClient(Mouse.CursorPos);
  sgUsers.MouseToCell(P.X, P.Y, ACol, ARow);

  if ACol <> 0 then
    Exit;

  if ARow = 0 then
  begin
    // Toggle select all
    LAllChecked := True;
    for I := 1 to sgUsers.RowCount - 1 do
    begin
      if sgUsers.Cells[0, I] <> CHECK_MARK then
      begin
        LAllChecked := False;
        Break;
      end;
    end;
    for I := 1 to sgUsers.RowCount - 1 do
    begin
      if LAllChecked then
        sgUsers.Cells[0, I] := ''
      else
        sgUsers.Cells[0, I] := CHECK_MARK;
    end;
  end
  else
  begin
    // Toggle individual checkbox
    if sgUsers.Cells[0, ARow] = CHECK_MARK then
      sgUsers.Cells[0, ARow] := ''
    else
      sgUsers.Cells[0, ARow] := CHECK_MARK;
  end;
end;

procedure TfrmUserManagement.sgUsersDblClick(Sender: TObject);
var
  ACol: Integer;
  ARow: Integer;
begin
  if sgUsers.Row = 0 then
    Exit; // Don't process clicks on header row
  
  ACol := sgUsers.Col;
  ARow := sgUsers.Row;
  
  // Check if click is on Delete column (column 5)
  if ACol = 5 then
  begin
    var LUserId := StrToIntDef(sgUsers.Cells[1, ARow], 0);
    if LUserId > 0 then
    begin
      if MessageDlg('Delete this user?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        var LDelResult := FUserService.DeleteUser(LUserId);
        if LDelResult.IsSuccess then
          LoadUsersPage
        else
          ShowMessage('Error: ' + LDelResult.GetErrorMessage);
      end;
    end;
  end
  // Check if click is on Edit column (column 6)
  else if ACol = 6 then
  begin
    btnEditClick(nil);
  end;
end;

procedure TfrmUserManagement.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Modal form: closing via X should just dismiss with mrCancel
  CanClose := True;
  ModalResult := mrCancel;
end;

end.
