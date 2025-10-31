# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a demonstration project showcasing SPIFFE identity management integrated with Cerbos authorization in a Kubernetes environment. The project consists of Node.js applications that demonstrate mTLS authentication using SPIFFE identities and policy-based authorization using Cerbos.

## Architecture

The system runs on minikube and consists of:

1. **SPIFFE Identity Infrastructure**

   - cert-manager with SPIFFE CSI driver (trust domain: demo.cerbos.io)
   - Automatic certificate issuance and mounting via CSI
   - Runtime certificate approval workflow

2. **Demo Applications** (Node.js/Express)

   - `spiffe-demo-app/`: Frontend app displaying SPIFFE identity and certificate info
   - `spiffe-demo-backend/`: Backend API service with Cerbos authorization

3. **Authorization Layer**
   - Cerbos PDP (Policy Decision Point) running as a service
   - Policies evaluate SPIFFE identities for access control
   - gRPC communication between services and Cerbos

## Common Development Commands

### Setup and Deployment

```bash
# Full automated setup (starts minikube, installs everything)
./setup.sh

# Clean up (stops apps but keeps minikube)
./cleanup.sh

# Complete cleanup (deletes minikube cluster)
./cleanup.sh --delete-minikube
```

### Node.js Applications

```bash
# Install dependencies for demo apps
cd spiffe-demo-app && npm install
cd spiffe-demo-backend && npm install

# Run locally (for development)
npm start
```

### Kubernetes Operations

```bash
# View pods in sandbox namespace
kubectl get pods -n sandbox

# Check application logs
kubectl logs -n sandbox deployment/spiffe-demo-app
kubectl logs -n sandbox deployment/spiffe-demo-backend
kubectl logs -n sandbox deployment/cerbos

# View SPIFFE identity of a pod
kubectl exec -n sandbox $(kubectl get pod -n sandbox -l app=spiffe-demo-app -o jsonpath='{.items[0].metadata.name}') -- cat /var/run/secrets/spiffe.io/tls.crt | openssl x509 --noout --text | grep "URI:"

# Approve certificate requests
cmctl approve -n cert-manager $(kubectl get cr -n cert-manager -ojsonpath='{.items[0].metadata.name}')
```

### Docker Build (uses minikube's docker daemon)

```bash
eval $(minikube -p zero-trust docker-env)
docker build -t spiffe-demo-app:latest ./spiffe-demo-app
docker build -t spiffe-demo-backend:latest ./spiffe-demo-backend
```

## Key Files and Their Purpose

- `setup.sh`: Automated setup script that configures the entire environment
- `cleanup.sh`: Cleanup script for teardown
- `cerbos-deployment.yaml`: Cerbos server deployment with policies embedded as ConfigMap
- `cluster-rbac.yaml`: RBAC rules for certificate request handling
- `spiffe-demo-app/k8s-deployment.yaml`: Frontend app Kubernetes deployment with SPIFFE CSI volume
- `spiffe-demo-backend/k8s-deployment.yaml`: Backend API Kubernetes deployment with SPIFFE CSI volume

## SPIFFE Identity Structure

Identities follow the pattern: `spiffe://demo.cerbos.io/ns/{namespace}/sa/{serviceaccount}`

The CSI driver mounts certificates at `/var/run/secrets/spiffe.io/` with:

- `tls.crt`: The certificate
- `tls.key`: The private key
- `ca.crt`: The CA certificate

## Cerbos Integration

Applications use the `@cerbos/grpc` package to communicate with Cerbos. The authorization flow:

1. Extract SPIFFE ID from mounted certificate
2. Pass SPIFFE ID as principal to Cerbos
3. Cerbos evaluates policies based on SPIFFE trust domain and path
4. Authorization decision returned to application

Policy evaluation uses SPIFFE-specific functions:

- `spiffeID()`: Parse SPIFFE ID from string
- `spiffeTrustDomain()`: Create trust domain matcher
- `spiffeMatchTrustDomain()`: Match against trust domain

## Port Forwarding

The setup script automatically configures:

- Port 8080 → spiffe-demo-app-service
- Port 8081 → spiffe-demo-backend-service

## Testing Authorization

The Cerbos policy allows actions for principals with:

- SPIFFE ID in the `demo.cerbos.io` trust domain
- Path containing `/ns/sandbox`
- Role of `api`

Test authorization decisions via the backend service endpoints.
