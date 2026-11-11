; 玫枫五笔 Windows 安装包（Inno Setup 6）
; 由 build.ps1 调用：ISCC /DAppVersion="x.y.z" /DSourceDir=<out/app> installer\MeifengWubi.iss
; AppVersion 必须加引号，否则 1.1.7-beta 会被预处理器当成 1.1.7 减 beta

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\out\app"
#endif
; /DAppVersion="1.1.7-beta" 时引号会进宏，文件名里不能有引号
#define AppVer RemoveQuotes(AppVersion)

[Setup]
AppId={{55C8F83B-3F8E-46AF-BFED-5B224BB9381A}
AppName=玫枫五笔
AppVersion={#AppVer}
AppPublisher=KyleBing
AppPublisherURL=https://github.com/KyleBing
DefaultDirName={autopf}\MeifengWubi
DefaultGroupName=玫枫五笔
DisableProgramGroupPage=yes
OutputDir=..\out
; 固定文件名，避免 1.1.7-beta 这类预发布号被 Inno 判为非法 OutputBaseFilename
OutputBaseFilename=MeifengWubi-setup
SetupIconFile=..\Resources\Brand\AppIcon.ico
UninstallDisplayIcon={app}\MeifengWubi.exe
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
; 文本服务 DLL 被各程序加载着，升级时可能要重启才能替换
CloseApplications=yes
RestartIfNeededByRun=no
WizardStyle=modern
; 安装失败时把日志留在 %TEMP%\Setup Log*.txt，方便排查“拒绝访问”这类问题
SetupLogging=yes

[Languages]
; 语言文件随仓库提供：Inno Setup 默认不带简体中文，只靠 {pf}\...\Languages 里的副本
; 在 CI 上会缺文件。路径相对本 .iss 所在目录。
Name: "chs"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "autostart"; Description: "登录 Windows 时在后台启动玫枫五笔（推荐）"; Flags: checkedonce

[Files]
; 服务进程被占用时改为重启后替换，而不是弹出“重试 / 跳过”
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "MeifengWubiTSF*.dll"; Flags: ignoreversion recursesubdirs createallsubdirs restartreplace uninsrestartdelete
Source: "{#SourceDir}\MeifengWubiTSF64.dll"; DestDir: "{app}"; Flags: ignoreversion regserver 64bit restartreplace uninsrestartdelete
Source: "{#SourceDir}\MeifengWubiTSF32.dll"; DestDir: "{app}"; Flags: ignoreversion regserver 32bit restartreplace uninsrestartdelete

[Icons]
Name: "{group}\玫枫五笔设置"; Filename: "{app}\MeifengWubi.exe"
Name: "{group}\卸载玫枫五笔"; Filename: "{uninstallexe}"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "MeifengWubi"; ValueData: """{app}\MeifengWubi.exe"" --background"; Tasks: autostart; Flags: uninsdeletevalue

[Run]
; 服务进程没能退出时文件要等重启才替换，这时不要拉起半新半旧的程序
Filename: "{app}\MeifengWubi.exe"; Description: "打开玫枫五笔设置"; Flags: nowait postinstall skipifsilent runasoriginaluser; Check: ShouldRunApp

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM MeifengWubi.exe"; Flags: runhidden; RunOnceId: "StopServer"

[Code]
const
  // 与 App.cs 里的 MutexName 保持一致：服务进程活着时互斥体一定存在
  ServerMutex = 'Local\MeifengWubi.Server';
  ServerExe = 'MeifengWubi.exe';
  // 框架依赖发布需要系统级 .NET 10 桌面运行时（WPF），和其它程序共用
  DotnetMajor = 10;
  DotnetDesktopUrl = 'https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe';

var
  // 服务进程始终没退出时为 True，用来跳过安装结束后的自动启动
  ServerStillRunning: Boolean;
  NeedDotNet: Boolean;
  DotnetPage: TWizardPage;
  DotnetDownloadPage: TDownloadWizardPage;

// 服务进程是否还在运行（靠它自己创建的互斥体判断，不依赖进程枚举）
function IsServerRunning: Boolean;
begin
  Result := CheckForMutexes(ServerMutex);
end;

function HasDotNetDesktop: Boolean;
var
  I, Count: Integer;
  Names: TArrayOfString;
  Key: String;
begin
  Result := False;
  Key := 'SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App';
  if not RegGetSubkeyNames(HKLM64, Key, Names) then
    Exit;
  Count := GetArrayLength(Names);
  for I := 0 to Count - 1 do
    if Pos(IntToStr(DotnetMajor) + '.', Names[I]) = 1 then
    begin
      Result := True;
      Exit;
    end;
end;

function DownloadDotNetInstaller: Boolean;
begin
  Result := False;
  if DotnetDownloadPage = nil then
    DotnetDownloadPage := CreateDownloadPage(
      '下载运行环境',
      '正在从微软官网下载 .NET ' + IntToStr(DotnetMajor) + ' 桌面运行时，请稍候，不要关闭此窗口。',
      nil);
  DotnetDownloadPage.Clear;
  DotnetDownloadPage.Add(DotnetDesktopUrl, 'windowsdesktop-runtime-win-x64.exe', '');
  DotnetDownloadPage.Show;
  try
    try
      DotnetDownloadPage.Download;
      Result := True;
    except
      if DotnetDownloadPage.AbortedByUser then
        Log('用户取消了 .NET 运行时下载')
      else
        MsgBox('下载运行环境失败。请确认电脑能上网，然后点「下一步」再试一次。安装程序会自动下载，你不需要自己去微软网站操作。', mbError, MB_OK);
    end;
  finally
    DotnetDownloadPage.Hide;
  end;
end;

function InstallDotNetDesktop(Quiet: Boolean): Boolean;
var
  ResultCode: Integer;
  Installer, Args: String;
begin
  Result := False;
  Installer := ExpandConstant('{tmp}\windowsdesktop-runtime-win-x64.exe');
  if not FileExists(Installer) then
  begin
    if Quiet then
      Exit;
    MsgBox('没有找到已下载的运行环境安装包，请点「下一步」重新下载。', mbError, MB_OK);
    Exit;
  end;
  if Quiet then
    Args := '/install /quiet /norestart'
  else
    Args := '/install /passive /norestart';
  if WizardForm <> nil then
    WizardForm.StatusLabel.Caption := '正在安装 .NET ' + IntToStr(DotnetMajor) + ' 桌面运行时，请稍候…';
  if not Exec(Installer, Args, '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
  begin
    if not Quiet then
      MsgBox('无法启动运行环境安装。请点「下一步」再试一次。', mbError, MB_OK);
    Exit;
  end;
  if (ResultCode <> 0) and (ResultCode <> 3010) then
  begin
    if not Quiet then
      MsgBox('运行环境没有装上（退出码 ' + IntToStr(ResultCode) + '）。请点「下一步」再试一次，不必自己去微软网站安装。', mbError, MB_OK);
    Exit;
  end;
  Result := HasDotNetDesktop;
  if (not Result) and (not Quiet) then
    MsgBox('运行环境安装结束后仍未检测到。请点「下一步」再试一次。', mbError, MB_OK);
end;

function InstallDotNetFromWizard: Boolean;
begin
  Result := True;
  if HasDotNetDesktop then
  begin
    NeedDotNet := False;
    Exit;
  end;
  if not DownloadDotNetInstaller then
  begin
    Result := False;
    Exit;
  end;
  if not InstallDotNetDesktop(False) then
  begin
    Result := False;
    Exit;
  end;
  NeedDotNet := False;
end;

procedure InitializeWizard;
var
  Info: TNewStaticText;
begin
  NeedDotNet := not HasDotNetDesktop;
  DotnetPage := CreateCustomPage(wpWelcome,
    '安装运行环境',
    '玫枫五笔会自动安装所需组件，你只需跟着点「下一步」。');
  Info := TNewStaticText.Create(DotnetPage);
  Info.Parent := DotnetPage.Surface;
  Info.AutoSize := False;
  Info.WordWrap := True;
  Info.Left := 0;
  Info.Top := 0;
  Info.Width := DotnetPage.SurfaceWidth;
  Info.Height := DotnetPage.SurfaceHeight;
  Info.Caption :=
    '本机还没有微软 .NET ' + IntToStr(DotnetMajor) + ' 桌面运行时，玫枫五笔需要它才能打开。' + #13#10#13#10 +
    '请直接点下面的「下一步」。安装程序会自动完成这些事，你不需要自己去微软网站查找或下载：' + #13#10#13#10 +
    '1. 从微软官网下载运行时（请保持网络畅通，窗口里会显示下载进度）' + #13#10 +
    '2. 自动安装运行时。可能会再弹出一个微软的进度窗口，出现进度条后请等待它自己完成，不要关闭、也不用再点按钮' + #13#10 +
    '3. 装好后继续安装玫枫五笔' + #13#10#13#10 +
    '全程跟着点「下一步」即可。';
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (DotnetPage <> nil) and (PageID = DotnetPage.ID) then
    Result := not NeedDotNet;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (DotnetPage <> nil) and (CurPageID = DotnetPage.ID) then
    Result := InstallDotNetFromWizard;
end;

// 安装前结束旧的服务进程：exe 被锁住时覆盖会报“错误代码 5 拒绝访问”。
// TSF 管道客户端在输入时会按需把服务重新拉起，自动更新时本进程也可能还没退干净，
// 所以最多等 10 秒，确认进程真的退出再复制文件。
procedure StopServerProcess;
var
  I, ResultCode: Integer;
  Taskkill: String;
begin
  ServerStillRunning := False;
  Taskkill := ExpandConstant('{sys}\taskkill.exe');
  for I := 1 to 20 do
  begin
    if not IsServerRunning then
      Exit;
    Log('停止服务进程 ' + ServerExe + '（第 ' + IntToStr(I) + ' 次）');
    Exec(Taskkill, '/F /IM ' + ServerExe, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(500);
  end;
  // 最后一轮 taskkill 可能刚好生效，再确认一次
  ServerStillRunning := IsServerRunning;
  // 仍没退出：交给 restartreplace 在重启后替换，不再弹“重试 / 跳过”
  if ServerStillRunning then
    Log('服务进程未能在安装前退出，文件将在重启后替换');
end;

// 安装结束是否拉起程序：文件要等重启替换时先别启动，避免新旧文件混用
function ShouldRunApp: Boolean;
begin
  Result := not ServerStillRunning;
end;

function EnsureDotNetDesktopSilent: String;
var
  ResultCode: Integer;
  Installer, ScriptFile: String;
begin
  Result := '';
  if HasDotNetDesktop then
    Exit;
  Log('静默安装：未检测到 .NET 桌面运行时，开始下载');
  Installer := ExpandConstant('{tmp}\windowsdesktop-runtime-win-x64.exe');
  if not FileExists(Installer) then
  begin
    ScriptFile := ExpandConstant('{tmp}\download-dotnet.ps1');
    SaveStringToFile(ScriptFile,
      'Invoke-WebRequest -UseBasicParsing -Uri "' + DotnetDesktopUrl + '" -OutFile "' + Installer + '"' + #13#10,
      False);
    if not Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptFile + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) or (not FileExists(Installer)) then
    begin
      Result := '自动下载运行环境失败，请检查网络后重新运行安装程序。安装程序会代为安装，不必自己去微软网站操作。';
      Exit;
    end;
  end;
  if not InstallDotNetDesktop(True) then
    Result := '自动安装运行环境失败，请重新运行安装程序再试一次。';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopServerProcess;
  Result := EnsureDotNetDesktopSilent;
end;
