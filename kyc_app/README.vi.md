# KYC Onboarding App (Flutter)

[English](README.en.md) · **Tiếng Việt**

App xác minh danh tính đa nền tảng (Android / iOS) cho bài tập KYC Onboarding. App làm việc với
backend thật trong [`../kyc_service`](../kyc_service) (không mock): đăng nhập, nhập thông tin cá nhân,
chụp giấy tờ và ảnh selfie với khung hướng dẫn trên camera, xem lại và nộp hồ sơ, rồi theo dõi trạng
thái xác minh cho đến khi được duyệt, bị từ chối hoặc được yêu cầu bổ sung. Bản nháp được giữ lại ở
mọi bước, kể cả khi app bị tắt hay khởi động lại.

> **Sơ đồ hệ thống:** [`../kyc_service/docs/system-architecture.html`](../kyc_service/docs/system-architecture.html)
> (mở bằng trình duyệt) - cách app, API, object storage và database giao tiếp với nhau.

**Công nghệ:** Flutter 3.x (Dart ≥ 3.13) · `flutter_bloc` + `rxdart` · `dio` (refresh JWT, retry,
multipart) · `shared_preferences` (bản nháp đã mã hoá) + `flutter_secure_storage` (token, khoá mã hoá
bản nháp) · `cryptography` (AES-256-GCM) · `camera` (khung hướng dẫn tự vẽ) + `image_picker` ·
`flutter_image_compress` · `bloc_test` + `mocktail`

