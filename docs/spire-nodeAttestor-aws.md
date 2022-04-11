# Setting up the SPIRE AWS NodeAttestor

## Setting up the cluster
Get AWS cli:
https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-mac.html

Configure cli:
https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-config

```console
aws configure
# get identtiy info:
aws sts get-caller-identity
# after the cluster created:
aws eks --region us-east-1 update-kubeconfig --name tsi-test-03
aws eks --region us-east-1 update-kubeconfig --name tsi-test-03 --kubeconfig /tmp/tsi-test-03

```

Install:
https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html


## Create AWS cluster:
```console
# create VPC stack (for netwo)
aws cloudformation create-stack \
  --region us-east-1 \
  --stack-name tsi-eks-vpc-stack \
  --template-url https://amazon-eks.s3.us-west-2.amazonaws.com/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml

# create: cluster-role-trust-policy.json

aws iam create-role \
  --role-name tsiAmazonEKSClusterRole \
  --assume-role-policy-document file://"cluster-role-trust-policy.json"

aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
  --role-name tsiAmazonEKSClusterRole
```

Configure the client:
```
# list clusters
aws eks list-clusters
# get KUBECONFIG
aws eks update-kubeconfig \
  --region us-east-1 \
  --name tsi-test-03

# test:
kubectl get svc
```

Cluster --> Configuration --> Details:
OpenID Connect provider URL:
https://oidc.eks.us-east-1.amazonaws.com/id/1CE11xxxx

Created: oidc.eks.us-east-1.amazonaws.com/id/1CE11xxxx

## Create nodes in the cluster

```console
# create  pod-execution-role-trust-policy.json
aws iam create-role \
  --role-name tsiAmazonEKSFargatePodExecutionRole \
  --assume-role-policy-document file://"pod-execution-role-trust-policy.json"

  aws iam attach-role-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy \
    --role-name tsiAmazonEKSFargatePodExecutionRole
````

## Using `eksctl`

https://eksctl.io/

Install `eksctl` on mac:
```console
brew install eksctl
```

```console
eksctl create cluster \
 --name tsi-test-03 \
 --region us-east-1 \
 --nodegroup-name linux-tsi-nodes \
 --node-type t2.medium \
 --nodes 2

eksctl delete cluster --name tsi-test-02
```

 get KUBECONFIG

```console
# aws eks --region <region-code> update-kubeconfig --name <cluster_name>
aws eks --region us-east-1 update-kubeconfig --name tsi-test-03

# aws eks --region <region-code> update-kubeconfig --name <cluster_name> --kubeconfig <file>
aws eks --region us-east-1 update-kubeconfig --name tsi-test-03 --kubeconfig /tmp/tsi-test-03
```

## Setting up SPIRE Server
in SPIRE server config:

```json
NodeAttestor "aws_iid" {
    plugin_data {
      access_key_id = "ACCESS_KEY_ID"
      secret_access_key = "SECRET_ACCESS_KEY"
      skip_block_device = true
    }
}
```

## Installing SPIRE agents
```console
helm install --set "spireServer.address=$SPIRE_SERVER" --set "clustername=tsi-test-03" --set "region=us-east-1" --set "trustdomain=openshift.space-x.com" spire charts/spire --debug
```

## ** Comments **
SPIRE nodeAttestor allows only the first instance to register with the SPIRE server.
If you get an error:
```
time="2021-08-19T16:48:43Z" level=error msg="Agent crashed" error="failed to get SVID: error getting attestation response from SPIRE server: rpc error: code = Internal desc = failed to attest: aws-iid: IID has already been used to attest an agent"
```
Delete the old agent object under "Agents"-->"Agent List" using Tornjak.
This should reset the record and allow agent to re-register.

## Setting up the Workload Registrar with AWS attestion.
To use AWS nodeAttestor, we need to create a separate entry per each agent,
using 'fleetId' as Selector, since this is the only attribute that guarantees the uniqueness.


Here are the sample entries for 2 nodes:
```console
/opt/spire # bin/spire-server entry show -socketPath /run/spire-server/private/api.sock
Found 30 entries

Entry ID         : 45186513-3ca2-4240-8e8b-5f1dd01aec7f
SPIFFE ID        : spiffe://openshift.space-x.com/k8s-workload-registrar/aws-tsi-test-03/node/ip-192-168-30-233.ec2.internal
Parent ID        : spiffe://openshift.space-x.com/spire/server
Revision         : 0
TTL              : default
Selector         : aws_iid:tag:aws:ec2:fleet-id:fleet-92fce57d-a9ff-8f79-ac1a-ab881fc88d49

Entry ID         : 40eefa40-94db-4ea5-8786-e5c45fcc4b0c
SPIFFE ID        : spiffe://openshift.space-x.com/k8s-workload-registrar/aws-tsi-test-03/node/ip-192-168-62-164.ec2.internal
Parent ID        : spiffe://openshift.space-x.com/spire/server
Revision         : 0
TTL              : default
Selector         : aws_iid:tag:aws:ec2:fleet-id:fleet-325e4fd5-8b5f-27d9-ac98-a9028cd63d23
```

Fleet Id can be obtained form the AWS portal:
https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#InstanceDetails:instanceId=i-0767cbf5aa2cxxx  (Tags)

Get AWS tags:
```console
https://stackoverflow.com/questions/3883315/query-ec2-tags-from-within-instance/3890289#38902xxx
```

From the agent container:
```
wget -qO- http://169.254.169.254/latest/meta-data/instance-id

```

Get metadata:

```console
wget -qO- http://169.254.169.254/latest/meta-data/instance-id
wget -qO- http://169.254.169.254/latest/meta-data/identity-credentials/ec2/info
```

Get identity token:
```console
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` \
&& curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/dynamic/instance-identity/document
```


Get Fleet id:
```console
wget -qO- http://169.254.169.254/latest/meta-data/instance-id
aws ec2 describe-instances --instance-id i-0767cbf5aa2c6c6a9 > /tmp/out2
```
