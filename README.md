# SPIFFE + Cerbos Authorization Demo

This project demonstrates how to use SPIFFE identities with Cerbos for fine-grained authorization in a Kubernetes environment.

## Overview

The demo consists of:

1. **SPIFFE Demo App** - A Node.js/Express web UI that displays the current SPIFFE identity and certificate information
2. **SPIFFE Demo Backend** - A REST API service that demonstrates SPIFFE identity extraction and Cerbos authorization
3. **Cerbos PDP** - Policy Decision Point that evaluates authorization policies based on SPIFFE identities
4. **cert-manager SPIFFE CSI Driver** - Automatically issues and mounts SPIFFE certificates to pods

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                 │    │                 │
│  SPIFFE Demo    │───▶│  SPIFFE Demo    │───▶│     Cerbos      │
│      App        │    │    Backend      │    │      PDP        │
│                 │    │                 │    │                 │
│  - Web UI       │    │  - REST API     │    │  - Evaluates    │
│  - Shows cert   │    │  - Extracts     │    │    policies     │
│    details      │    │    SPIFFE ID    │    │  - Returns      │
│  - Makes API    │    │  - Calls Cerbos │    │    decisions    │
│    calls        │    │    for authz    │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │                 │
                    │ cert-manager    │
                    │  SPIFFE CSI     │
                    │    Driver       │
                    │                 │
                    │  Trust Domain:  │
                    │  demo.cerbos.io │
                    │                 │
                    │  Auto-mounts at:│
                    │  /var/run/      │
                    │  secrets/       │
                    │  spiffe.io/     │
                    └─────────────────┘
```

## Quick Start

### Prerequisites

- Docker
- minikube
- kubectl
- helm
- cmctl (will be installed automatically if missing)

### Setup

```bash
./setup.sh
```

The script will:

- Start minikube with profile 'zero-trust'
- Install cert-manager (v1.18.2) with SPIFFE CSI driver
- Configure trust domain as `demo.cerbos.io`
- Enable Istio addons in minikube and turn on sidecar injection for the sandbox namespace
- Deploy Cerbos PDP with authorization policies
- Build Docker images for demo applications
- Deploy demo applications to sandbox namespace
- Configure an Istio gateway and virtual services for external access
- Apply namespace-scoped Kubernetes NetworkPolicies
- Approve certificate requests automatically
- Set up port forwarding

### Access the Applications

Once setup is complete:

- **SPIFFE Demo App**: http://localhost:8080
- **SPIFFE Demo Backend**: http://localhost:8081

The applications will have SPIFFE identities in the format:
`spiffe://demo.cerbos.io/ns/sandbox/sa/{service-account}`

### Access via Istio Ingress Gateway

The cluster now exposes the demo services through the shared Istio ingress gateway. To exercise the gateway locally:

```bash
kubectl port-forward -n istio-system svc/istio-ingressgateway 8088:80
```

Then add the following entries to your `/etc/hosts` (or equivalent) so your browser resolves the virtual hosts:

```
127.0.0.1 spiffe-demo.local spiffe-backend.local
```

With the port-forward in place you can browse to `http://spiffe-demo.local:8088` for the UI or call the backend with `curl -H 'Host: spiffe-backend.local' http://localhost:8088/api/resources`.

## Cleanup

To clean up the demo environment:

```bash
# Stop applications and port forwarding (keeps minikube running)
./cleanup.sh

# Completely remove minikube cluster
./cleanup.sh --delete-minikube
```

## Resources

- [SPIFFE Documentation](https://spiffe.io/docs/)
- [cert-manager SPIFFE CSI Driver](https://cert-manager.io/docs/usage/csi-driver-spiffe/)
- [Cerbos Documentation](https://docs.cerbos.dev/)
- [Kubernetes CSI Documentation](https://kubernetes-csi.github.io/docs/)

## Network Policies

Three ingress-focused Kubernetes `NetworkPolicy` objects are applied to the `sandbox` namespace:

- A namespace-wide default deny that blocks all ingress traffic unless explicitly allowed.
- Per-application allowlists that accept traffic from the Istio ingress gateway (`istio-system`), readiness probes (`kube-system`), and the expected in-namespace callers (frontend → backend, backend → Cerbos).
- Dedicated Cerbos rules that only admit connections from the backend on ports 3592/3593.

Egress remains open for now, which keeps Envoy sidecars free to talk to Istiod while still constraining inbound flows to the minimum required set.
