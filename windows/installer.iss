#define AppName "AstraMusic"
#define AppVersion "1.1.0"
#define AppPublisher "AstraMusic Team"
#define AppExeName "astramusic.exe"

[Setup]
AppId={{C74BB16D-A0F7-47E2-8D26-7B37A24E68C0}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\AstraMusic
DefaultGroupName=AstraMusic
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir=..\build\windows\installer
OutputBaseFilename=AstraMusic-Setup-{#AppVersion}
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\AstraMusic"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\AstraMusic"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon
