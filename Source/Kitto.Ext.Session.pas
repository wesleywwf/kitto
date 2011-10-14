﻿unit Kitto.Ext.Session;

interface

uses
  SysUtils,
  ExtPascal, Ext,
  EF.Tree,
  Kitto.Ext.Base, Kitto.Ext.Controller, Kitto.Environment, Kitto.Metadata.Views,
  Kitto.Ext.Login;

type
  TKExtSession = class(TExtThread)
  private
    FHomeController: IKExtController;
    FEnvironment: TKEnvironment;
    FUserFormatSettings: TFormatSettings;
    FLoginWindow: TKExtLoginWindow;
    FViewHost: TExtTabPanel;
    FJSFormatSettings: TFormatSettings;
    FStatusHost: TKExtStatusBar;
    function GetEnvironment: TKEnvironment;
    procedure LoadLibraries;
    procedure DisplayHomeView;
    procedure DisplayLoginWindow;
  protected
    function BeforeHandleRequest: Boolean; override;
    procedure AfterHandleRequest; override;
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;
  public
    ///	<summary>
    ///	  A reference to the panel to be used as the main view container.
    ///	</summary>
    property ViewHost: TExtTabPanel read FViewHost write FViewHost;

    ///	<summary>
    ///	  A reference to the status bar to be used for wait messages.
    ///	</summary>
    property StatusHost: TKExtStatusBar read FStatusHost write FStatusHost;

    procedure DisplayView(const AName: string); overload;
    procedure DisplayView(const AView: TKView); overload;

    property Environment: TKEnvironment read GetEnvironment;
    procedure InitDefaultValues; override;
    procedure Home; override;

    ///	<summary>
    ///	  <para>
    ///	    Adds to the current session a style class named after AView's
    ///	    ImageName (or the specified custom AImageName) plus a '_img'
    ///	    suffix, that sets background:url to the URL of the view's image.
    ///	  </para>
    ///	  <para>
    ///	    The style class can have an optional custom prefix before the name
    ///	    and custom rules attached to it.
    ///	  </para>
    ///	</summary>
    ///	<returns>
    ///	  Returns the class name so that it can be assigned to a component's
    ///	  IconCls property.
    ///	</returns>
    function SetViewIconStyle(const AView: TKView; const AImageName: string = '';
      const ACustomPrefix: string = ''; const ACustomRules: string = ''): string;

    // Test
    function GetGCObjectCount: Integer;

    property JSFormatSettings: TFormatSettings read FJSFormatSettings;
    property UserFormatSettings: TFormatSettings read FUserFormatSettings;

    ///	<summary>Adapts a standard number format string (with , ad thousand
    ///	separator and . as decimal separator) according to the
    ///	FormatSettings.</summary>
    function AdaptExtNumberFormat(const AFormat: string): string;


    ///	<summary>Tries to read from the session a value for each child node of
    ///	ANode and interpret it according to the child's DataType. Read values
    ///	are stored in the child nodes.</summary>
    procedure GetQueryValues(const ANode: TEFNode; const AExpectJSFormat: Boolean);

    procedure Flash(const AMessage: string);
  published
    procedure Logout;
  end;

function Session: TKExtSession;

implementation

uses
  Classes, StrUtils, ActiveX, ComObj, Types,
  ExtPascalUtils, ExtForm, FCGIApp,
  EF.Intf, EF.StrUtils, EF.Localization,
  Kitto.Ext.Utils, Kitto.Auth, Kitto.Types;

function GetSessionEnvironment: TKEnvironment;
begin
  Assert(Session <> nil);

  Result := Session.Environment;
end;

function Session: TKExtSession;
begin
  Result := TKExtSession(CurrentWebSession);
end;

function TKExtSession.AdaptExtNumberFormat(const AFormat: string): string;
var
  I: Integer;
begin
  Result := AFormat;
  if UserFormatSettings.DecimalSeparator = ',' then
  begin
    for I := 1 to Length(Result) do
    begin
      if Result[I] = '.' then
        Result[I] := ','
      else if Result[I] = ',' then
        Result[I] := '.';
    end;
    Result := Result + '/i';
  end;
end;

procedure TKExtSession.AfterConstruction;
begin
  inherited;
  SetEnvironmentSingleton(@GetSessionEnvironment);
