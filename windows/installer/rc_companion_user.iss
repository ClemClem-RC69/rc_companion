; RC Companion - Installateur User Windows
; Généré pour le build GitHub Actions.
; MySource et MyOutput sont fournis par le workflow via /D.

#ifndef MySource
  #error MySource is required
#endif

#ifndef MyOutput
  #error MyOutput is required
#endif

#define MyAppName "RC Companion"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "RC Companion"
#define MyAppExeName "rc_companion.exe"

[Setup]
AppId={{F2B47AE3-31D4-4E3D-9E18-1E1BFC699069}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\RC Companion
DefaultGroupName=RC Companion
DisableProgramGroupPage=yes
OutputDir={#MyOutput}
OutputBaseFilename=RC Companion User Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\runner\resources\app_icon.ico
CloseApplications=yes
RestartApplications=no
ChangesAssociations=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "{#MySource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\RC Companion"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\RC Companion"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Icônes supplémentaires :"; Flags: unchecked


[Registry]
Root: HKCR; Subkey: "rccompanion"; ValueType: string; ValueName: ""; ValueData: "URL:RC Companion Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "rccompanion"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "rccompanion\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCR; Subkey: "rccompanion\shell\open\command"; ValueType: string; ValueName: ""; ValueData: "\"{app}\{#MyAppExeName}\" \"%1\""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer RC Companion"; Flags: nowait postinstall skipifsilent
