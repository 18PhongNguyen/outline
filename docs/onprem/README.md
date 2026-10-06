# Outline on-prem (AWS Neverland) - vận hành

Thiết kế chi tiết: [design.md](design.md).

## Kiến trúc
- 1 EC2 t3.small (AL2023, EIP) chạy docker compose: caddy (TLS) + outline + postgres 16 + redis 7.
- File upload lưu S3 `outline-attachments-970385383746` qua instance role; secret nằm ở SSM `/outline/*`.
- Image build từ source trên GitHub Actions (`Dockerfile.base` -> `Dockerfile`), push ECR, deploy bằng SSM Run Command (không SSH).
- Backup `pg_dump` hằng ngày 19:00 UTC (systemd `outline-backup.timer`) lên `outline-backups-970385383746`, giữ 14 ngày.
- Hạ tầng bằng Terraform: `infra/terraform/bootstrap` (state bucket) và `infra/terraform/main`.

## Bootstrap (một lần, chạy local bằng AWS creds của account 970385383746)
1. `cd infra/terraform/bootstrap && terraform init && terraform apply` (tạo state bucket).
2. `cd ../main && terraform init && terraform apply`.
3. Tạo record A `outline.launch-mate.com` -> output `elastic_ip` (ở account giữ zone `launch-mate.com`).
4. Tạo Google OAuth client, redirect URI `https://outline.launch-mate.com/auth/google.callback`, rồi:
   ```
   aws ssm put-parameter --name /outline/GOOGLE_CLIENT_ID --type SecureString --overwrite --value '...'
   aws ssm put-parameter --name /outline/GOOGLE_CLIENT_SECRET --type SecureString --overwrite --value '...'
   ```
5. Đặt GitHub repo variables từ Terraform outputs: `AWS_REGION`, `AWS_DEPLOY_ROLE_ARN`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `ECR_REGISTRY`, `DEPLOY_BUCKET`, `INSTANCE_ID`, `TF_STATE_BUCKET`. Tạo environment `production` (required reviewer).
6. Chạy workflow `build-deploy` (workflow_dispatch). Kiểm tra `curl -fsS https://outline.launch-mate.com/_health` trả `OK`.
7. Đăng nhập Google; user đầu tiên tạo workspace, sau đó giới hạn domain trong Settings.

## Deploy
Push lên `main` (trừ thay đổi chỉ ở `infra/**`, `docs/**`) hoặc chạy tay `build-deploy`. Job `deploy` upload `deploy/` lên S3, chạy `deploy.sh <sha>` trên máy: render `.env` từ SSM, backup `pre-deploy`, `up -d`, chờ `/_health` tối đa 5 phút. Fail thì tự quay về tag cũ và job đỏ. Migration DB do Outline tự chạy lúc start.

Infra: PR sửa `infra/terraform/main/**` chạy `plan` và comment vào PR; `apply` chạy tay qua workflow `terraform` (cần approve environment `production`).

## Rollback tay
Mở session: `aws ssm start-session --target <INSTANCE_ID>`, rồi:
```
sudo -i
cat /opt/outline/state/previous_tag
ls /opt/outline/releases/
bash /opt/outline/releases/<previous_tag>/deploy.sh <previous_tag>
```
Lưu ý: nếu bản mới đã chạy migration thì rollback image có thể lỗi; khi đó restore backup `pre-deploy` (bên dưới).

## Backup / restore
- Chạy tay: `sudo systemctl start outline-backup.service`; file nằm ở `s3://outline-backups-970385383746/`.
- Restore (trên instance, root):
  ```
  aws s3 cp s3://outline-backups-970385383746/<file>.dump /tmp/restore.dump
  C="docker compose -p outline -f /opt/outline/current/docker-compose.yml --env-file /opt/outline/.env"
  $C stop outline
  $C exec -T postgres dropdb -U outline outline
  $C exec -T postgres createdb -U outline outline
  $C exec -T postgres pg_restore -U outline -d outline --no-owner < /tmp/restore.dump
  $C start outline
  ```

## Sync upstream
Từ repo root, working tree sạch: `scripts/onprem/sync-upstream.sh v1.11.0`. Script fetch tag, tạo nhánh `sync/<tag>`, merge, xoá workflow upstream, push và mở PR bằng `gh`. Conflict ngoài `.github/workflows/` phải xử lý tay. Merge PR thì `build-deploy` chạy.