end;

function TKExtSession.GetEnvironment: TKEnvironment;
begin
  if not Assigned(FEnvironment) then
    FEnvironment := TKEnvironment.Create;
  Result := FEnvironment;
end;

type
  PGarbage = ^TGarbage;
  TGarbage = record
    Garbage    : TObject;
    Persistent : Boolean;
  end;

function TKExtSession.GetGCObjectCount: Integer;
var
  I: Integer;
  LObject: TObject;
begin
  Result := 0;
  for I := 0 to FGarbageCollector.Count - 1 do
  begin
    LObject := FGarbageCollector.Objects[I];
    if (LObject <> nil) and (PGarbage(LObject)^.Garbage <> nil) then
      Inc(Result);
  end;
end;

procedure TKExtSession.GetQueryValues(const ANode: TEFNode; const AExpectJSFormat: Boolean);
var
  I: Integer;
  LChild: TEFNode;

  function GetDateTime: TDateTime;
  begin
    if AExpectJSFormat then
      Result := JSDateToDateTime(Session.Query[LChild.Name])
    else
      Result := StrToDateTime(Session.Query[LChild.Name], UserFormatSettings);
  end;

  function GetFloat: Double;
  begin
    if AExpectJSFormat then
      Result := StrToFloat(Session.Query[LChild.Name], JSFormatSettings)
    else
      Result := StrToFloat(Session.Query[LChild.Name], UserFormatSettings);
  end;

begin
  Assert(Assigned(ANode));

  for I := 0 to ANode.ChildCount - 1 do
  begin
    LChild := ANode.Children[I];
    Assert(LChild.Name <> '');
    case LChild.DataType of
      edtUnknown, edtString: LChild.AsString := Session.Query[LChild.Name];
      edtInteger: LChild.AsInteger := Session.QueryAsInteger[LChild.Name];
      edtBoolean: LChild.AsBoolean := Session.QueryAsBoolean[LChild.Name];
      edtDate: LChild.AsDate := GetDateTime;
      edtTime: LChild.AsTime := GetDateTime;
      edtDateTime: LChild.AsDateTime := GetDateTime;
      edtCurrency: LChild.AsCurrency := GetFloat;
      edtFloat: LChild.AsFloat := GetFloat;
      edtDecimal: LChild.AsDecimal := GetFloat;
      edtObject: raise EKError.CreateFmt(_('Unsupported data type %s.'), [EFDataTypeToString(LChild.DataType)]);
    end;
  end;
end;

destructor TKExtSession.Destroy;
begin
  NilEFIntf(FHomeController);
  FreeAndNil(FEnvironment);
  inherited;
end;

procedure TKExtSession.DisplayHomeView;
var
  LHomeView: TKView;
begin
  NilEFIntf(FHomeController);

  LHomeView := Environment.Views.ViewByNode(Environment.Config.FindNode('HomeView'));
  FHomeController := TKExtControllerFactory.Instance.CreateController(LHomeView, nil);
  FHomeController.Display;
end;

procedure TKExtSession.Home;
begin
  if not IsAjax then
    LoadLibraries;

  // Try authentication with default credentials, if any, and skip login
  // window if it succeeds.
  if TKExtLoginWindow.Authenticate then
    DisplayHomeView
  else
    DisplayLoginWindow;
end;

procedure TKExtSession.DisplayLoginWindow;
begin
  FreeAndNil(FLoginWindow);
  FLoginWindow := TKExtLoginWindow.Create;
  FLoginWindow.OnLogin := DisplayHomeView;
  FLoginWindow.Show;
end;

procedure TKExtSession.Flash(const AMessage: string);
begin
  { TODO : move functionality into kitto-core.js. }
  JSCode('Ext.example.msg("' + Environment.AppTitle + '", "' + AMessage + '");');
end;

procedure TKExtSession.LoadLibraries;

  procedure SetRequiredLibrary(const ALibName: string);
  var
    LLibURL: string;
  begin
    LLibURL := Environment.GetResourceURL(IncludeTrailingPathDelimiter('js') + ALibName + '.js');
    SetLibrary(StripSuffix(LLibURL, '.js'), False, False, True);
  end;

  procedure SetOptionalLibrary(const ALibName: string);
  var
    LLibURL: string;
  begin
    LLibURL := Environment.FindResourceURL(IncludeTrailingPathDelimiter('js') + ALibName + '.js');
    if LLibURL <> '' then
      SetLibrary(StripSuffix(LLibURL, '.js'), False, False, True);
  end;

