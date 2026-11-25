# B-box Next 初始架构

## 目标

在 B-box 现有工程上演进：

- UI：跟进 FlClash 最新 Flutter UI / prism_ui，保留 B-box 的 sing-box 页面适配。
- 核心：使用 giturass/sing-box 的 B-box 分支及其最新稳定发布基线，不把 Mihomo/Clash 内核引入运行时。
- Android 逻辑：吸收 NekoBoxForAndroid 的成熟能力，但通过 Kotlin/Go bridge 适配到现有 Flutter + libbox 架构。
- 订阅：URL 返回 YAML、JSON、纯节点链接时，统一识别、解析、校验、转换为 sing-box 节点集合。
- 设置：工具 → 设置/常规中增加 NekoBox 能力开关和配置项，避免直接复制 NekoBox 的旧设置页。

## 分层

```text
Flutter UI (FlClash latest + B-box screens)
  ├─ presentation: pages/components/widgets
  ├─ state: Riverpod/BoxController adapters
  └─ features: settings, subscriptions, nodes, diagnostics

Application bridge
  ├─ NodeImportService       统一导入入口
  ├─ SubscriptionService     下载、UA、重试、缓存、更新策略
  ├─ NekoCompatService       NekoBox 兼容逻辑的 Dart/Kotlin 接口
  ├─ ProfileService          配置/来源/节点所有权与迁移
  └─ DiagnosticsService      日志、测速、网络诊断、失败报告

Android platform (Kotlin)
  ├─ VpnService / foreground service
  ├─ app filtering / bypass / always-on compatibility
  ├─ subscription scheduler / notification / clipboard / share receiver
  ├─ DoH/DoT/system DNS and network callback integration
  └─ libbox lifecycle, permissions, battery optimization

sing-box libbox (Go)
  ├─ core protocol and transport
  ├─ UI node parser / config validation / group operations
  ├─ route, DNS, TUN, endpoint and service lifecycle
  └─ optional B-box UI extensions, only when needed by the app

Persistence
  ├─ existing B-box profile/config storage
  ├─ subscription source metadata and ownership tags
  ├─ Neko-compatible preferences migration
  └─ backup/export schema versioning
```

## 推荐目录增量

```text
flutter/lib/features/
  subscription/
    subscription_service.dart
    subscription_detector.dart
    subscription_models.dart
    subscription_import_page.dart
  neko_compat/
    neko_settings.dart
    neko_compat_service.dart
    neko_feature_flags.dart
  settings/
    general_settings_page.dart
    neko_settings_section.dart
android/app/src/main/kotlin/.../compat/
  SubscriptionScheduler.kt
  NekoPreferenceMigration.kt
  AppFilterRepository.kt
  NetworkPolicyCompat.kt
core/experimental/libbox/
  （只保留确有必要的 B-box 扩展；解析优先复用现有 ui_nodes_parse）
test/
  subscription/
  migration/
  fixtures/
```

## 订阅导入状态机

1. 下载：限制 URL scheme、大小、重定向次数；使用来源配置的 User-Agent/Headers；保存 HTTP 状态和响应头。
2. 解码：BOM、UTF-8/常见中文编码、gzip；拒绝超大正文，避免内存峰值。
3. 形态探测（不依赖 Content-Type）：
   - 首选严格 JSON：sing-box 配置、sing-box outbounds/endpoints、节点数组。
   - 再尝试 YAML：Clash/Mihomo `proxies`、sing-box YAML 兼容文档、常见订阅包装结构。
   - 最后尝试 Base64：解码后回到纯节点链接/JSON/YAML探测。
   - 逐行 URI：`vmess://`、`vless://`、`trojan://`、`ss://`、`ssr://`、`hysteria://`、`hysteria2://`、`tuic://`、`socks://`、`http://` 等。
4. 统一模型：解析结果只表达节点/端点、名称、来源、警告，不把未知字段静默当成 sing-box 配置。
5. 核心转换：交给 libbox 当前协议注册表和 CheckConfig 校验；不支持节点逐项报告原因，可配置“严格失败/允许跳过”。
6. 合并：按 subscriptionId + node tag 做来源所有权；更新只替换该来源节点，保留本地节点、其他来源、DNS、路由、入站、分组。
7. 回滚：任何配置校验失败都不写入旧配置；写入 profile、source、report 使用同一事务/修订号。

## NekoBox 能力迁移优先级

### P0：初始架构必须具备

- 多订阅来源、手动更新、自动更新策略、更新时机和失败重试。
- UA、请求头、重定向、Base64/编码兼容。
- 节点去重、正则过滤、分组和排序。
- 应用分流/绕过、VPN 服务生命周期、开机恢复、通知和剪贴板导入。
- 配置/设置备份恢复、旧数据迁移、错误可见化。

### P1：第一轮打磨

- 节点测速、并发限制、缓存与取消。
- DoH/DoT、FakeDNS、IPv6、MTU、TCP keepalive 等 UI 配置。
- 远程控制、分享接收、二维码、快捷开关。
- NekoBox 常见协议字段的表单编辑和 sing-box 映射。

### P2：后续增强

- Root/Shizuku、高级网络栈、TUN/透明代理细项。
- 脚本、规则集、远程资源、WebDAV 等高级能力。
- 兼容导入/导出和迁移测试矩阵。

## 版本升级边界

- FlClash UI、prism_ui、B-box app、sing-box core 四者版本独立记录，不能只改一个版本号。
- 核心升级先在 sing-box fork 完成 rebase、协议扩展和 Go 测试，再更新主工程子模块指针。
- UI 升级先建立来源清单和适配补丁，禁止覆盖 B-box 的业务页面后再猜差异。
- Android 逻辑迁移以能力为单位，禁止把 NekoBox 的 Room 数据库/旧 Activity 直接塞进 Flutter 工程。

## CI / 构建分工

- VPS：轻量检查、Dart 格式化/静态分析、Go 单测、架构脚本、依赖缓存和问题复现。
- GitHub Actions：核心 AAR、Flutter AAR、Android arm64 Release、签名和 artifact/release 发布。
- GitHub Secrets：签名材料、发布 token 等只在 Actions 使用；不写入仓库和日志。
- 低内存 VPS 不执行完整 Gradle/NDK Release，避免 2GB 内存 OOM。

## 第一阶段验收

- `flutter analyze`、Dart 单测、Go `TestUI` 通过。
- YAML / JSON / Base64 / 纯 URI 四类 fixtures 均能得到节点或明确的逐项错误。
- 更新某一来源不会删除其他来源和本地节点。
- 非法输入不会覆盖旧 profile。
- 设置页能看到并保存 NekoBox 兼容能力的 P0 开关。
- GitHub Actions 能从干净环境构建 arm64 APK；VPS 只承担轻量验证。

## 许可证与命名

B-box、FlClash、NekoBox、sing-box 的许可证和商标/应用名限制必须分别保留。新应用使用独立名称、包名、图标和签名；发布包内附完整第三方许可证与来源清单。
