# Tier0 本地可观测性栈

OTel 统一可观测性方案（`bayjf/docs/tier0/OTel统一可观测性方案-2026-11-14.md`）的阶段 1 落地。
全部本地容器、loopback 绑定、稳态零外部网络调用、零外部费用。

## 组件

| 容器 | 作用 | 端口（仅 127.0.0.1） |
|---|---|---|
| `otel-collector` | 收 OTLP（4317 gRPC / 4318 HTTP）、批处理、scrape 六个 Tier0 服务指标、转发 | 4317 / 4318 |
| `tempo` | 本地 trace 存储（monolithic，磁盘卷 `tempo-data`，保留 7 天） | 3200 查询 API |
| `prometheus` | 本地指标后端（scrape collector 的 exporter），磁盘卷 `prometheus-data` | 9090 |
| `grafana` | 看板（数据源置备指向 Prometheus + Tempo），磁盘卷 `grafana-data` | 3001 |

全部容器接入既有的 `tier0-net`，业务容器用服务名 `otel-collector:4317/4318` 上报；
主机进程用 `http://127.0.0.1:4318`。

## 仓库与状态（2026-11-15）

- GitHub 远端：`github.com/bayernjf/observability`（**私有**，默认分支 main）。
- **全容器方案已上线并通过冒烟（当前主用）**：`otel-collector` + `tempo` 两容器在
  tier0-net 运行，`./smoke-test.sh` PASS（trace 经 collector 存入 Tempo 可查回）。
  镜像：`otel/opentelemetry-collector-contrib:0.115.1`、`grafana/tempo:2.6.1`
  （后者从 daocloud 拉取后 `docker tag` 为标准名）。
- 配置注意：Tempo 2.6.1 的 compactor 只支持 `block_retention`，**不支持
  `retention_concurrency`**（更高版本字段，写入会让容器启动崩溃），`tempo/tempo.yaml` 已修正。
- **fallback（备用，非默认）**：`start-local-fallback.sh` 用主机 darwin/arm64 Tempo 二进制
  + 临时 collector，仅在容器镜像完全拉不动时使用。它的 `otel-collector-local` 占用
  127.0.0.1:4318，与全容器方案互斥；切换前先 `docker compose down` 并 `docker rm -f otel-collector-local`。

## 启动（当前主用：全容器）

```bash
cd ~/000mycodes/observability
docker compose up -d          # 起 otel-collector + tempo（镜像已在本地）
./smoke-test.sh               # 阶段 1 验收：发一条 trace 并从 Tempo 读回
```

停止：`docker compose down`（保留数据）；清空：`docker compose down -v`。

## 镜像拉取受阻时的 fallback（备用，非默认）

若 `grafana/tempo` 镜像无法拉取，用官方 darwin/arm64 二进制在宿主机跑 Tempo：

```bash
cd ~/000mycodes/observability
./start-local-fallback.sh     # 起宿主 tempo (4327 gRPC / 3200 查询) + collector 容器 (4318)
./smoke-test.sh               # 已验证 PASS
```

二进制放在 `tempo/bin/tempo`（74MB，gitignored，一次性从 GitHub release 获取
`tempo_2.6.1_darwin_arm64.tar.gz`，国内可走 `https://ghfast.top/` 前缀加速）。
停止：`docker rm -f otel-collector-local` + `pkill -f tempo/bin/tempo`。

## 2026-11-14 网络阻塞记录（历史，镜像源次日已部分恢复）

当日 daocloud 镜像源（`image-mirror.r2.daocloud.vip`）对所有镜像的 blob 下载均
返回 EOF，连 `busybox` 也无法拉取，直连 registry-1.docker.io 不可达。2026-11-15
镜像源恢复（busybox、collector 可拉），但 Tempo 大镜像仍可能间歇失败，需重试。
备选镜像源（Registry 可达但 blob 同样受网络影响）：`docker.1ms.run`、`docker.xuanyuan.me`。

## 后续阶段（本目录之外）

