@echo off
setlocal EnableDelayedExpansion EnableExtensions 

REM		Backup changer - HDD changer for your backups
REM		
REM		Usage: <this file name> <drive letter> <volume id> <job name> <action>
REM		where action is prebackup or postbackup
REM		For instance:
REM		<this file name> r cfe0c634-0000-0000-0000-100000000000 home prebackup
REM		
REM		Mounts plugged HDD for backup and then unmounts it. Written for 
REM		Acronis True Image. Supports multiple simultaneous backups.
REM 	First launched backup job mounts drive, any of launched - unmounts, 
REM		if last. Use mountvol to determine required volume GUID.
REM
REM		Requirements:
REM		* Sync (in path)
REM		(https://docs.microsoft.com/en-us/sysinternals/downloads/sync)
REM 	* Elevated command prompt

REM ################### Snippets section #####################################

REM Get current date and time

for /f "tokens=1-4 delims=. " %%a in ('date /t') do ^
set "bc_currdate=%%c.%%a.%%b" )
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do ^
set "bc_currtime=%%a:%%b" )

REM ################### Constants section #####################################

set "bc_msg_lockexists=INFO: Lock file exists."
set "bc_msg_lockcreated=INFO: Lock file created."
set "bc_msg_mountfailed=ERROR: Mount failed."
set "bc_msg_lockfailed=ERROR: Lock failed."
set "bc_msg_drivenotfound=WARNING: Drive letter does not exist."
set "bc_msg_guidnotfound=ERROR: GUID does not exist."
set "bc_msg_poisonedjobname=ERROR: Job name should be alphanumeric."
set "bc_msg_unkaction=ERROR: Action ^is not ^"prebackup^" or ^"postbackup^"^."

set "bc_lockfile=%1:\%~n0.%3.lock"
set "bc_anylockfile=%1:\%~n0.*.lock"

set "bc_driveletter=%1:"
set "bc_volume=\\?\Volume{%2}\
set "bc_jobname=%3"
set "bc_action=%4"
set "bc_fullscriptname=%~dpnx0"

REM ##################### Main section #######################################

:Help

if "%1"=="-h" ( set "help=1" )
if "%1"=="-help" ( set "help=1" )
if "%1"=="--help" ( set "help=1" )
if "%1"=="?" ( set "help=1" )
if "%1"=="-?" ( set "help=1" )
if "%1"=="/?" ( set "help=1" )

if not [%help%]==[] (
	if "%help%" EQU 1 (
		echo.
		echo Usage: %~n0 ^<drive letter^> ^<volume id^> ^<job name^> ^<action^>
		echo.
		echo where action is ^"prebackup^" or ^"postbackup^"
		echo.
		echo For instance:
		echo %~n0 r cfe0c634-0000-0000-0000-100000000000 homedirs prebackup
	)
	exit /b
)

:PreChecks

for /f %%a in ('mountvol ^| findstr %2 ^| find ^/c ^/v ^"^"') do ^
set "bc_guid=%%a"
if %bc_guid% EQU 0 ( echo %bc_msg_guidnotfound% & exit /b )

:PreBackup

if "%bc_action%"=="prebackup" (
	if exist %bc_driveletter% (
		if exist %bc_lockfile% ( echo %bc_msg_lockexists% & exit /b )				
		echo This file was created by %bc_fullscriptname% ^
		at %bc_currdate% %bc_currtime% > %bc_lockfile%		
		if errorlevel 1 ( echo %bc_msg_lockfailed% & exit /b )
	) else (
		call mountvol %bc_driveletter% %bc_volume%
		call :Wait 10
		if errorlevel 1 ( echo %bc_msg_mountfailed% & exit /b )
		goto :PreBackup	
	)	
exit /b
) 

:PostBackup

if "%bc_action%"=="postbackup" (
	if not exist %bc_driveletter% ( echo %bc_msg_drivenotfound% & exit /b )
	if exist %bc_lockfile% (
		del /s /q /f %bc_lockfile% > nul
	)
	if exist %bc_anylockfile% (		
		call :Wait 30
		goto :PostBackup	
	) else (	
		sync %bc_driveletter%
		call :Wait 15
		if not exist %bc_driveletter% ( echo %bc_msg_drivenotfound% & exit /b )
		mountvol %bc_driveletter% /p
		exit /b
	)	
) else (
	echo %bc_msg_unkaction%
	exit /b	
)

REM	 ################### Functions section #####################################
:Wait
timeout /t %1 > nul & exit /b