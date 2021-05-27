# OIDC Tutorial with AWS S3
This tutorial shows steps for creating a sample AWS identity provider, policy, role, and S3 bucket.
Then test the deployment by accessing the S3 bucket from the workload.

This tutorial is based on the documentation for [Using SPIRE and OIDC to Authenticate
Workloads on Kubernetes to AWS S3](https://spiffe.io/docs/latest/keyless/oidc-federation-aws/)

This part of the tutorial assumes that OIDC is already [enabled on SPIRE](./spire-oidc-tutorial.md)

### Create AWS S3 Bucket and Test File

1. Create a text file on your local computer called `test.txt` and there some text.

2. Navigate to the [AWS Amazon S3](https://s3.console.aws.amazon.com/s3/home) page, logging in if necessary.

3. Click **Create bucket**. Under **Bucket name** type a name for the S3 bucket that you’ll use for testing. The bucket name must be unique across all S3 bucket names in Amazon S3 since buckets can be accessed via a URL.
e.g. `tsi-spire-bucket`

4. Leave the **Region**, **Bucket settings for Block Public Access**, and **Advanced settings** at the default values and click **Create bucket**.

5. Click the name of your bucket to open the bucket.

6. Click Upload.

7. Add the `test.txt` file to the upload area using your local file navigator or drag and drop. Click *Upload*.

### Set up an OIDC Identity Provider on AWS

1. Navigate to the [AWS Identity and Access Management (IAM)](https://console.aws.amazon.com/iam/home?#/home) page, logging in if necessary.

2. Click **Identity Providers** on the left and then click **Add Provider** at the top of the page.

3. For Provider Type, choose **OpenID Connect**.
   For Provider URL use the value output by the OpenShift install script that we tested earlier, but without the `/.well-known/openid-configuration` suffix:
   ```
   https://oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud
   ```
    Then press **Get thumbprint** button.

4. For Audience, type **mys3**. The SPIRE Agent presents this string to AWS when authenticating to the Amazon S3 bucket.

5. Click **Next Step**. AWS verifies access to the Provider URL after you click the button and displays an error if it is inaccessible. If this occurs, ensure that the OIDC endpoint is accessible.

6. Verify the information on the **Verify Provider Information** page and if OK, click **Create**.

### Create an AWS IAM Policy
These steps create AWS IAM policy governing access to the S3 bucket.
1. While still on **AWS Identity and Access Management (IAM)** portal, click **Policies** on the left and then click **Create policy** in the top middle of the page.

2. Select the **JSON** tab.

3. Replace the existing skeleton JSON with the following JSON policy definition and replace MY_TEST_BUCKET with the name of the S3 test bucket that you created earlier:
  ```
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:PutAccountPublicAccessBlock",
                "s3:GetAccountPublicAccessBlock",
                "s3:ListAllMyBuckets",
                "s3:ListJobs",
                "s3:CreateJob",
                "s3:ListBucket"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::MY_TEST_BUCKET",
                "arn:aws:s3:::MY_TEST_BUCKET/*",
                "arn:aws:s3:*:*:job/*"
            ]
        }
    ]
  }
  ```
4. Click **Review policy**.

5. For Name, type the name **oidc-federation-test-policy**.

6. Click **Create policy**.


### Create an AWS IAM Role for the Identity Provider
The IAM role contains the connection parameters for the OIDC federation to AWS such as the OIDC identity provider, IAM policy, and SPIFFE ID of the connecting workloads.

1. Click **Roles** on the left and then click **Create Role** in the middle of the page.

2. Click **Web Identity** near the top of the page.

3. For **Identity provider**, choose the identity provider that you created in AWS. The identity provider will be your Discovery document followed by `:aud`, such as `oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud:aud`.

    For **Audience**, choose the audience you specified in the identity provider: `mys3`.

    Click **Next: Permissions**.

4. Search for the policy that you created in the previous section: `oidc-federation-test-policy`. Click the **check box** next to that policy and then click **Next: Tags**. (Don’t click the name of the policy.)

5. Click **Next: Review** to skip the **Add Tags** screen.

6. Type the name `oidc-federation-test-role` for the IAM role and click **Create role**.


### Add the SPIFFE ID to the IAM Role
To allow the workload from outside AWS to access AWS S3, add the workload’s SPIFFE ID to the IAM role. This restricts access to the IAM role to JWT SVIDs with the specified SPIFFE ID.

1. Click **Roles** on the left, use the search field to find the `oidc-federation-test-role` IAM role that you created in the last section, and click the role.

2. At the top of the **Summary** page, next to **Role ARN**, copy the role ARN into the clipboard by clicking the small icon at the end. Save the ARN in a file such as `oidc-arn.txt` for use in the testing section.

3. Click the **Trust relationships** tab near the middle of the page and then click **Edit trust relationship**.

4. In the JSON access control policy, modify a condition line at the end of the `StringEquals` attribute to restrict access to workloads matching the workload SPIFFE ID that we will be using for testing. The new code is:

  ```
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "ForAllValues:StringLike": {
        "oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud:sub": "spiffe://openshift.space-x.com/eu-*/*/*/elon-musk/mars-mission-main/c0d076b51c28dc937a70a469b4cc946fb465ab6c86d6ae89ae2cf8eac1f55d6b",
        "oidc-tornjak.space-x-01-9d995c4a8c7c5f281ce13d5467ff-0000.us-south.containers.appdomain.cloud:aud": "mys3"
      }
    }
  ```
  This policy states that only containers with `openshift.space-x.com` trust domain, deployed in Europe, running on `elon-mask` service account with `mars-mission-main` container can access this S3 bucket.

5. Click **Update Trust Policy**. This change to the IAM role takes a minute or two to propagate.


## Test Access to AWS S3
We are going to start a container in our SPIRE environment. This container has AWS S3 as well as SPIRE agent binaries for running the experiment.

Additionally, the test deployment file [examples/spire/mars-spaceX.yaml](examples/spire/mars-spaceX.yaml) has an annotation like this:

```yaml
metadata:
  annotations:
    spire-workload-id: eu-de/space-x.01/default/elon-musk/mars-mission-main/c0d076b51c28dc937a70a469b4cc946fb465ab6c86d6ae89ae2cf8eac1f55d6b

```
This represent a sample identity of this container. Just for the demo purpose.

Start the test container in `default` namespace.
```
oc project default
oc create -f examples/spire/mars-spaceX.yaml -n default
```

When pod is created, get inside:
```
oc get po
NAME                           READY   STATUS    RESTARTS   AGE
mars-mission-68ddb9567-6x7hs   1/1     Running   0          101s
oc exec -it mars-mission-68ddb9567-6x7hs -- sh
```

Once inside, let's try to obtain this pod's identity, if form of the JWT token,
requesting **audience** for `mys3`:
```console
bin/spire-agent api fetch jwt -audience mys3 -socketPath /run/spire/sockets/agent.sock
```

Get the long JWT token that follows the `token(spiffe://openshift.space-x.com/eu-de/space-x.01/default/elon-musk/mars-mission-main/c0d076b51c28dc937a70a469b4cc946fb465ab6c86d6ae89ae2cf8eac1f55d6b):`
and save it in the file `token.jwt`.

Now, build the AWS request, where:
* `AWS_ROLE_ARN` is the value you captured earlier in `oidc-arn.txt` file
* `AWS_WEB_IDENTITY_TOKEN_FILE` references the file with the token (`token.jwt`)
* S3 represents the bucket you created at the beginning.

In our example this would be:

```console
AWS_ROLE_ARN=arn:aws:iam::581274594392:role/oidc-federation-test-role-space-x-01 AWS_WEB_IDENTITY_TOKEN_FILE=token.jwt aws s3 cp s3://tsi-spire-bucket/test.txt secret-file.txt
```

If everything went fine, we should now have a local file `secret-file.txt` that
contains the information stored in S3 bucket.

If you like, you can now try the [Vault secrets](./spire-oidc-vault.md) tutorial.
