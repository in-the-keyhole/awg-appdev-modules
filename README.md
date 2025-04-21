# AWG Application Development Modules

This repository contains reusable artifacts incorporated into the various AWG Application Development architecture components:

+ Shared Terraform Modules in /terraform
  + dns-resolver: An implementation of a Private DNS Resolver using Core DNS deployed on Ubuntu Minimal servers. This resource appears in each Application Development Platform instance to handle external queries for private DNS zones within the platform. It is also used in the Fake Hub project for the same.
+ Helm Charts
  + awg-appdev-boot: Will serve as a bootstrap package that installs before Crossplane to prepare the cluster.
  + awg-appdev-init: Installed immediately after Crossplane to install any resources that depend on Crossplane. Schedules the install of `awg-appdev-conf` using the Crossplane Helm Provider.
  + awg-appdev-conf: Configures any remaining elements of the cluster that must occur after package installs initiated by init.
+ Crossplane Configuration Packages:
  + awg-appdev: Contains Crossplane Modules that form the basis of the AWG Application Environment. [README](xpkg/awg-appdev/README.md)

## AWG AppDev Init

This helm chart package uses Crossplane's Helm provider to schedule the installation of a number of supporting services:

+ Traefik (internal)
  An instance of the Traefik ingress controller running on the Internal Load Balancer.
  This instance is configured to accept class Ingress as well as the new Gateway API resources with GatewayClass `traefik-internal`.
  It is also configured as the default Ingress controller.
+ Traefik (external)
  An instance of the Traefik ingress controller running on the External Load Balancer.
  This instance is configured to accept class Ingress as well as the new Gateway API resources with GatewayClass `traefik-external`.
+ Kyverno
  Kyverno is a Kubernetes policy agent that defines a Mutating and Validating webhook to process ClusterPolicy and Policy documents. These allow interception and injection of information into Kubernetes manifests on the fly. This is used by the `awg-appdev` Crossplane Configuration Package to implement `ServiceAccount` and `Pod` bindings for Azure Workload Identity against the identity implicitely created by an associated `Application`.
  