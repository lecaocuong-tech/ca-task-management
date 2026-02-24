object frmUserManagement: TfrmUserManagement
  Left = 0
  Top = 0
  Caption = 'User Management'
  ClientHeight = 600
  ClientWidth = 800
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poOwnerFormCenter
  OnShow = FormShow
  TextHeight = 13
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 800
    Height = 50
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblTitle: TLabel
      Left = 16
      Top = 16
      Width = 120
      Height = 21
      Caption = 'Manage Users'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -17
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object pnlContent: TPanel
    Left = 0
    Top = 50
    Width = 800
    Height = 450
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 1
    object sgUsers: TStringGrid
      Left = 16
      Top = 16
      Width = 768
      Height = 418
      ColCount = 7
      DefaultColWidth = 100
      DefaultRowHeight = 18
      RowCount = 2
      FixedRows = 1
      FixedCols = 0
      Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRangeSelect, goRowSelect]
      TabOrder = 0
      OnClick = sgUsersClick
      OnDblClick = sgUsersDblClick
      OnDrawCell = sgUsersDrawCell
      OnSelectCell = sgUsersSelectCell
      ColWidths = (
        40
        40
        150
        80
        150
        80
        80)
    end
  end
  object pnlActions: TPanel
    Left = 0
    Top = 500
    Width = 800
    Height = 100
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    object lblPageInfo: TLabel
      Left = 16
      Top = 16
      Width = 33
      Height = 13
      Caption = 'Page 1'
    end
    object btnPrevPage: TButton
      Left = 16
      Top = 36
      Width = 75
      Height = 25
      Caption = '< Previous'
      TabOrder = 0
      OnClick = btnPrevPageClick
    end
    object btnNextPage: TButton
      Left = 101
      Top = 36
      Width = 75
      Height = 25
      Caption = 'Next >'
      TabOrder = 1
      OnClick = btnNextPageClick
    end
    object btnAdd: TButton
      Left = 336
      Top = 36
      Width = 75
      Height = 25
      Caption = 'Add User'
      TabOrder = 2
      OnClick = btnAddClick
    end
    object btnEdit: TButton
      Left = 421
      Top = 36
      Width = 75
      Height = 25
      Caption = 'Edit'
      Enabled = False
      TabOrder = 3
      OnClick = btnEditClick
    end
    object btnDelete: TButton
      Left = 506
      Top = 36
      Width = 75
      Height = 25
      Caption = 'Delete'
      Enabled = False
      TabOrder = 4
      OnClick = btnDeleteClick
    end
    object btnClose: TButton
      Left = 709
      Top = 36
      Width = 75
      Height = 25
      Caption = 'Close'
      TabOrder = 5
      OnClick = btnCloseClick
    end
  end
end
