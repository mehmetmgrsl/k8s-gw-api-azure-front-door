# We will create two certificates:
### edge: azurefd-sim TLS (CN=localhost, SAN: localhost)
### origin: Gateway TLS (CN=web-gw.gateway-system.svc.cluster.local)

#!/usr/bin/env bash
set -euo pipefail
mkdir -p out

# 1) Root CA
openssl genrsa -out out/rootCA.key 2048
openssl req -x509 -new -nodes -key out/rootCA.key -sha256 -days 3650 \
  -subj "/CN=Local Test Root CA" -out out/rootCA.crt

# 2) Edge (azurefd-sim) cert (CN=localhost)
cat > out/edge.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = v3_req
prompt = no

[ dn ]
CN = localhost

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = localhost
EOF

openssl genrsa -out out/edge.key 2048
openssl req -new -key out/edge.key -out out/edge.csr -config out/edge.cnf
openssl x509 -req -in out/edge.csr -CA out/rootCA.crt -CAkey out/rootCA.key \
  -CAcreateserial -out out/edge.crt -days 825 -sha256 -extensions v3_req -extfile out/edge.cnf

# 3) Origin (Gateway) cert (CN=localhost)
cat > out/origin.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = v3_req
prompt = no

[ dn ]
CN = localhost

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = localhost
EOF

openssl genrsa -out out/origin.key 2048
openssl req -new -key out/origin.key -out out/origin.csr -config out/origin.cnf
openssl x509 -req -in out/origin.csr -CA out/rootCA.crt -CAkey out/rootCA.key \
  -CAcreateserial -out out/origin.crt -days 825 -sha256 -extensions v3_req -extfile out/origin.cnf

echo "Certificates generated under ./out"
