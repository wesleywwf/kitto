unit Kitto.Ext.Form;

{$I Kitto.Defines.inc}

interface

uses
  Generics.Collections,
  Ext, ExtData, ExtForm,
  EF.ObserverIntf,
  Kitto.Ext.Base, Kitto.Ext.DataPanel, Kitto.Ext.Editors,
  Kitto.Metadata.Views, Kitto.Metadata.DataView, Kitto.Ext.Controller, Kitto.Store;

type
  ///	<summary>
  ///	  A button that opens a popup detail form.
  ///	</summary>
  TKExtDetailFormButton = class(TExtButton)
  private
    FViewTable: TKViewTable;
    FDetailHostWindow: TKExtModalWindow;
    FView: TKDataView;
    FServerStore: TKViewTableStore;
    FMasterRecord: TKViewTableRecord;
    procedure SetViewTable(const AValue: TKViewTable);
  public
    destructor Destroy; override;
    property ViewTable: TKViewTable read FViewTable write SetViewTable;
    property View: TKDataView read FView write FView;
    property ServerStore: TKViewTableStore read FServerStore write FServerStore;
    property MasterRecord: TKViewTableRecord read FMasterRecord write FMasterRecord;
  published
    procedure ShowDetailWindow;
  end;

  ///	<summary>
  ///	  The Form controller.
  ///	</summary>
  TKExtFormPanelController = class(TKExtDataPanelController)
  private
    FFormPanel: TKExtEditPanel;
    FIsReadOnly: Boolean;
    //FEditors: TList<IKExtEditor>;
    FSaveButton: TExtButton;
    FCancelButton: TExtButton;
    FDetailToolbar: TExtToolbar;
    FDetailButtons: TObjectList<TKExtDetailFormButton>;
    FOperation: string;
    FFocusField: TExtFormField;
    FStoreRecord: TKViewTableRecord;
    procedure CreateDetailToolbar;
    procedure CreateEditors(const AForceReadOnly: Boolean);
    procedure StartOperation;
    procedure FocusFirstField;
  protected
    procedure LoadData; override;
    procedure InitComponents; override;
  public
    destructor Destroy; override;
  published
    procedure GetRecord;
    procedure SaveChanges;
    procedure CancelChanges;
  end;

implementation

uses
  SysUtils, StrUtils,
  EF.Localization, EF.Types, EF.Intf, EF.Tree,
  Kitto.Environment, Kitto.AccessControl, Kitto.JSON, Kitto.Rules,
  Kitto.Ext.Session, Kitto.Ext.Utils;

{ TKExtFormPanelController }

destructor TKExtFormPanelController.Destroy;
begin
  FreeAndNil(FDetailButtons);
  inherited;
end;

procedure TKExtFormPanelController.CreateDetailToolbar;
var
  I: Integer;
begin
  Assert(ViewTable <> nil);
  Assert(FDetailToolbar = nil);
  Assert(Assigned(FStoreRecord));

  if ViewTable.DetailTableCount > 0 then
  begin
    FStoreRecord.CreateDetailStores;
    Assert(FStoreRecord.DetailStoreCount = ViewTable.DetailTableCount);
    FDetailToolbar := TExtToolbar.Create;
    FDetailButtons := TObjectList<TKExtDetailFormButton>.Create(False);
    for I := 0 to ViewTable.DetailTableCount - 1 do
    begin
      FDetailButtons.Add(TKExtDetailFormButton.AddTo(FDetailToolbar.Items));
      FDetailButtons[I].ServerStore := FStoreRecord.DetailStores[I];
      FDetailButtons[I].MasterRecord := FStoreRecord;
      FDetailButtons[I].ViewTable := ViewTable.DetailTables[I];
      FDetailButtons[I].View := View;
    end;
    Tbar := FDetailToolbar;
  end;
end;

procedure TKExtFormPanelController.CreateEditors(const AForceReadOnly: Boolean);
var
  LLayoutProcessor: TKExtLayoutProcessor;
  LLayoutName: string;
begin
//  FreeAndNil(FEditors);
//  FEditors := TList<IKExtEditor>.Create;
  LLayoutProcessor := TKExtLayoutProcessor.Create;
  try
    LLayoutProcessor.ViewTable := ViewTable;
    LLayoutProcessor.StoreHeader := ServerStore.Header;
    LLayoutProcessor.FormPanel := FFormPanel;
