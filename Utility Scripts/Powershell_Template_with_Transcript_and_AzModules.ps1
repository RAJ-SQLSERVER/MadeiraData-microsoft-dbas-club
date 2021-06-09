# when creating a scheduled task to run such scripts, use the following structure example:
# powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Madeira\Powershell_Template_with_Transcript.ps1"
Param
(
 ## Specify the relevant subscription Name.
 [Parameter(Mandatory=$false,
 HelpMessage="Enter the Name of the relevant Subscription")]
 [string]
 $SubscriptionName = "Visual Studio MPN",
[string]$logFileFolderPath = "C:\Madeira\log",
[string]$logFilePrefix = "my_ps_script_",
[string]$logFileDateFormat = "yyyyMMdd_HHmmss",
[int]$logFileRetentionDays = 30
)
Process {
#region initialization
function Get-TimeStamp {
    Param(
    [switch]$NoWrap,
    [switch]$Utc
    )
    $dt = Get-Date
    if ($Utc -eq $true) {
        $dt = $dt.ToUniversalTime()
    }
    $str = "{0:MM/dd/yy} {0:HH:mm:ss}" -f $dt

    if ($NoWrap -ne $true) {
        $str = "[$str]"
    }
    return $str
}

if ($logFileFolderPath -ne "")
{
    if (!(Test-Path -PathType Container -Path $logFileFolderPath)) {
        Write-Output "$(Get-TimeStamp) Creating directory $logFileFolderPath" | Out-Null
        New-Item -ItemType Directory -Force -Path $logFileFolderPath | Out-Null
    } else {
        $DatetoDelete = $(Get-Date).AddDays(-$logFileRetentionDays)
        Get-ChildItem $logFileFolderPath | Where-Object { $_.Name -like "*$logFilePrefix*" -and $_.LastWriteTime -lt $DatetoDelete } | Remove-Item | Out-Null
    }
    
    $logFilePath = $logFileFolderPath + "\$logFilePrefix" + (Get-Date -Format $logFileDateFormat) + ".LOG"

    # attempt to start the transcript log, but don't fail the script if unsuccessful:
    try 
    {
        Start-Transcript -Path $logFilePath -Append
    }
    catch [Exception]
    {
        Write-Warning "$(Get-TimeStamp) Unable to start Transcript: $($_.Exception.Message)"
        $logFileFolderPath = ""
    }
}
#endregion initialization


#region install-modules

## Uninstall deprecated AzureRm modules
if (Get-Module -ListAvailable -Name "AzureRm*") {
    Write-Verbose "$(Get-TimeStamp) AzureRm module found. Uninstalling..."

    Get-Module -ListAvailable -Name "AzureRm*" | foreach {
        Write-Output "$(Get-TimeStamp) Uninstalling: $_"
        Remove-Module $_ -Force -Confirm:$false | Out-Null
        Uninstall-Module $_ -AllVersions -Force -Confirm:$false | Out-Null
    }
}

## Install the modules that you need from the PowerShell Gallery

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (Get-PSRepository -Name "PSGallery") {
    Write-Verbose "$(Get-TimeStamp) PSGallery already registered"
} 
else {
    Write-Information "$(Get-TimeStamp) Registering PSGallery"
    Register-PSRepository -Default
}

## you can add or remove additional modules here as needed
$modules = @("Az.Accounts", "Az.Compute", "Az.Sql", "dbatools")
        
foreach ($module in $modules) {
    if (Get-Module -ListAvailable -Name $module) {
        Write-Verbose "$(Get-TimeStamp) $module already installed"
    } 
    else {
        Write-Information "$(Get-TimeStamp) Installing $module"
        Install-Module $module -Force -SkipPublisherCheck -Scope CurrentUser -ErrorAction Stop | Out-Null
        Import-Module $module -Force -Scope Local | Out-Null
    }
}
#endregion install-modules


#region azure-logon

## Log into Azure if you aren't already logged in. Unfortunately there
## appears to be a problem using regular MS accounts as credentials for
## Login-AzAccount so you have to go through the pop-up window & log in manually.
$needLogin = $true
Try 
{
    $content = Get-AzContext
    if ($content) 
    {
        $needLogin = ([string]::IsNullOrEmpty($content.Account))
    } 
} 
Catch 
{
    if ($_ -like "*Connect-AzAccount to login*") 
    {
        $needLogin = $true
    } 
    else 
    {
        throw
    }
}

if ($needLogin)
{
    Connect-AzAccount -Subscription $SubscriptionName | Out-Null
}

## Switch to the correct directory and subscription

Get-AzSubscription | Where-Object {$_.Name -eq $SubscriptionName} | ForEach-Object {
    Write-Output "$(Get-TimeStamp) Switching to subscription '$($_.Name)' in TenantId '$($_.TenantId)'"
    $SubscriptionId = $_.Id
    Connect-AzAccount -Subscription $SubscriptionName -Tenant $_.TenantId | Out-Null
}

if ($SubscriptionId -eq "" -or $SubscriptionId -eq $null)
{
    Stop-PSFFunction -Message "$(Get-TimeStamp) No suitable subscription found" -Category InvalidArgument
}

#endregion azure-logon


#region main



# TODO: Replace this code with your actual script body:

Write-Output "$(Get-TimeStamp) Example output message. Check out the timestamp on this bad boy."

# When using Invoke-Sqlcmd, be sure to add parameters -OutputSqlErrors $true -Verbose to capture all output. For example:
Invoke-Sqlcmd -Server "." -Database "master" -Query "PRINT 'This is the output of a SQL command, generated by: ' + PROGRAM_NAME() + ' on server ' + @@SERVERNAME" -QueryTimeout 0 -OutputSqlErrors $true -Verbose



#endregion main


#region finalization
if ($logFileFolderPath -ne "") { Stop-Transcript }
#endregion finalization
}