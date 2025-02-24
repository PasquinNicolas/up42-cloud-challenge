# Challenge Implementation Thoughts

I am doing this challenge completly sick with a gastro ,
I did my best with the limited time I could really work on this. 

### .1

- First challenge for me was the machine I was using. Because of the last project I worked on, I had to use Windows + WSL2. 
- I Started to do a test install of Minikube inside WSL2 with Docker driver - Extremely Slow.
- Install Metallb for Loadbalancing head scratch -- this is not working.
- Then I had many networking issue because WSL2 does not use bridge mode anymore but mirrored - (Network Mess) ... Try VirtualBox 
- Can't have WSL2 on Windows 11 and virtualbox runing at the same time. 

Solution:

Use of 3 nodes Microk8s cluster install on a Proxmox VM I had on the side


### .2

- Installed everything , started the deployment , impossible to have this deployed properly. 
- Minio keep CrashloopBackoff , burried in logs : "Fatal glibc error: CPU does not support x86-64-v2" 
  My cpu was to old.


Solution:

Add cpuv1 after the release in minio and mc images: "minio:RELEASE.2024-01-18T22-51-28Z-cpuv1"


### .3

- Deploy Minio and S3www lets add inter pod mtls.
- Install Certmanager , Minio work with the selfsigned certificate but s3www does not.
- In the meantime lets check prometheus Minio export metrics on /metrics, S3www does not.


Solution:

Installation on Linkerd service mesh, create Mtls between pods with sidecar proxy.
Add the same time provide a trace and logging with prometheus on all linkerd patch namespace or pods.

### .4

- During testing the "file to serve" was a .txt docukent of a few kb. Fisrt that came in mind was a configmap and load everything inside.
- When used the real .gif, the file was to big, first compressed it, did not worked .

Solution:

Build my own image of minio client  minio/mc and copy the gif inside.
Push to my gitlab registry, and use in an init-job side container to load the gif file to the bucket at startup time.

 

  
## Design Decisions

Architecture:

- S3www and Minio deployed on 3 nodes HA Microk8s Kubernetes.
- Terraform for deployment.
- Helm for Packagind and deployment.

Scalability:
- HPA with a target ofcpu 60%


Security:

Secrets are handled by a 3 node HA Hashicorp Vault integrated with ESO. External Secret Operator.
Policy applied to the access of the S3 bucket.
Trivy installed scanning all pod deployed

Access:
Metallb load Balancer + Nginx ingress Controller.


 

## Concerns and Considerations

- This application s3www is listening on 127.0.0.1:8080 to have this working with a load balancer and ingress controller
I had to change the listening port to 0.0.0.0:8080 which is not the best in regard to security.

- CI/CD will likely fail, with a chicken and eggs issue:
Terraform is deploy: namespace, secret store and secret needed for the App deployment. To the vault.
The values are not retrieved from Gitlab variables but from Teraform asking to check Vault for creentials.



## Future Improvements

- Use RBAC for access or Keycloack and Gitlab oidc.
- Have a jump server to manage the cluster and not use my local machine.
- Separate Infrastructure deployment in Terraform and Application which is the best practice in DEVOPS.
- Consider Testing the Helm Chart before deployment.
- Cenralise all secrets to one location. To simplify this: I could create a namespace different from my application , store all the secrets needed for
my deployment in it.
- Currently all the pvc are on longhorn and can be backedup tp and S3 Bucket.
- Can use Velero to backup the volumes if another solution than Longhorn is used.
