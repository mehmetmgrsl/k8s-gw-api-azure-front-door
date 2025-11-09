## Azure Front Door -> AKS Gateway API Simulation

- This guide walks you through simulating Azure Front Door routing traffic to an AKS cluster using the Gateway API and NGINX Gateway Fabric (NGF).The setup runs fully in a local kind cluster for fast testing.

![Architecture](architecture.png)


### 1) kind cluster
kind create cluster --config 00-kind.yaml

### 2) Namespaces
kubectl apply -f 01-namespaces.yaml

### 3) Gateway Controller (NGINX Gateway Fabric)

- Installs Gateway API resource types (Gateway, HTTPRoute, etc.)
- Installs NGF-specific CRDs
- Deploys the NGF controller and data-plane using NodePort
- Patches NGF Service to use port 443 and simulate an internal Azure load balancer


```
helm repo add nginx-stable https://helm.nginx.com/stable

helm repo update

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml


kubectl apply --server-side -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.2.0/deploy/crds.yaml


kubectl apply -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.2.0/deploy/nodeport/deploy.yaml


kubectl -n nginx-gateway patch svc nginx-gateway \
  --type merge \
  -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/azure-load-balancer-internal":"true"}},"spec":{"type":"LoadBalancer","ports":[{"name":"https","port":443,"targetPort":8443}]}}'
```

### 4) Certificates
- Generates TLS certs for Azure Front Door simulation, Gateway, and Root CA

```chmod +x 02-gencerts.sh && ./02-gencerts.sh```

- This produces certs in the ```out/``` directory for:

   - Azure FD simulator (edge.crt/key)
   - Gateway listener (origin.crt/key)
   - Root CA (rootCA.crt)

### 5) Secrets + CA ConfigMap

- Creates TLS secret for Azure Front Door simulator

```
kubectl create secret tls azurefd-sim-tls \
  --namespace edge \
  --cert=./out/edge.crt \
  --key=./out/edge.key
```

- Creates TLS secret for Gateway listener

```
kubectl create secret tls web-gw-tls \
  --namespace nginx-gateway \
  --cert=./out/origin.crt \
  --key=./out/origin.key
```

- Creates ConfigMap with Root CA for upstream TLS validation

```
kubectl create configmap azurefd-sim-ca \
  --namespace edge \
  --from-file=rootCA.crt=./out/rootCA.crt
```


### 6) Gateway resources
- Deploys GatewayClass, Gateway (443 listener), and HTTPRoute for routing to the app

```
kubectl apply -f 20-gateway/gatewayclass.yaml
```

```
kubectl apply -f 20-gateway/gateway.yaml
```
- This creates ```web-gw-nginx-****```.

```
kubectl apply -f 20-gateway/httproute.yaml
```

### 7) Create the data-plane Service

- When we create GatewayClass, Gateway, and HTTPRoute resources, they only define the control-plane configuration (i.e., how routing should behave).
However, these resources do not automatically create a Service that exposes the data-plane (the actual NGINX proxy that processes traffic).

- Therefore, to make the Gateway API accessible inside the cluster, we manually create a Service that targets the NGF data-plane pods (web-gw-nginx).

- ```kubectl apply -f 03-web-gw-dp-svc.yaml```


### 8) Azure Front Door simulator
- Deploys Nginx-based Azure Front Door simulator with HTTPS

```
kubectl apply -f 10-azurefd-sim/azurefd-sim-configmap.yaml
kubectl apply -f 10-azurefd-sim/azurefd-sim-deploy.yaml
kubectl apply -f 10-azurefd-sim/azurefd-sim-svc.yaml
```

### 9) App

- Deploys demo echo app and exposes it internally via app-svc

```
kubectl apply -f 30-app/app-deploy.yaml
kubectl apply -f 30-app/app-svc.yaml
```


### 10) Test

- Exposes Azure Front Door simulator on localhost:8443

```kubectl -n edge port-forward svc/azurefd-sim 8443:443```


curl -k https://localhost:8443/healthz

 - Output should be "ok"


curl -k https://localhost:8443/

 - Output should be "hello-from-app"


### 11) After the test, delete the K8s Cluster

```kind delete cluster --name aks-azurefd-gwapi```