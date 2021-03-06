{-------------------------------------------------------------------------------
   Copyright 2012 Ethea S.r.l.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-------------------------------------------------------------------------------}

unit Kitto.Ext.MainFormUnit;

{$I Kitto.Defines.inc}

interface

uses
  {$IF RTLVersion >= 23.0}Themes, Styles,{$IFEND}
  Windows, Messages, SysUtils, Variants, Classes, Graphics,
  Controls, Forms, Dialogs, ComCtrls, ToolWin, Kitto.Ext.Application,
  ActnList, Kitto.Config, StdCtrls, Buttons, ExtCtrls, ImgList, EF.Logger,
  Actions, Vcl.Tabs, Vcl.Grids;

type
  TKExtLogEvent = procedure (const AString: string) of object;

  TKExtMainFormLogEndpoint = class(TEFLogEndpoint)
  private
    FOnLog: TKExtLogEvent;
  protected
    procedure DoLog(const AString: string); override;
  public
    property OnLog: TKExtLogEvent read FOnLog write FOnLog;
  end;

  TKExtMainForm = class(TForm)
    ActionList: TActionList;
    StartAction: TAction;
    StopAction: TAction;
    PageControl: TPageControl;
    HomeTabSheet: TTabSheet;
    SessionCountLabel: TLabel;
    RestartAction: TAction;
    ConfigFileNameComboBox: TComboBox;
    ConfigLinkLabel: TLabel;
    StartSpeedButton: TSpeedButton;
    StopSpeedButton: TSpeedButton;
    ImageList: TImageList;
    LogMemo: TMemo;
    ControlPanel: TPanel;
    AppTitleLabel: TLabel;
    OpenConfigDialog: TOpenDialog;
    SpeedButton1: TSpeedButton;
    HomeURLLabel: TLabel;
    AppIcon: TImage;
    MainTabSet: TTabSet;
    SessionPanel: TPanel;
    SessionToolPanel: TPanel;
    Button1: TButton;
    SessionListView: TListView;
    procedure StartActionUpdate(Sender: TObject);
    procedure StopActionUpdate(Sender: TObject);
    procedure StartActionExecute(Sender: TObject);
    procedure StopActionExecute(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ActionListUpdate(Action: TBasicAction; var Handled: Boolean);
    procedure RestartActionUpdate(Sender: TObject);
    procedure RestartActionExecute(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure ConfigFileNameComboBoxChange(Sender: TObject);
    procedure ConfigLinkLabelClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure HomeURLLabelClick(Sender: TObject);
    procedure MainTabSetChange(Sender: TObject; NewTab: Integer;
      var AllowChange: Boolean);
    procedure Button1Click(Sender: TObject);
    procedure SessionListViewEdited(Sender: TObject; Item: TListItem;
      var S: string);
    procedure SessionListViewInfoTip(Sender: TObject; Item: TListItem;
      var InfoTip: string);
  private
    FAppThread: TKExtAppThread;
    FRestart: Boolean;
    FLogEndPoint: TKExtMainFormLogEndpoint;
    procedure ShowTabGUI(const AIndex: Integer);
    procedure UpdateSessionInfo;
    const
      TAB_LOG = 0;
      TAB_SESSIONS = 1;
    function IsStarted: Boolean;
    function GetAppThread: TKExtAppThread;
    procedure AppThreadTerminated(Sender: TObject);
    procedure UpdateSessionCountlabel;
    function GetSessionCount: Integer;
    procedure FillConfigFileNameCombo;
    procedure SelectConfigFile;
    procedure DisplayHomeURL(const AHomeURL: string);
    property AppThread: TKExtAppThread read GetAppThread;
    function HasConfigFileName: Boolean;
    procedure DoLog(const AString: string);
  public	
    procedure SetConfig(const AFileName: string);
  end;

var
  KExtMainForm: TKExtMainForm;

implementation

{$R *.dfm}

uses
  Math, SyncObjs,
  EF.SysUtils, EF.Shell, EF.Localization,
  FCGIApp,
  Kitto.Ext.Session;

procedure TKExtMainForm.AppThreadTerminated(Sender: TObject);
begin
  FAppThread := nil;
  DoLog(_('Listener stopped'));
  SessionCountLabel.Visible := False;
end;

procedure TKExtMainForm.Button1Click(Sender: TObject);
begin
  UpdateSessionInfo;
end;

procedure TKExtMainForm.ConfigLinkLabelClick(Sender: TObject);
begin
  SelectConfigFile;
end;

procedure TKExtMainForm.SelectConfigFile;
begin
  OpenConfigDialog.InitialDir := TKConfig.AppHomePath;
  if OpenConfigDialog.Execute then
  begin
    // The Home is the parent directory of the Metadata directory.
    TKConfig.AppHomePath := ExtractFilePath(OpenConfigDialog.FileName) + '..';
    Caption := TKConfig.AppHomePath;
    FillConfigFileNameCombo;
    SetConfig(ExtractFileName(OpenConfigDialog.FileName));
  end;
end;

procedure TKExtMainForm.SessionListViewEdited(Sender: TObject; Item: TListItem;
  var S: string);
begin
  if TObject(Item.Data) is TKExtSession then
    TKExtSession(Item.Data).DisplayName := S;
end;

procedure TKExtMainForm.SessionListViewInfoTip(Sender: TObject; Item: TListItem;
  var InfoTip: string);
begin
  if Assigned(Item) and  (TObject(Item.Data) is TKExtSession) then
  begin
    InfoTip :=
      'HTTP_USER_AGENT: ' + TKExtSession(Item.Data).RequestHeader['HTTP_USER_AGENT'] + sLineBreak +
      'SERVER_SOFTWARE: ' + TKExtSession(Item.Data).RequestHeader['SERVER_SOFTWARE'];
  end;
end;

procedure TKExtMainForm.DoLog(const AString: string);
begin
  LogMemo.Lines.Add(FormatDateTime('[yyyy-mm-dd hh:nn:ss.zzz] ', Now()) + AString);
end;

procedure TKExtMainForm.StopActionExecute(Sender: TObject);
begin
  if IsStarted then
  begin
    DoLog(_('Stopping listener...'));
    FAppThread.Terminate;
    HomeURLLabel.Visible := False;
    while IsStarted do
      Forms.Application.ProcessMessages;
    if FRestart then
    begin
      FRestart := False;
      StartAction.Execute;
    end;
  end;
  UpdateSessionInfo;
end;

procedure TKExtMainForm.StopActionUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := IsStarted;
end;

procedure TKExtMainForm.MainTabSetChange(Sender: TObject; NewTab: Integer;
  var AllowChange: Boolean);
begin
  ShowTabGUI(NewTab);
end;

procedure TKExtMainForm.ShowTabGUI(const AIndex: Integer);
begin
  case AIndex of
    TAB_LOG:
      LogMemo.BringToFront;

    TAB_SESSIONS:
    begin
      UpdateSessionInfo;
      SessionPanel.BringToFront;
    end;
  end;
end;

procedure TKExtMainForm.RestartActionExecute(Sender: TObject);
begin
  FRestart := True;
  StopAction.Execute;
end;

procedure TKExtMainForm.RestartActionUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := IsStarted;
end;

procedure TKExtMainForm.ActionListUpdate(Action: TBasicAction;
  var Handled: Boolean);
begin
  UpdateSessionCountlabel;
end;

procedure TKExtMainForm.UpdateSessionCountlabel;
begin
  SessionCountLabel.Caption := Format('Active Sessions: %d', [GetSessionCount]);
end;

procedure TKExtMainForm.UpdateSessionInfo;

  procedure AddItem(const AThreadData: TFCGIThreadData);
  var
    LItem: TListItem;
    LSession: TKExtSession;
  begin
    LItem := SessionListView.Items.Add;
    if Assigned(AThreadData.Session) and (AThreadData.Session is TKExtSession) then
    begin
      LSession := TKExtSession(AThreadData.Session);
      LItem.Data := LSession;
      LItem.Caption := LSession.DisplayName;
      // Start Time.
      LItem.SubItems.Add(DateTimeToStr(LSession.CreationDateTime));
      // Last Req.
      LItem.SubItems.Add(DateTimeToStr(LSession.LastRequestDateTime));
      // User.
      LItem.SubItems.Add(LSession.GetLoggedInUserName);
      // Origin.
      LItem.SubItems.Add(LSession.GetOrigin);
    end
    else
    begin
      LItem.Caption := _('None');
    end;
  end;

var
  I: Integer;
  LThreadData: TFCGIThreadData;
begin
  SessionListView.Clear;
  if Assigned(FCGIApp.Application) then
  begin
    FCGIApp.Application.AccessThreads.Enter;
    try
      if FCGIApp.Application.ThreadsCount <= 0 then
      begin
        LThreadData.Session := nil;
        AddItem(LThreadData);
      end
      else
      begin
        for I := 0 to FCGIApp.Application.ThreadsCount - 1 do
        begin
          LThreadData := FCGIApp.Application.GetThreadData(I);
          AddItem(LThreadData);
        end;
      end;
    finally
      FCGIApp.Application.AccessThreads.Leave;
    end;
  end
  else
  begin
    LThreadData.Session := nil;
    AddItem(LThreadData);
  end;
end;

function TKExtMainForm.GetSessionCount: Integer;
begin
  if Assigned(FCGIApp.Application) then
    Result := Max(0, FCGIApp.Application.ThreadsCount)
  else
    Result := 0;
end;

function TKExtMainForm.HasConfigFileName: Boolean;
begin
  Result := ConfigFileNameComboBox.Text <> '';
end;

procedure TKExtMainForm.HomeURLLabelClick(Sender: TObject);
begin
  OpenDocument(HomeURLLabel.Caption);
end;

function TKExtMainForm.IsStarted: Boolean;
begin
  Result := Assigned(FAppThread);
end;

procedure TKExtMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  StopAction.Execute;
  Sleep(100); // Apparently avoids a finalization problem in DBXCommon.
end;

procedure TKExtMainForm.FormCreate(Sender: TObject);
begin
  FLogEndPoint := TKExtMainFormLogEndpoint.Create;
  FLogEndPoint.OnLog := DoLog;
end;

procedure TKExtMainForm.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FLogEndPoint);
end;

procedure TKExtMainForm.FormShow(Sender: TObject);
begin
  ShowTabGUI(TAB_LOG);
  Caption := TKConfig.AppHomePath;
  DoLog(Format(_('Build date: %s'), [DateTimeToStr(GetFileDateTime(ParamStr(0)))]));
  FillConfigFileNameCombo;
  if HasConfigFileName then
    StartAction.Execute
  else
    SelectConfigFile;
end;

procedure TKExtMainForm.ConfigFileNameComboBoxChange(Sender: TObject);
begin
  SetConfig(ConfigFileNameComboBox.Text);
end;

procedure TKExtMainForm.SetConfig(const AFileName: string);
var
  LConfig: TKConfig;
  LWasStarted: Boolean;
  LAppIconFileName: string;
begin
  LWasStarted := IsStarted;
  if LWasStarted then
    StopAction.Execute;
  ConfigFileNameComboBox.ItemIndex := ConfigFileNameComboBox.Items.IndexOf(AFileName);
  TKConfig.BaseConfigFileName := AFileName;
  LConfig := TKConfig.Create;
  try
    AppTitleLabel.Caption := Format(_('Application: %s'), [_(LConfig.AppTitle)]);
    LAppIconFileName := LConfig.FindResourcePathName(LConfig.AppIcon+'.png');
    if FileExists(LAppIconFileName) then
      AppIcon.Picture.LoadFromFile(LAppIconFileName)
    else
      AppIcon.Picture.Bitmap := nil;
  finally
    FreeAndNil(LConfig);
  end;
  StartAction.Update;
  if LWasStarted then
    StartAction.Execute;
end;

procedure TKExtMainForm.DisplayHomeURL(const AHomeURL: string);
begin
  DoLog(Format(_('Home URL: %s'), [AHomeURL]));
  HomeURLLabel.Caption := AHomeURL;
  HomeURLLabel.Visible := True;
end;

procedure TKExtMainForm.FillConfigFileNameCombo;
var
  LDefaultConfig: string;
  LConfigIndex: Integer;
begin
  FindAllFiles('yaml', TKConfig.GetMetadataPath, ConfigFileNameComboBox.Items, False, False);
  if ConfigFileNameComboBox.Items.Count > 0 then
  begin
    //Read command line param -config
    LDefaultConfig := ChangeFileExt(GetCmdLineParamValue('Config', TKConfig.BaseConfigFileName),'.yaml');
    LConfigIndex := ConfigFileNameComboBox.Items.IndexOf(LDefaultConfig);
    if LConfigIndex <> -1 then
    begin
      ConfigFileNameComboBox.ItemIndex := LConfigIndex;
      ConfigFileNameComboBoxChange(ConfigFileNameComboBox);
    end
    else
    begin
      ConfigFileNameComboBox.ItemIndex := 0;
      ConfigFileNameComboBoxChange(ConfigFileNameComboBox);
    end;
  end;
end;

function TKExtMainForm.GetAppThread: TKExtAppThread;
begin
  if not Assigned(FAppThread) then
  begin
    FAppThread := TKExtAppThread.Create(True);
    FAppThread.FreeOnTerminate := True;
    FAppThread.OnTerminate := AppThreadTerminated;
    FAppThread.Configure;
  end;
  Result := FAppThread;
end;

procedure TKExtMainForm.StartActionExecute(Sender: TObject);
var
  LConfig: TKConfig;
begin
  AppThread.Start;
  SessionCountLabel.Visible := True;
  DoLog(_('Listener started'));
  LConfig := TKConfig.Create;
  try
    DisplayHomeURL(LConfig.GetHomeURL);
  finally
    FreeAndNil(LConfig);
  end;
end;

procedure TKExtMainForm.StartActionUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := HasConfigFileName and not IsStarted;
end;

{ TKExtMainFormLogEndpoint }

procedure TKExtMainFormLogEndpoint.DoLog(const AString: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AString);
end;

{$IF RTLVersion >= 23.0}
initialization
  TStyleManager.TrySetStyle('Aqua Light Slate');
{$IFEND}

end.
