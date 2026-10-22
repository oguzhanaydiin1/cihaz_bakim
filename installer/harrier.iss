; Harrier Cleaner kurulum betiği (Inno Setup 6).
; GitHub Actions'ta: ISCC /DMyAppVersion=0.1.0 installer\harrier.iss
; Uygulama kullanıcı klasörüne kurulur (yönetici izni gerekmez); böylece otomatik
; güncellemeler sessizce, izin penceresi açılmadan kurulabilir.

#define MyAppName "Harrier Cleaner"
#define MyAppExe "harrier_cleaner.exe"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

[Setup]
; AppId sabit kalmalı: güncellemeler aynı kurulumun üzerine yazılır.
AppId={{8C3B2C1E-6F1A-4C55-9E2E-6B8E0A4D1F21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=OA Labs
AppPublisherURL=https://oalabs.dev/
AppSupportURL=https://oalabs.dev/
AppContact=destek@oalabs.dev
VersionInfoVersion={#MyAppVersion}
DefaultDirName={autopf}\Harrier Cleaner
DisableProgramGroupPage=yes
DisableDirPage=auto
OutputDir=..\dist
OutputBaseFilename=HarrierCleaner-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
; Normal kurulumun sonunda "Harrier Cleaner'ı başlat" kutusu
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
; Uygulama içinden yapılan sessiz güncellemeden sonra uygulamayı yeniden aç
Filename: "{app}\{#MyAppExe}"; Flags: nowait; Check: WizardSilent
