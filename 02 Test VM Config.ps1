#Map the HackMe share drive to Z as The Adminstrator, aka SID 500 on marvel.local
[string]$userName = 'research\ADCS.Admin'
[string]$userPassword = 'SuperSecretCertPassword12!@'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$ADCSAdminCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

#Map the HackMe share drive to Z as The Adminstrator, aka SID 500 on marvel.local
[string]$userName = 'research\SQL.Admin'
[string]$userPassword = 'NoOneWillEverGuessThis1234!@#$'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$SQLAdminCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)


Expand-Archive "C:\CredentialManager.zip" -DestinationPath "C:\CredentialManager"
Copy-Item -Path "C:\CredentialManager" -Destination "C:\Program Files\WindowsPowerShell\Modules" -Recurse
Import-Module -Name CredentialManager
#Install-Module -Name CredentialManager -Confirm -Force -SkipPublisherCheck
New-StoredCredential -Comment "Access share drive on Research-DC" -Credentials $ADCSAdminCredObject -Target "Research-DC" -Persist Enterprise | Out-Null
New-StoredCredential -Comment "This should show up in credman" -Credentials $SQLAdminCredObject -Target "Research-DC" -Persist Enterprise | Out-Null

$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskAction = New-ScheduledTaskAction -Execute "PowerShell" -Argument "C:\Scripts\Generate-TrafficII.ps1"
Register-ScheduledTask 'Fat Finger the Share name' -Action $taskAction -Trigger $taskTrigger -User "research\ADCS.Admin" -Password 'SuperSecretCertPassword12!@' -RunLevel Highest

$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskAction = New-ScheduledTaskAction -Execute "PowerShell" -Argument "C:\Scripts\Generate-TrafficII.ps1"
Register-ScheduledTask 'Fat Finger the Share name, again' -Action $taskAction -Trigger $taskTrigger -User "research\MSSQL" -Password 'SuperSafeLogin1234!@#$' -RunLevel Highest

#Create a service to run as Break.Glass
[string]$userName = "research\Break.Glass"
[string]$userPassword = 'ExtraSafeDomainPassword1234!@#$'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$CousinDomainAdminCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

New-Service -Name "Testing Service" -BinaryPathName 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -DisplayName "Testing Service" -StartupType Automatic -Credential $CousinDomainAdminCredObject
#"Write-Host 'This service does not actually do anything.' ; Start-Sleep -Seconds 60"

#Last step, change the local admin's password
[string]$DSRMPassword = 'ForTestingOnly1234!@#$'
# Convert to SecureString
[securestring]$SecureStringPassword = ConvertTo-SecureString $DSRMPassword -AsPlainText -Force

Set-LocalUser -Name Administrator -Password $SecureStringPassword

#Restart-Computer -Force