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

Create-VM -VMName "Research-Test"           #Create the cousin domain's testing VM
Write-Host "Please wait, the VM is booting up."
Start-Sleep -Seconds 180
Set-Location C:\VM_Stuff_Share\Lab\CousinDomain

#VM's initial local admin:
[string]$userName = "Changme\Administrator"
[string]$userPassword = 'SuperSecureLocalPassword123!@#'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$InitialCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

#VM's local admin after re-naming the computer:
[string]$userName = "Research-Test\Administrator"
[string]$userPassword = 'SuperSecureLocalPassword123!@#'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$ResearchTestLocalCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

#resarch.local Ent Admin:
[string]$userName = "research\Break.Glass"
[string]$userPassword = 'ExtraSafeDomainPassword1234!@#$'
# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force
[pscredential]$CousinDomainAdminCredObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

#Create the AD account for Research-Test
Invoke-Command -VMName "Research-DC" {$ADRoot = (Get-ADDomain).DistinguishedName ; New-ADComputer -Name "Research-Test" -SAMAccountName "Research-Test" -DisplayName "Research-Test" -Path "ou=PlaceHolder,$ADRoot"} -Credential $CousinDomainAdminCredObject

# --- Network config ---

$NIC = Invoke-Command -VMName "Research-DC" {(Get-NetIPConfiguration).InterfaceAlias} -Credential $CousinDomainAdminCredObject
$DC_GW = Invoke-Command -VMName "Research-DC" {(Get-NetIPConfiguration -InterfaceAlias (Get-NetAdapter).InterfaceAlias).IPv4DefaultGateway.NextHop} -Credential $CousinDomainAdminCredObject
$DC_IP = Invoke-Command -VMName "Research-DC" {(Get-NetIPAddress | Where-Object {$_.InterfaceAlias -eq"$using:NIC"}).IPAddress} -Credential $CousinDomainAdminCredObject
$DC_Prefix = Invoke-Command -VMName "Research-DC" {(Get-NetIPAddress | Where-Object {$_.InterfaceAlias -eq"$using:NIC"}).PrefixLength} -Credential $CousinDomainAdminCredObject

$FirstOctet =  $DC_IP.Split("\.")[0]
$SecondOctet = $DC_IP.Split("\.")[1]
$ThirdOctet = $DC_IP.Split("\.")[2]
$NetworkPortion = "$FirstOctet.$SecondOctet.$ThirdOctet"
$Gateway = $DC_GW
#$NIC = (Get-NetAdapter).InterfaceAlias
$IP = "$NetworkPortion.149"

#Set IPv4 address, gateway, & DNS servers
Invoke-Command -VMName "Research-Test" {$NIC = (Get-NetAdapter).InterfaceAlias ; New-NetIPAddress -InterfaceAlias $NIC -AddressFamily IPv4 -IPAddress $using:IP -PrefixLength $using:DC_Prefix -DefaultGateway $using:Gateway} -Credential $InitialCredObject
Invoke-Command -VMName "Research-Test" {$NIC = (Get-NetAdapter).InterfaceAlias ; Set-DNSClientServerAddress -InterfaceAlias $NIC -ServerAddresses ("$using:NetworkPortion.145", "$using:NetworkPortion.141", "$using:NetworkPortion.140", "1.1.1.1", "8.8.8.8")} -Credential $InitialCredObject
Invoke-Command -VMName "Research-Test" -FilePath '.\01 Test Network Config.ps1' -Credential $InitialCredObject
Start-Sleep -Seconds 120
Invoke-Command -VMName "Research-Test" -FilePath '.\VMConfig (ResearchClient P2).ps1' -Credential $ResearchTestLocalCredObject    #Joins research.local
Start-Sleep -Seconds 120

#Create a 02 Test VM Config and store credentials in credman and LSA
Enable-VMIntegrationService "Guest Service Interface" -VMName "Research-Test"
Copy-VMFile "Research-Test" -SourcePath "..\..\Modules\CredentialManager.zip" -DestinationPath "C:\CredentialManager.zip" -CreateFullPath -FileSource Host
Invoke-Command -VMName "Research-Test" {New-Item -Path "C:\" -Name "Scripts" -ItemType "Directory"} -Credential $CousinDomainAdminCredObject
Copy-VMFile "Research-Test" -SourcePath '..\Generate-TrafficII.ps1' -DestinationPath 'C:\Scripts\Generate-TrafficII.ps1' -CreateFullPath -FileSource Host
Start-Sleep -Seconds 60

Invoke-Command -VMName "Research-Test" -FilePath '.\02 Test VM Config.ps1' -Credential $CousinDomainAdminCredObject