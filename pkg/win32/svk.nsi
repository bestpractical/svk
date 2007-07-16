SetCompressor bzip2

!define MUI_COMPANY "Best Practical Solutions, LLC"
!define MUI_PRODUCT "SVK"
!ifndef MUI_VERSION
!define MUI_VERSION "unknown"
!endif
!define MUI_NAME    "svk"
!define MUI_ICON "${MUI_NAME}.ico"
!define MUI_UNICON "${MUI_NAME}-uninstall.ico"

!include "MUI.nsh"
!include "Path.nsh"

!include "Library.nsh"

XPStyle On
Name "${MUI_PRODUCT}"
OutFile "..\${MUI_NAME}-${MUI_VERSION}.exe"
InstallDir "$PROGRAMFILES\${MUI_NAME}"
ShowInstDetails hide
InstProgressFlags smooth

  !define MUI_ABORTWARNING

;--------------------------------
;Pages

  !insertmacro MUI_PAGE_LICENSE "..\ARTISTIC"
  !insertmacro MUI_PAGE_DIRECTORY
  !insertmacro MUI_PAGE_INSTFILES
  
  !insertmacro MUI_UNPAGE_CONFIRM
  !insertmacro MUI_UNPAGE_INSTFILES
  !insertmacro MUI_LANGUAGE "English"

Section "modern.exe" SecCopyUI
    WriteRegStr HKLM \
		"SOFTWARE\${MUI_COMPANY}\${MUI_PRODUCT}" "" "$INSTDIR"
    SetOverwrite on
    SetOutPath $INSTDIR
    File /r ..\bin
    File /r ..\lib
    File /r /x checkout ..\site
    File /r ..\win32

    Delete "$INSTDIR\svk.bat"

    ; Generate bootstrap batch file on the fly using $INSTDIR
    FileOpen $1 "$INSTDIR\bin\svk.bat" w
    FileWrite $1 "@echo off$\n"
    FileWrite $1 "if $\"%OS%$\" == $\"Windows_NT$\" goto WinNT$\n"
    FileWrite $1 "$\"$INSTDIR\bin\perl.exe$\" $\"$INSTDIR\bin\svk$\" %1 %2 %3 %4 %5 %6 %7 %8 %9$\n"
    FileWrite $1 "goto endofsvk$\n"
    FileWrite $1 ":WinNT$\n"
    FileWrite $1 "$\"%~dp0perl.exe$\" $\"%~dp0svk$\" %*$\n"
    FileWrite $1 "if NOT $\"%COMSPEC%$\" == $\"%SystemRoot%\system32\cmd.exe$\" goto endofperl$\n"
    FileWrite $1 "if %errorlevel% == 9009 echo You do not have Perl in your PATH.$\n"
    FileWrite $1 "if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul$\n"
    FileWrite $1 ":endofperl$\n"
    FileClose $1

    WriteUninstaller "$INSTDIR\Uninstall.exe"

Libeay32:
    IfFileExists "$SYSDIR\libeay32.dll" RenameLibeay32 SSLeay32
RenameLibeay32:
    Rename "$SYSDIR\libeay32.dll" "$SYSDIR\libeay32.dll.old"

SSLeay32:
    IfFileExists "$SYSDIR\ssleay32.dll" RenameSSLeay32 Done
RenameSSLeay32:
    Rename "$SYSDIR\ssleay32.dll" "$SYSDIR\ssleay32.dll.old"


Done:
    ; Add \bin directory to the PATH for svk.bat and DLLs
    Push "$INSTDIR\bin"
    Call AddToPath
SectionEnd
 
Section "Uninstall"
  Push $INSTDIR
  Call un.RemoveFromPath
  RMDir /r $INSTDIR
  DeleteRegKey HKLM "SOFTWARE\${MUI_COMPANY}\${MUI_PRODUCT}"
SectionEnd
