######################################################
#                                                    #
# Environment-specific settings                      #
# Change these as necessary                          #
#                                                    #
# The default configuration below will work after    #
# Foundation if no changes have been made            #
#                                                    #
# You will almost definitely have to change the      #
# $vcServer IP address ...                           #
#                                                    #
######################################################

# vCenter IP address and credentials
# Script default is vCenter default i.e. "root" and "vmware"

$vcServer = Read-Host -Prompt 'Enter vCenter IP address or hostname: '
#$vcUser = Read-Host -Prompt 'Enter vCenter username: '
#$vcPassword = Read-Host -Prompt 'Enter vCenter user password: ' -AsSecureString
#$vcServer = '10.216.201.50'
$vcUser = "root"
$vcPassword = "nutanix/4u"

# ESX credentials

#$esxUser = Read-Host -Prompt 'Enter ESXi server username: '
#$esxPassword = Read-Host -Prompt 'Enter ESXi server user password: ' -AsSecureString
$esxUser = "root"
$esxPassword = "nutanix/4u"

# vSphere Datacenter and Cluster names

$dcName = Read-Host -Prompt 'Enter vCenter Datacenter name: '
$clusterName = Read-Host -Prompt 'Enter vCenter Cluster name: '
#$dcName = "dc"
#$clusterName = "cls"

# DNS server address

$dnsIP = Read-Host -Prompt 'Enter DNS server IP address: '
#$dnsIP = "146.197.251.237"

<#
# The NTP servers below will be *removed* from the VM Hosts

$ntpServersToRemove = @( "10.10.10.230", "0.north-america.pool.ntp.org", "1.north-america.pool.ntp.org", "2.north-america.pool.ntp.org", "3.north-america.pool.ntp.org" )

# The NTP servers below will be added to the VM hosts

$ntpServersToAdd = @("10.10.10.230")
#>

# Default gateway and DNS domain name to apply to the hosts

$gwIP = Read-Host -Prompt 'Enter default gateway IP address: '
$domain = Read-Host -Prompt 'Enter domain name to apply to ESXi servers: '
#$gwIP = "10.216.201.1"
#$domain = "local.local"

######################################################
#                                                    #
# These percentages will work for a 3 host cluster   #
# They should be calculated properly to avoid        #
# your cluster's HA configuration being incorrect    #
#                                                    #
######################################################

$HACPUPercent = Read-Host -Prompt 'Enter vSphere cluster HA Admidmission Control CPU resource reservation percentage (number 1-100): '
$HAMemPercent = Read-Host -Prompt 'Enter vSphere cluster HA Admidmission Control Memory resource reservation percentage (number 1-100): '

# These advanced settings will all be set to true
# Note that das.ignoreRedundantNetWarning is set because many Nutanix SE blocks are connected with single 1GbE only during demos (e.g. mine)

$advancedSettings = @("das.ignoreRedundantNetWarning", "das.ignoreInsufficientHbDatastore")

# List of servers to add to the new vCenter cluster

$servers = (Read-Host "Enter ESXi servers to add to vCenter cluster (separate with comma)").split(',') | % {$_.trim()}


######################################################
#                                                    #
# You shouldn't have to edit anything below here ... #
#                                                    #
######################################################

# Connect to the vCenter server

Connect-VIServer $vcServer -Protocol https -User $vcUser -Password $vcPassword

# Create top-level folder and DC, if they doesn't already exist

$dc = Get-Datacenter -Name $dcName -ErrorAction SilentlyContinue
if( -Not $dc )
{
	New-Datacenter -Location (Get-Folder -NoRecursion | New-Folder -Name Nutanix) -Name $dcName
}

# Create Nutanix vSphere Cluster, if it doesn't already exist
# This doesn't configure DRS or HA, yet

$cluster = Get-Cluster $clusterName -ErrorAction SilentlyContinue
if( -Not $cluster )
{
	New-Cluster -Location (Get-Datacenter $dcName) -Name $clusterName
}

# Set Nutanix-specific vSphere Cluster configuration

Set-Cluster (Get-Cluster $clusterName) -DRSEnabled $true -DRSAutomationLevel PartiallyAutomated -HAAdmissionControlEnabled $true -HAEnabled $true -VMSwapFilePolicy WithVM -Confirm:$false

# Configure Admission Control percentages

