Function Create-VM
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]
         [string] $VMName,
         [Parameter(Mandatory=$false, Position=1)]
         [string] $IP
    )

#Creates the VM from a provided ISO & answer file, names it provided VMName
Set-Location "C:\VM_Stuff_Share\Lab"
$isoFilePath = "..\ISOs\Windows Server 2022 (20348.169.210806-2348.fe_release_svc_refresh_SERVER_EVAL_x64FRE_en-us).iso"
$answerFilePath = ".\2022_autounattend.xml"

New-Item -ItemType Directory -Path C:\Hyper-V_VMs\$VMName

$convertParams = @{
    SourcePath        = $isoFilePath
    SizeBytes         = 100GB
    Edition           = 'Windows Server 2022 Datacenter Evaluation (Desktop Experience)'
    VHDFormat         = 'VHDX'
    VHDPath           = "C:\Hyper-V_VMs\$VMName\$VMName.vhdx"
    DiskLayout        = 'UEFI'
    UnattendPath      = $answerFilePath
}

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser
. '..\Convert-WindowsImage (from PS Gallery)\Convert-WindowsImage.ps1'

Convert-WindowsImage @convertParams

New-VM -Name $VMName -Path "C:\Hyper-V_VMs\$VMName" -MemoryStartupBytes 6GB -Generation 2
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MinimumBytes 6GB -StartupBytes 6GB -MaximumBytes 8GB
Connect-VMNetworkAdapter -VMName $VMName -Name "Network Adapter" -SwitchName "Testing"
$vm = Get-Vm -Name $VMName
$vm | Add-VMHardDiskDrive -Path "C:\Hyper-V_VMs\$VMName\$VMName.vhdx"
$bootOrder = ($vm | Get-VMFirmware).Bootorder
#$bootOrder = ($vm | Get-VMBios).StartupOrder
if ($bootOrder[0].BootType -ne 'Drive') {
    $vm | Set-VMFirmware -FirstBootDevice $vm.HardDrives[0]
    #Set-VMBios $vm -StartupOrder @("IDE", "CD", "Floppy", "LegacyNetworkAdapter")
}
Start-VM -Name $VMName
}#Close the Create-VM function

Create-VM -VMName "Research-DC"           #Create the cousin domain's DC
Create-VM -VMName "Research-Client"       #Create the cousin domain's first client
Create-VM -VMName "Research-SQL"          #Create the cousin domian's MSSQL server
Create-VM -VMName "Dave-PC"               #Create the cousin domain's toe hold VM
Write-Host "Please wait, the VMs are booting up."
Start-Sleep -Seconds 180


#Create the cousin domain
Function Create-CousinDomain
{
Set-Location "C:\VM_Stuff_Share\Lab\CousinDomain"

# --- Research-DC ---

#VM's initial local admin:
[string]$userName = "Changme\Administrator"
[string]$userPassword = 'SuperSecureLocalPassword123!@#'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$InitialCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

#VM's local admin after re-naming the computer:
[string]$userName = "Research-DC\Administrator"
[string]$userPassword = 'SuperSecureLocalPassword123!@#'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$ResearchDCLocalCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

#VM's Domain Admin:
[string]$userName = "research\Administrator"
[string]$userPassword = 'SuperSecureLocalPassword123!@#'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$CousinDomainAdminCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

Invoke-Command -VMName "Research-DC" -FilePath '.\VMConfig (ResearchDC P1).ps1' -Credential $InitialCredObject   #Configs IPv4, disables IPv6, renames the VM
Start-Sleep -Seconds 120
Invoke-Command -VMName "Research-DC" -FilePath '.\VMConfig (ResearchDC P2).ps1' -Credential $ResearchDCLocalCredObject   #Makes the VM a DC in a new forest; research.local
Start-Sleep -Seconds 300 
Invoke-Command -VMName "Research-DC" -FilePath '.\VMConfig (ResearchDC P3).ps1' -Credential $CousinDomainAdminCredObject   #Creates Backup Ent Admin, users, computers, etc

#Create Dave in lab.local

#lab.local Ent Admin:
[string]$userName = "lab\Break.Glass"
[string]$userPassword = 'SuperSecureDomainPassword1234!@#$'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$ParentDomainAdminCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

#Store a password for Dave
[string]$DSRMPassword = 'PasswordReuseIsFun!'
# Convert to SecureString
[securestring]$UserPassword = ConvertTo-SecureString $DSRMPassword -AsPlainText -Force
$User = "Dave"
Invoke-Command -VMName "Lab-DC" {New-ADUser -SamAccountName $using:User -Name $using:User -UserPrincipalName "$using:User@lab.local" -AccountPassword $using:UserPassword -Enabled $true -Description "email me at dave@research.local" -PasswordNeverExpires $true} -Credential $ParentDomainAdminCredObject

#Last step; set the Administrator password

#resarch.local Ent Admin:
[string]$userName = "research\Break.Glass"
[string]$userPassword = 'ExtraSafeDomainPassword1234!@#$'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$CousinDomainAdminCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

Invoke-Command -VMName "Research-DC" {Set-ADAccountPassword -Identity "Administrator" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText 'ExtraSafeDomainPassword1234!@#$' -Force)} -Credential $CousinDomainAdminCredObject
Invoke-Command -VMName "Research-DC" -FilePath '.\VMConfig (ResearchDC P4).ps1' -Credential $CousinDomainAdminCredObject   #Configs Research.local and Lab.local to trust each other

