# observability · handoff

## 待办登记（标准）

> 本段是本产品唯一活跃待办入口；详细背景见下方原有章节。完成一项改 `[x]`，并在“最近变更 / Recently shipped”留证据。
> 最近同步：2026-11-19

- [ ] **其余 Tier0 服务指标接入** — 状态：open；commerce-os / growth-os 按需跟进；当前 zeus / agent-world / loom / atlas 已接入。
- [ ] **真实告警渠道** — 状态：blocked；飞书/微信/Slack bot URL 未定义，当前只到 `scripts/fake-alert-receiver.mjs`；外部确定后经 `GRAFANA_ALERT_WEBHOOK_URL` 覆盖。

> 状态主入口。开工前先读；每完成一个工作单元立即更新（已完成划掉、待办保留）。
> 组件/配置/启动细节以 `README.md` 为权威，本文件只记录交接信息（进度 + 下一步 + 阻塞）。

## Current state（2026-11-19）

- **仓库**：git 私有 `github.com/bayernjf/observability`，默认分支 main。
- **形态**：本地可观测性栈（集中式 Grafana），全容器方案为主用、主机二进制 fallback 备用。
  全部 loopback 绑定、稳态零外部网络调用、零外部费用。
- **组件**：otel-collector（OTLP + 指标 scrape）、tempo（trace 存储，保留 7 天）、
  prometheus（指标后端）、grafana（看板 + 告警）。

## 阶段进度（1–8 全部闭环，明细见 README）

- ✅ 阶段 1：collector + tempo 容器上线，`smoke-test.sh` PASS。
- ✅ 阶段 2：zeus + agent-world 接 OTLP trace（各仓内联 + 统一 env 契约）。
- ✅ 阶段 3：loom backend 接官方 Python OTel SDK（1.45.2，零 instrumentation 全家桶）。
- ✅ 阶段 4：agent-world `/metrics` 经 collector 转 Prometheus。
- ✅ 阶段 5：Grafana「Tier0 可观测性总览」看板（默认数据源 Prometheus + Tempo）。
- ✅ 阶段 6：Grafana 内置告警三条规则，接触点默认本地假接收端。
- ✅ 阶段 7：loom + atlas 指标接入；看板 8 → 13 面板；两处 Grafana 11 告警求值坑已修。
- ✅ 阶段 8：zeus 决策运行时接入（zeus 新增 `GET /metrics` Prometheus 文本面；
  看板 13 → 19 面板）；已端到端现测，非配置推断。

## 待办

- [ ] 其余 Tier0 服务指标接入：commerce-os / growth-os 按需跟进（当前 zeus / agent-world /
      loom / atlas 已接入）。
- [ ] 真实告警渠道：飞书/微信/Slack bot URL 未定义，当前只到 `scripts/fake-alert-receiver.mjs`；
      外部确定后经 `GRAFANA_ALERT_WEBHOOK_URL` 覆盖即可，规则无需改。

## 阻塞 / 外部依赖

| 项 | 说明 |
|---|---|
| 真实告警 webhook URL | 未定义，属外部凭据/渠道，本地无法完成 |
| 服务指标接入的下一步 | 非阻塞，按产品优先级择机跟进 |

## 备注

- 本仓不承载业务功能，无测试基线；验收口径为 `smoke-test.sh`（trace 端到端）+ 各阶段现测记录。
- 分级清单（`bayjf/docs/PROJECT-TIER-CONVENTION.md` §4）为本仓 Tier 0 归属权威。