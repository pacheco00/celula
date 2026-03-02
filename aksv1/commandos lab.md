# Comandos para la ejecución del lab

kubectl get namespace

kubectl get svc -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   10.100.110.232   <pending>     80:30796/TCP,443:30224/TCP   27m
ingress-nginx-controller-admission   ClusterIP      10.100.110.144   <none>        443/TCP       


# Identificar identidad del AKS
az aks show -g rg-cloud-lab -n aks-e00 --query identity

# Crear el rol
az role assignment create \
  --assignee e040350a-18cd-4a01-b4b5-56015a9a6f67 \
  --scope /subscriptions/2582c624-5631-45e8-848b-8f4b7cdd6490/resourceGroups/rg-cloud-lab/providers/Microsoft.Network/virtualNetworks/vnet-aks-e00 \
  --role "Network Contributor"

# Asignación role acr pull
az role assignment create \
  --assignee 0e9559e5-6ed3-4282-a791-14d45b692091 \
  --role "AcrPull" \
  --scope /subscriptions/2582c624-5631-45e8-848b-8f4b7cdd6490/resourceGroups/rg-cloud-lab/providers/Microsoft.ContainerRegistry/registries/acre00

# error backoff acr a aks
az aks update -n aks-e00 -g rg-cloud-lab --attach-acr acre00
This grants the AKS node pool permission to pull images from your ACR.

# secreto acr
kubectl delete secret acr-secret -n default

kubectl create secret docker-registry acr-secret \
  --docker-server=acre00.azurecr.io \
  --docker-username=acre00 \
  --docker-password=CiZ6V1p5zaHabFjp2zbOGl03YBAPXx9xCqIoG4vAXjodeNbB1IjkJQQJ99CBACYeBjFEqg7NAAACAZCRD309 \
  --docker-email=lab-app \
  -n default

# deployment
kubectl apply -f deployment.yml