#Enable AD CS & import an AD CS template. 'Guest Service Interface' must be enabled for Copy-VMFile to work
Enable-VMIntegrationService "Guest Service Interface" -VMName "Research-DC"
Copy-VMFile "Research-DC" -SourcePath ".\HTTPsCertificates.json" -DestinationPath "C:\HTTPsCertificates.json" -CreateFullPath -FileSource Host
Start-Sleep -Seconds 60
Invoke-Command -VMName "Research-DC" -FilePath '.\VMConfig (ResearchDC P5).ps1' -Credential $CousinDomainAdminCredObject   #Install & enables AD CS role
Invoke-Command -VMName "Research-DC" -FilePath '.\VMConfig (ResearchDC P6).ps1' -Credential $CousinDomainAdminCredObject   #Delegate MSSQL rights on Research-Client


# --- Research-Client --

#VM's local admin after re-naming the computer:
[string]$userName = "Research-Client\Administrator"
[string]$userPassword = 'SuperSecureLocalPassword123!@#'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$ResarchClientLocalCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

Invoke-Command -VMName "Research-Client" -FilePath '.\VMConfig (ResearchClient P1).ps1' -Credential $InitialCredObject   #Configs IPv4, disables IPv6, renames the VM
Start-Sleep -Seconds 120
Invoke-Command -VMName "Research-Client" -FilePath '.\VMConfig (ResearchClient P2).ps1' -Credential $ResarchClientLocalCredObject    #Joins research.local
Start-Sleep -Seconds 120
Invoke-Command -VMName "Research-DC" {setspn -S CIFS/research-client.research.local research\research-client} -Credential $CousinDomainAdminCredObject
Invoke-Command -VMName "Research-DC" {setspn -S HTTP/research-client.research.local research\research-client} -Credential $CousinDomainAdminCredObject
Invoke-Command -VMName "Research-Client" -FilePath '.\VMConfig (ResearchClient P3).ps1' -Credential $CousinDomainAdminCredObject   #Puts ADCS.Admin in scheduled tasks & local admins


# --- Dave-PC, formerly called Research-ClientII ---

#VM's local admin after re-naming the computer:
[string]$userName = "Dave-PC\Administrator"
[string]$userPassword = 'SuperSecureLocalPassword123!@#'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$DavePCLocalCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

Invoke-Command -VMName "Dave-PC" -FilePath '.\VMConfig (ResearchClientII P1).ps1' -Credential $InitialCredObject   #Configs IPv4, disables IPv6, renames the VM
Start-Sleep -Seconds 120
Invoke-Command -VMName "Dave-PC" -FilePath '.\VMConfig (ResearchClient P2).ps1' -Credential $DavePCLocalCredObject    #Joins research.local
Start-Sleep -Seconds 120
Invoke-Command -VMName "Dave-PC" -FilePath '.\VMConfig (ResearchClientII P3).ps1' -Credential $CousinDomainAdminCredObject   #Puts Dave in local admins

# --- Research-SQL ---

#VM's local admin after re-naming the computer:
[string]$userName = "Research-SQL\Administrator"
[string]$userPassword = 'SuperSecureLocalPassword123!@#'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$DavePCLocalCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

Set-Location "C:\VM_Stuff_Share\Lab\CousinDomain"
Invoke-Command -VMName "Research-SQL" -FilePath '.\VMConfig (ResearchSQL P1).ps1' -Credential $InitialCredObject  #Configs IPv4, disables IPv6, renames the VM
Start-Sleep -Seconds 120
Invoke-Command -VMName "Research-SQL" -FilePath '.\VMConfig (ResearchClient P2).ps1' -Credential $DavePCLocalCredObject    #Joins research.local
Start-Sleep -Seconds 120

Enable-VMIntegrationService "Guest Service Interface" -VMName "Research-SQL"
Copy-VMFile "Research-SQL" -SourcePath ".\SQL2022.zip" -DestinationPath "C:\SQL2022.zip" -CreateFullPath -FileSource Host

#Install PowerShell Desired State Configuration (DSC)
Invoke-Command -VMName "Research-SQL" {Install-Module -Name SqlServerDsc} -Credential $CousinDomainAdminCredObject   #Installs the Desired State Configuration module
Invoke-Command -VMName "Research-DC" -FilePath ".\Create-SQLUser.ps1" -Credential $CousinDomainAdminCredObject       #Creates users to run & manage MSSQL, gives Dave pwd reset
Invoke-Command -VMName "Research-SQL" -FilePath ".\Install-SQL.ps1" -Credential $CousinDomainAdminCredObject         #Uses DSC to setup MSSQL on Research-SQL
Invoke-Command -VMName "Research-SQL" -FilePath ".\Config-SQL.ps1" -Credential $CousinDomainAdminCredObject          #[mis]configs Research-SQL IOT put it in the escalation path

} #Close the Create-CousinDomain function

Create-CousinDomain