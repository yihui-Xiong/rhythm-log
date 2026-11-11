# Rhythm Log

[英文说明](README.md) · [上手指南](docs/index.html) · [示例截图](docs/index.html#start) · [研究依据与计算方法](docs/index.html#evidence)

一个使用 SwiftUI、Swift Charts 和 HealthKit 的 iPhone App。选择日期，就能回看 Apple「健康」里已保存的心率、心率变异性（SDNN）、静息心率、步数、睡眠和体能训练。

界面支持英文和简体中文。点右上角齿轮可选择语言和浅色／深色外观，语言默认跟随 iPhone，外观默认使用纯白浅色。

## 安装到自己的 iPhone

需要装有包含 iOS 27 SDK 的 Xcode 的 Mac，以及运行 iOS 17 或以上的 iPhone。Apple 提供的训练心率区间需要 iOS 27；较早系统可在设置中手动输入区间边界。

1. 解压项目并双击 `HealthTimeline.xcodeproj`。
2. 在 Xcode 的 **Settings → Apple Accounts** 登录你的 Apple 账户。
3. 选中左侧项目，再选 **HealthTimeline** target。在 **Signing & Capabilities** 里开启 **Automatically manage signing**，从 **Team** 选择自己的团队。项目已配置基础 HealthKit 读取能力。如果 Xcode 提示 Bundle Identifier 已被使用，把它改成自己的唯一标识。
4. 连接并解锁 iPhone。如果手机询问是否信任这台 Mac，按屏幕提示确认。如果 Xcode 要求开启开发者模式，在 iPhone 的 **设置 → 隐私与安全性 → 开发者模式** 开启，并按手机提示重启确认。
5. 在 Xcode 顶部选择你的 iPhone，点 **Run ▶**（⌘R）。第一次打开 App，点「连接 Apple 健康」（Connect Apple Health），允许你希望在时间轴上显示的数据类型。如系统让你选择历史访问范围，选择与你想回看的日期相符的范围。

用免费 Personal Team 安装的签名配置通常七天到期，届时可用 Xcode 重新运行。若签名报错，先核对 **Team**、**Bundle Identifier** 和 **HealthKit** 的配置。

## 在手机上核对

- 选一个之前有训练的日期。在心率图上核对橙色训练时段，再点开训练，查看完整训练时段的放大心率图和逐条读数。
- 轻点心率、HRV 或静息心率图中的测量点，查看时间、数值和来源。也可点「查看逐条记录」，和「健康」里的对应日期核对。
- 日视图的 HRV 散点按个人压力估计分色。白天的有效读数与同一数据来源在该日之前 30 天的每日 SDNN 中位数比较，至少需要 7 个有效日。分数是历史上高于该读数的天数比例（相同计半），线性映射到 1–100。已记录的睡眠和训练时段，以及当地 06:00–22:00 之外的读数，不参与估计。
- 每日 HRV 评分先计算当天符合条件读数的中位数，再用同一来源在此前 30 天的每日中位数分布打分。优先选择能评分且当天有效读数最多的来源。评分使用同一套四档颜色，在日、周、月和月历可见。
- 「夜间 HRV」按醒来日期取主睡眠时段内至少两次同来源读数的中位数，与该来源此前 30 晚比较。
- 「周 / 月 → 恢复」显示白天 HRV、静息心率和步数。有睡眠记录时还显示睡眠时段和夜间生命体征。每日 HRV 使用至少两次同来源读数的中位数，缺测留空。
- 「周 / 月 → 训练」按运动种类堆叠最近八个七日周期的训练分钟数。点柱子查看训练列表，点训练查看心率 Zone。配速和平均心率、1 分钟心率恢复按同类训练比较。
- 在 Xcode 的 Run Arguments 中添加 `-rhythmDemoNoSleep` 可用无睡眠样本运行 Debug 版本。
- 在周、月或年视图查看三项心脏指标。周和月显示每日趋势，年按月汇总。空白表示该时段没有读数。日视图的步数按小时显示。
- 在「月 → 日历」切换每日 HRV 评分、心率、HRV 和静息心率，查看每天的数值和有记录的天数。点日期可打开当天时间轴。
- 选一个有睡眠数据的日期，展开「睡眠明细」。跨午夜的记录在图里只显示落在当天的部分，明细保留原始起止时间。
- 新数据写入 Apple「健康」后，回到 App 或下拉刷新即可重新查询。没有可用记录时，检查「健康」里是否有原始数据，以及头像页面下此 App 的读取权限。

第一版在设备上直接读取 HealthKit，使用前台刷新。图中只画已采集的测量点。训练详情按完整训练时段筛选心率样本。

## Apple 文档

- [配置 HealthKit](https://developer.apple.com/documentation/xcode/configuring-healthkit-access)
- [在 iPhone 上运行项目](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [启用开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