- 阶段 2（**2026-11-15 已完成**）：单仓独立架构下不抽共享包（`~/000mycodes` 无
  monorepo 根、无 `packages/` 共享目录），改为**各仓内联 + 统一 env 契约**
  （`OTEL_EXPORTER_OTLP_ENDPOINT` 空=不初始化、`OTEL_SERVICE_NAME`、
  `deployment.environment=local`）。zeus 走既有 `OtlpTraceExporter`（G2 opt-in，
  `ZEUS_OTLP_ENDPOINT`，并已加入 `ZEUS_OUTBOUND_ALLOW_HOSTS`）；agent-world 新增
  `packages/server/src/observability/otlp.ts`，在 `/api/*` 中间件 fire-and-forget
  导出请求 span。两者均已端到端验证：经 collector→tempo 可查回
  `service.name=zeus` 与 `service.name=agent-world`。
- 阶段 3（**2026-11-15 已完成**）：loom backend 接官方 Python OTel SDK（api /
  sdk / exporter-otlp-proto-http，1.45.2），自写 ASGI 中间件（不引 instrumentation
  全家桶），同样 env opt-in（`OTEL_EXPORTER_OTLP_ENDPOINT` 空=不初始化、
  `OTEL_SERVICE_NAME` 默认 loom-backend、`deployment.environment=local`）。
  `requirements.lock` 增 12 pin、既有 43 pin 零漂移。已端到端验证：中间件产出的
  `GET /healthz` span 经 collector 落 tempo，可查回 `service.name=loom-backend`；
  loom compose 已默认指向 tier0-net 的 collector（覆盖为空串即关闭）。
- 阶段 4（**2026-11-15 已完成**）：agent-world 本就有 `/metrics`（Prometheus 文本格式，
  自写 metrics.ts 输出 RED + run 成本指标），经 docker-compose.local.yml 已在 tier0-net。
  collector 加 `prometheus` receiver scrape `agent-world:8791/metrics`，经 `prometheus`
  exporter（:8889）转给 Prometheus（`prom/prometheus:3.16.0`，宿主 `127.0.0.1:9090`）。
  端到端实证：Prometheus 可查到 `http_requests_total` 且 label 带
  `exported_job="agent-world"`。当前 metrics 后端为 Prometheus，数据落本机 volume。
- 阶段 5（**2026-11-15 完成**）：Grafana 看板。`grafana/grafana:11.4.0` 接
  Prometheus（默认数据源）+ Tempo，文件式置备数据源与「Tier0 可观测性总览」看板
  （HTTP RED + run 计数/失败/成本/活跃 + 最近 trace）。loopback 绑 `127.0.0.1:3001`
  （宿主 3000 被占用），管理员口令默认可经 `GRAFANA_ADMIN_PASSWORD` 覆盖。
  访问 `http://127.0.0.1:3001`（admin / admin，或按 env 覆盖值）。
- 阶段 6（**2026-11-15 完成**）：Grafana 内置告警（unified alerting，无需额外
  Alertmanager 容器）。文件式置备三条规则（`grafana/provisioning/alerting/rules.yml`）：
  ① agent-world `/metrics` 抓取失败（up=0，critical）② 5xx 速率异常（warning）
  ③ Run 失败率异常（warning）。接触点（`contact-points.yml`）为单一 webhook，默认
  指向本地 loopback 假接收端 `scripts/fake-alert-receiver.mjs`（:9099），真实外部渠道
  （飞书/微信/Slack bot）通过 `GRAFANA_ALERT_WEBHOOK_URL` 环境变量覆盖 URL 即可，
  规则无需改。通知策略（`policies.yml`）默认路由到该接触点。
  端到端已实证：规则求值报错 → Grafana 发 `DatasourceError` 告警 → webhook →
  fake receiver 收到 firing 告警。验证：`node scripts/fake-alert-receiver.mjs` 后
  在 Grafana UI「Alerting」页看规则 firing，或直接看 receiver 日志。
  注意：Grafana 11 的 alert rule `data[].relativeTimeRange` 是顶层必填字段
  （缺了会 `invalidRelativeTime` 崩溃循环），`from: 300` 表示回看 5m 窗口。
