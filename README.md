# Tier0 本地可观测性栈

OTel 统一可观测性方案（`bayjf/docs/tier0/OTel统一可观测性方案-2026-11-14.md`）的阶段 1 落地。
全部本地容器、loopback 绑定、稳态零外部网络调用、零外部费用。

## 组件

| 容器 | 作用 | 端口（仅 127.0.0.1） |
|---|---|---|
| `otel-collector` | 收 OTLP（4317 gRPC / 4318 HTTP）、批处理、scrape agent-world 指标、转发 | 4317 / 4318 |
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
- 阶段 7（**2026-11-15 完成**）：loom backend 指标接入集中式栈。collector 的
  prometheus receiver 增 `loom-backend` scrape 目标（`backend:8000/metrics`，loom
  后端在 tier0-net 上的服务名是 `backend`）。loom 零依赖自写 Prometheus 文本
  （`http_requests_total`/`http_request_duration_seconds`/`up` 等）现与 agent-world
  并存于同一 Prometheus，靠 `exported_job` label 区分（agent-world 用 `_ms` 直方图、
  loom 用 `_seconds` 直方图，命名不冲突）。已端到端验证：Prometheus 与 Grafana 代理
  均可查到 `up{exported_job="loom-backend"}=1`。这是「集中式 Grafana 统一收编 Tier0
  服务」的第 1 步；atlas 及其余服务按需跟进。
- 统一资源属性：`service.name` / 版本 / `deployment.environment=local`。