//    LLayoutProcessor.OnNewEditor :=
//      procedure (AEditor: IKExtEditor)
//      begin
//        FEditors.Add(AEditor);
//      end;
    LLayoutProcessor.ForceReadOnly := AForceReadOnly;

    LLayoutName := ViewTable.GetString('Controller/Form/Layout');
    if LLayoutName <> '' then
      LLayoutProcessor.CreateEditors(View.Catalog.Layouts.FindLayout(LLayoutName))
    else
      LLayoutProcessor.CreateEditors(ViewTable.FindLayout('Form'));
    FFocusField := LLayoutProcessor.FocusField;
  finally
    FreeAndNil(LLayoutProcessor);
  end;
  // Scroll back to top - can't do that until afterrender because body.dom is needed.
  FFormPanel.On('afterrender', JSFunction(FFormPanel.JSName + '.body.dom.scrollTop = 0;'));
end;

procedure TKExtFormPanelController.LoadData;
begin
  inherited;
  CreateEditors(FIsReadOnly);
  CreateDetailToolbar;
  StartOperation;
end;

procedure TKExtFormPanelController.StartOperation;
var
  LDefaultValues: TEFNode;
begin
  Assert(Assigned(FStoreRecord));

  if FOperation = 'Add' then
  begin
    LDefaultValues := ViewTable.GetDefaultValues;
    try
      FStoreRecord.ReadFromNode(LDefaultValues);
    finally
      FreeAndNil(LDefaultValues);
    end;
  end;

  // Load data from FServerRecord.
  Session.JSCode(
    FFormPanel.JSName + '.getForm().load({url:"' + MethodURI(GetRecord) + '",' +
      'failure: function(form, action) { Ext.Msg.alert("' + _('Load failed.') + '", action.result.errorMessage);}});');
  FocusFirstField;
end;

procedure TKExtFormPanelController.FocusFirstField;
begin
  if Assigned (FFocusField) then
    FFocusField.Focus(False, 500);
end;

procedure TKExtFormPanelController.GetRecord;
begin
  Assert(Assigned(FStoreRecord));

  Session.Response := '{success:true,data:' + FStoreRecord.GetAsJSON(True) + '}';
end;

procedure TKExtFormPanelController.SaveChanges;
begin
  FStoreRecord.Backup;
  try
    Session.GetQueryValues(FStoreRecord, False,
      function(const AName: string): string
      var
        LViewField: TKViewField;
      begin
        LViewField := ViewTable.FindFieldByAliasedName(AName);
        if Assigned(LViewField) then
          Result := LViewField.GetMinifiedName
        else
          Result := AName;
      end);
    ViewTable.ApplyRules(
      procedure (const ARuleImpl: TKRuleImpl)
      begin
        ARuleImpl.BeforeWrite(FStoreRecord);
      end);
  except
    FStoreRecord.Restore;
    raise;
  end;

  FStoreRecord.MarkAsDirty;
  if not ViewTable.IsDetail then
  begin
    FStoreRecord.Save(True);
    Session.Flash(_('Changes saved succesfully.'));
  end;
  NotifyObservers('Confirmed');
  if not CloseHostWindow then
    StartOperation;
end;

procedure TKExtFormPanelController.InitComponents;
var
  LHostWindow: TExtWindow;
