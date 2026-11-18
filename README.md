# AstroSkyFinder (iPhone Personal Astrophotography + Stellarium AR)

Ứng dụng iOS cá nhân (SwiftUI + AVFoundation RAW + GPU Metal + CoreMotion/CoreLocation) thiết kế riêng để khắc phục các hạn chế của *Even Longer*: khóa nét chuẩn sao `MF`, chỉnh tự do `ISO` cao, xuất chuỗi `.DNG` tuyến tính không nén tốc độ cao, tự gộp nhiều frame căn chỉnh sao ngay trên GPU Metal, kèm bản đồ sao AR trực tiếp giống Stellarium.

---

## Tính năng chính

1. **Bản đồ sao AR trực tiếp kiểu Stellarium (có nút bật/tắt riêng từng lớp):**
   - `Sao`: Các sao sáng định hướng kèm độ sáng và màu phổ (`Betelgeuse, Rigel, Capella, Vega, Sirius, Antares, Polaris...`).
   - `Chòm sao`: Nối nét chòm sao (*Orion, Cassiopeia, Cygnus, Auriga, Taurus, Perseus, Scorpius, Sagittarius, Ursa Major...*).
   - `Ngân Hà`: Dải Ngân Hà tính toán động theo tọa độ Thiên Hà IAU khớp đúng ngày/giờ/GPS và góc rộng ống kính.
   - `Deep-Sky`: Đánh dấu vòng tròn định vị `M31, M42, M45, NGC 869, NGC 7000, M8, IC 434, NGC 1499...`.
   - `La bàn / Lưới` & `Cân AR 1 sao`: Vạch đường chân trời, cân bằng bọt nước (`±1.5°` xanh), cảnh báo rung chân máy và tính năng chạm 1 sao sáng để triệt tiêu sai lệch từ trường khi gắn tripod/nóc xe.
   - `Zoom 4x` & `Đêm đỏ`: Phóng đại trung tâm hỗ trợ soi sao + giao diện đỏ bảo vệ mắt + chế độ tối màn hình tiết kiệm pin khi chụp chuỗi dài.

2. **Điều khiển Camera Thiên Văn Chuyên Sâu:**
   - **Auto Nét Sao (`Auto Focus Sweep`)**: Tự quét `lensPosition` (`0.78 → 1.00`), đo độ tập trung đỉnh sáng tại tâm để khóa nét vô cực chuẩn sao (tránh lỗi trượt nét mờ như `18.9 px`), kèm thanh kéo `MF` thủ công.
   - **Đa ống kính + Khẩu độ thật**: Chuyển `0.5x` / `1x` / `Tele`, hiển thị đúng khẩu cố định vật lý trên máy (ví dụ `f/1.6`).
   - **Chế độ chụp kép:**
     - `RAW DNG`: Intervalometer xuất liên tiếp `5–300` file **Bayer RAW `.DNG`** thuần lưu vào **Tệp (`Files → AstroSkyFinder`)** để copy thẳng sang PC stack.
     - `Gộp Metal`: Chụp `3–30` sub-frame RAW, tự căn chỉnh dịch + xoay trường sao bằng `Accelerate` + GPU `Metal` rồi gộp ra ảnh `16-bit TIFF` + bản xem trước `JPG` lưu thẳng vào Thư viện Ảnh.
     - `Cả 2 (RAW+Gộp)`: Vừa lưu trọn chuỗi `.DNG` gốc, vừa gộp ngay bản xem trước tại chỗ.

---

## Kiểm chứng & Chạy thử MIỄN PHÍ từ Windows (Chưa cần iPhone!)

Mỗi khi bạn đẩy code lên GitHub (nên để repo **Public** để chạy GitHub Actions macOS miễn phí không giới hạn phút, hoặc dùng quota miễn phí hàng tháng ở repo Private), workflow `.github/workflows/build-ipa.yml` sẽ tự động làm 3 việc:

1. **Chạy `AstroSkyFinderTests` & `AstroSkyFinderUITests` trên iPhone Simulator thật** (dùng **Chế độ Giả lập Bầu Trời Metal + AR** tự động kích hoạt khi không có camera vật lý):
   - Kiểm chứng toán học tọa độ sao/Ngân Hà, kiểm chứng bộ gộp Metal trên GPU, bấm test từng nút AR, chạy **Auto Nét Sao** khóa nét ở `0.935`, bật chế độ **Đêm đỏ** và xuất các file **ảnh chụp màn hình thật** vào Artifact **`simulator-test-screenshots`**.
2. **Xuất `AstroSkyFinder-Simulator-App` (`AstroSkyFinder-Simulator.app.zip`):**
   - Tải `.zip` này về rồi kéo thả lên gói Free của **Appetize.io** (`30 phút/tháng miễn phí, $0`) để bấm thử trực tiếp màn hình iPhone ảo ngay trên trình duyệt Chrome ở Windows.
3. **Xuất `AstroSkyFinder-unsigned-ipa` (`AstroSkyFinder-unsigned.ipa`):**
   - Khi muốn cài lên iPhone 17 thật, tải file `.ipa` này rồi dùng **Sideloadly** hoặc **AltStore** miễn phí trên Windows ký bằng Apple ID thường.

---

## Cách đẩy lên GitHub để chạy kiểm thử ngay

```bash
git init
git add .
git commit -m "Initial AstroSkyFinder iOS project with Simulator tests"
git branch -M main
git remote add origin https://github.com/<ten-cua-ban>/AstroSkyFinder.git
git push -u origin main
```
Vào tab **Actions** trên GitHub để xem kết quả Test xanh, tải **`simulator-test-screenshots`** xem giao diện thực tế, tải **`AstroSkyFinder-Simulator-App`** nếu muốn bấm thử trên web, và tải **`AstroSkyFinder-unsigned-ipa`** khi cài lên iPhone.
