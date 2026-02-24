object frmUserEdit: TfrmUserEdit
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Edit User'
  ClientHeight = 280
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
    Height = 280
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 0
    object lblTitle: TLabel
      Left = 16
      Top = 16
      Width = 368
      Height = 21
      Caption = 'Edit User'
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
      Top = 85
      Width = 53
      Height = 13
      Caption = 'Password:'
    end
    object lblConfirmPassword: TLabel
      Left = 16
      Top = 125
      Width = 104
      Height = 13
      Caption = 'Confirm Password:'
    end
    object lblRole: TLabel
      Left = 16
      Top = 165
      Width = 28
      Height = 13
      Caption = 'Role:'
    end
    object lblPasswordNote: TLabel
      Left = 75
      Top = 85
      Width = 200
      Height = 13
      Caption = ''
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -9
      Font.Name = 'Tahoma'
      Font.Style = [fsItalic]
      ParentFont = False
    end
    object lblStatus: TLabel
      Left = 16
      Top = 205
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
      Top = 63
      Width = 368
      Height = 21
      TabOrder = 0
      TextHint = 'Username'
    end
    object edtPassword: TEdit
      Left = 16
      Top = 100
      Width = 368
      Height = 21
      PasswordChar = '*'
      TabOrder = 1
      TextHint = 'Password (leave empty to keep current)'
    end
    object edtConfirmPassword: TEdit
      Left = 16
      Top = 140
      Width = 368
      Height = 21
      PasswordChar = '*'
      TabOrder = 2
      TextHint = 'Confirm password'
    end
    object cmbRole: TComboBox
      Left = 16
      Top = 180
      Width = 368
      Height = 21
      Style = csDropDownList
      TabOrder = 3
    end
    object btnSave: TButton
      Left = 216
      Top = 242
      Width = 75
      Height = 25
      Caption = 'Save'
      Default = True
      TabOrder = 4
      OnClick = btnSaveClick
    end
    object btnCancel: TButton
      Left = 309
      Top = 242
      Width = 75
      Height = 25
      Caption = 'Cancel'
      TabOrder = 5
      OnClick = btnCancelClick
    end
  end
end