begin
  inherited;
  Title := ViewTable.DisplayLabel;

  FOperation := Config.GetString('Sys/Operation');
  if FOperation = '' then
    FOperation := View.GetString('Controller/Operation');

  FStoreRecord := Config.GetObject('Sys/Record') as TKViewTableRecord;
  Assert((FOperation = 'Add') or Assigned(FStoreRecord));
  if FOperation = 'Add' then
  begin
    Assert(not Assigned(FStoreRecord));
    FStoreRecord := ServerStore.AppendRecord(nil);
  end;

  if SameText(FOperation, 'Add') then
    FIsReadOnly := View.GetBoolean('IsReadOnly') or ViewTable.IsReadOnly or View.GetBoolean('Controller/PreventAdding')
      or not ViewTable.IsAccessGranted(ACM_ADD)
  else
    FIsReadOnly := View.GetBoolean('IsReadOnly') or ViewTable.IsReadOnly or View.GetBoolean('Controller/PreventEditing')
      or not ViewTable.IsAccessGranted(ACM_MODIFY);
  if SameText(FOperation, 'Add') and FIsReadOnly then
    raise EEFError.Create(_('Operation Add not supported on read-only data.'));

  ExtQuickTips.Init(True);

  FFormPanel := TKExtEditPanel.AddTo(Items);
  FFormPanel.Region := rgCenter;
  FFormPanel.Border := False;
  FFormPanel.Header := False;
  FFormPanel.Frame := True;
  FFormPanel.AutoScroll := True;
  FFormPanel.AutoWidth := True;
  FFormPanel.LabelWidth := 120;
  FFormPanel.MonitorValid := True;
  //TExtFormBasicForm(FFormPanel.GetForm).Url := MethodURI(SaveChanges);

  if not FIsReadOnly then
  begin
    FSaveButton := TExtButton.AddTo(FFormPanel.Buttons);
    FSaveButton.Scale := View.GetString('Controller/ButtonScale', 'medium');
    FSaveButton.FormBind := True;
    FSaveButton.Text := _('Save');
    FSaveButton.Tooltip := _('Save changes and finish editing');
    FSaveButton.Icon := Environment.GetImageURL('ok');
    FSaveButton.Handler := AjaxForms(SaveChanges, [FFormPanel]);
    //FSaveButton.Handler := JSFunction(FFormPanel.JSName + '.getForm().doAction("submit", {success:"AjaxSuccess", failure:"AjaxFailure"});');
  end;
  FCancelButton := TExtButton.AddTo(FFormPanel.Buttons);
  FCancelButton.Scale := View.GetString('Controller/ButtonScale', 'medium');
  if FIsReadOnly then
  begin
    FCancelButton.Text := _('Close');
    FCancelButton.Tooltip := _('Close this panel');
    FCancelButton.Icon := Environment.GetImageURL('close');
    // No need for an ajax call when we just close the client-side panel.
    LHostWindow := GetHostWindow;
    if Assigned(LHostWindow) then
      FCancelButton.Handler := JSFunction(LHostWindow.JSName + '.close();');
  end
  else
  begin
    FCancelButton.Text := _('Cancel');
    FCancelButton.Tooltip := _('Cancel changes');
    FCancelButton.Icon := Environment.GetImageURL('cancel');
    FCancelButton.Handler := Ajax(CancelChanges);
  end;
end;

procedure TKExtFormPanelController.CancelChanges;
begin
  if FOperation = 'Add' then
  begin
    ServerStore.RemoveRecord(FStoreRecord);
    FStoreRecord := nil;
  end;
  NotifyObservers('Canceled');
  if not CloseHostWindow then
    StartOperation;
end;

{ TKExtDetailFormButton }

destructor TKExtDetailFormButton.Destroy;
begin
  //FreeAndNil(FDetailHostWindow);
  inherited;
end;

procedure TKExtDetailFormButton.SetViewTable(const AValue: TKViewTable);
begin
  FViewTable := AValue;
  if Assigned(FViewTable) then
  begin
    Text := FViewTable.PluralDisplayLabel;
    Icon := Environment.GetImageURL(FViewTable.ImageName);
    Handler := Ajax(ShowDetailWindow, []);
  end;
end;

procedure TKExtDetailFormButton.ShowDetailWindow;
var
  LController: IKExtController;
begin
  Assert(Assigned(FViewTable));

  if Assigned(FDetailHostWindow) then
    FDetailHostWindow.Free(True);
  FDetailHostWindow := TKExtModalWindow.Create;
  { TODO : use a master-record-specific title - define a way to specify a record's caption }
  FDetailHostWindow.Title := ViewTable.PluralDisplayLabel;
  FDetailHostWindow.Closable := True;

  LController := TKExtControllerFactory.Instance.CreateController(FView, FDetailHostWindow);
  LController.OwnsView := False;
  LController.Config.SetObject('Sys/ServerStore', ServerStore);
  LController.Config.SetObject('Sys/MasterRecord', FMasterRecord);
  LController.Config.SetObject('Sys/ViewTable', ViewTable);
  LController.Config.SetObject('Sys/HostWindow', FDetailHostWindow);
  LController.Display;
  FDetailHostWindow.Show;
end;

initialization
  TKExtControllerRegistry.Instance.RegisterClass('Form', TKExtFormPanelController);

finalization
  TKExtControllerRegistry.Instance.UnregisterClass('Form');

end.
