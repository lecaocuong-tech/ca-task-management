object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Task Manager Pro'
  ClientHeight = 550
  ClientWidth = 792
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 13
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 792
    Height = 60
    Align = alTop
    BevelOuter = bvNone
    Color = clWhitesmoke
    TabOrder = 0
    ExplicitWidth = 800
    object lblWelcome: TLabel
      Left = 20
      Top = 15
      Width = 88
      Height = 23
      Caption = 'Welcome'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -19
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object btnLogout: TButton
      Left = 700
      Top = 15
      Width = 80
      Height = 30
      Caption = 'Logout'
      TabOrder = 0
      OnClick = btnLogoutClick
    end
    object btnManageUsers: TButton
      Left = 600
      Top = 15
      Width = 90
      Height = 30
      Caption = 'Manage Users'
      Enabled = False
      TabOrder = 1
      OnClick = btnManageUsersClick
    end
  end
  object pnlTaskList: TPanel
    Left = 0
    Top = 60
    Width = 792
    Height = 340
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 1
    ExplicitWidth = 800
    ExplicitHeight = 390
    object sgTasks: TStringGrid
      Left = 0
      Top = 0
      Width = 792
      Height = 340
      Align = alClient
      ColCount = 7
      DefaultColWidth = 100
      DefaultRowHeight = 20
      RowCount = 2
      FixedRows = 1
      FixedCols = 0
      Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRangeSelect, goTabs]
      TabOrder = 0
      OnClick = sgTasksClick
      OnDblClick = sgTasksDblClick
      OnDrawCell = sgTasksDrawCell
      OnSelectCell = sgTasksSelectCell
      ExplicitWidth = 800
      ExplicitHeight = 400
      ColWidths = (
        40
        60
        250
        100
        200
        80
        80)
      RowHeights = (
        20
        20)
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 400
    Width = 792
    Height = 150
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    ExplicitTop = 450
    ExplicitWidth = 800
    object pnlTaskActions: TPanel
      Left = 0
      Top = 0
      Width = 792
      Height = 80
      Align = alTop
      BevelOuter = bvNone
      Color = clSilver
      TabOrder = 0
      ExplicitWidth = 800
      object lblNewTask: TLabel
        Left = 10
        Top = 10
        Width = 73
        Height = 13
        Caption = 'New Task Title:'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = []
        ParentFont = False
      end
      object lblStatus: TLabel
        Left = 10
        Top = 38
        Width = 60
        Height = 13
        Caption = 'Task Status:'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = []
        ParentFont = False
      end
      object lblFilterStatus: TLabel
        Left = 480
        Top = 38
        Width = 43
        Height = 13
        Caption = 'Filter by:'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = []
        ParentFont = False
      end
      object edtNewTask: TEdit
        Left = 120
        Top = 10
        Width = 400
        Height = 21
        TabOrder = 0
      end
      object btnAddTask: TButton
        Left = 540
        Top = 10
        Width = 80
        Height = 21
        Caption = 'Add Task'
        TabOrder = 1
        OnClick = btnAddTaskClick
      end
      object btnRefresh: TButton
        Left = 630
        Top = 10
        Width = 80
        Height = 21
        Caption = 'Refresh'
        TabOrder = 2
        OnClick = btnRefreshClick
      end
      object cmbStatus: TComboBox
        Left = 120
        Top = 38
        Width = 150
        Height = 21
        Style = csDropDownList
        ItemIndex = 0
        TabOrder = 3
        Text = 'Pending'
        Items.Strings = (
          'Pending'
          'InProgress'
          'Done')
      end
      object cmbFilterStatus: TComboBox
        Left = 545
        Top = 38
        Width = 150
        Height = 21
        Style = csDropDownList
        ItemIndex = 0
        TabOrder = 6
        Text = 'All'
        OnChange = cmbFilterStatusChange
        Items.Strings = (
          'All'
          'Pending'
          'InProgress'
          'Done')
      end
      object btnDeleteTask: TButton
        Left = 280
        Top = 38
        Width = 80
        Height = 21
        Caption = 'Delete Task'
        TabOrder = 4
        OnClick = btnDeleteTaskClick
      end
      object btnUpdateStatus: TButton
        Left = 370
        Top = 38
        Width = 100
        Height = 21
        Caption = 'Update Status'
        TabOrder = 5
        OnClick = btnUpdateStatusClick
      end
    end
    object pnlUserManagement: TPanel
      Left = 0
      Top = 80
      Width = 792
      Height = 70
      Align = alClient
      BevelOuter = bvNone
      Color = clSilver
      TabOrder = 1
      ExplicitWidth = 800
      ExplicitHeight = 75
      object lblJobStatus: TLabel
        Left = 10
        Top = 0
        Width = 89
        Height = 13
        Caption = 'Job Status: Ready'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGreen
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = []
        ParentFont = False
      end
      object lblPageInfo: TLabel
        Left = 237
        Top = 0
        Width = 33
        Height = 13
        Caption = 'Page 1'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Tahoma'
        Font.Style = []
        ParentFont = False
      end
      object progressBar: TProgressBar
        Left = 10
        Top = 15
        Width = 772
        Height = 17
        TabOrder = 0
      end
      object btnStartAutoCleanup: TButton
        Left = 10
        Top = 40
        Width = 120
        Height = 20
        Caption = 'Start Auto Cleanup'
        TabOrder = 1
        OnClick = btnStartAutoCleanupClick
      end
      object btnStartLongJob: TButton
        Left = 140
        Top = 40
        Width = 120
        Height = 20
        Caption = 'Start Long Job (5s)'
        TabOrder = 2
        OnClick = btnStartLongJobClick
      end
      object btnCancelJob: TButton
        Left = 400
        Top = 40
        Width = 120
        Height = 20
        Caption = 'Cancel Job'
        TabOrder = 3
        OnClick = btnCancelJobClick
      end
      object btnDeleteDoneJob: TButton
        Left = 270
        Top = 40
        Width = 120
        Height = 20
        Caption = 'Delete Done Tasks'
        TabOrder = 6
        OnClick = btnDeleteDoneJobClick
      end
      object btnPrevPage: TButton
        Left = 615
        Top = 40
        Width = 80
        Height = 20
        Caption = '< Previous'
        TabOrder = 4
        OnClick = btnPrevPageClick
      end
      object btnNextPage: TButton
        Left = 710
        Top = 40
        Width = 72
        Height = 20
        Caption = 'Next >'
        TabOrder = 5
        OnClick = btnNextPageClick
      end
    end
  end
end
