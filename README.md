# Azure Custom DNS with forwarders example

This repository will help set up Azure DNS to function in a hub and spoke model with private DNS zones and use of on-premises DNS resolvers.

- [DNS Forwarding Virtual Machine Scale Set](#dns-forwarding-vmss)
- [Azure Policy for Custom DNS](#azure-policy-for-custom-dns)
- [On-premises DNS Setup](#on-premises-dns-setup)

## DNS Forwarding VMSS
This ARM template deploys a virtual machine scale set consisting of 3 Ubuntu 18.04 VMs with dnsmasq installed and configured. It is deployed in a stateless configuration, so the VMs can automatically patch and self-heal in the event of a failed instance.

### Deployment instructions
- Deploy via the command line
  1. Modify parameters.json as appropriate for your environment
      - `vmssName`: name of the scaleset
      - <details>
        <summary>
        <code>vnetId</code>: the full resource ID of the virtual network to use
        </summary>
        <ul>
        <li>via <a href="https://portal.azure.com/">Azure Portal</a>: found in the properties blade of the virtual network</li>
        <li>via <a href="https://docs.microsoft.com/en-us/cli/azure/">Azure CLI</a>: <code>az network vnet show --resource-group rg-hub-network-centralus --name vnet-hub-centralus-001 --query id -o tsv</code></li>
        <li>via <a href="https://docs.microsoft.com/en-us/powershell/azure/">Azure PowerShell</a>: <code>Get-AzVirtualNetwork -ResourceGroupName rg-hub-network-centralus -Name vnet-hub-centralus-001 | Select-Object -ExpandProperty Id</code></li>
        </ul>
        </details>
      - `subnetName`: the name of the subnet
      - `stgAcctName`: the name of the storage account to use for boot diagnostics
      - `sshUser`: the username to use for admin access via SSH
      - `sshKey`: the public key to assign to `sshUser`
  2. Modify customData.json to appropriately set up dnsmasq
      - add `server=/domain/nameserverIP` lines for each domain you want to forward to on-premises (if you have multiple nameservers, use one line per nameserver)
      - if you have multiple domains to forward to the same nameserver, you can use the format `server=/domain1/domain2/nameserverIP`
      - leave the last server line intact to forward any non-matching queries to Azure DNS: `server=168.63.129.16`
  3. Deploy the template
      - <details>
        <summary>
        Using Azure CLI
        </summary>
        <pre><code>az deployment group create \
          --resource-group rg-hub-dnsfwd-centralus \
          --template-file template-vmss.json \
          --parameters @parameters.json \
          --parameters customData=@customData.yaml</code></pre>
        </details>
      - <details>
        <summary>
        Using Azure PowerShell
        </summary>
        <pre><code>New-AzResourceGroupDeployment `
          -ResourceGroupName rg-hub-dnsfwd-centralus `
          -TemplateFile .\template-vmss.json `
          -TemplateParameterFile .\parameters.json `
          -customData $(Get-Content .\customData.yaml -Raw)</code></pre>
        </details>

## Azure Policy for Custom DNS

### [privateDNShubLinkPolicyDeployINE.json](azure-policy/privateDNShubLinkPolicyDeployINE.json)
This policy will automatically deploy a link from any private DNS zones in scope to the hub vnet where your DNS forwarders are running if one does not already exist. This is critical for having your DNS servers able to resolve private DNS zones in a spoke virtual network.

### [vnetDNSServersAppend.json](azure-policy/vnetDNSServersAppend.json)
This policy will ensure that all virtual networks deployed have the DNS servers set to the values specified so that DNS lookups forward to on-premises and private DNS zones correctly.

## On-premises DNS setup

Also provided is [a script](ad-dns/Add-AzureDNSFowarderZones.ps1) that will forward all currently used Azure Private Link DNS domains from an on-premises Active Directory DNS server to the forwarders deployed above. If you create custom private DNS zones in Azure, you will need to set your forwarding up in the same way if you want them resolvable from on premises.
