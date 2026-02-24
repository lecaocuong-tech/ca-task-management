object frmRegistration: TfrmRegistration
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Register New User'
  ClientHeight = 350
  ClientWidth = 400
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poOwnerFormCenter
  OnShow = FormShow
  TextHeight = 13
  object pnlMain: TPanel
    Left = 0
    Top = 0
    Width = 400
    Height = 350
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 0
    object lblTitle: TLabel
      Left = 16
      Top = 16
      Width = 368
      Height = 21
      Caption = 'Create New User Account'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -17
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblUsername: TLabel
      Left = 16
      Top = 50
      Width = 60
      Height = 13
      Caption = 'Username:'
    end
    object lblPassword: TLabel
      Left = 16
      Top = 90
      Width = 53
      Height = 13
      Caption = 'Password:'
    end
    object lblConfirmPassword: TLabel
      Left = 16
      Top = 130
      Width = 104
      Height = 13
      Caption = 'Confirm Password:'
    end
    object lblStatus: TLabel
      Left = 16
      Top = 170
      Width = 368
      Height = 13
      Caption = ''
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = []
      ParentFont = False
    end
    object edtUsername: TEdit
      Left = 16
      Top = 65
      Width = 368
      Height = 21
      TabOrder = 0
      TextHint = 'Enter username'
    end
    object edtPassword: TEdit
      Left = 16
      Top = 105
      Width = 368
      Height = 21
      PasswordChar = '*'
      TabOrder = 1
      TextHint = 'Enter password (min 6 characters)'
      OnKeyPress = edtPasswordKeyPress
    end
    object edtConfirmPassword: TEdit
      Left = 16
      Top = 145
      Width = 368
      Height = 21
      PasswordChar = '*'
      TabOrder = 2
      TextHint = 'Confirm password'
      OnKeyPress = edtConfirmPasswordKeyPress
    end
    object chkShowPassword: TCheckBox
      Left = 16
      Top = 190
      Width = 368
      Height = 17
      Caption = 'Show Password'
      TabOrder = 3
      OnClick = chkShowPasswordClick
    end
    object btnRegister: TButton
      Left = 216
      Top = 280
      Width = 75
      Height = 25
      Caption = 'Register'
      Default = True
      TabOrder = 4
      OnClick = btnRegisterClick
    end
    object btnCancel: TButton
      Left = 309
      Top = 280
      Width = 75
      Height = 25
      Caption = 'Cancel'
      TabOrder = 5
      OnClick = btnCancelClick
    end
  end
end
