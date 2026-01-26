# Cloud Computing Project — Automation Failure Report

## Overview

This project implements a multi-tenant Odoo deployment using Terraform, Kubernetes, and Minikube.  
While the Terraform configuration validates successfully and the intended architecture is sound, **Minikube cluster provisioning via Terraform automation failed in a nondeterministic manner** due to environment and tooling constraints.

This README documents the failure clearly, including environment details, observed behavior, logs, and interpretation, as permitted under the assignment guidelines.

---

## Environment

### Toolchain Versions

- **Terraform:** v1.14.3 (linux_amd64)
- **Terraform Providers:**
  - hashicorp/kubernetes v3.0.1
  - hashicorp/tls v4.1.0
  - hashicorp/null v3.2.4
  - hashicorp/local v2.6.1
- **Minikube:** v1.37.0  
  Commit: `65318f4cfff9c12cc87ec9eb8f4cdd57b25047f3`
- **Docker Engine:** 20.10.25+azure-2  
  API Version: 1.41
- **containerd:** 2.2.1-1
- **Kernel / OS:** Linux 6.14.0-37-generic (Ubuntu 24.04.1 kernel build)

---

## Intended Architecture

- Terraform-managed infrastructure
- One Minikube cluster per tenant workspace
- Terraform workspaces:
  - `airbnb`
  - `mcdonalds`
  - `nike`
- Kubernetes namespaces per environment (dev / prod)
- Odoo deployed via Kubernetes manifests managed by Terraform

---

## Terraform Workspaces

Terraform workspaces were correctly created and detected:

- `default`
- `airbnb` (active)
- `mcdonalds`
- `nike`

Terraform validation and planning completed successfully.

---

## Key Failure Mode Observed

Minikube repeatedly reported that **no profiles exist**, despite state being present on disk:

```text
Exiting due to MK_USAGE_NO_PROFILE: No minikube profile was found.
Suggestion: You can create one using 'minikube start'.```

However, Minikube state did exist inside the project directory.

## Key Failure Mode Observed
`terraform/.minikube/` contained:

*   CA certificates and keys
    
*   profiles/airbnb/
    
*   machines/airbnb/
    
*   logs/
    
*   cached Kubernetes binaries
    

Meanwhile:

*   terraform/.kube/ was empty at the time of failure
    
*   Kubernetes provider requests fell back to localhost

---

## Symptoms During Automation

The following errors were repeatedly observed:

*   context does not exist
    
*   client.crt: no such file or directory
    
*   Kubernetes API calls to:
    
    *   `http://localhost`
        
    *   `https://localhost:8443`
        
*   Minikube addon enablement failures (ingress, storage-provisioner)
    
*   Kubernetes provider attempting to connect without a valid kubeconfig

---

## Interpretation

This behavior indicates a **Minikube home / profile resolution mismatch under automation**:

*   Terraform `local-exec` attempted to force Minikube state into `terraform/.minikube`
    
*   Minikube internal callbacks (addon enablement, validation) invoked `kubectl` using a **different Minikube home**
    
*   This caused Minikube to believe no profile existed, despite profile files being present on disk
    

As a result:

*   kubeconfig generation was inconsistent
    
*   Terraform Kubernetes provider fell back to default behavior
    
*   Automation became nondeterministic and unrecoverable within time constraints

---

## Why This Blocks Completion


*   Terraform configuration is syntactically correct
    
*   Module structure and workspace logic are correct
    
*   Failure occurs at runtime due to Minikube behavior outside Terraform’s control
    
*   local-exec provisioners provide no lifecycle guarantees or rollback safety
    

Given the deadline and environment constraints, further refactoring (e.g., external cluster bootstrap, Kind, or remote Kubernetes) was not feasible within the submission window.

---

## Conclusion

This submission documents a real-world automation failure caused by tooling interactions rather than configuration errors.The issue has been analyzed, reproduced, and logged thoroughly.

In a production setting, this would be escalated with Minikube maintainers or resolved by changing the cluster provisioning strategy.

---

## Notes

*   Local Minikube state directories are intentionally ignored in version control
    
*   This README serves as the formal failure report for the assignment