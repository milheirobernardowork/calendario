; Instalador do WolfCal para Windows (Inno Setup 6).
; O AppId é fixo: instalar uma versão nova por cima atualiza a existente,
; mantendo os dados e a sessão do utilizador.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8F3B6C1E-5A47-4C0B-9B7E-2D1A6E4F9C31}
AppName=WolfCal
AppVersion={#AppVersion}
AppPublisher=WolfCal
DefaultDirName={autopf}\WolfCal
DisableProgramGroupPage=yes
DisableDirPage=auto
; Instala só para o utilizador atual: não pede permissões de administrador.
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=WolfCal-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\wolfcal.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Ao atualizar, fecha a app se estiver aberta.
CloseApplications=yes
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Remove recursos da versão anterior que já não existam na nova.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\WolfCal"; Filename: "{app}\wolfcal.exe"
Name: "{autodesktop}\WolfCal"; Filename: "{app}\wolfcal.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\wolfcal.exe"; Description: "{cm:LaunchProgram,WolfCal}"; Flags: nowait postinstall skipifsilent
