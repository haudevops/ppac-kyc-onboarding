# PPAC · KYC Onboarding

[English](README.md) · **Tiếng Việt**

Bài tập Senior Full-stack: luồng xác minh danh tính (KYC) trên mobile, có backend thật.

| Project | Là gì | Tài liệu |
|---|---|---|
| [`kyc_service/`](kyc_service) | REST API - TypeScript, Express 5, Prisma, Zod. Chạy trên **Cloudflare Workers + D1 + R2** (Durable Object cho reviewer giả lập) hoặc chạy local như server Node với SQLite | [README](kyc_service/README.vi.md) · [English](kyc_service/README.en.md) |
| [`kyc_app/`](kyc_app) | App Flutter (Android / iOS) - BLoC + rxdart, Dio, camera có khung hướng dẫn, bản nháp mã hoá, tiếp tục sau khi tắt app | [README](kyc_app/README.vi.md) · [English](kyc_app/README.en.md) |

**Sơ đồ hệ thống:** [`kyc_service/docs/system-architecture.html`](kyc_service/docs/system-architecture.html) - tải về và mở bằng
trình duyệt (kiến trúc, state machine KYC, sequence diagram, bảng giao tiếp giữa các hệ thống).

**API đang chạy:** `https://kyc-service.tranduchau10d4.workers.dev` (kiểm tra: `/health`).

## Tính năng

- Đăng ký / đăng nhập / đăng xuất, JWT access + refresh token xoay vòng, phát hiện token bị dùng lại
- Wizard 5 bước: thông tin cá nhân (kiểm tra ở cả app và server) → ảnh giấy tờ → selfie → xem lại & sửa → nộp
- Camera có khung hướng dẫn (chữ nhật cho giấy tờ, oval cho khuôn mặt), nén ảnh, xoá EXIF
- Bản nháp lưu trên máy (AES-256-GCM) và trên server: tắt app ở bất kỳ bước nào vẫn tiếp tục đúng chỗ
- Trạng thái xác minh bằng polling; reviewer giả lập quyết định sau khoảng 10 giây:
  **duyệt** → màn hình hồ sơ, **từ chối** (cuối cùng), **yêu cầu nộp lại** → sửa các mục bị đánh dấu rồi nộp lại
- Ảnh lưu riêng tư, chỉ xem qua URL ký có hạn; chặn chụp màn hình và che nội dung trong màn hình đa nhiệm
- Test: backend 58 unit / HTTP + 4 end-to-end; app có test cho BLoC, mapper, bộ lưu bản nháp, widget

## Chạy nhanh

```bash
# Backend (server Node local, không cần tài khoản cloud)
cd kyc_service
cp .env.example .env
npm install && npm run setup && npm run dev      # http://localhost:3000

# App
cd ../kyc_app
cp .env.example .env                             # API_BASE_URL: server local hoặc URL Worker đang chạy
flutter pub get
flutter run --dart-define-from-file=.env         # hoặc nút Run trong Android Studio / VS Code
```

Deploy backend lên Cloudflare: xem [README kyc_service → Deploy lên Cloudflare](kyc_service/README.vi.md#deploy-lên-cloudflare-workers--d1--r2).

## Kịch bản demo

Mỗi kịch bản dùng một tài khoản mới; kết quả phụ thuộc họ tên nhập ở bước 1.

| Họ tên | Kết quả khoảng 10 giây sau khi nộp |
|---|---|
| `Nguyen Van A` | Được duyệt → *My profile* |
| `Reject Tester` | Bị từ chối (cuối cùng) |
| `Retake Tester` | Yêu cầu chụp lại selfie → chụp lại, nộp lại → được duyệt |

## Cấu trúc repo

```
.
├── kyc_service/   # backend (src/, worker/, prisma/, migrations/, test/, docs/)
└── kyc_app/       # app Flutter (lib/, test/, android/, ios/)
```

Không commit secret: `.env`, `.dev.vars`, database và ảnh local đều nằm trong `.gitignore`; secret production
nằm trên Cloudflare (`wrangler secret put`).
