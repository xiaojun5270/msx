# MusicX — Flutter 版

MusicX 原生客户端的 Flutter 版本，目标平台 **Android**。

## 首次构建（Windows）

工程只包含手写的源码与 Android 配置，Gradle wrapper / gradlew / 启动图标等自动生成文件需由 Flutter 补齐：

```bash
cd msx

# 1) 让 Flutter 生成 gradle wrapper、gradlew、图标等缺失的脚手架文件
#    （会保留已存在的 lib/、pubspec.yaml、android/app/src 下的手写文件）
flutter create --platforms=android --org com.musix .

# 2) 拉取依赖
flutter pub get

# 3) 构建 APK
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 若 `flutter create` 覆盖了 `AndroidManifest.xml`，用 git 恢复本仓库版本（内含 cleartext HTTP、音频前台服务、musicx:// deep link、桌面小组件声明）。

## 默认服务器

`http://127.0.0.1:8080`（登录页可改）。消费 Musix Hub REST API，Cookie 鉴权 `musix_session` + 反向代理 cookie，响应信封 `{result:{status,data,error}}`。

## 架构对照

| 原生 (Swift) | Flutter |
| --- | --- |
| `@Observable` stores | `ChangeNotifier` + `provider` |
| `APIClient` / `AuthBox` | `lib/api/` |
| `AVPlayer` + `StreamResourceLoader` | `just_audio` + `audio_service`（自定义 Cookie header）|
| `Kingfisher` | `cached_network_image` + Cookie header |
| `SwiftData` `AppPrefs`/caches | `shared_preferences` (`lib/local/`) |
| `MPNowPlayingSession` / 锁屏 | `audio_service` |
| `WidgetKit` 小组件 | `home_widget` + Android AppWidget |
| CoreImage 取色 | `palette_generator` |
