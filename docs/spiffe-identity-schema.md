# Identity Schema Definition Design

**Warning: This document is considered Work In Progress (WIP) and is subject to change.**

This document is a design doc that talks about how identity schema can be defined and configured so that workloads can automatically 
be registered with its associated identity that adheres to the defined schema. This is based around the idea of
behavior and property based identity (from attestations, metadata, etc.) as well as the ability to have user 
defined fields.

## Example of identity

A SPIFFE identity is always prefixed by "spiffe://" and the trust domain of the identity. Anything after can be 
defined by the user. The following allows one to define an identity schema based on the concepts talked about in
the [SPIFFE/SPIRE book](https://spiffe.io/book) Chapter 8: Using SPIFFE Identities to Inform Authorization.

An example of an identity schema can be like the following:
```
spiffe://trustdomain.org/v1/<provider>/<region>/<workload-namespace>/<workload-pod-name>
```
Where version is the versioning of the identity schema. The other fields would
indicate user defined or attestation properties. For example, provider would 
indicate the cloud provider, and workload would be the pod information, determined 
by via attestation configuration and/or metadata configured in the runtime. 

User defined fields can also be created, specifying additional metadata on the
cluster, node or workloads via annotations and labels.


## Example Specification of schema

We define the ability to specify a schema through a YAML/JSON structure. In this
section, we will show how one can define a simpler schema that looks like the 
following:

```
spiffe://trustdomain.org/v1/<provider>/<region>/<workload-namespace>/<workload-pod-name>
```

The following YAML is an example of a definition to achieve the above identity schema:
```
identity-schema:
    version: v1
    fields:
    - name:provider
      source: 
        nodeAttestor:
          mapping:
          - from: aws_iid:*
            to: aws
          - from: gcp_iit:*
            to: gcloud
          - from: azure_msi:*
            to: azure
    - name: region
      source: 
        k8s:
          configMap:
            ns: kube-system
            name: cluster-info
            field: cluster-region
    - name: workload-namespace
      source:
        workloadAttestor:
          mapping:
          - from: k8s:ns:?ns
            to: ${ns}
    - name: workload-podname
      source:
        workloadAttestor:
          mapping:
          - from: k8s:pod-name:?podName
            to: ${podName}
```


Based on the above designed schema:
```
spiffe://trustdomain.org/v1/<provider>/<region>/<workload-namespace>/<workload-pod-name>

```
An instance of an identity registered would look like:
```
spiffe://trustdomain.org/v1/aws/eu-de/medical/patient-data-processor
```
If:
- The node on which the pod runs has an AWS attestation with the node attestor `aws_iid`
- The configmap `cluster-info` in `kube-system` in field `cluster-region` has value `eu-de`
- The pod is run in kubernetes namespace `medical`
- The pod has name `patient-data-processor`


## How identity schema definitions can be used

The identity schema definitions can be consumed in two main ways. One is by the cluster
that will be assisting in performing SPIRE entry registration. One or more identity schemas
can be defined (by version) to help provide backward compatibility or use of multiple schemas
for different purposes.

The other consumer of this is the policy engine enforcing the SPIRE registrations (i.e. OPA).
The policy engine will use this identity schema definition to ensure that entries adhere to the 
necessary attestation enforcements when available. For example, if an identity of 
`spiffe://trustdomain.org/v1/aws/.../patient-data-processor` is registered, the entry being 
registered must have the node selector`aws_iit:...` and workload selector  `k8s:pod-name: patient-data-processor`.


## Complex schema trees

In some scenarios, there may be a need for a schema to branch. An example of this is illustrated
in the [SPIFFE/SPIRE book](https://spiffe.io/book) Chapter 8: Using SPIFFE Identities to Inform Authorization.
In that scenario there are two different platforms, Kubernetes and Openstack and each has its own
set of metadata.

A definition of a split may look something like the following:
```
identity-schema:
    version: v1
    fields:
    - name:provider
      source: 
        nodeAttestor:
          mapping:
          - from: aws_iid:*
            to: aws
          - from: gcp_iit:*
            to: gcloud
          - from: azure_msi:*
            to: azure
    - name: platform
      schema-branch:
      - name: kubernetes
        subSchema: kubernetes-schema
      - name: openstack
        subSchema: openstack-schema

    subSchemas:
    - name: kubernetes-schema
      schema:
      - name: region
        source: 
          k8s:
            configMap:
              ns: kube-system
              name: cluster-info
              field: cluster-region
      - name: workload-namespace
        source:
          workloadAttestor:
            mapping:
            - from: k8s:ns:?ns
              to: ${ns}
      - name: workload-podname
        source:
          workloadAttestor:
            mapping:
            - from: k8s:pod-name:?podName
              to: ${podName}
    - name: openstack-schema
      schema:
      - name: vm-name
        source: 
        ...
```

This above configuration would result in the following schema for both platforms:

Kubernetes
```
spiffe://trustdomain.org/v1/<provider>/kubernetes/<region>/<workload-namespace>/<workload-pod-name>
spiffe://trustdomain.org/v1/aws/kubernetes/eu-de/medical/patient-data-processor
```
Openstack
```
Schema:  spiffe://trustdomain.org/<version>/<provider>openstack/<vm-name>
Example: spiffe://trustdomain.org/v1/aws/openstack/my-vm
```
