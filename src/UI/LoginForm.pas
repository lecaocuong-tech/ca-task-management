unit LoginForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  AppInterfaces,
  Result,
  RegistrationForm;

type
  TfrmLogin = class(TForm)
    pnlMain: TPanel;
    lblTitle: TLabel;
    lblUsername: TLabel;
    edtUsername: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    btnLogin: TButton;
    btnExit: TButton;
    lblStatus: TLabel;
    chkShowPassword: TCheckBox;
    btnRegister: TButton;
    procedure btnLoginClick(Sender: TObject);
    procedure btnExitClick(Sender: TObject);
    procedure chkShowPasswordClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure edtPasswordKeyPress(Sender: TObject; var Key: Char);
    procedure btnRegisterClick(Sender: TObject);    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);  private
    FAuthService: IAuthenticationService;
    FUserService: IUserService;
    procedure SetAuthService(AService: IAuthenticationService);
    procedure SetUserService(AService: IUserService);
  public
    property AuthService: IAuthenticationService write SetAuthService;
    property UserService: IUserService write SetUserService;
  end;

var
  frmLogin: TfrmLogin;

implementation

{$R *.dfm}

procedure TfrmLogin.SetAuthService(AService: IAuthenticationService);
begin
  FAuthService := AService;
end;

procedure TfrmLogin.SetUserService(AService: IUserService);
begin
  FUserService := AService;
end;

procedure TfrmLogin.FormShow(Sender: TObject);
begin
  edtUsername.SetFocus;
end;

procedure TfrmLogin.chkShowPasswordClick(Sender: TObject);
begin
  if chkShowPassword.Checked then
    edtPassword.PasswordChar := #0
  else
    edtPassword.PasswordChar := '*';
end;

procedure TfrmLogin.edtPasswordKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then // Enter key
  begin
    btnLoginClick(nil);
    Key := #0;
  end;
end;

procedure TfrmLogin.btnLoginClick(Sender: TObject);
var
  LResult: TResult;
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

  lblStatus.Caption := 'Logging in...';
  lblStatus.Font.Color := clBlue;
  Application.ProcessMessages;

  try
    LResult := FAuthService.Login(edtUsername.Text, edtPassword.Text);
    
    if LResult.IsSuccess then
    begin
      lblStatus.Caption := 'Login successful';
      lblStatus.Font.Color := clGreen;
      ModalResult := mrOk;
    end
    else
    begin
      lblStatus.Caption := 'Login failed: ' + LResult.GetErrorMessage;
      lblStatus.Font.Color := clRed;
      edtPassword.Clear;
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

procedure TfrmLogin.btnExitClick(Sender: TObject);
begin
  // Exit: close the modal — main loop handles app termination
  ModalResult := mrCancel;
end;

procedure TfrmLogin.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Clicking X should dismiss the modal — main loop handles app termination
  CanClose := True;
  ModalResult := mrCancel;
end;

procedure TfrmLogin.btnRegisterClick(Sender: TObject);
var
  LFormReg: TfrmRegistration;
begin
  LFormReg := TfrmRegistration.Create(nil);
  try
    LFormReg.AuthService := FAuthService;
    LFormReg.ShowModal;
    if LFormReg.ModalResult = mrOk then
    begin
      lblStatus.Caption := 'Registration successful. Please login.';
      lblStatus.Font.Color := clGreen;
      edtUsername.Clear;
      edtPassword.Clear;
      edtUsername.SetFocus;
    end;
  finally
    LFormReg.Free;
  end;
end;

end.
