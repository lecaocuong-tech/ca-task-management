unit RegistrationForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  AppInterfaces,
  Result,
  DomainModels;

type
  TfrmRegistration = class(TForm)
    pnlMain: TPanel;
    lblTitle: TLabel;
    lblUsername: TLabel;
    edtUsername: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblConfirmPassword: TLabel;
    edtConfirmPassword: TEdit;
    btnRegister: TButton;
    btnCancel: TButton;
    lblStatus: TLabel;
    chkShowPassword: TCheckBox;
    procedure btnRegisterClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure chkShowPasswordClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure edtPasswordKeyPress(Sender: TObject; var Key: Char);
    procedure edtConfirmPasswordKeyPress(Sender: TObject; var Key: Char);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FAuthService: IAuthenticationService;
    procedure SetAuthService(AService: IAuthenticationService);
  public
    property AuthService: IAuthenticationService write SetAuthService;
  end;

var
  frmRegistration: TfrmRegistration;

implementation

{$R *.dfm}

procedure TfrmRegistration.SetAuthService(AService: IAuthenticationService);
begin
  FAuthService := AService;
end;

procedure TfrmRegistration.FormShow(Sender: TObject);
begin
  edtUsername.SetFocus;
end;

procedure TfrmRegistration.chkShowPasswordClick(Sender: TObject);
begin
  if chkShowPassword.Checked then
  begin
    edtPassword.PasswordChar := #0;
    edtConfirmPassword.PasswordChar := #0;
  end
  else
  begin
    edtPassword.PasswordChar := '*';
    edtConfirmPassword.PasswordChar := '*';
  end;
end;

procedure TfrmRegistration.edtPasswordKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then // Enter key
  begin
    edtConfirmPassword.SetFocus;
    Key := #0;
  end;
end;

procedure TfrmRegistration.edtConfirmPasswordKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then // Enter key
  begin
    btnRegisterClick(nil);
    Key := #0;
  end;
end;

procedure TfrmRegistration.btnRegisterClick(Sender: TObject);
var
  LResult: TResult<TUser>;
begin
  if edtUsername.Text = '' then
  begin
    lblStatus.Caption := 'Please enter username';
    lblStatus.Font.Color := clRed;
    edtUsername.SetFocus;
    Exit;
  end;

  if edtPassword.Text = '' then
  begin
    lblStatus.Caption := 'Please enter password';
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

  // Validate password policy via service before attempting registration
  var LPolicyResult := FAuthService.ValidatePasswordPolicy(edtPassword.Text);
  if not LPolicyResult.IsSuccess then
  begin
    lblStatus.Caption := LPolicyResult.GetErrorMessage;
    lblStatus.Font.Color := clRed;
    edtPassword.SetFocus;
    Exit;
  end;

  lblStatus.Caption := 'Registering...';
  lblStatus.Font.Color := clBlue;
  Application.ProcessMessages;

  try
    LResult := FAuthService.Register(edtUsername.Text, edtPassword.Text);
    
    if LResult.IsSuccess then
    begin
      lblStatus.Caption := 'Registration successful';
      lblStatus.Font.Color := clGreen;
      ShowMessage('User registered successfully. Please login with your credentials.');
      ModalResult := mrOk;
    end
    else
    begin
      lblStatus.Caption := 'Registration failed: ' + LResult.GetErrorMessage;
      lblStatus.Font.Color := clRed;
      edtPassword.Clear;
      edtConfirmPassword.Clear;
      edtPassword.SetFocus;
    end;
  except
    on E: Exception do
    begin
      lblStatus.Caption := 'Error: ' + E.Message;
      lblStatus.Font.Color := clRed;
    end;
  end;
end;

procedure TfrmRegistration.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TfrmRegistration.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Modal form: closing via X should just dismiss with mrCancel
  CanClose := True;
  ModalResult := mrCancel;
end;

end.
