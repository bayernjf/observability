# observability · handoff

## 待办登记（标准）

> 本段是本产品唯一活跃待办入口；详细背景见下方原有章节。完成一项改 `[x]`，并在“最近变更 / Recently shipped”留证据。
> 最近同步：2026-11-22

<!-- tier0:todos v1 -->
| id | title | status | priority | owner | next | evidence | updated |
|---|---|---|---|---|---|---|---|
| OB-01 | 其余 Tier0 服务指标接入 | open | p2 | self | model-hub / growth-agent / ops-console 已接入；剩 agent-ops 按需跟进 | `observability/handoff.md` | 2026-11-27 |
| OB-02 | 真实告警渠道 | blocked | p1 | owner | owner 提供飞书/微信/Slack webhook，经 `GRAFANA_ALERT_WEBHOOK_URL` 覆盖 | - | 2026-11-22 |
<!-- /tier0:todos -->

### 已完成（历史）

- [x] **commerce-os / growth-os 指标接入** — 2026-11-22 完成；两仓新增 `GET /metrics`，
  collector 增两个 scrape job，看板 19 → 26 面板，服务不可达告警增两项；已端到端现测。

> 状态主入口。开工前先读；每完成一个工作单元立即更新（已完成划掉、待办保留）。
> 组件/配置/启动细节以 `README.md` 为权威，本文件只记录交接信息（进度 + 下一步 + 阻塞）。


## Current state（2026-11-22）

- **仓库**：git 私有 `github.com/bayernjf/observability`，默认分支 main。
- **形态**：本地可观测性栈（集中式 Grafana），全容器方案为主用、主机二进制 fallback 备用。
  全部 loopback 绑定、稳态零外部网络调用、零外部费用。
- **组件**：otel-collector（OTLP + 指标 scrape）、tempo（trace 存储，保留 7 天）、
  prometheus（指标后端）、grafana（看板 + 告警）。

## 阶段进度（1–9 全部闭环，明细见 README）

- ✅ 阶段 1：collector + tempo 容器上线，`smoke-test.sh` PASS。
- ✅ 阶段 2：zeus + agent-world 接 OTLP trace（各仓内联 + 统一 env 契约）。
- ✅ 阶段 3：loom backend 接官方 Python OTel SDK（1.45.2，零 instrumentation 全家桶）。
- ✅ 阶段 4：agent-world `/metrics` 经 collector 转 Prometheus。
- ✅ 阶段 5：Grafana「Tier0 可观测性总览」看板（默认数据源 Prometheus + Tempo）。
- ✅ 阶段 6：Grafana 内置告警三条规则，接触点默认本地假接收端。
- ✅ 阶段 7：loom + atlas 指标接入；看板 8 → 13 面板；两处 Grafana 11 告警求值坑已修。
- ✅ 阶段 8：zeus 决策运行时接入（zeus 新增 `GET /metrics` Prometheus 文本面；
  看板 13 → 19 面板）；已端到端现测，非配置推断。
- ✅ 阶段 9：commerce-os + growth-os 指标接入（两仓各新增 `GET /metrics`；
  看板 19 → 26 面板；服务不可达告警增加两项）；已端到端现测，非配置推断。
- ⬜ 阶段 10（进行中）：model-hub + growth-agent + ops-console 指标接入
  （三仓各新增 `GET /metrics`，collector 增 `model-hub:8791` / `orchestrator:8790` /
  `ops-console:3022`，看板 26 → 38 面板，不可达告警增 `modelhub_up` /
  `growth_agent_up` / `ops_console_up`）；代码与配置已落地，待容器运行后端到端现测。

## 最近变更 / Recently shipped

