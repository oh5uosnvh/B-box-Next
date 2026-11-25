# B-box Next 验收标准

出包不代表合格。每次构建前逐条自查，全部满足才提交验收；用户验收通过后才允许创建 GitHub Release。

## A. 架构与合规（每次发版）

- [ ] 内核为 sing-box fork（giturass/sing-box `b-box` 分支），无 Mihomo 运行时
- [ ] core / flutter/packages/prism_ui 子模块指针指向已推送提交
- [ ] 三个上游基线（UI / core / app）在 docs 中记录到具体 commit/tag
- [ ] 不复用任何上游签名、包名、品牌
- [ ] 未经用户明确同意，不创建 Release、不推送 tag

## B. 订阅导入（改到导入逻辑时必测）

- [ ] Clash YAML 订阅（含 proxies 列表）导入后得到节点
- [ ] 纯节点链接（vmess/vless/trojan/ss/ssr/hysteria2/tuic，单条与多行）导入后得到节点
- [ ] sing-box JSON（outbounds/endpoints）导入后得到节点
- [ ] Base64 编码订阅解码后按上述规则识别
- [ ] 无可导入节点时给出明确错误，不写入空配置
- [ ] 更新订阅只替换该来源节点，其他来源与本地节点保留
- [ ] 更新失败时旧配置保持不变

## C. 仪表盘（UI 级）

- [ ] 默认卡片常驻：状态、网速、规则模式、当前配置、代理组，启动前后不增减、不跳位
- [ ] 规则模式卡片在未启动时也显示（默认 Rule 高亮、不可点），启动后可切换
- [ ] 启动按钮开/关过程中无闪白、无灰跳、无布局抖动
- [ ] 卡片顺序由编辑器保存，重启后保持

## D. 配置页（FlClash 风格）

- [ ] 配置分组以垂直卡片列表呈现（FlClash Profiles 样式），不是顶部横向滑动条
- [ ] 添加订阅/新建配置后卡片立即可见
- [ ] 卡片支持：选择、编辑、更新、分享、二维码、导出、删除
- [ ] "全部更新"、"配置排序"入口可用

## E. 代理页（NekoBox 复刻）

- [ ] 顶部胶囊 = 配置分组（profile）名称，点按切换配置
- [ ] 胶囊下方直接是纯节点卡片，无代理分组（selector/urltest）胶囊条
- [ ] 节点跨分组去重显示
- [ ] 点按节点 = 在包含该节点的可切换组中生效（选中态有标识）
- [ ] 每个节点可单独测延迟；工具栏"测延迟"作用于全部组
- [ ] 搜索、排序、布局选项仍然可用

## F. 构建产物（每次验收包）

- [ ] `flutter analyze --no-fatal-infos` 无 error/warning
- [ ] `flutter test` 全绿
- [ ] Release APK 签名成功、可在 Actions Artifacts 下载
- [ ] 版本号与 version.properties 一致，产物附 sha256 元数据
- [ ] 只构建 Artifact，不发布 Release

## G. 回归底线

- [ ] VPN 启动/停止正常
- [ ] 节点选择在停止状态下可保存（revision 校验通过）
- [ ] 剪贴板节点导入提示仍工作
- [ ] 中文界面文案完整（l10n key 未缺失）
