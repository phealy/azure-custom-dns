# Azure Custom DNS with forwarders example

- [Overview](#overview)
- [DNS Forwarding Virtual Machine Scale Set](#dns-forwarding-vmss)
- [Azure Policy for Custom DNS](#azure-policy-for-custom-dns)
- [On-premises DNS Setup](#on-premises-dns-setup)

## Overview

When using Azure Private DNS services, either on their own or with private link endpoints, the DNS configuration required for resolution to function properly across a hub-and-spoke network design in Azure as well as on-premises takes some setup. In a standard setup where you want to be able to resolve on-premises hostnames from Azure and private link hostnames from on-premises, a DNS forwarder setup can meet your resolution needs.

**❗ IMPORTANT: implementing this configuration requires forwarding ALL DNS lookups for the given Azure service via this forwarder configuration. This means that misconfigurations or outages in your DNS forwarders will cause failures to connect to the Azure service in question, *even via a public endpoint*, for any client or server using your DNS servers.**

Requirements:
1. [Custom DNS servers on your Azure Virtual Networks](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-name-resolution-for-vms-and-role-instances#name-resolution-that-uses-your-own-dns-server) pointing at a DNS resolver that can resolve your on-premises hostnames - often this is Windows DNS on your AD domain controllers. In a POC environment, you can add a configuration statement to the DNS forwarders deployed by this template that will conditionally forward your on-premises domains to your on-premises nameservers, enabling you to use the same scale set to meet both needs. *This configuration is not recommended for production as it places a hard dependency on your WAN link - VPN or ExpressRoute - for DNS resolution.*
2. A DNS forwarder that answers incoming DNS requests by forwarding them to [168.63.129.16, which is an Azure service IP that provides filtered DNS resolution.](https://docs.microsoft.com/en-us/archive/blogs/mast/what-is-the-ip-address-168-63-129-16). This repository implements this as an auto-patching virtual machine scale set using dnsmasq, but this can also be implemented using any DNS server you are comfortable with. If you choose to use Windows DNS, you cannot use your regular domain DNS zones - this must be standalone. This is because these forwarders **must** be hosted in Azure (n.b. if you only have domain controllers in Azure, you could point your entire DNS setup to the Azure DNS server as an upstream resolver - but this doesn't work if you have DCs on-premises because they're not in your virtual network).
3. Any private DNS zones created in Azure need a virtual network link to the virtual network that your DNS forwarders are running in (usually your hub). This repository includes an [[Azure Policy for Custom DNS](#azure-policy-for-custom-dns) that creates that link whenever a private DNS zone is created.
4. A conditional forwarder set in your main DNS servers for the [**public DNS zone forwarders** of the Azure service](https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns#azure-services-dns-zone-configuration) you want to use via private link. Note that setting the conditional forwarder on the privatelink.service.dns.name will not function properly.

Please reference the [Virtual network and on-premises workloads using a DNS forwarder](https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns#virtual-network-and-on-premises-workloads-using-a-dns-forwarder) section of the [private endpoint DNS](https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns) documentation for more details.

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
      - Optional
        - `deployExternalLoadBalancer`: Needed to allow external connectivity per [scenario 2](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-outbound-connections) **unless** your network has egress enabled via a UDR to an Azure Firewall, Azure NAT Gateway, or NVA.
        - `externalLoadBalancerName`: Name of the external load balancer to deploy if `deployExternalLoadBalancer` is true. Defaults to `lbe-dnsfwd-<region>-001`
        - `externalLoadBalancerPublicIPName`: Name of the public IP for the external load balancer if `deployExternalLoadBalancer` is true. Defaults to `lbe-dnsfwd-<region>-001-pip`
        - `internalLoadBalancerName`: Name of the internal load balancer to deploy in front of the VM scale set. Defaults to `lbi-dnsfwd-<region>-001`
        - `vmssName`: name of the Virtual Machine scale set. Defaults to `vmss-dnsfwd-<region>-001`
        - `stgAcctName`: the name of the storage account to use for boot diagnostics. If not supplied, boot diagnostics will not be enabled.
        - `sshUser`: the username to use for admin access via SSH. Defaults to `azureuser`
        - `sshPassword`: the password to assign to `sshUser` (`sshUser` is set to `azureuser` by default) - this can be used for serial console access if a `stgAcctName` is supplied, or via SSH if no `sshKey` is supplied.
        - `sshKey`: the public key to assign to `sshUser` (`sshUser` is set to `azureuser` by default). Supplying an SSH key will disable password login via SSH.
        - `optionLine#`, where # is 1-8: additional option lines to add to /etc/dnsmasq.conf. These can be used to direct traffic for your internal domains to other name servers as appropriate. For example, you can send traffic for your internal domains `mydomain.com` and `mydomain2.com` to 10.0.10.10 by including the line `server=/mydomain.com/mydomain2.com/10.0.10.10`. See the [DNSMASQ man page](http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html) for more details.
  1. Deploy the template
      - Using Azure CLI
        <pre><code>az deployment group create \
          --resource-group rg-hub-dnsfwd-centralus \
          --template-file template-vmss.json \
          --parameters @parameters.json</code></pre>
      - Using Azure PowerShell
        <pre><code>New-AzResourceGroupDeployment `
          -ResourceGroupName rg-hub-dnsfwd-centralus `
          -TemplateFile .\template-vmss.json `
          -TemplateParameterFile .\parameters.json</code></pre>

## Azure Policy for Custom DNS

### [privateDNShubLinkPolicyDeployINE.json](azure-policy/privateDNShubLinkPolicyDeployINE.json)
This policy will automatically deploy a link from any private DNS zones in scope to the hub vnet where your DNS forwarders are running if one does not already exist. This is critical for having your DNS servers able to resolve private DNS zones in a spoke virtual network.

### [vnetDNSServersAppend.json](azure-policy/vnetDNSServersAppend.json)
This policy will ensure that all virtual networks deployed have the DNS servers set to the values specified so that DNS lookups forward to on-premises and private DNS zones correctly.

## On-premises DNS setup

Also provided is [a script](ad-dns/Add-AzureDNSFowarderZones.ps1) that will forward all currently used Azure Private Link DNS domains from an on-premises Active Directory DNS server to the forwarders deployed above. If you create custom private DNS zones in Azure, you will need to set your forwarding up in the same way if you want them resolvable from on premises.
