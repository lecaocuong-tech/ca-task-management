unit UserEditForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  AppInterfaces,
  DomainModels,
  Result;

type
  TfrmUserEdit = class(TForm)
    pnlMain: TPanel;
    lblTitle: TLabel;
    lblUsername: TLabel;
    edtUsername: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblConfirmPassword: TLabel;
    edtConfirmPassword: TEdit;
    lblRole: TLabel;
    cmbRole: TComboBox;
    btnSave: TButton;
    btnCancel: TButton;
    lblStatus: TLabel;
    lblPasswordNote: TLabel;
    procedure btnSaveClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FUserService: IUserService;
    FLogger: ILogger;
    FUser: TUser;
    FIsNewUser: Boolean;
    procedure SetUserService(AService: IUserService);
    procedure SetLogger(ALogger: ILogger);
    procedure SetUser(AUser: TUser);
    procedure SetIsNewUser(AIsNew: Boolean);
  public
    property UserService: IUserService write SetUserService;
    property Logger: ILogger write SetLogger;
    property User: TUser read FUser write SetUser;
    property IsNewUser: Boolean read FIsNewUser write SetIsNewUser;
  end;

var
  frmUserEdit: TfrmUserEdit;

implementation

{$R *.dfm}

procedure TfrmUserEdit.SetUserService(AService: IUserService);
begin
  FUserService := AService;
end;

procedure TfrmUserEdit.SetLogger(ALogger: ILogger);
begin
  FLogger := ALogger;
end;

procedure TfrmUserEdit.SetUser(AUser: TUser);
begin
  FUser := AUser;
end;

procedure TfrmUserEdit.SetIsNewUser(AIsNew: Boolean);
begin
  FIsNewUser := AIsNew;
end;

procedure TfrmUserEdit.FormShow(Sender: TObject);
begin
  cmbRole.Items.Clear;
  cmbRole.Items.Add('User');
  cmbRole.Items.Add('Admin');
  cmbRole.ItemIndex := 0;

  if FIsNewUser then
  begin
    lblTitle.Caption := 'Add New User';
    edtUsername.Clear;
    edtPassword.Clear;
    edtConfirmPassword.Clear;
    edtUsername.SetFocus;
  end
  else
  begin
    lblTitle.Caption := 'Edit User';
    edtUsername.Text := FUser.Username;
    edtUsername.ReadOnly := True;
    
    if FUser.Role = urAdmin then
      cmbRole.ItemIndex := 1
    else
      cmbRole.ItemIndex := 0;
    
    lblPasswordNote.Caption := 'Leave empty to keep current password';
    edtPassword.SetFocus;
  end;
end;

procedure TfrmUserEdit.btnSaveClick(Sender: TObject);
var
  LResult: TResult<TUser>;
  LUpdateResult: TResult;
begin
  if edtUsername.Text = '' then
  begin
    lblStatus.Caption := 'Username cannot be empty';
    lblStatus.Font.Color := clRed;
    edtUsername.SetFocus;
    Exit;
  end;

  if FIsNewUser then
  begin
    if edtPassword.Text = '' then
    begin
      lblStatus.Caption := 'Password cannot be empty';
      lblStatus.Font.Color := clRed;
      edtPassword.SetFocus;
      Exit;
    end;

    if edtConfirmPassword.Text = '' then
    begin
      lblStatus.Caption := 'Please confirm password';
      lblStatus.Font.Color := clRed;
      edtConfirmPassword.SetFocus;
      Exit;
    end;

    if edtPassword.Text <> edtConfirmPassword.Text then
    begin
      lblStatus.Caption := 'Passwords do not match';
      lblStatus.Font.Color := clRed;
      edtConfirmPassword.SetFocus;
      Exit;
    end;

    if Length(edtPassword.Text) < 6 then
    begin
      lblStatus.Caption := 'Password must be at least 6 characters';
      lblStatus.Font.Color := clRed;
      edtPassword.SetFocus;
      Exit;
    end;

    // Create new user
    lblStatus.Caption := 'Creating user...';
    lblStatus.Font.Color := clBlue;
    Application.ProcessMessages;

    LResult := FUserService.CreateUser(edtUsername.Text, edtPassword.Text, TUserRole(cmbRole.ItemIndex));

    if LResult.IsSuccess then
    begin
      lblStatus.Caption := 'User created successfully';
      lblStatus.Font.Color := clGreen;
      ShowMessage('User created successfully');
      ModalResult := mrOk;
    end
    else
    begin
      lblStatus.Caption := 'Error creating user: ' + LResult.GetErrorMessage;
      lblStatus.Font.Color := clRed;
    end;
  end
  else
  begin
    // Update existing user
    lblStatus.Caption := 'Updating user...';
    lblStatus.Font.Color := clBlue;
    Application.ProcessMessages;

    // Update role via domain method
    FUser.ChangeRole(TUserRole(cmbRole.ItemIndex));

    LUpdateResult := FUserService.UpdateUser(FUser, edtPassword.Text);

    if LUpdateResult.IsSuccess then
    begin
      lblStatus.Caption := 'User updated successfully';
      lblStatus.Font.Color := clGreen;
      ShowMessage('User updated successfully');
      ModalResult := mrOk;
    end
    else
    begin
      lblStatus.Caption := 'Error updating user: ' + LUpdateResult.GetErrorMessage;
      lblStatus.Font.Color := clRed;
    end;
  end;
end;

procedure TfrmUserEdit.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TfrmUserEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Modal form: closing via X should just dismiss with mrCancel
  CanClose := True;
  ModalResult := mrCancel;
end;

end.
