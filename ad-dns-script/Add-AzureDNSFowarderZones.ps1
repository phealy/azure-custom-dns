[CmdletBinding()]
param (
    [Parameter()]
    [String[]]
    $DNSForwarderIPs
)

$AzureDomains = @('api.azureml.ms','azconfig.io','azmk8s.io','azure-automation.net','azurecr.io','azure-devices.net','azurewebsites.net','backup.windowsazure.com','blob.core.windows.net','cassandra.cosmos.azure.com','cognitiveservices.azure.com','database.windows.net','dfs.core.windows.net','documents.azure.com','eventgrid.azure.net','file.core.windows.net','gremlin.cosmos.azure.com','mariadb.database.azure.com','mongo.cosmos.azure.com','monitor.azure.com','mysql.database.azure.com','postgres.database.azure.com','queue.core.windows.net','search.windows.net','service.signalr.net','servicebus.windows.net','table.core.windows.net','table.cosmos.azure.com','vault.azure.net','vaultcore.azure.net','web.core.windows.net')
$DNSForwarderZones = Get-DnsServerZone | Where-Object { $_.ZoneType -eq "Forwarder" }

$AzureDomains | ForEach-Object { 
    if ($_ -in $DNSForwarderZones.ZoneName) {
        Write-Host "Updating DNS forwarder zone ${_}..."
        Set-DnsServerConditionalForwarderZone -Name $_ -MasterServers $DNSForwarderIPs
    } else {
        Write-Host "Adding DNS forwarder zone ${_}..."
        Add-DnsServerConditionalForwarderZone -Name $_ -MasterServers $DNSForwarderIPs -ReplicationScope Forest
    }
}