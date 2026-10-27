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
# Daily at $Time, then retried every hour until the end of the day. Runs after everyone is
# messaged exit straight away, so the retries cost nothing.
$daily = New-ScheduledTaskTrigger -Daily -At $Time -RandomDelay (New-TimeSpan -Minutes $RandomMinutes)
$daily.Repetition = (New-ScheduledTaskTrigger -Once -At $Time `
    -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Hours 23)).Repetition
# Also run as soon as you log in or unlock the PC (catches days the laptop was closed).
$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$unlockClass = Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskSessionStateChangeTrigger
$unlock = New-CimInstance -CimClass $unlockClass -ClientOnly -Property @{ StateChange = 8; UserId = $env:USERNAME }
# StartWhenAvailable: if the PC was off/asleep at that time, run as soon as it's back.
# No WakeToRun: waking a sleeping laptop often leaves it without Wi-Fi.
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($daily, $logon, $unlock) `
    -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "Scheduled '$TaskName' daily from $Time (+ up to $RandomMinutes min), retrying hourly and on login/unlock."
