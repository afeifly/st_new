[Setup]
AppName=CSD Viewer
AppVersion=1.0.0
DefaultDirName={pf}\CSD Viewer
DefaultGroupName=CSD Viewer
OutputDir=.\output
OutputBaseFilename=CSDViewerSetup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64

[Files]
; Main executable (rename st_new.exe to csdviewer.exe)
Source: "build\windows\x64\runner\Release\st_new.exe"; DestDir: "{app}"; DestName: "csdviewer.exe"; Flags: ignoreversion

; Flutter Windows DLL
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion

; Data folder and its contents (recursively)
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Create a Start Menu shortcut
Name: "{group}\CSD Viewer"; Filename: "{app}\csdviewer.exe"

[Run]
; Optionally run the application after installation
Filename: "{app}\csdviewer.exe"; Description: "Launch CSD Viewer"; Flags: nowait postinstall skipifsilent
