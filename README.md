# Redpanda BYOC: IaC + CI/CD promotion demo

Manages Redpanda data plane resources on existing BYOC clusters with Terraform, and promotes changes **dev → prod** through GitHub Actions.

| Resource | Terraform | Name |
|---|---|---|
| Topic | `redpanda_topic.demo` | `mskcc-demo-topic` |
| User (SCRAM-SHA-256) | `redpanda_user.demo` | `mskcc-demo-user` |
| Role | `redpanda_role.demo` | `mskcc-demo-role` |
| ACLs (DESCRIBE/READ/WRITE on topic, bound to the role) | `redpanda_acl.demo_role_topic` | `RedpandaRole:mskcc-demo-role` |
| Role binding | `redpanda_role_assignment.demo` | `User:mskcc-demo-user` → `mskcc-demo-role` |

All names come from `local.name_prefix` in `main.tf`.

## Layout

```
main.tf, variables.tf, outputs.tf, versions.tf   # one config, promoted unchanged
envs/<env>.tfvars                                 # per-env differences (partitions, deletion protection)
envs/<env>.s3.tfbackend                           # per-env state key in S3 (bucket/region injected by CI)
bootstrap/                                        # one-time: S3 state bucket + GitHub OIDC IAM role
.github/workflows/pipeline.yml                    # orchestration
.github/workflows/terraform-run.yml               # reusable init/plan/apply/destroy job
.github/workflows/destroy.yml                     # manual teardown (prod still gated)
```

## Pipeline

```
PR ──► checks (fmt, validate) ──► plan dev (plan in job summary)

merge to main ──► checks ──► apply dev (auto) ──► ⏸ approval ──► apply prod
```

- **Checks**: `terraform fmt -check`, `terraform validate`.
- **dev**: applies automatically once checks pass on `main`.
- **prod**: GitHub Environment `prod` requires reviewer approval. The job plans and applies only after approval.
- Credentials are scoped per GitHub Environment. The dev job can't read prod secrets.
- **Destroy**: run *redpanda-iac-destroy* manually (Actions → redpanda-iac-destroy → Run workflow, or `gh workflow run destroy.yml -f environment=dev -f confirm=dev`). You must type the environment name to confirm, and prod waits for the same approval. The workflow lifts deletion protection on resources in state before destroying, so protected prod resources are actually deleted rather than just dropped from state.
- The user password uses a write-only argument plus an ephemeral variable, so it is never stored in state or plan files.

## Setup

### 1. Redpanda Cloud
Create a service account for **each** environment in Redpanda Cloud (Organization IAM → Service accounts). Note each client ID and secret, and each cluster's ID.

### 2. AWS state backend (one time)
```bash
cd bootstrap
terraform init
terraform apply -var region=us-west-2 -var state_bucket_name=<unique-bucket-name>   # add -var create_oidc_provider=false if the account already has one; set github_oidc_sub_prefix for your repo
```
Outputs `state_bucket` and `ci_role_arn`.

### 3. GitHub
This repo is public (GitHub Free only supports required reviewers on public repos), so no account-specific values are committed. They're injected from GitHub variables and secrets.

Repo **variables**:
- `AWS_ROLE_ARN`: the `ci_role_arn` output
- `AWS_REGION`: e.g. `us-east-1`
- `TF_STATE_BUCKET`: the `state_bucket` output

**Environment variable** on both `dev` and `prod`:
- `REDPANDA_CLUSTER_ID`: that environment's BYOC cluster ID

**Environment secrets** on both `dev` and `prod`:
- `REDPANDA_CLIENT_ID`
- `REDPANDA_CLIENT_SECRET`
- `APP_USER_PASSWORD`

The `prod` environment has **Required reviewers** and a branch policy that allows `main` only.

```bash
gh variable set AWS_ROLE_ARN --body "arn:aws:iam::<acct>:role/redpanda-iac-demo-ci"
gh variable set AWS_REGION   --body "us-east-1"
gh variable set TF_STATE_BUCKET --body "<bucket>"
gh variable set REDPANDA_CLUSTER_ID --env dev  --body "<dev-cluster-id>"
gh variable set REDPANDA_CLUSTER_ID --env prod --body "<prod-cluster-id>"
for e in dev prod; do
  gh secret set REDPANDA_CLIENT_ID     --env $e
  gh secret set REDPANDA_CLIENT_SECRET --env $e
  gh secret set APP_USER_PASSWORD      --env $e
done
```

## Demo script

1. **Initial rollout**: push the config to `main`. dev applies, prod waits for approval, approve, prod applies.
2. **Promote a change**:
   ```bash
   git checkout -b retention-3d
   # main.tf: "retention.ms" = "259200000"
   git commit -am "Reduce demo topic retention to 3 days" && git push -u origin retention-3d
   gh pr create --fill
   ```
   The PR runs checks and a dev plan (visible in the run summary). Merge it: dev updates automatically and prod waits for approval.
3. **Show a failed gate**: push a mis-formatted `.tf` file in a PR. `checks` fails, and nothing is planned or applied.
4. **Verify** with rpk against each cluster:
   ```bash
   rpk topic describe mskcc-demo-topic -c
   rpk security role describe mskcc-demo-role
   rpk security acl list --allow-role mskcc-demo-role
   ```
5. **Rotate the password**: change the `APP_USER_PASSWORD` secret and bump `app_user_password_version`.

## Notes
- `allow_deletion = false` in prod: removing a resource from code drops it from state but leaves it on the cluster (a safety net).
- Deleting the role also deletes the ACLs bound to it.
- Runners must reach the clusters' data plane API. For private BYOC clusters, switch `runs-on` to a self-hosted runner in (or peered with) the VPC.
- Possible extensions: tflint/checkov/OPA in `checks`, a saved prod plan reviewed before approval, and scheduled drift detection (`plan -detailed-exitcode`).