var
  LLibraries: TStringDynArray;
  LLibName: string;
begin
  SetLibrary(ExtPath + '/examples/ux/statusbar/StatusBar');
  SetCSS(ExtPath + '/examples/ux/statusbar/css/statusbar');
  SetLibrary(ExtPath + '/examples/shared/examples'); // For Ext.msg.
  SetLibrary(ExtPath + '/src/locale/ext-lang-' + Language);
  SetRequiredLibrary('DateTimeField');
  SetRequiredLibrary('DefaultButton');
  SetRequiredLibrary('kitto-core');
  SetOptionalLibrary('application');

  LLibraries := Environment.Config.GetStringArray('JavaScriptLibraries');
  for LLibName in LLibraries do
    SetRequiredLibrary(LLibName);
end;

procedure TKExtSession.Logout;
begin
  Environment.Authenticator.Logout;
  Home;
end;

procedure TKExtSession.DisplayView(const AName: string);
begin
  Assert(AName <> '');

  DisplayView(Environment.Views.ViewByName(AName));
end;

procedure TKExtSession.DisplayView(const AView: TKView);
var
  LController: IKExtController;
begin
  Assert(Assigned(AView));
  Assert(Assigned(FViewHost));

  LController := TKExtControllerFactory.Instance.CreateController(AView, FViewHost);
  LController.Display;
  FViewHost.SetActiveTab(FViewHost.Items.Count - 1);
  if Assigned(FStatusHost) then
    FStatusHost.ClearStatus;
end;

procedure TKExtSession.InitDefaultValues;
var
  LLanguageId: string;
begin
  inherited;
  ExtPath := Environment.Config.GetString('Ext/URL', '/ext');
  Charset := Environment.Config.GetString('Charset', 'utf-8');
  LLanguageId := Environment.Config.GetString('LanguageId');
  if LLanguageId <> '' then
    Language := LLanguageId;
  FUserFormatSettings := TFormatSettings.Create;
  FUserFormatSettings.ShortTimeFormat := 'hh:mm:ss';
  { TODO : read default format settings from environment and allow to change them on a per-user basis. }

  FJSFormatSettings := TFormatSettings.Create;
  FJSFormatSettings := TFormatSettings.Create;
  FJSFormatSettings.DecimalSeparator := '.';
  FJSFormatSettings.ShortDateFormat := 'yyyy/mm/dd';
  FJSFormatSettings.ShortTimeFormat := 'hh:mm:ss';

  Theme := Environment.Config.GetString('Ext/Theme');
end;

procedure TKExtSession.AfterHandleRequest;
begin
  inherited;
  { TODO : only do this when ADO is used }
  CoUninitialize;
end;

function TKExtSession.BeforeHandleRequest: Boolean;
begin
  { TODO : only do this when ADO is used }
  OleCheck(CoInitialize(nil));
  Result := inherited BeforeHandleRequest;
end;

function TKExtSession.SetViewIconStyle(const AView: TKView; const AImageName: string;
  const ACustomPrefix: string; const ACustomRules: string): string;
var
  LIconURL: string;
  LRule: string;
begin
  Assert(Assigned(AView));

  Result := IfThen(AImageName <> '', AImageName, AView.ImageName);
  LIconURL := Environment.GetImageURL(Result);
  Result := ACustomPrefix + Result + '_img';
  // The !important rule allows to use a non-specific selector, so that the icon
  // can be shared by different components.
  // no-repeat is added because some components (such as buttons) repeat by default
  // (others, such as menu items and tree nodes, don't).
  LRule := '.' + Result + ' {background: url(' + LIconURL + ') no-repeat left !important;' + ACustomRules + '}';
  if IsAjax then
    JSCode('addStyleRule("' + LRule + '", 0);')
  else
    SetStyle(LRule);
end;

initialization

finalization
  SetEnvironmentSingleton(nil);

end.