| Yêu cầu của đề bài | Đáp ứng ở đâu |
|---|---|
| Xác thực: đăng nhập, quản lý phiên, đăng xuất | `features/auth` - `AuthBloc`, token lưu trong Keychain / Keystore, refresh một lần duy nhất (single-flight), hộp thoại đăng xuất |
| Thông tin cá nhân có kiểm tra hợp lệ | Bước 1 - `PersonalDetailsValidator` (cùng quy tắc với backend), tự lưu có debounce |
| Chụp giấy tờ tuỳ thân | Bước 2 - camera tự làm với khung chữ nhật thẻ, mặt trước / mặt sau (hộ chiếu không cần mặt sau) |
| Chụp selfie | Bước 3 - camera trước với khung oval khuôn mặt |
| Xem lại, chỉnh sửa, nộp | Bước 4 - sửa được từng phần, xác nhận đồng ý, nộp bằng một request multipart |
| Trạng thái xác minh, từ chối, nộp lại | Bước 5 - polling bằng rxdart; từ chối (cuối cùng) khác yêu cầu nộp lại (sửa các mục bị đánh dấu) |
| Tiếp tục sau khi đóng app | Bản nháp local đã mã hoá + bản nháp trên server, hợp nhất bởi `KycResumeResolver` |
| Dữ liệu nhạy cảm, xử lý lỗi, test | Xem [Bảo mật & PII](#bảo-mật--pii), [Mạng](#mạng), [Kiểm thử](#kiểm-thử) |

---

## Chạy app

Cần có: Flutter SDK (Dart ≥ 3.13), Android Studio và / hoặc Xcode, và backend đang chạy.

```bash
# 1. Backend (xem ../kyc_service/README.vi.md)
cd ../kyc_service && npm install && npm run setup && npm run dev

# 2. App
cd ../kyc_app
cp .env.example .env          # sau đó đặt API_BASE_URL theo thiết bị (bảng bên dưới)
flutter pub get
flutter run --dart-define-from-file=.env
flutter test
```

**Android Studio / VS Code:** cấu hình chạy trong `.idea/runConfigurations/main_dart.xml` và
`.vscode/launch.json` đã truyền sẵn `--dart-define-from-file=.env`, nên chỉ cần bấm nút **Run ▶** như bình thường.

### Cấu hình (`.env`)

`.env` không được commit (mẫu: `.env.example`) và **được biên dịch vào app lúc build**: sau khi sửa,
hãy dừng app rồi chạy lại - hot reload / hot restart là không đủ. Không bao giờ đặt secret vào file này.

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `API_BASE_URL` | mặc định của emulator | URL backend, không có `/api/v1` (xem bảng bên dưới) |
| `API_CONNECT_TIMEOUT_MS` / `API_RECEIVE_TIMEOUT_MS` / `API_SEND_TIMEOUT_MS` | 10000 / 20000 / 60000 | Timeout của Dio (send dài hơn để upload ảnh) |
| `API_MAX_RETRIES` | 3 | Số lần thử lại khi lỗi tạm thời |
| `KYC_STATUS_POLL_INTERVAL_MS` | 2000 | Chu kỳ polling trạng thái sau khi nộp |
| `PROTECT_SCREEN` | `true` | Chặn chụp / quay màn hình và che nội dung app trong màn hình đa nhiệm |

### Chọn `API_BASE_URL` nào?

| Thiết bị | `API_BASE_URL` |
|---|---|
| Android emulator | để trống (→ `http://10.0.2.2:3000`) hoặc `http://localhost:3000` + `adb reverse tcp:3000 tcp:3000` |
| Điện thoại Android thật cắm USB | `http://localhost:3000` + `adb reverse tcp:3000 tcp:3000` (chạy lại sau mỗi lần cắm lại cáp) |
| iOS simulator | để trống hoặc `http://localhost:3000` |
| iPhone / điện thoại bất kỳ cùng mạng Wi-Fi | `http://<tên Mac>.local:3000` (`scutil --get LocalHostName`) hoặc `http://<IP của Mac>:3000` (`ipconfig getifaddr en0`) |

Giữ `PUBLIC_BASE_URL` trong `kyc_service/.env` **giống hệt** `API_BASE_URL`, nếu không ảnh đã upload
sẽ không hiển thị được. Kiểm tra nhanh: mở `<API_BASE_URL>/health` bằng trình duyệt trên điện thoại.

iOS simulator không có camera: dùng nút **Gallery** trên màn hình chụp.

### Kịch bản demo

Reviewer giả lập của backend ra quyết định khoảng 10 giây sau khi nộp, dựa trên họ tên:

| Họ tên | Kết quả trong app |
|---|---|
| tên bình thường, ví dụ `Nguyen Van A` | **Được duyệt** → màn hình *My profile* |
| chứa `reject`, ví dụ `Reject Tester` | **Bị từ chối** (cuối cùng) - liên hệ hỗ trợ, không sửa được nữa |
| chứa `retake`, ví dụ `Retake Tester` | **Yêu cầu nộp lại** ảnh selfie → chụp lại và nộp lại → được duyệt |

- Mỗi kịch bản dùng **một email mới** (mỗi tài khoản chỉ có một hồ sơ).
- Cẩn thận chính tả: re**ject** là từ chối hẳn, re**take** là yêu cầu chụp lại selfie.
- *Bị từ chối*: màn hình hiện lý do và dòng "This decision is final…", không có nút sửa; mở lại app
  hay đăng nhập lại vẫn như vậy. Đây là trạng thái cuối, không có bước tiếp theo.
- *Retake*: hiện lời nhắn của reviewer → bấm **Fix and resubmit** mở bước selfie (ảnh cũ đã bị bỏ) →
  chụp ảnh mới → Review → Submit → khoảng 10 giây sau được duyệt.
- Các kết quả khác (ví dụ yêu cầu chụp lại mặt trước giấy tờ) có thể ép từ backend - xem mục
  *Test tay cùng app* trong README backend.

Khi quay video demo, đặt `PROTECT_SCREEN=false`, chạy lại app, quay xong thì đặt lại `true`.

---

## Kiến trúc

```
lib/
├── main.dart                     # khởi động (config, bảo vệ màn hình, DI)
├── app/                          # composition root (dependencies.dart), MaterialApp + điều hướng theo đăng nhập, theme
├── core/
│   ├── bloc/event_transformers   # rxdart: droppable / restartable / debounce
│   ├── config/                   # AppConfig (giá trị từ .env)
│   ├── constants/                # danh sách quốc gia
│   ├── error/app_exception       # một kiểu lỗi duy nhất; đọc định dạng lỗi của backend
│   ├── network/                  # ApiClient + AuthInterceptor, RetryInterceptor, SafeLogInterceptor
│   ├── security/                 # DraftCipher (AES-GCM), ScreenSecurity (FLAG_SECURE), PrivacyOverlay
│   ├── storage/token_storage     # lưu token bằng Keychain / Keystore
│   ├── media/image_processor     # nén JPEG + xoá EXIF
│   ├── utils/                    # validator cho auth, helper ngày tháng
│   └── presentation/             # widget dùng chung, UiMessage (snackbar hiện một lần)
└── features/
    ├── auth/  {domain, data, presentation}   # đăng nhập / đăng ký / đăng xuất / kiểm tra phiên
    ├── kyc/
    │   ├── domain/      entity, KycRepository (interface), validator, resume resolver
    │   ├── data/        data source remote (Dio) + local (SharedPreferences mã hoá + file), mapper
    │   └── presentation/
    │       ├── bloc/    KycBloc (event / state)
    │       ├── pages/   KycFlowPage (khung chứa wizard)
    │       ├── steps/   1 thông tin · 2 giấy tờ · 3 selfie · 4 xem lại · 5 xác minh
    │       ├── camera/  màn hình camera tự làm, painter vẽ khung (chữ nhật / oval), xem trước
    │       └── widgets/ chỉ báo bước, ô ảnh giấy tờ, ô nhập ngày
    └── profile/         # hồ sơ người dùng đã xác minh (ProfileCubit + màn hình, ảnh phóng to được)
```

Phụ thuộc hướng vào trong: **presentation → domain ← data**. Bloc chỉ biết interface
`KycRepository` / `AuthRepository`, nên được unit test bằng mock. Cố ý không tách tầng use case
riêng - với mỗi feature một repository, use case chỉ chuyển tiếp lời gọi. Các phụ thuộc được nối
thủ công trong `app/dependencies.dart`.

### Luồng KYC (`KycBloc`)

| Bước | Diễn ra như thế nào |
|---|---|
| **Tiếp tục** (`KycStarted`) | Đọc bản nháp local và `GET /kyc`, rồi hợp nhất (`KycResumeResolver`): server quyết định trạng thái, chỉnh sửa local được ưu tiên theo từng trường, ảnh local được ưu tiên hơn bản trên server, và bước đã lưu bị giới hạn về bước chưa hoàn thành đầu tiên. Hồ sơ đang chờ duyệt sẽ mở màn hình trạng thái và tiếp tục polling. Nếu không kết nối được backend, app tiếp tục từ bản nháp local (hiện banner offline). |
| **1. Thông tin** | Tự lưu có debounce mỗi khi thay đổi (`debounceTime` + `switchMap`). Khi bấm "Continue", `PersonalDetailsValidator` chạy cùng quy tắc với backend (họ tên, ngày sinh đủ 18 tuổi, số giấy tờ theo loại giấy tờ / quốc tịch, ngày hết hạn, số điện thoại E.164, ...); lỗi theo trường từ backend hiển thị ở đúng ô nhập. |
| **2. Giấy tờ / 3. Selfie** | Camera tự làm → xem trước → nén (cạnh ngắn ≤1600 px, xoá EXIF) → lưu trong thư mục documents của app → **upload ngầm** (`POST /kyc/documents/:type`). Mỗi ảnh hiển thị trạng thái riêng (đã lưu trên máy / đang upload / đã upload / thử lại). |
| **4. Xem lại** | Sửa được từng phần; ô xác nhận đồng ý; nộp. |
| **5. Nộp + trạng thái** | Một request multipart `POST /kyc/submit` gồm thông tin và chỉ những ảnh server chưa có (hiện tiến độ upload). Sau đó polling `GET /kyc/status` bằng rxdart (`startWith` + `exhaustMap` + `takeWhileInclusive`) cho đến khi reviewer quyết định; làm mới khi app quay lại foreground và khi kéo để làm mới. **Được duyệt** → hồ sơ cá nhân. **Bị từ chối** → kết thúc, liên hệ hỗ trợ. **Yêu cầu nộp lại** → hiện lời nhắn của reviewer và các mục cần làm lại; "Fix and resubmit" mở bước đầu tiên cần sửa, bỏ các ảnh bị đánh dấu để buộc chụp lại, và hiện phản hồi ở mọi bước liên quan. |

Mọi thay đổi trạng thái quan trọng đều được ghi vào bản nháp local, nên tắt app ở bất kỳ lúc nào
cũng sẽ quay lại đúng bước với đúng dữ liệu và ảnh. Thông tin + bước hiện tại cũng được đồng bộ lên
backend (`PUT /kyc/draft`) để tiếp tục trên thiết bị khác.

Khi **được duyệt**, người dùng vào màn hình **My profile** (`features/profile`): dữ liệu đúng như
backend đã xác minh (`GET /kyc`), avatar từ ảnh selfie, ảnh giấy tờ (chạm để phóng to), ngày xác minh
và mã tham chiếu. URL ảnh là presigned URL ngắn hạn, được làm mới khi kéo để làm mới hoặc khi app
quay lại foreground sau vài phút.

### Mạng

- **AuthInterceptor**: gắn access token; khi gặp 401 thì refresh một lần (single-flight: nhiều 401
  đồng thời dùng chung một lần refresh - quan trọng vì backend xoay vòng refresh token và thu hồi
  phiên khi token bị dùng lại) rồi gửi lại request. Nếu refresh token bị từ chối, token bị xoá và
  `SessionEvents` báo cho `AuthBloc` hiện màn hình đăng nhập (bản nháp local được giữ, người dùng
  tiếp tục sau khi đăng nhập lại).
  Việc hết hạn được phát hiện ở **lần gọi API kế tiếp**, không dùng timer: màn hình đang đứng yên sẽ
  giữ nguyên cho đến khi người dùng làm gì đó cần tới server. Mỗi lần refresh lại cấp refresh token
  mới, nên người dùng đang thao tác sẽ không bao giờ bị đăng xuất (sliding session).
- **RetryInterceptor**: backoff luỹ thừa + jitter cho lỗi kết nối, timeout, 429/502/503/504.
  Chỉ áp dụng cho method idempotent và các request chủ động cho phép (nộp KYC: nếu bị gửi trùng,
  server trả `409 KYC_NOT_EDITABLE`, bloc hiểu là "đã nộp rồi"). Body multipart được tạo lại từ
  factory trước mỗi lần thử lại. Request refresh không bao giờ được thử lại.
- **SafeLogInterceptor** (chỉ ở debug): method, path, status và thời gian - không bao giờ log header hay body.
- **Lỗi**: mọi lỗi được chuyển thành `AppException` (mạng, timeout, validation kèm lỗi theo trường,
  chưa xác thực, xung đột, lỗi server) và hiển thị thông báo dễ hiểu; lỗi theo trường hiện ở đúng ô nhập.

---

## Giả định

- **Từ chối và yêu cầu nộp lại.** `REJECTED` là quyết định cuối cùng; `RESUBMISSION_REQUESTED`
  kèm danh sách mục cần làm lại (`PERSONAL_DETAILS`, `ID_FRONT`, `ID_BACK`, `SELFIE`). Xem README
  backend để biết đầy đủ state machine.
- Mỗi người dùng một hồ sơ KYC; bản nháp trên máy gắn với từng người dùng và bị xoá khi đăng xuất.
- Chỉ người trưởng thành (18+), giấy tờ còn hạn; hộ chiếu không có mặt sau.
- Reviewer giả lập của backend thay cho nhà cung cấp KYC; tên chứa "reject" / "retake" kích hoạt
  hai kết quả tiêu cực để demo.

## Bảo mật & PII

- Token lưu trong Keychain / Keystore (`flutter_secure_storage`); token cũ còn sót trong Keychain iOS
  bị xoá ở lần mở đầu tiên sau khi cài lại app.
- Bản nháp (họ tên, ngày sinh, số giấy tờ, địa chỉ) lưu trong SharedPreferences **được mã hoá bằng
  AES-256-GCM** (`core/security/draft_cipher.dart`). Khoá ngẫu nhiên nằm trong Keychain / Keystore
  (`first_unlock_this_device`: không bao giờ được chuyển sang bản sao lưu hay thiết bị khác); bản
  nháp bị sửa đổi hoặc không đọc được sẽ bị bỏ.
- **Bảo vệ màn hình** (`PROTECT_SCREEN=true` mặc định): Android bật `FLAG_SECURE`
  (không chụp / quay màn hình được, ảnh xem trước trong recent apps bị trống, `MainActivity.kt`);
  trên cả hai nền tảng, một lớp che riêng tư phủ lên UI mỗi khi app rời foreground, nên ảnh chụp
  trong màn hình đa nhiệm không bao giờ lộ PII.
- Android `allowBackup="false"`: dữ liệu app (bản nháp, ảnh) không bị sao lưu lên Google Drive.
- Ảnh được nén và xoá EXIF (không còn vị trí GPS), lưu trong sandbox của app, file tạm của camera bị
  xoá. Khi đăng xuất và khi hồ sơ được duyệt, bản nháp và ảnh local đều bị xoá.
- Ảnh từ server được hiển thị qua presigned URL ngắn hạn và không bao giờ được lưu lại.
- Đánh đổi: bản thân các ảnh đã nén là file trong sandbox của app (được bảo vệ bởi sandbox của hệ
  điều hành và iOS Data Protection) nhưng app không tự mã hoá, vì chúng được hiển thị và upload trực
  tiếp từ ổ đĩa. Mã hoá cả ảnh nằm trong phần hướng phát triển tiếp theo.

## Kiểm thử

```bash
flutter test
```

| File | Nội dung được test |
|---|---|
| `test/features/kyc/kyc_bloc_test.dart` | Tiếp tục hồ sơ, khởi động khi offline, giới hạn về bước chưa xong đầu tiên, validation, submit chỉ gửi ảnh còn thiếu, xử lý `KYC_INCOMPLETE` từ server, polling đến khi có quyết định, luồng nộp lại, từ chối cuối cùng |
| `kyc_resume_resolver_test.dart` | Hợp nhất bản nháp local và server |
| `personal_details_validator_test.dart` | Quy tắc từng trường (tuổi, định dạng số giấy tờ, ngày hết hạn, số điện thoại) |
| `kyc_mappers_test.dart` | Chuyển đổi dữ liệu API / bản nháp, các mục cần nộp lại |
| `kyc_local_data_source_test.dart` | Lưu bản nháp mã hoá: không có PII dạng rõ, phát hiện bị sửa đổi, dọn dẹp |
| `test/core/app_exception_test.dart` | Đọc định dạng lỗi của backend |
| `test/features/profile/profile_cubit_test.dart` | Tải và làm mới hồ sơ, URL ảnh hết hạn |
| `test/widget_test.dart` | Widget: chỉ báo bước, tỉ lệ khung hướng dẫn chụp |

### Checklist test tay

Bắt đầu với backend sạch (`rm -rf storage prisma/dev.db* && npm run setup && npm run dev`).

| Phần | Cần kiểm tra |
|---|---|
| Đăng nhập | Mật khẩu yếu và email trùng bị từ chối; sai mật khẩu hiện *Invalid email or password*; tắt hẳn app rồi mở lại vẫn còn đăng nhập; đăng xuất về màn hình login |
| Phiên | Access token 30 giây thì app tự refresh ngầm; refresh token 60 giây và để yên hơn 60 giây thì lần gọi API kế tiếp đưa về login (xem README backend) |
| Thông tin | Form trống báo lỗi ở mọi ô bắt buộc; dưới 18 tuổi, giấy tờ hết hạn, ngày hết hạn trước ngày cấp, số điện thoại không theo E.164 đều bị chặn |
| Chụp ảnh | Khung chữ nhật cho giấy tờ, oval cho selfie; chụp lại và Gallery hoạt động; hộ chiếu bỏ qua mặt sau; mọi ảnh kết thúc ở trạng thái *uploaded* |
| Tiếp tục | Tắt hẳn app ở bất kỳ bước nào → quay lại đúng bước, đúng dữ liệu và ảnh |
| Mất kết nối | Tắt server giữa chừng → app vẫn chạy, ảnh lỗi hiện *Retry*; mở lại app có banner offline; bật server → *Retry* và lần sửa tiếp theo đồng bộ lại |
| Xem lại | Sửa được từng phần; chưa tích ô đồng ý thì không nộp được |
| Trạng thái | Ba kịch bản ở trên; hồ sơ đang chờ vẫn polling sau khi mở lại app; người dùng đã duyệt mở thẳng vào *My profile* |
| Bảo mật | Với `PROTECT_SCREEN=true`, Android chặn chụp màn hình và màn hình đa nhiệm không lộ nội dung |

---

## Xử lý sự cố

| Hiện tượng | Cách xử lý |
|---|---|
| Build Android lỗi ở `camera_android_camerax` (`ListenableFuture` / `concurrent-futures`) | Đã xử lý trong `android/build.gradle.kts`; chạy `flutter clean && flutter pub get` |
| "Không kết nối được server" trên điện thoại Android cắm USB | `adb reverse tcp:3000 tcp:3000` (chạy lại sau khi cắm lại cáp); mở `<API_BASE_URL>/health` bằng trình duyệt trên điện thoại |
| iPhone không gọi được tới Mac | Cùng mạng Wi-Fi, dùng `<tên Mac>.local` hoặc IP của Mac, cho phép Node trong tường lửa macOS |
| Sửa `.env` mà không có tác dụng | Dừng app và chạy lại (giá trị được biên dịch vào app); đảm bảo lệnh chạy có `--dart-define-from-file=.env` |
| Ảnh không hiện sau khi upload | `PUBLIC_BASE_URL` (backend) ≠ `API_BASE_URL` (app) |
| iOS simulator không có camera | Dùng nút **Gallery** |
| Ảnh chụp màn hình bị đen / video quay màn hình trống | `PROTECT_SCREEN=true` - chỉ đặt `false` khi quay demo |
| Token hết hạn mà chưa bị đưa về login | Đúng thiết kế cho đến lần gọi API kế tiếp (kéo để làm mới, sửa một ô); token cấp trước khi đổi thời hạn ở backend vẫn giữ thời hạn cũ - đăng nhập lại |
| Nhập *Retake Tester* nhưng vẫn bị từ chối | Họ tên bị gõ thành *Reject Tester*, hoặc dùng lại tài khoản đã bị từ chối - đăng ký email mới |
| Mất bản nháp sau khi cập nhật từ bản build cũ | Bản nháp cũ chưa mã hoá bị bỏ có chủ đích; bản nháp trên server vẫn được khôi phục |

## Hướng phát triển tiếp theo

Mã hoá ảnh lưu trên máy và loại khỏi bản sao lưu iCloud, kiểm tra chất lượng ảnh trên thiết bị trước
khi upload (phát hiện mờ / loá, nhận diện khuôn mặt bằng ML Kit), cắt ảnh theo khung hướng dẫn, push
notification hoặc WebSocket thay cho polling, đa ngôn ngữ (vi / en), integration test với `patrol`,
và certificate pinning.
