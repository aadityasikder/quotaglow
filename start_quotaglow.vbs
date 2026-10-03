Option Explicit

Dim shell, fileSystem, projectDirectory, widgetScript, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

projectDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
widgetScript = fileSystem.BuildPath(projectDirectory, "desktop-widget\QuotaGlow.ps1")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & widgetScript & """"

shell.Run command, 0, False
