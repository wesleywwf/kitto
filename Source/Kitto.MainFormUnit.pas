unit Kitto.MainFormUnit;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics,
  Controls, Forms, Dialogs, ComCtrls, ToolWin, Kitto.Ext.Application,
  ActnList, Kitto.Environment, StdCtrls;

type
  TKMainForm = class(TForm)
    ToolBar1: TToolBar;
    ToolButton1: TToolButton;
    ToolButton2: TToolButton;
    ActionList: TActionList;
    StartAction: TAction;
    StopAction: TAction;
    StatusBar: TStatusBar;
    PageControl: TPageControl;
    LogTabSheet: TTabSheet;
    MonitorTabSheet: TTabSheet;
    LogMemo: TMemo;
    SessionCountLabel: TLabel;
    ToolButton3: TToolButton;
    RestartAction: TAction;
    procedure StartActionUpdate(Sender: TObject);
    procedure StopActionUpdate(Sender: TObject);
    procedure StartActionExecute(Sender: TObject);
    procedure StopActionExecute(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ActionListUpdate(Action: TBasicAction; var Handled: Boolean);
    procedure RestartActionUpdate(Sender: TObject);
    procedure RestartActionExecute(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FKAppThread: TKExtAppThread;
    FRestart: Boolean;
    function GetKAppThread: TKExtAppThread;
    procedure KAppThreadTerminated(Sender: TObject);
    procedure UpdateSessionCountlabel;
    function GetSessionCount: Integer;
    property KAppThread: TKExtAppThread read GetKAppThread;
  end;

var
  KMainForm: TKMainForm;

implementation

{$R *.dfm}

uses
  Math,
  FCGIApp;

procedure TKMainForm.KAppThreadTerminated(Sender: TObject);
begin
  FKAppThread := nil;
  StatusBar.SimpleText := 'Stopped';
  if FRestart then
  begin
    FRestart := False;
    { TODO : needed when you stop on form close, otherwise OnTerminate
      is not called. Should be done in a different way. }
    Sleep(100);
    StartActionExecute(StartAction);
  end;
end;

procedure TKMainForm.RestartActionExecute(Sender: TObject);
begin
  FRestart := True;
  StopAction.Execute;
end;

procedure TKMainForm.RestartActionUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := Assigned(FKAppThread);
end;

procedure TKMainForm.ActionListUpdate(Action: TBasicAction;
  var Handled: Boolean);
begin
  UpdateSessionCountlabel;
end;

procedure TKMainForm.UpdateSessionCountlabel;
begin
  SessionCountLabel.Caption := Format('Active Sessions: %d', [GetSessionCount]);
end;

function TKMainForm.GetSessionCount: Integer;
begin
  if Assigned(FCGIApp.Application) then
    Result := Max(0, FCGIApp.Application.ThreadsCount)
  else
    Result := 0;
end;

procedure TKMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  StopAction.Execute;
end;

procedure TKMainForm.FormShow(Sender: TObject);
begin
  StartAction.Execute;
end;

function TKMainForm.GetKAppThread: TKExtAppThread;
var
  LEnvironment: TKEnvironment;
begin
  if not Assigned(FKAppThread) then
  begin
    FKAppThread := TKExtAppThread.Create(True);
    FKAppThread.OnTerminate := KAppThreadTerminated;
    LEnvironment := TKEnvironment.Create;
    try
      FKAppThread.AppTitle := LEnvironment.AppTitle;
      FKAppThread.TCPPort := LEnvironment.Config.GetInteger('TCPPort', 2014);
      FKAppThread.SessionTimeout := LEnvironment.Config.GetInteger('SessionTimeout', 30);
      FKAppThread.FreeOnTerminate := True;
    finally
      FreeAndNil(LEnvironment);
    end;
  end;
  Result := FKAppThread;
end;

procedure TKMainForm.StartActionExecute(Sender: TObject);
begin
  KAppThread.Start;
  StatusBar.SimpleText := 'Started';
end;

procedure TKMainForm.StartActionUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := not Assigned(FKAppThread);
end;

procedure TKMainForm.StopActionExecute(Sender: TObject);
begin
  if Assigned(FKAppThread) then
  begin
    FCGIApp.Application.TerminateAllThreads;
    FKAppThread.Terminate;
    StatusBar.SimpleText := 'Stopping...';
  end;
end;

procedure TKMainForm.StopActionUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := Assigned(FKAppThread);
end;

end.
