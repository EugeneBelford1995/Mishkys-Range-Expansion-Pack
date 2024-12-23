#https://www.sqlservercentral.com/articles/install-sql-server-using-powershell-desired-state-configuration-dsc

#Zip the SQL2022 folder, upload it to Research-DC, Expand-Archive
#Re-work this so it runs via Invoke-Command -VMName "Research-DC" -FileName ".\Install-SQL.ps1"
#Should install SQL Server on Dave-PC at that point using research\break.glass creds

# Install PowerShell Desired State Configuration (DSC)
Install-Module -Name SqlServerDsc

#Run this part on the hypervisor to extract SQL from the ISO and then create the Zip
New-Item -Path "C:\VM_Stuff_Share\SQL2022" -ItemType Directory
$mountResult = Mount-DiskImage -ImagePath 'C:\VM_Stuff_Share\ISOs\SQLServer2022-x64-ENU.iso' -PassThru
$volumeInfo = $mountResult | Get-Volume
$driveInfo = Get-PSDrive -Name $volumeInfo.DriveLetter
Copy-Item -Path ( Join-Path -Path $driveInfo.Root -ChildPath '*' ) -Destination "C:\VM_Stuff_Share\SQL2022" -Recurse
Dismount-DiskImage -ImagePath 'C:\VM_Stuff_Share\ISOs\SQLServer2022-x64-ENU.iso'

#DSC
Configuration InstallSQLServer
{
Import-DscResource -ModuleName SqlServerDsc
   Node "Dave-PC"
    {
       WindowsFeature 'NetFramework45'
          {
                Name   = 'NET-Framework-45-Core'
                Ensure = 'Present'
          }
  
      SqlSetup SQLInstall
         {
                InstanceName = "MSSQLSERVER"
                Features = "SQLENGINE"
                SourcePath = "C:\SQL2022"
                SQLSysAdminAccounts = @("research\Administrator","research\Dave")
                DependsOn = "[WindowsFeature]NetFramework45"
}
}
}

# Compile the DSC configuration file
InstallSQLServer -OutputPath "C:\DSC"