- 阶段 7（**2026-11-15 完成**）：loom backend 与 atlas 指标接入集中式栈。collector 的
  prometheus receiver 增 `loom-backend`（`backend:8000/metrics`）与 `atlas`
  （`atlas:8000/metrics`）两个 scrape 目标。三服务现并存于同一 Prometheus，靠
  `exported_job` label 区分：agent-world（`runs_*`/`http_request_duration_ms`）、
  loom（`http_request_duration_seconds`/`up`）、atlas（`atlas_*` 前缀全隔离）。
  已端到端验证：`up{exported_job="loom-backend"}=1`、`atlas_up=1` 均可在 Prometheus
  与 Grafana 代理查到。这是「集中式 Grafana 统一收编 Tier0 服务」的前两步；其余
  服务（zeus/commerce-os/growth-os 等）按需跟进。
- 阶段 7 附带修正（**告警规则求值修复**）：三服务接入后暴露了两处 Grafana 11 告警
  规则的求值坑，均已修并记录：① `instant:true` 与 `range:true` 不能同设——同设会
  `frame has wrong type, expected NumericMulti but got timeseries-multi`；alert 规则
  只用 `instant:true`。② 空向量问题——表达式在「无告警」时须返回明确数值而非空向量，
  否则 `input data must be a wide series`；做法是最外层 `or vector(0)` 兜底。
  且 agent-world 不吐 `up` 指标，「服务不可达」用 `absent(<稳定指标>)` 检测而非
  `up==0`。最终三条规则 `health=ok`、`state=inactive`、`lastError=None`。
- 阶段 7 看板增强（**2026-11-15 完成**）：「Tier0 可观测性总览」看板从 8 面板扩到
  13 面板，按服务分区：agent-world（HTTP 速率/5xx/延迟/Run 累计+三个 stat）→
  loom（HTTP 速率/延迟 P50·P90·P99）→ atlas（存活/活跃租户/Run 累计 stat）→
  最近 Trace。三服务的指标现都能在同一个看板里看到。
- 阶段 8（**2026-11-15 完成**）：zeus 决策运行时接入集中式栈。zeus 此前只有 bearer
  保护的 `/api/metrics` JSON，没有 Prometheus 文本面，所以 collector 抓不到它——这是
  它缺席看板的唯一技术原因。本阶段跨两仓：
  - **zeus 仓**新增 `GET /metrics`（`src/observability/prometheus.ts`，纯投影、零 IO）：
    把 `/api/metrics` 的同一份 `MetricsSnapshot` 渲染成 `zeus_*` 文本族，不新建第二条
    记账路径，两个面因此不可能互相矛盾。挂在 `internalToken` 块之外，未配 operator
    token 的进程照样报自身健康；鉴权用独立的可选 `ZEUS_METRICS_TOKEN`（抓取器不该
    持有操作者凭证）。没有已结束调用的执行 Agent 只输出 `in_flight`，不输出延迟族
    （0ms 的 p95 会被读成「极快」而不是「未知」）。
  - **本仓** collector 增 `zeus`（`zeus:8787/metrics`）scrape 目标；看板增 zeus 分区
    6 面板（存活 / 在途分支 / 排队·拒绝 / 分支终态与背压速率 / 每执行 Agent 失败率 /
    派发与排队延迟 P95），13 → **19 面板**，最近 Trace 下移到 y58；「服务不可达」告警
    增第四项 `count(absent(zeus_up))`。
  - **已端到端现测**（不是配置推断）：`docker compose build zeus && up -d` 重建容器后
    `curl 127.0.0.1:18787/metrics` → HTTP 200、`text/plain; version=0.0.4`、17 个族
    （当时尚无已结束分支，执行 Agent 族按设计不输出）；
    collector 日志 `Scrape job added {"jobName":"zeus"}`；Prometheus
    `up{exported_job="zeus"}=1`；看板 13 个 zeus target 全部求值成功；Grafana
    `/api/ds/query` 取回 `max(zeus_up)=1`。再经容器内 `POST /api/intents` 跑真意图
    （两个执行 Agent 各 2 分支、4 分支 completed），Grafana 侧读回
    `zeus_executor_latency_ms{stat="p95"}`：example-agent **35ms**、llm-agent
    **26488ms**，`zeus_queue_wait_ms{stat="p95"}=10`。三条告警规则
    `health=ok`、`state=inactive`、`lastError=""`。
  - **本阶段踩到并修掉的坑**：`<裸指标> or vector(0)` 在指标存在时返回 **2 条**序列
    （`vector(0)` 标签集为空，与带 `exported_job` 的左侧不匹配，`or` 不去重），stat
    面板会同时显示「在线 1」和「离线 0」。必须先聚合再兜底：`max(zeus_up) or vector(0)`
    / `sum(...) or vector(0)` → 1 条。正对照：把 `zeus_up` 换成不存在的指标名，
    告警表达式从 `0` 变 `1`，证明新增项真的进了求和而不是装饰。既有 7 阶段的告警与
    面板本来就用聚合形式，无此缺陷。
  - 另记：Grafana **看板**置备每 10s 热加载（`updateIntervalSeconds: 10`），**告警规则**
    置备不热加载，改 `rules.yml` 后必须 `docker compose restart grafana` 才生效。
