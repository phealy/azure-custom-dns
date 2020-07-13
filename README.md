# Azure Custom DNS with forwarders example

This repository will help set up Azure DNS to function in a hub and spoke model with private DNS zones and use of on-premises DNS resolvers.

- [DNS Forwarding Virtual Machine Scale Set](#dns-forwarding-vmss)
- [Azure Policy for Custom DNS](#azure-policy-for-custom-dns)
- [On-premises DNS Setup](#on-premises-dns-setup)

## DNS Forwarding VMSS
This ARM template deploys a virtual machine scale set consisting of 3 Ubuntu 18.04 VMs with dnsmasq installed and configured. It is deployed in a stateless configuration, so the VMs can automatically patch and self-heal in the event of a failed instance. The VMs will answer DNS queries from any host that can reach them via internal traffic (but not the internet). Queries will be forwarded to the Azure DNS servers, but domains can be configured to be delegated to on-premises servers if desired.

### Deployment instructions
- Deploy via the portal<br>
  [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fphealy%2Fazure-custom-dns%2Fmaster%2Fvmss-dnsfwd%2Ftemplate-vmss.json)
- Deploy via the command line
  1. Modify parameters.json as appropriate for your environment
      - Required
        - `vnetName`: the name of the virtual network to deploy into
        - `vnetRGName`: the name of the resource group `vnetName` is in, if not the same as the template deployment.
        - `subnetName`: the name of the subnet in `vnetName` to use
        - `stgAcctName`: the name of the storage account to use for boot diagnostics
        - `sshUser`: the username to use for admin access via SSH
        - `sshKey`: the public key to assign to `sshUser`
      - Optional
        - `deployExternalLoadBalancer`: Needed to allow external connectivity per [scenario 2](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-outbound-connections) **unless** your network has egress enabled via a UDR to an Azure Firewall, Azure NAT Gateway, or NVA.
        - `externalLoadBalancerName`: Name of the external load balancer to deploy if `deployExternalLoadBalancer` is true. Defaults to `lbe-dnsfwd-<region>-001`
        - `externalLoadBalancerPublicIPName`: Name of the public IP for the external load balancer if `deployExternalLoadBalancer` is true. Defaults to `lbe-dnsfwd-<region>-001-pip`
        - `internalLoadBalancerName`: Name of the internal load balancer to deploy in front of the VM scale set. Defaults to `lbi-dnsfwd-<region>-001`
        - `vmssName`: name of the Virtual Machine scale set. Defaults to `vmss-dnsfwd-<region>-001`
        - `optionLine#`, where # is 1-8: additional option lines to add to /etc/dnsmasq.conf. These can be used to direct traffic for your internal domains to other name servers as appropriate. For example, you can send traffic for your internal domains `mydomain.com` and `mydomain2.com` to 10.0.10.10 by including the line `server=/mydomain.com/mydomain2.com/10.0.10.10`. See the [DNSMASQ man page](http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html) for more details.
  1. Deploy the template
      - <details>
        <summary>
        Using Azure CLI
        </summary>
        <pre><code>az deployment group create \
          --resource-group rg-hub-dnsfwd-centralus \
          --template-file template-vmss.json \
          --parameters @parameters.json</code></pre>
        </details>
      - <details>
        <summary>
        Using Azure PowerShell
        </summary>
        <pre><code>New-AzResourceGroupDeployment `
          -ResourceGroupName rg-hub-dnsfwd-centralus `
          -TemplateFile .\template-vmss.json `
          -TemplateParameterFile .\parameters.json</code></pre>
        </details>

## Azure Policy for Custom DNS

### [privateDNShubLinkPolicyDeployINE.json](azure-policy/privateDNShubLinkPolicyDeployINE.json)
This policy will automatically deploy a link from any private DNS zones in scope to the hub vnet where your DNS forwarders are running if one does not already exist. This is critical for having your DNS servers able to resolve private DNS zones in a spoke virtual network.

### [vnetDNSServersAppend.json](azure-policy/vnetDNSServersAppend.json)
This policy will ensure that all virtual networks deployed have the DNS servers set to the values specified so that DNS lookups forward to on-premises and private DNS zones correctly.

## On-premises DNS setup

Also provided is [a script](ad-dns/Add-AzureDNSFowarderZones.ps1) that will forward all currently used Azure Private Link DNS domains from an on-premises Active Directory DNS server to the forwarders deployed above. If you create custom private DNS zones in Azure, you will need to set your forwarding up in the same way if you want them resolvable from on premises.