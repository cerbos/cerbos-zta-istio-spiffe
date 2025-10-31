Docs https://cert-manager.io/docs/usage/csi-driver-spiffe/

Setup the infrastructure

```
minikube -p zero-trust start


kubectl create ns cert-manager
helm repo add jetstack https://charts.jetstack.io --force-update
helm install \
 cert-manager jetstack/cert-manager \
 --namespace cert-manager \
 --create-namespace \
 --version v1.18.2 \
 --set crds.enabled=true

helm upgrade cert-manager-csi-driver jetstack/cert-manager-csi-driver \
 --install \
 --namespace cert-manager \
 --wait

existing_cert_manager_version=$(helm get metadata -n cert-manager cert-manager | grep '^VERSION' | awk '{ print $2 }')
helm upgrade cert-manager jetstack/cert-manager \
 --reuse-values \
 --namespace cert-manager \
 --version $existing_cert_manager_version \
 --set disableAutoApproval=true

kubectl create configmap -n cert-manager spiffe-issuer \
 --from-literal=issuer-name=csi-driver-spiffe-ca \
 --from-literal=issuer-kind=ClusterIssuer \
 --from-literal=issuer-group=cert-manager.io

helm upgrade -i -n cert-manager cert-manager-csi-driver-spiffe jetstack/cert-manager-csi-driver-spiffe --wait \
 --set "app.logLevel=1" \
 --set "app.trustDomain=demo.cerbos.io" \
 --set "app.issuer.name=" \
 --set "app.issuer.kind=" \
 --set "app.issuer.group=" \
 --set "app.runtimeIssuanceConfigMap=spiffe-issuer"

kubectl apply -f https://raw.githubusercontent.com/cert-manager/csi-driver-spiffe/ed646ccf28b1ecdf63f628bf16f1d350a9b850c1/deploy/example/clusterissuer.yaml
```

Deploy a sample app

```
kubectl apply -f https://raw.githubusercontent.com/cert-manager/csi-driver-spiffe/ed646ccf28b1ecdf63f628bf16f1d350a9b850c1/deploy/example/example-app.yaml
```

Approve the sample apps certificate request

```
cmctl approve -n cert-manager $(kubectl get cr -n cert-manager -ojsonpath='{.items[0].metadata.name}')
```

Run the following to log out the mounted SPIFFE identity

```
kubectl exec -n sandbox \
 $(kubectl get pod -n sandbox -l app=my-csi-app -o jsonpath='{.items[0].metadata.name}') \
 -- \
 cat /var/run/secrets/spiffe.io/tls.crt | \
 openssl x509 --noout --text | \
 grep "Issuer:"

kubectl exec -n sandbox \
 $(kubectl get pod -n sandbox -l app=my-csi-app -o jsonpath='{.items[0].metadata.name}') \
 -- \
 cat /var/run/secrets/spiffe.io/tls.crt | \
 openssl x509 --noout --text | \
 grep "URI:"
```

Todo:

- Demo app which has a UI which shows the SPIFFE identity in a browser
- Cerbos policy which gets pass the SPIFFE identity and makes an authorization decision for a service call
- Automate the setup