- 阶段 9（**2026-11-22 完成**）：commerce-os 与 growth-os 指标接入，补齐交易与增长两个业务面。
  - **commerce-os 仓**新增 `GET /metrics`（`src/observability/prometheus.ts`）：把
    `DashboardService.getMetrics()` 的同一份 `DashboardMetrics` 纯投影成 Prometheus
    文本 0.0.4，不新建第二条记账路径。指标族：`commerce_up`、快照时间戳、
    `commerce_currency_info`、`commerce_orders{state}`、`commerce_gross_amount{currency}`、
    `commerce_refunds{state}`、`commerce_refunded_amount{currency}`、
    `commerce_content_published`、`commerce_net_amount{currency}`。端点挂在 `/api/v1`
    与 bearer 中间件之外，只输出聚合值，不暴露订单明细。
  - **growth-os 仓**新增 `GET /metrics`（`src/observability/prometheus.ts` +
    `src/api/metrics-http.ts`，`Cache-Control: no-store`）：`growth_up`、uptime、
    快照时间戳、`growth_leads{status}` + total、`growth_lead_followups{state}`、
    `growth_campaigns`、`growth_outreach_drafts{status}` + total、
    `growth_research_reports`。标签只到状态枚举；邮箱、主题、正文不会成为 label。
  - **本仓** collector 增 `commerce-os`（`commerce-os:8787/metrics`）与 `growth-os`
    （`growth-os:8788/metrics`）两个 scrape job；两仓 compose 的业务服务同时接入
    `tier0-net`，collector 可直接按服务名抓取。
  - 看板 19 → **26 面板**，新增 id 20–26：commerce 存活、GMV/净额、订单按状态；
    growth 存活、线索总数、到期跟进、外联草稿。最近 Trace 面板下移到 `y=76`。
    「服务不可达」告警在原有四项之外增加 `commerce_up` / `growth_up` 两个 `absent` 项。
  - **已端到端现测**（2026-11-22，不是配置推断）：重建两个业务容器并重启 collector 后，
    collector 日志出现 `Scrape job added` 的 `commerce-os` / `growth-os`；Prometheus
    `up{exported_job="commerce-os"}=1`、`up{exported_job="growth-os"}=1`；
    `commerce_up=1`、`growth_up=1`；Grafana 置备看板确为 26 面板，新面板查询全部成功：
    commerce GMV **2697** / 净额 **899**、订单 all=3 / paid=3 / completed=0；
    growth leads=1 / due=0 / drafts=1。不可达告警表达式求值为 0，active alerts=0。
  - **本阶段踩到并修掉的坑**：`sum by (state) (commerce_orders) or vector(0)` 在指标
    存在时会多出一条空标签 `{} = 0` 序列（`vector(0)` 的标签集与按状态聚合的序列不匹配，
    `or` 不去重），图例会多一条空名线。按标签拆分的面板不能加 `vector(0)` 兜底，已改为
    `sum by (state) (commerce_orders)`；单值 stat 面板继续用
    `max(...) or vector(0)` / `sum(...) or vector(0)`。
- 统一资源属性：`service.name` / 版本 / `deployment.environment=local`。
