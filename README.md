# Tier0 本地可观测性栈

OTel 统一可观测性方案（`bayjf/docs/tier0/OTel统一可观测性方案-2026-11-14.md`）的阶段 1 落地。
全部本地容器、loopback 绑定、稳态零外部网络调用、零外部费用。

## 组件

| 容器 | 作用 | 端口（仅 127.0.0.1） |
|---|---|---|
| `otel-collector` | 收 OTLP（4317 gRPC / 4318 HTTP）、批处理、转发 | 4317 / 4318 |
| `tempo` | 本地 trace 存储（monolithic，磁盘卷 `tempo-data`，保留 7 天） | 3200 查询 API |

两者接入既有的 `tier0-net`，业务容器用服务名 `otel-collector:4317/4318` 上报；
主机进程用 `http://127.0.0.1:4318`。

## 启动（需镜像源可用）

```bash
cd ~/000mycodes/observability
docker compose up -d          # 首次会拉 grafana/tempo:2.6.1 与 otel collector 0.115.1
./smoke-test.sh               # 阶段 1 验收：发一条 trace 并从 Tempo 读回
```

停止：`docker compose down`（保留数据）；清空：`docker compose down -v`。

## 2026-11-14 网络阻塞记录

当日 daocloud 镜像源（`image-mirror.r2.daocloud.vip`）对所有镜像的 blob 下载均
返回 EOF，连 `busybox` 也无法拉取，直连 registry-1.docker.io 不可达。因此配置与
冒烟脚本已就绪但容器未启动。镜像源恢复后，上面的 `docker compose up -d` 即可补齐，
无需改任何配置。备选镜像源（当时 Registry 可达但 blob 同样受网络影响）：
`docker.1ms.run`、`docker.xuanyuan.me`。

## 后续阶段（本目录之外）

- 阶段 2：抽 `@tier0/observability` TS 包，env opt-in（`OTEL_EXPORTER_OTLP_ENDPOINT`
  空=不初始化），先接 zeus（复用既有 span 映射）与 agent-world。
- 阶段 3：loom 用 Python OTel SDK，同样 env opt-in。
- 阶段 4：agent-world prom-client 指标经 collector 收编。
- 统一资源属性：`service.name` / 版本 / `deployment.environment=local`。
