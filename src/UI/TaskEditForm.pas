unit TaskEditForm;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes, DomainModels;

type
  TfrmTaskEdit = class(TForm)
    edtTitle: TEdit;
    memDescription: TMemo;
    cmbStatus: TComboBox;
    btnSave: TButton;
    btnCancel: TButton;
    lblTitle: TLabel;
    lblDescription: TLabel;
    lblStatus: TLabel;
    procedure btnSaveClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FTask: TTask;
    FIsEdit: Boolean;
    procedure LoadTaskToForm;
    procedure SaveFormToTask;
  public
    property Task: TTask read FTask write FTask;
    property IsEdit: Boolean read FIsEdit write FIsEdit;
    function ExecuteEdit(ATask: TTask): Boolean;
  end;

implementation

{$R *.dfm}

procedure TfrmTaskEdit.btnSaveClick(Sender: TObject);
begin
  SaveFormToTask;
  ModalResult := mrOk;
end;

procedure TfrmTaskEdit.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TfrmTaskEdit.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Modal form: closing via X should just dismiss with mrCancel
  CanClose := True;
  ModalResult := mrCancel;
end;

procedure TfrmTaskEdit.LoadTaskToForm;
begin
  if Assigned(FTask) then
  begin
    edtTitle.Text := FTask.Title;
    memDescription.Text := FTask.Description;
    cmbStatus.ItemIndex := cmbStatus.Items.IndexOf(StatusToString(FTask.Status));
  end;
end;

procedure TfrmTaskEdit.SaveFormToTask;
begin
  if Assigned(FTask) then
  begin
    FTask.UpdateContent(edtTitle.Text, memDescription.Text);
    FTask.ChangeStatus(StringToStatus(cmbStatus.Text));
  end;
end;

function TfrmTaskEdit.ExecuteEdit(ATask: TTask): Boolean;
begin
  FTask := ATask;
  FIsEdit := True;
  LoadTaskToForm;
  Result := ShowModal = mrOk;
end;

end.
