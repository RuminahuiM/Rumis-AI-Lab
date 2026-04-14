# GitHub Actions — One-Click Deploy to AWS EC2

This document covers everything you need to run `.github/workflows/deploy.yml`:
the IAM policy to attach to your deploy user, every secret to add in GitHub,
and how to verify the deployment.

---

## Prerequisites

- An AWS account with an existing **Elastic IP** in `eu-north-1`
- A GitHub **Personal Access Token** (PAT) with `repo` read scope
- DNS records for your subdomains already pointing at the Elastic IP

---

## 1 — AWS IAM Setup

### 1a. Create the deploy IAM user

In the AWS Console → IAM → Users → **Create user**.  
Name it `rumis-ai-lab-deploy` (or similar).  
Select **Programmatic access** and save the access key + secret.

### 1b. Attach the deploy policy

Create a new managed policy with the JSON below, attach it to the deploy user.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2Provision",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeImages",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateTags",
        "ec2:TerminateInstances",
        "ec2:DescribeAddresses",
        "ec2:AssociateAddress",
        "ec2:DisassociateAddress"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMForEC2Role",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:GetRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:DeleteRole",
        "iam:CreateInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:ListAttachedRolePolicies",
        "iam:TagRole"
      ],
      "Resource": [
        "arn:aws:iam::*:role/RumisAILabEC2Role",
        "arn:aws:iam::*:instance-profile/RumisAILabEC2Profile"
      ]
    },
    {
      "Sid": "PassRoleToEC2Only",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::*:role/RumisAILabEC2Role",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    },
    {
      "Sid": "SSMOperations",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:DescribeInstanceInformation"
      ],
      "Resource": "*"
    }
  ]
}
```

The workflow will automatically create `RumisAILabEC2Role` and
`RumisAILabEC2Profile` on first run (idempotent — safe to re-run).

---

## 2 — GitHub Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret**
for each row below.

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | Deploy user access key ID |
| `AWS_SECRET_ACCESS_KEY` | Deploy user secret access key |
| `AWS_ELASTIC_IP_ALLOCATION_ID` | Allocation ID of your Elastic IP, e.g. `eipalloc-0123456789abcdef0` (find it in EC2 → Elastic IPs) |
| `GH_PAT` | GitHub PAT with `repo` read scope — lets EC2 clone this private repo |
| `ANTHROPIC_API_KEY` | Anthropic API key |
| `OPENAI_API_KEY` | OpenAI API key |
| `GEMINI_API_KEY` | Google Gemini API key |
| `HF_TOKEN` | HuggingFace token (optional, for gated models) |
| `LITELLM_MASTER_KEY` | Master key for LiteLLM proxy, e.g. `sk-rumis-master-...` |
| `OUI_DOMAIN` | Open WebUI subdomain, e.g. `oui.ruminahui.ch` |
| `OC_DOMAIN` | OpenClaw subdomain, e.g. `oc.ruminahui.ch` |
| `CERTBOT_EMAIL` | Email for Let's Encrypt expiry notifications |
| `OC_AUTH_USER` | Username for OpenClaw nginx basic auth |
| `OC_AUTH_PASSWORD` | Password for OpenClaw nginx basic auth |

> **Note:** `GH_PAT` must **not** be named `GITHUB_TOKEN` — that name is
> reserved by GitHub Actions and cannot be used as a custom secret.

---

## 3 — DNS

Before triggering the workflow, ensure both subdomains resolve to your
Elastic IP:

```
oui.ruminahui.ch  →  <your Elastic IP>
oc.ruminahui.ch   →  <your Elastic IP>
```

Let's Encrypt will fail to issue certificates if DNS is not propagated.

---

## 4 — Running the Workflow

1. Go to **Actions → Deploy to AWS EC2 → Run workflow**
2. In the confirmation field, type exactly: `deploy`
3. Click **Run workflow**

### What happens (~12–15 min total)

| Step | Duration |
|------|----------|
| IAM role/profile (idempotent) | ~30 s |
| Old instance teardown + EIP disassociation | ~2 min |
| New instance launch | ~1 min |
| EIP association | ~10 s |
| UserData: Docker install + swap | ~3–4 min |
| SSM agent online | ~1 min |
| Repo clone + `init-ssl.sh` + `docker compose up` | ~5–7 min |

---

## 5 — Verification

After the workflow completes, verify all services:

```bash
# Open WebUI (HTTP/2 200)
curl -sI https://oui.ruminahui.ch | head -1

# OpenClaw (401 = nginx basic auth working)
curl -sI https://oc.ruminahui.ch  | head -1
```

Or with credentials:
```bash
curl -sI -u admin:yourpassword https://oc.ruminahui.ch | head -1
```

---

## 6 — Re-deploying

Simply run the workflow again. It will:
- Disassociate the Elastic IP from the current instance
- Terminate the current instance
- Provision a fresh instance and re-associate the IP
- Re-clone and re-deploy the stack

Docker volumes (Open WebUI data, OpenClaw config) are on ephemeral instance
storage and will be **lost** on each redeploy. If you need persistence, attach
an EBS volume and mount it before running `docker compose up`.

---

## 7 — Troubleshooting

**SSM agent never comes online**  
The instance profile may not have the `AmazonSSMManagedInstanceCore` policy.
Check IAM → Instance profiles → `RumisAILabEC2Profile` → Roles → Policies.

**`init-ssl.sh` fails: certificate not issued**  
DNS is not yet pointing at the new Elastic IP. Check with:
```bash
dig +short oui.ruminahui.ch
```
Wait for propagation, then redeploy.

**Deploy command fails: `docker: command not found`**  
UserData is still running when SSM executes the deploy script. The deploy
script polls for Docker for up to 5 minutes; if this keeps failing, check
`/var/log/userdata.log` on the instance via the AWS Console Session Manager.

**View deploy logs on the instance**  
Use AWS Console → Systems Manager → Session Manager → Start session →
select the instance, then:
```bash
tail -f /var/log/rumis-deploy.log
tail -f /var/log/userdata.log
```
