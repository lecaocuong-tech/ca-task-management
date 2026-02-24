object frmTaskEdit: TfrmTaskEdit
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Edit Task'
  ClientHeight = 260
  ClientWidth = 400
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 13
  object lblTitle: TLabel
    Left = 24
    Top = 24
    Width = 24
    Height = 13
    Caption = 'Title:'
  end
  object lblDescription: TLabel
    Left = 24
    Top = 56
    Width = 57
    Height = 13
    Caption = 'Description:'
  end
  object lblStatus: TLabel
    Left = 24
    Top = 148
    Width = 35
    Height = 13
    Caption = 'Status:'
  end
  object edtTitle: TEdit
    Left = 80
    Top = 20
    Width = 280
    Height = 21
    TabOrder = 0
  end
  object memDescription: TMemo
    Left = 80
    Top = 52
    Width = 280
    Height = 80
    TabOrder = 1
  end
  object cmbStatus: TComboBox
    Left = 80
    Top = 144
    Width = 150
    Height = 21
    Style = csDropDownList
    TabOrder = 2
    Items.Strings = (
      'Pending'
      'InProgress'
      'Done')
  end
  object btnSave: TButton
    Left = 200
    Top = 200
    Width = 75
    Height = 25
    Caption = 'Save'
    Default = True
    TabOrder = 3
    OnClick = btnSaveClick
  end
  object btnCancel: TButton
    Left = 285
    Top = 200
    Width = 75
    Height = 25
    Cancel = True
    Caption = 'Cancel'
    TabOrder = 4
    OnClick = btnCancelClick
  end
end
