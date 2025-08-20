# SPIFFE + Cerbos Authorization Demo

This project demonstrates how to use SPIFFE identities with Cerbos for fine-grained authorization in a Kubernetes environment.

## Overview

The demo consists of:

1. **SPIFFE Demo App** - A web UI that displays the current SPIFFE identity and certificate information
2. **Cerbos Authorization Service** - A service that makes authorization decisions based on SPIFFE identities
3. **Cerbos Policies** - Policy definitions that control access to resources based on SPIFFE ID attributes

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                 │    │                 │
│  SPIFFE Demo    │    │  Cerbos Service │    │     Cerbos      │
│      App        │    │                 │    │    Engine       │
│                 │    │                 │    │                 │
│  - Shows SPIFFE │    │  - Extracts     │    │  - Evaluates    │
│    identity     │    │    SPIFFE ID    │    │    policies     │
│  - Certificate  │    │  - Makes authz  │    │  - Returns      │
│    details      │    │    calls        │    │    decisions    │
│                 │    │                 │    │                 │
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
                    │  - Issues       │
                    │    certificates │
                    │  - Mounts       │
                    │    SPIFFE IDs   │
                    │                 │
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

1. **Run the automated setup:**
   ```bash
   ./setup.sh
   ```

   This script will:
   - Start minikube
   - Install cert-manager and SPIFFE CSI driver
   - Deploy Cerbos with policies
   - Build and deploy the demo applications
   - Set up port forwarding

2. **Access the applications:**
   - SPIFFE Demo App: http://localhost:8080
   - Cerbos Authorization Service: http://localhost:3000

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