$spec = New-Object VMware.Vim.ClusterConfigSpecEx
$spec.dasConfig = New-Object VMware.Vim.ClusterDasConfigInfo
$spec.dasConfig.admissionControlPolicy = New-Object VMware.Vim.ClusterFailoverResourcesAdmissionControlPolicy
$spec.dasConfig.admissionControlPolicy.cpuFailoverResourcesPercent = $HACPUPercent
$spec.dasConfig.admissionControlPolicy.memoryFailoverResourcesPercent = $HAMemPercent
$Cluster = Get-View (Get-Cluster -Name $clusterName)
$Cluster.ReconfigureComputeResource_Task( $spec, $true )

# Configure HA advanced settings
# Note that additional HA Advanced Settings can be specified above

foreach( $advancedSetting in $advancedSettings )
{
	$settingTest = Get-AdvancedSetting -Entity (Get-Cluster -Name $clusterName) -Name $advancedSetting
	if( -Not $settingTest )
	{
		New-AdvancedSetting -Entity (Get-Cluster -Name $clusterName) -Name $advancedSetting -Value true -Type ClusterHA -Confirm:$false
	}
}

# Add hosts to vSphere Cluster
# Omitting the -Force parameter will cause the process to fail due to invalid SSL host certificate on default installations

foreach( $server in $servers )
{
    # Check to see if the host is already in the cluster

	$hostTest = Get-VMHost -Location $dcName $server -ErrorAction SilentlyContinue
	if( -Not $hostTest )
	{
        # Add hosts to the new cluster		

		Add-VMHost $server -Location (Get-Cluster -Name $clusterName) -User $esxUser -Password $esxPassword -Force
		$vmHostNetworkInfo = Get-VMHostNetwork -Host $server

        # Set the host network configuration

		Set-VMHostNetwork -Network $vmHostNetworkInfo -VMKernelGateway $gwIP -Domain $domain -DNSFromDHCP $false -DNSAddress $dnsIP

        # Remove all NTP servers specified in the array above
        # Ensures clean configuration

		foreach( $ntpServer in $ntpServersToRemove )
		{
			Remove-VMHostNtpServer -NtpServer $ntpServer -VMHost $server -Confirm:$false -ErrorAction SilentlyContinue
		}

        # Add new NTP servers specified in array above

		foreach( $ntpServer in $ntpServersToAdd )
		{
			Add-VMHostNTPServer -NtpServer $ntpServer -VMHost $server
		}

        # Check to see if Lockdown mode is enabled on the host
        # If it is, disable it
        # Note that check needs to happen first as disabling Lockdown mode command fails if Lockdown is already disabled

		if( ( Get-VMHost $server | Get-View ).Config.AdminDisabled )
		{
			(Get-VMHost $server | Get-View).ExitLockdownMode()
		}
	}
}

# Configure CVM-specific HA & DRA settings
# Note that this builds a list of VMs that have "CVM" in their name ...

$cvms = Get-VM | where { $_.Name -match "CVM" }

foreach( $cvm in $cvms )
{
	Set-VM $cvm.Name -HARestartPriority Disabled -HAIsolationResponse DoNothing -DRSAutomationLevel Disabled -Confirm:$false

    # Disable VM monitoring on the CVMs only (doesn't touch any other VMs)

    $spec = New-Object VMware.Vim.ClusterConfigSpecEx
    $spec.dasVmConfigSpec = New-Object VMware.Vim.ClusterDasVmConfigSpec
    $spec.dasVmConfigSpec[0].operation = "edit"
    $spec.dasVmConfigSpec[0].info = New-Object VMware.Vim.ClusterDasVmConfigInfo
    $spec.dasVmConfigSpec[0].info.key = New-Object VMware.Vim.ManagedObjectReference
    $spec.dasVmConfigSpec[0].info.key.value = $cvm.ExtensionData.MoRef.Value
    $spec.dasVmConfigSpec[0].info.dasSettings = New-Object VMware.Vim.ClusterDasVmSettings
    $spec.dasVmConfigSpec[0].info.dasSettings.vmToolsMonitoringSettings = New-Object VMware.Vim.ClusterVmToolsMonitoringSettings
    $spec.dasVmConfigSpec[0].info.dasSettings.vmToolsMonitoringSettings.enabled = $false
    $spec.dasVmConfigSpec[0].info.dasSettings.vmToolsMonitoringSettings.vmMonitoring = "vmMonitoringDisabled"
    $spec.dasVmConfigSpec[0].info.dasSettings.vmToolsMonitoringSettings.clusterSettings = $false
    $_this = Get-View -Id $cvm.VMHost.Parent.Id
    $_this.ReconfigureComputeResource_Task( $spec, $true )
}

# Disconnect from the vCenter server

Disconnect-VIServer -Confirm:$false
