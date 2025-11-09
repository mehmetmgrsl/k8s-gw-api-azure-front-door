curl -> Azure Front Door-sim (Nginx) -> web-gw-dp Service -> NGF data-plane -> HTTPRoute -> app-svc -> echo pod



# 1) kind cluster
kind create cluster --config 00-kind.yaml

# 2) Namespaces
kubectl apply -f 01-namespaces.yaml

# 3) Gateway API CRDs (v1.4.0)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

# 4) Gateway Controller

# NGINX Gateway Fabric:
helm repo add nginx-stable https://helm.nginx.com/stable

helm repo update

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml


kubectl apply --server-side -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.2.0/deploy/crds.yaml


kubectl apply -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v2.2.0/deploy/nodeport/deploy.yaml


kubectl -n nginx-gateway patch svc nginx-gateway \
  --type merge \
  -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/azure-load-balancer-internal":"true"}},"spec":{"type":"LoadBalancer","ports":[{"name":"https","port":443,"targetPort":443}]}}'


# 5) Certificates
chmod +x 02-gencerts.sh && ./02-gencerts.sh

# 6) Secrets + CA ConfigMap

kubectl create secret tls azurefd-sim-tls \
  --namespace edge \
  --cert=./out/edge.crt \
  --key=./out/edge.key


kubectl create secret tls web-gw-tls \
  --namespace nginx-gateway \
  --cert=./out/origin.crt \
  --key=./out/origin.key


kubectl create configmap azurefd-sim-ca \
  --namespace edge \
  --from-file=rootCA.crt=./out/rootCA.crt


# 7) azurefd-sim
kubectl apply -f 10-azurefd-sim/azurefd-sim-configmap.yaml
kubectl apply -f 10-azurefd-sim/azurefd-sim-deploy.yaml
kubectl apply -f 10-azurefd-sim/azurefd-sim-svc.yaml


# 8) Gateway resources
kubectl apply -f 20-gateway/gatewayclass.yaml
kubectl apply -f 20-gateway/gateway.yaml
kubectl apply -f 20-gateway/httproute.yaml

# 9) App
kubectl apply -f 30-app/app-deploy.yaml
kubectl apply -f 30-app/app-svc.yaml




# 10) Test

kubectl -n edge port-forward svc/azurefd-sim 8443:443


curl -k https://localhost:8443/healthz

 - Output should be "ok"


 

# Tarayıcı veya:
curl -k https://localhost/healthz
curl -k https://localhost/      # "hello-from-app" beklenir


## After the test, delete the K8s Cluster

kind delete cluster --name aks-azurefd-gwapi




kubectl -n edge exec -it deploy/azurefd-sim -- \
  sh -lc 'openssl s_client -connect nginx-gateway.nginx-gateway.svc.cluster.local:443 \
  -servername localhost -CAfile /etc/nginx/ca/rootCA.crt -brief </dev/null'