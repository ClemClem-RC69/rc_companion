; RC Companion - Installateur bêta Windows
; Généré pour le build GitHub Actions.
; MySource et MyOutput sont fournis par le workflow via /D.

#ifndef MySource
  #error MySource is required
#endif

#ifndef MyOutput
  #error MyOutput is required
#endif

#define MyAppName "RC Companion"
#define MyAppVersion "1.0.0 Beta"
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
OutputBaseFilename=RC Companion Beta Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=windows\runner\resources\app_icon.ico
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "{#MySource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\RC Companion"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\RC Companion"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Icônes supplémentaires :"; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer RC Companion"; Flags: nowait postinstall skipifsilent