- **2026-11-22 · 阶段 9 收口**：commerce-os / growth-os 指标接入集中式栈。
  - commerce-os `GET /metrics` 输出 9 个聚合族；growth-os `GET /metrics` 输出 10 个聚合族；
    端点均不要求 bearer，且不暴露明细。
  - collector 增 `commerce-os:8787` / `growth-os:8788`；两仓 compose 服务接入 `tier0-net`。
  - 看板新增 7 面板（id 20–26），Trace 下移到 `y=76`；不可达告警增
    `commerce_up` / `growth_up` 两个 `absent` 项。
  - 证据：`up{exported_job="commerce-os"}=1`、`up{exported_job="growth-os"}=1`；
    `commerce_up=1`、`growth_up=1`；Grafana 26 面板；新面板查询取到
    commerce GMV 2697 / 净额 899、growth leads 1 / due 0 / drafts 1；
    不可达告警表达式 0、active alerts 0。
  - 门禁：commerce-os 192 tests、growth-os 229 tests；两仓 typecheck/lint/build/
    migration 检查全绿。
  - 修复：按标签拆分面板去掉 `vector(0)` 兜底，避免指标存在时多出空标签 `{} = 0` 序列。
- **2026-11-27 · 阶段 10 首片（model-hub）**：model-hub 指标接入集中式栈。
  - model-hub `GET /metrics` 输出 10 个聚合族（`modelhub_*`，含 usage calls/tokens/
    cost_micros 按 `model × billing_source` 分组 + projects/providers 计数）；端点无鉴权、
    不暴露 prompt 内容/key/项目 id。
  - collector 增 `model-hub:8791`；看板新增 4 面板（id 27–30），Trace 下移到 `y=82`；
    不可达告警增 `modelhub_up` 一个 `absent` 项。
  - 门禁：model-hub 49 文件 / 425 tests 全绿、typecheck 0、lint 0。
  - ⬜ 端到端现测待 model-hub 容器在 tier0-net 运行后补（`modelhub_up=1` + 面板取到样本）。
- **2026-11-27 · 阶段 10 第二片（growth-agent）**：growth-agent 指标接入集中式栈。
  - growth-agent `GET /metrics` 输出 14 个聚合族（`growth_agent_*`：任务按 status/type、
    API 调用与成本按 provider、webhook 按 source×result、channel failure、GSC 快照计数）；
    端点无鉴权，不暴露 task id / PR ref（仓库 URL）/ decision id / delivery id / 错误文本。
  - growth-agent compose `orchestrator` 加入 `tier0-net`；collector 增 `orchestrator:8790`；
    看板新增 4 面板（id 31–34），Trace 下移到 `y=88`；不可达告警增 `growth_agent_up`。
  - 门禁：growth-agent 49 文件 / 472 tests 全绿、typecheck 0、lint 0、`docker compose config` OK。
  - ⬜ 端到端现测待 growth-agent 容器在 tier0-net 运行后补（`growth_agent_up=1` + 面板取到样本）。
- **2026-11-27 · 阶段 10 第三片（ops-console）**：ops-console 指标接入集中式栈。
  - ops-console `GET /metrics` 输出 5 个聚合族（`ops_console_*`：up/uptime/timestamp +
    通知投递账本按 event×status 计数 + 总数）；端点免鉴权，不导出 decision id /
    deep link / webhook URL / error text。
  - ops-console compose 加入 `tier0-net`；collector 增 `ops-console:3022`；看板新增
    4 面板（id 35–38），Trace 下移到 `y=94`；不可达告警增 `ops_console_up`。
  - 门禁：ops-console 38 文件 / 273 tests 全绿、lint 0、`astro check` 0（fnm v22.23.4）、
    build 通过、`docker compose config` OK。
  - ⬜ 端到端现测待 ops-console 容器在 tier0-net 运行后补（`ops_console_up=1` + 面板取到样本）。

## 阻塞 / 外部依赖

| 项 | 说明 |
|---|---|
| 真实告警 webhook URL | 未定义，属外部凭据/渠道，本地无法完成 |
| 其余服务指标接入 | 非阻塞，按产品优先级择机跟进；model-hub / growth-agent / ops-console 已接（阶段 10 前三片），剩 agent-ops |

## 备注

- 本仓不承载业务功能，无测试基线；验收口径为 `smoke-test.sh`（trace 端到端）+ 各阶段现测记录。
- 分级清单（`bayjf/docs/PROJECT-TIER-CONVENTION.md` §4）为本仓 Tier 0 归属权威。