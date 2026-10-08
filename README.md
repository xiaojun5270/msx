# MusicX — Flutter 版

MusicX 原生客户端的 Flutter 版本，目标平台 **Android**。

构建使用 Flutter **3.47.4**（GitHub Actions 已固定此版本）。底部导航栏与迷你播放器使用 `liquid_glass_widgets 1.10.0`，要求 Flutter 至少 3.41.0；旧版 3.24 无法编译。玻璃统一使用 standard 画质。“我的”和“设置”内容卡片仅保留排版和内边距，静止与滑动时均完全透明，不绘制底色、背景模糊或玻璃材质层。播放器和导航栏保留玻璃材质及展开/收起，滚动内容末尾预留防遮挡空间。

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

## 固定 APK 签名

Release 构建使用同一份 PKCS12 密钥，禁止回退到临时 debug 签名。GitHub Actions 从以下仓库 Secrets 恢复密钥：

- `ANDROID_KEYSTORE_BASE64`：PKCS12 文件的 Base64。
- `ANDROID_KEYSTORE_PASSWORD`：密钥库密码。
- `ANDROID_KEY_ALIAS`：别名。
- `ANDROID_KEY_PASSWORD`：私钥密码。

构建后使用 `apksigner verify` 校验 APK，并与 `android/signing-certificate.sha256` 的固定公钥指纹比较，签名不一致不会上传或发布。

显示版本从 `0.7.8(001)` 开始，后续新构建依次为 `0.7.8(002)`、`0.7.8(003)`。括号内序号为工作流 `github.run_number` 减去 `android/version.properties` 的固定基数 42，至少补齐三位；失败或取消的构建也占用序号，重跑同次构建不变。Android 内部 `versionCode` 仍为序号加 42，以兼容之前已发布的 APK。不要重置该基数。设置页、APK 系统信息和 Release 标题使用同一显示版本。主版本只在修改 `pubspec.yaml` 时改变。

本地构建从被 Git 忽略的 `android/key.properties` 读取 `storeFile`（绝对路径）、`storePassword`、`keyAlias` 和 `keyPassword`，也可以使用对应的 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 环境变量。不要提交密钥库或密码文件。

首次配置脚本：`scripts/configure_android_signing.py --backup-dir <仓库外的备份目录> --upload`，需要 Python、PyNaCl、OpenSSL 及有仓库管理权限的 GitHub Git 凭据。脚本只生成一次密钥，不覆盖已有 GitHub 签名 Secrets；已固定指纹后，必须恢复原备份，不得重新生成。

请长期备份目录中的 `musix-release.p12` 和 `signing-credentials.json`。新证书无法覆盖使用旧临时证书签名的 APK，首次迁移可能需要卸载旧版（会清除本地数据）；后续版本使用固定证书可覆盖升级。

## 默认服务器

播放音频直接交由原生播放器读取 HTTP 流（支持 Range 和鉴权头），不再强制通过 `LockCachingAudioSource` 本地代理。保留 3–5 分钟的原生内存预缓冲；暂不新增整首磁盘缓存。切歌与加载超时会隔离旧引擎，锁屏控制随新引擎重新绑定。

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
