param([string] $subDomain = "Demo")

$group = "Client-$($subDomain)-rg"
$domain = "possumlab.com"
$ipName = "Client-$($subDomain)-ip"

$staticIpCreate = az network public-ip show --resource-group "$($group)" --name "$($ipName)" | ConvertFrom-Json
$staticIp = $staticIpCreate.ipAddress
Write-Host "Static Ip :$($staticIp)"

az group delete -n "$($group)" --yes
az network dns record-set a remove-record -g possumlabinfrastructure -z $domain -n "*.$($subDomain)" --ipv4-address "$($staticIp)"