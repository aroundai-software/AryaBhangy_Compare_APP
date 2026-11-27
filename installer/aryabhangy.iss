; Aryabhangy Compare 1.0.2
; Build with installer\build_setup.ps1. The staged files are in dist\stage.

#define AppVersion "1.0.2"
#define AppName "Aryabhangy Compare"
#define AppExe "aryabhangy_compare.exe"

[Setup]
AppId={{C4E8A1B2-7D35-4F19-9A60-1B2E8C7D4A91}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Arya Bhangy Motors
DefaultDirName={autopf}\Aryabhangy Compare
DefaultGroupName=Aryabhangy Compare
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=AryabhangyCompare-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Files]
Source: "..\dist\stage\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"

[Run]
Filename: "{app}\{#AppExe}"; Description: "Open {#AppName}"; Flags: nowait postinstall skipifsilent
