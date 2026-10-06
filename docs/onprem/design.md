# Outline on-prem trên AWS Neverland — Design

Ngày: 2026-10-06 · Repo triển khai: https://github.com/18PhongNguyen/outline (fork public của `outline/outline`)

## Mục tiêu
- Outline self-hosted tại `https://outline.launch-mate.com`, cấu hình tối thiểu (~22 USD/tháng).
- Login Google Workspace.
- CI/CD: push `main` của fork → build image từ source → deploy tự động, rollback khi health fail.
- Toàn bộ hạ tầng bằng Terraform trong chính fork.

## Quyết định đã chốt
| Mục | Chọn |
|---|---|
| AWS account | `970385383746` (Neverland), region `ap-southeast-1` |
| Compute | 1 EC2 t3.small (2GB + 2GB swap), AL2023, gp3 30GB, Elastic IP |
| Runtime | docker compose: caddy + outline + postgres:16 + redis:7 |
| File storage | S3 private bucket |
| Auth | Google OAuth |
| DNS | Zone `launch-mate.com` ở account khác → record A tạo tay, trỏ EIP (Terraform output) |
| CI/CD | GitHub Actions trên fork, OIDC assume role, deploy qua SSM (không SSH) |
| Base code | `main` fork = upstream tag `v1.10.1` + thư mục infra |

## Cấu trúc thêm vào fork
```
infra/terraform/
  bootstrap/        # state bucket (apply local 1 lần)
  main/             # mọi resource còn lại, backend S3 use_lockfile
deploy/
  docker-compose.yml
  Caddyfile
  deploy.sh         # render .env từ SSM, pull, up, health, rollback
  backup.sh         # pg_dump → S3
.github/workflows/
  build-deploy.yml
  terraform.yml
scripts/onprem/sync-upstream.sh
docs/onprem/README.md  # bootstrap + vận hành
```
Workflow upstream sẵn có trong `.github/workflows/` bị xoá khỏi fork (tránh chạy lỗi/tốn minutes).

## Terraform resources (`infra/terraform/main`)
- **Mạng:** default VPC; SG ingress 80/443 từ 0.0.0.0/0, không mở 22.
- **EC2:** t3.small, IMDSv2 bắt buộc, EBS gp3 30GB encrypted, EIP. `user_data`: cài docker + compose plugin, tạo swap 2GB, cron `backup.sh` 19:00 UTC hằng ngày.
- **S3:** `<prefix>-attachments` (block public, CORS cho domain), `<prefix>-backups` (lifecycle xoá 14 ngày), `<prefix>-deploy` (bundle `deploy/` do CI upload). Tất cả SSE-S3.
- **ECR:** repo `outline`, lifecycle giữ 10 image.
- **IAM instance role:** `AmazonSSMManagedInstanceCore`, ECR pull, S3 RW attachments/backups, S3 read deploy, SSM GetParameters `/outline/*`.
- **GitHub OIDC:** 3 role deploy/plan/apply — xem mục IAM cho GitHub.
- **SSM Parameter Store (SecureString)** `/outline/`: `SECRET_KEY`, `UTILS_SECRET`, `POSTGRES_PASSWORD` (Terraform `random_*` sinh), `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (Terraform tạo placeholder, `ignore_changes` value; người dùng nhập giá trị thật).
- **Outputs:** EIP, instance id, ECR URL, OIDC role ARN, bucket names.

## Runtime (`deploy/`)
- `caddy`: reverse proxy `outline.launch-mate.com` → `outline:3000`, auto TLS, volume giữ cert.
- `outline`: image `${ECR}/outline:${TAG}`, env từ `.env`: `URL`, `SECRET_KEY`, `UTILS_SECRET`, `DATABASE_URL`, `REDIS_URL`, `FILE_STORAGE=s3`, `AWS_REGION`, `AWS_S3_UPLOAD_BUCKET_NAME/URL`, `AWS_S3_ACL=private`, `GOOGLE_CLIENT_ID/SECRET`, `PGSSLMODE=disable`, `FORCE_HTTPS=true`.
- `postgres:16`, `redis:7` — volume local, không expose port ra host.
- Credential S3 cho Outline: ưu tiên instance role (SDK default chain). Lúc implement kiểm tra source v1.10.1; nếu Outline bắt buộc access key thì Terraform tạo IAM user riêng chỉ có quyền bucket attachments, key lưu SSM.
- Migration DB: kiểm tra source v1.10.1 xem server có tự migrate lúc start không; nếu không, `deploy.sh` chạy `yarn db:migrate` qua `docker compose run --rm outline` trước khi `up`.

## CI/CD
### build-deploy.yml (push `main`, `workflow_dispatch`)
1. OIDC → assume role.
2. `docker buildx build` (Dockerfile của repo, linux/amd64, cache GHA) → push `ECR:outline:<sha>`.
3. Upload `deploy/` → `s3://<deploy-bucket>/<sha>/`.
4. `ssm send-command` (AWS-RunShellScript) lên instance: tải bundle, chạy `deploy.sh <sha>`; poll kết quả, fail job nếu script fail.
5. `deploy.sh`: render `.env` từ SSM, ghi tag hiện tại vào `.previous_tag`, `compose pull && up -d`, chờ `GET /_health` 200 tối đa 180s; fail → quay lại tag cũ, `up -d`, exit 1.
- `concurrency: deploy` để không deploy chồng.

