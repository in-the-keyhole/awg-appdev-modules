# Application XRD

`
apiVersion: appdev.awginc.com/v1alpha1
kind: Application
metadata:
  name: applicationname
spec:
  name: applicationname
  metadataLocation: northcentralus
  defaultResourceLocation: southcentralus
`

An Application claim serves as the root of an AWG application deployment. Generally only a single Application object should exist in each Kubernetes namespace.

The following features are driven by an Application:
+ An Azure Resource group named `rg-awg-appdev-{env}-{name}` is created.
+ A User Assigned Identity is created with the name `awg-appdev-{env}-{name}`.
+ A DNS Zone is created with the name `{name}.{env}.{plat}.appdev.az.awginc.com`.
+ A Private DNS Zone is created with the name `{name}.{env}.{plat}.appdev.az.int.awginc.com`.
+ The User Principal is assigned DNS Zone Contributor and Private DNS Zone Contributor on the Resource Group.
+ External-DNS is installed within the namespace to manage the public zone.
+ External-DNS is installed within the namespace to manage the private zone.

An Application accepts the following parameters:

+ name: determines the name used for the Azure Resources
+ metadataLocation: the location of the Resource Group
+ defaultResourceLocation: the Azure region where resources should be created unless otherwise specified

# External DNS

External-DNS has a number of issues which need to be corrected:

+ It can only have one active provider at a time, however since AWG has two DNS zones (public, private), we need to install two copies with different providers.
+ It must operate in namespace-scope for the Azure Workload Identity to be effective: it needs to use the User Assigned Identity created for this application.
+ When set in namespace-scope, it still issues queries for cluster-scoped objects. However the Helm chart does not add permissions to those objects. To smooth this over, we grant it a ClusterRoleBinding to the required APIs. When upstream addresses this issue these bindings can be removed.
+ It is set to filter out its respective zone names.
+ We enable the Kubernetes Gateway API on it so that it can pull host names from Gateway API resources.
+ We enable ingress on it so it can pull from classic Ingress resources.
+ We do not yet enable it to pull from Istio Gateways, as that has not yet been installed in the clusters.
