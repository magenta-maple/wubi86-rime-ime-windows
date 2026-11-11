; 玫枫五笔 Windows 安装包（Inno Setup 6）
; 由 build.ps1 先写出 out/version.iss（字符串宏），再：ISCC /DSourceDir=<out/app> installer\MeifengWubi.iss

#ifndef AppVersion
  #include "..\out\version.iss"
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\out\app"
#endif

[Setup]
AppId={{55C8F83B-3F8E-46AF-BFED-5B224BB9381A}
AppName=玫枫五笔
AppVersion={#AppVersion}
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
  DotnetDownloadPage: TDownloadWizardPage;

// 服务进程是否还在运行（靠它自己创建的互斥体判断，不依赖进程枚举）
function IsServerRunning: Boolean;
begin
  Result := CheckForMutexes(ServerMutex);
end;

function IsDotNet10Name(const Name: String): Boolean;
begin
  Result := (Length(Name) > 0) and (Name[1] <> '.') and
    (Pos(IntToStr(DotnetMajor) + '.', Name) = 1);
end;

function DotnetRoot: String;
begin
  Result := ExpandConstant('{pf64}\dotnet');
  if not DirExists(Result) then
    Result := ExpandConstant('{pf}\dotnet');
end;

function DirHasDotNet10Dll(const Dir, DllName: String): Boolean;
var
  FindRec: TFindRec;
begin
  Result := False;
  if not DirExists(Dir) then
    Exit;
  if FindFirst(Dir + '\10.*', FindRec) then
  try
    repeat
      if ((FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) and
         IsDotNet10Name(FindRec.Name) and
         FileExists(Dir + '\' + FindRec.Name + '\' + DllName) then
      begin
        Result := True;
        Exit;
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

// 必须同时有 hostfxr、核心运行时、WPF 桌面运行时，缺一不可（只看注册表会误判）
function HasDotNetDesktop: Boolean;
var
  Root: String;
begin
  Root := DotnetRoot;
  Result :=
    DirHasDotNet10Dll(Root + '\host\fxr', 'hostfxr.dll') and
    DirHasDotNet10Dll(Root + '\shared\Microsoft.NETCore.App', 'coreclr.dll') and
    DirHasDotNet10Dll(Root + '\shared\Microsoft.WindowsDesktop.App', 'WindowsBase.dll');
end;

function WaitForDotNetDesktop: Boolean;
var
  I: Integer;
begin
  for I := 1 to 15 do
  begin
    Result := HasDotNetDesktop;
    if Result then
      Exit;
    Sleep(400);
  end;
  Result := False;
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
        Log('下载 .NET 桌面运行时失败');
    end;
  finally
    DotnetDownloadPage.Hide;
  end;
end;

function InstallDotNetDesktop: Boolean;
var
  ResultCode: Integer;
  Installer: String;
begin
  Result := False;
  Installer := ExpandConstant('{tmp}\windowsdesktop-runtime-win-x64.exe');
  if not FileExists(Installer) then
    Exit;
  if WizardForm <> nil then
    WizardForm.StatusLabel.Caption := '正在安装 .NET ' + IntToStr(DotnetMajor) + ' 桌面运行时，请稍候…';
  if not Exec(Installer, '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Exit;
  if (ResultCode <> 0) and (ResultCode <> 3010) then
  begin
    Log('.NET 桌面运行时安装失败，退出码 ' + IntToStr(ResultCode));
    Exit;
  end;
  Result := WaitForDotNetDesktop;
end;

function EnsureDotNetDesktopNow: Boolean;
var
  Installer: String;
begin
  Result := HasDotNetDesktop;
  if Result then
    Exit;
  Log('未检测到完整的 .NET 10 桌面运行时，开始下载安装');
  Installer := ExpandConstant('{tmp}\windowsdesktop-runtime-win-x64.exe');
  if not FileExists(Installer) or (FileSize(Installer) < 1000000) then
  begin
    if not DownloadDotNetInstaller then
      Exit;
    if not FileExists(Installer) or (FileSize(Installer) < 1000000) then
    begin
      Log('下载的运行时安装包无效');
      Exit;
    end;
  end;
  if not InstallDotNetDesktop then
    Exit;
  Result := HasDotNetDesktop;
end;

procedure InitializeWizard;
begin
  WizardForm.WelcomeLabel2.Caption :=
    WizardForm.WelcomeLabel2.Caption + #13#10#13#10 +
    '点「下一步」后，若本机还没有微软 .NET 10 桌面运行时，会先自动下载并安装，装好后再继续安装玫枫五笔。请保持网络畅通，不要关闭窗口。';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  // 欢迎页点下一步：先把运行时装好，成功后才进入输入法安装步骤
  if CurPageID = wpWelcome then
  begin
    if HasDotNetDesktop then
      Exit;
    Result := EnsureDotNetDesktopNow;
    if not Result then
      MsgBox('需要先安装微软 .NET ' + IntToStr(DotnetMajor) + ' 桌面运行时才能安装玫枫五笔。请保持网络畅通，不要关闭窗口，然后再次点「下一步」。安装程序会自动下载，你不必自己去微软网站。', mbError, MB_OK);
  end;
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
  Result := (not ServerStillRunning) and HasDotNetDesktop;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopServerProcess;
  Result := '';
  if HasDotNetDesktop then
    Exit;
  if not EnsureDotNetDesktopNow then
    Result := '还没有装好 .NET ' + IntToStr(DotnetMajor) + ' 桌面运行时，不能安装玫枫五笔。请保持网络畅通后重新运行本安装程序。';
end;
