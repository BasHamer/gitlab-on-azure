param([string] $subDomain = "Demo")

#this is to work around azure caching issue around aks
$stamp = Get-Date -format "HHmmss"
$group = "Client-$($subDomain)-rg"
$aksCluster = "Client-$($subDomain)-aks-$($stamp)"
$containerRegistry = "Client$($subDomain)Acr"
$ipName = "Client-$($subDomain)-ip"

Write-Host "stamp :$($stamp)"
Write-Host "group :$($group)"
Write-Host "aks :$($aksCluster)"
Write-Host "acr :$($containerRegistry)"
Write-Host "public-ip :$($ipName)"

az group create --location centralus -n "$($group)" --tags client="$($subDomain)"

# az network public-ip create  output
#{
#  "publicIp": {
#    "ipAddress": "168.62.4.192",
#  }
#}

$staticIpCreate = az network public-ip create --resource-group "$($group)" --name "$($ipName)" --allocation-method static | ConvertFrom-Json
$staticIp = $staticIpCreate.publicIp.ipAddress
Write-Host "Static Ip :$($staticIp)"

az network dns record-set a add-record -g possumlabinfrastructure -z possumlab.com -n "*.$($subDomain)" -a $staticIp

Write-Host "////// aks"
az aks create --resource-group "$($group)" --name "$($aksCluster)" --enable-addons monitoring --generate-ssh-keys  #--enable-rbac (on by default) 

##only needs to be done once
#az aks install-cli
#$env:path += 'C:\Users\live\.azure-kubectl'
az aks get-credentials --resource-group "$($group)" --name "$($aksCluster)" 

Write-Host "////// helm"
#https://github.com/helm/helm/blob/master/docs/rbac.md
kubectl create -f tiller-rbac-config.yaml
$helmhome = helm home 
if(-not ([string]::IsNullOrEmpty($helmhome)))
{
	Remove-Item -Force -Recurse -Path "$($helmhome)"
}
helm init --service-account tiller --wait

Write-Host "////// nginx-ingress"

helm install stable/nginx-ingress `
  --namespace kube-system `
  --set controller.service.loadBalancerIP="$($staticIp)" `
  --set controller.replicaCount=1 `
  --timeout 600 `
  --wait

Write-Host "////// cert-manager"

#helm install stable/cert-manager `
#  --namespace kube-system `
#  --set ingressShim.defaultIssuerName=letsencrypt-staging `
#  --set ingressShim.defaultIssuerKind=ClusterIssuer `
#  --timeout 600 `
#  --wait

Write-Host "////// cluster-issuer"

kubectl apply -f cluster-issuer.yaml

Write-Host "////// gitlab"

helm repo add gitlab https://charts.gitlab.io/
helm repo update

helm upgrade --install gitlab gitlab/gitlab `
  --timeout 600 `
  --set global.hosts.domain=demo.possumlab.com `
  --set global.hosts.externalIP="$($staticIp)" `
  --set certmanager-issuer.email=bas@possumlabs.com `
  --set gitlab.migrations.image.repository=registry.gitlab.com/gitlab-org/build/cng/gitlab-rails-ce `
  --set gitlab.sidekiq.image.repository=registry.gitlab.com/gitlab-org/build/cng/gitlab-sidekiq-ce `
  --set gitlab.unicorn.image.repository=registry.gitlab.com/gitlab-org/build/cng/gitlab-unicorn-ce `
  --set gitlab.unicorn.workhorse.image=registry.gitlab.com/gitlab-org/build/cng/gitlab-workhorse-ce `
  --set gitlab.task-runner.image.repository=registry.gitlab.com/gitlab-org/build/cng/gitlab-task-runner-ce `
  --wait

 kubectl get secret gitlab-gitlab-initial-root-password -o yaml > "$($subDomain)-gitlab-initial-root-password.yaml"

 kubectl create clusterrolebinding kubernetes-dashboard --clusterrole=cluster-admin --serviceaccount=kube-system:kubernetes-dashboard

Write-Host "////// container registry"
az acr create --resource-group "$($group)" --name "$($containerRegistry)" --sku Basic
az acr login --name "$($containerRegistry)"

az aks browse --resource-group "$($group)" --name "$($aksCluster)"