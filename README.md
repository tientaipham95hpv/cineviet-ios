# CineViet iOS Native

Nền móng iOS native dùng Swift, SwiftUI, MVVM-ready services, URLSession, Codable, async/await và Keychain.

## Phạm vi hiện tại

- App entry point và Authentication MVVM; chưa có giao diện Home.
- Environment/API configuration.
- API client có bearer token và refresh khi HTTP 401.
- Keychain token storage.
- Auth models/service.
- Movie/episode models và movie service theo parser Flutter.
- Dependency container và UserDefaults settings (`AppSettings`).
- Login screen, session restore, logout và dark/light preference.

## Module Authentication

Authentication dùng endpoint thật đã đối chiếu từ Flutter:

- `POST /auth/login`
- `POST /auth/google/mobile` (service đã sẵn sàng nhận Google ID token từ lớp tích hợp Google Sign-In sau)
- `POST /auth/refresh`
- `GET /auth/me`

Luồng hiện tại: khôi phục Keychain session → gọi `/auth/me` → nếu access token hết hạn thì refresh một lần → hiển thị Login nếu session không còn hợp lệ. Sau login thành công, token được lưu Keychain và hiển thị trạng thái đã đăng nhập. Home chưa được nối vào để giữ đúng phạm vi module.

## Mở trong Xcode

1. Trên macOS, tạo iOS App project tên `CineViet` với SwiftUI lifecycle và deployment target iOS 16+.
2. Thêm toàn bộ thư mục `CineViet/` vào app target.
3. Bảo đảm target có capability Picture in Picture/Background audio khi module Player được triển khai sau.
4. Build bằng Xcode hoặc:

```bash
xcodebuild -scheme CineViet -destination 'platform=iOS Simulator,name=iPhone 16' build
```

`Package.swift` chỉ dùng để kiểm tra cấu trúc source ở môi trường SwiftPM; app iOS thực tế cần Xcode trên macOS vì Linux không có SwiftUI/Security/AVKit SDK.
