# Registers a daily Windows scheduled task that runs streak.py.
#   .\setup_task.ps1                 -> daily at 00:00 (midnight), randomised by up to 30 min
#   .\setup_task.ps1 -Time 21:30     -> pick your own time
#   .\setup_task.ps1 -Remove         -> delete the task
param(
    [string]$Time = "00:00",
    [int]$RandomMinutes = 30,
    [switch]$Remove
)

$TaskName = "TikTok Streak"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($Remove) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed '$TaskName'."
    return
}

$action = New-ScheduledTaskAction `
    -Execute (Join-Path $Here ".venv\Scripts\pythonw.exe") `
    -Argument "`"$(Join-Path $Here 'streak.py')`"" `
    -WorkingDirectory $Here
$trigger = New-ScheduledTaskTrigger -Daily -At $Time -RandomDelay (New-TimeSpan -Minutes $RandomMinutes)
# StartWhenAvailable: if the PC was off/asleep at that time, run as soon as it's back.
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "Scheduled '$TaskName' daily at $Time (+ up to $RandomMinutes min random delay)."
