# PPAC · KYC Onboarding

[English](README.md) · **Tiếng Việt**

Bài tập Senior Full-stack: luồng xác minh danh tính (KYC) trên mobile, có backend thật.

| Project | Là gì | Tài liệu |
|---|---|---|
| [`kyc_service/`](kyc_service) | REST API - TypeScript, Express 5, Prisma, Zod. Chạy trên **Cloudflare Workers + D1 + R2** (Durable Object cho reviewer giả lập) hoặc chạy local như server Node với SQLite | [README](kyc_service/README.vi.md) · [English](kyc_service/README.md) |
| [`kyc_app/`](kyc_app) | App Flutter (Android / iOS) - BLoC + rxdart, Dio, camera có khung hướng dẫn, bản nháp mã hoá, tiếp tục sau khi tắt app | [README](kyc_app/README.vi.md) · [English](kyc_app/README.md) |

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

Deploy backend lên Cloudflare: xem [README kyc_service → Triển khai lên Cloudflare](kyc_service/README.vi.md#triển-khai-lên-cloudflare-workers--d1--r2).

## Kịch bản demo

Mỗi kịch bản dùng một tài khoản mới; kết quả phụ thuộc họ tên nhập ở bước 1.

| Họ tên | Kết quả khoảng 10 giây sau khi nộp |
|---|---|
| `Nguyen Van A` | Được duyệt → *My profile* |
| `Reject Tester` | Bị từ chối (cuối cùng) |
| `Retake Tester` | Yêu cầu chụp lại selfie → chụp lại, nộp lại → được duyệt |

## Kiến trúc tóm tắt

- **Backend:** TypeScript, Express 5, Prisma, Zod, phân lớp (routes → controllers → services → repositories).
  Một codebase, hai runtime: Node + SQLite ở local, **Cloudflare Workers + D1 + R2** ở production.
- **App:** Flutter, BLoC + rxdart, Dio với interceptor refresh token và retry, bản nháp mã hóa trên máy.
- **State machine KYC:** `DRAFT → SUBMITTED → PROCESSING → APPROVED | REJECTED | RESUBMISSION_REQUESTED`,
  mỗi lần chuyển trạng thái là một `UPDATE` có điều kiện kèm một dòng lịch sử.
- Chi tiết: [kiến trúc backend](kyc_service/README.vi.md#kiến-trúc) · [kiến trúc app](kyc_app/README.vi.md#kiến-trúc) · [sơ đồ](kyc_service/docs/system-architecture.html).

## Bảo mật

- Access JWT ngắn hạn + refresh token xoay vòng, phát hiện tái sử dụng; chỉ lưu hash của token.
- Ảnh là riêng tư: kiểm tra magic byte, giới hạn dung lượng, xóa EXIF, URL ký HMAC có hạn ngắn.
- Trên thiết bị: token lưu trong secure keystore, bản nháp mã hóa AES-256-GCM, chặn chụp màn hình / app switcher.
- PII không ghi vào log; mật khẩu băm bằng bcrypt; dữ liệu được validate bằng Zod ở server và trong app.
- Chi tiết: [PII & bảo mật backend](kyc_service/README.vi.md#pii--bảo-mật) · [bảo mật app](kyc_app/README.vi.md#bảo-mật--pii).

## Các đánh đổi chính

- **D1 không có interactive transaction** - các lệnh ghi có điều kiện giữ an toàn khi chạy đồng thời; mất tính all-or-nothing giữa hai câu lệnh trên Cloudflare.
- **Review được giả lập** (worker đọc DB / alarm Durable Object) thay vì dùng nhà cung cấp KYC thật.
- **Rate limit theo từng isolate** trên Workers; muốn giới hạn toàn cục cần rule của Cloudflare WAF.
- **Giả định** được liệt kê ở [backend](kyc_service/README.vi.md#giả-định) và [app](kyc_app/README.vi.md#giả-định).

## Nếu có thêm thời gian

- Mã hóa cấp trường (envelope) cho cột PII, re-encode ảnh phía server và quét mã độc.
- Nhà cung cấp KYC thật (xác thực giấy tờ, liveness, so khớp khuôn mặt) với webhook thay vì polling.
- Review theo hàng đợi, PostgreSQL, OpenAPI spec, audit log truy cập tài liệu, job xóa dữ liệu theo retention, deny list access token.
- Làm sâu hơn phần xác thực: xác minh email và đặt lại mật khẩu, MFA (TOTP / OTP SMS), mở khóa bằng sinh trắc học (Face ID / vân tay) khi mở lại app, gắn thiết bị và danh sách phiên để người dùng thu hồi các thiết bị khác, cùng danh sách chặn access token khi đăng xuất.
- Làm sâu hơn phần AI nhận diện khuôn mặt: liveness / chống giả mạo ngay trên thiết bị (chớp mắt, quay đầu, chống phát lại), so khớp khuôn mặt giữa selfie và ảnh chân dung trên giấy tờ kèm điểm tin cậy, tự kiểm tra chất lượng ảnh (mờ, lóa, kích thước mặt, nhiều khuôn mặt) và OCR giấy tờ để đối chiếu với thông tin đã nhập; điểm ở ngưỡng biên thì chuyển sang duyệt thủ công.
- App: certificate pinning, hàng đợi upload offline, integration test trên thiết bị thật, đa ngôn ngữ.

## Cấu trúc repo

```
.
├── kyc_service/   # backend (src/, worker/, prisma/, migrations/, test/, docs/)
└── kyc_app/       # app Flutter (lib/, test/, android/, ios/)
```

Không commit secret: `.env`, `.dev.vars`, database và ảnh local đều nằm trong `.gitignore`; secret production
nằm trên Cloudflare (`wrangler secret put`).