### terraform.yml
- PR đụng `infra/**`: `fmt -check`, `validate`, `plan`, comment plan vào PR.
- `workflow_dispatch` → `apply` trong GitHub environment `production` (yêu cầu approve).

### Upstream sync — script local `scripts/onprem/sync-upstream.sh <tag>`
(Không làm workflow: `GITHUB_TOKEN` không push được commit đụng `.github/workflows`, upstream merge luôn đụng → cần PAT, không đáng.)
- Fetch tag upstream, branch `sync/<tag>`, merge; tự `git rm` workflow upstream (modify/delete conflict hoặc workflow mới), giữ đúng 2 workflow của fork; push + `gh pr create`. Merge PR → build-deploy chạy.

### Đã xác minh trong source v1.10.1
- S3Client không truyền credential → SDK default chain → instance role OK. EC2 phải đặt IMDSv2 `http_put_response_hop_limit = 2` (container qua docker bridge).
- Server tự chạy migration lúc start (`checkPendingMigrations`) → `deploy.sh` không cần bước migrate. Hệ quả: rollback image sau khi migration mới đã chạy có thể lỗi → backup trước deploy (`deploy.sh` gọi `backup.sh` trước `up`).
- Image build 2 bước: `Dockerfile.base` → `Dockerfile --build-arg BASE_IMAGE=...`. Health `/_health` kiểm DB + Redis, trả `OK`.
- Google: không có env whitelist domain; user đầu tiên đăng nhập tạo workspace, sau đó giới hạn domain trong Settings UI.

### IAM cho GitHub (OIDC provider đã có sẵn trong account → `data` source)
- `outline-gh-deploy`: trust `repo:18PhongNguyen/outline:ref:refs/heads/main`; ECR push, S3 deploy bucket write, SSM SendCommand/GetCommandInvocation.
- `outline-gh-plan`: trust `repo:18PhongNguyen/outline:pull_request`; `ReadOnlyAccess` + state bucket read + `kms:Decrypt` (aws/ssm). Plan chạy `-lock=false`.
- `outline-gh-apply`: trust `repo:18PhongNguyen/outline:environment:production` (bắt buộc approve); `AdministratorAccess` (Terraform quản IAM). **Rủi ro bảo mật chấp nhận được nhờ environment reviewer.**

### Bảo vệ dữ liệu
- PG data trên root EBS → `aws_instance` `lifecycle.ignore_changes = [ami, user_data]` + `disable_api_termination = true`; backup hằng ngày (systemd timer — AL2023 không có cron).

## Bootstrap (một lần, chạy local bằng creds env)
1. `infra/terraform/bootstrap`: apply → state bucket.
2. `infra/terraform/main`: apply lần đầu.
3. Người dùng: tạo record A `outline.launch-mate.com` → EIP ở account giữ zone.
4. Người dùng: tạo Google OAuth client (redirect `https://outline.launch-mate.com/auth/google.callback`), `aws ssm put-parameter --overwrite` 2 giá trị.
5. Set GitHub repo variables `AWS_ROLE_ARN`, `AWS_REGION`, `ECR_REPO`, `DEPLOY_BUCKET`, `INSTANCE_ID`; tạo environment `production`.
6. Chạy build-deploy lần đầu.

## Kiểm chứng
- CI: `terraform fmt/validate`, `shellcheck deploy/*.sh`, `docker compose config`.
- Sau deploy: `/_health` 200 qua HTTPS, login Google thành công, upload ảnh → object xuất hiện trong bucket attachments, `backup.sh` chạy tay → file trong bucket backups.
- Rollback: deploy tag image hỏng có chủ đích → script quay lại tag cũ.

## Ngoài phạm vi
HA/multi-AZ, RDS, CDN, SMTP email notifications, monitoring/alerting ngoài health check.
