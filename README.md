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

## 仓库与状态（2026-11-15）

- GitHub 远端：`github.com/bayernjf/observability`（**私有**，默认分支 main）。
- 镜像：`otel/opentelemetry-collector-contrib:0.115.1` 已拉取并通过镜像内 `validate`（配置 exit 0）；
  `grafana/tempo:2.6.1` **镜像仍未拉取**——2026-11-15 实测 7 个镜像源均失败（daocloud/1ms.run/dockerproxy
  卡死在同名层零写入、xuanyuan 免费节点繁忙、nju 403、163 EOF、iscas 无该镜像）。
- **fallback 已跑通并验收**：Tempo 官方 darwin/arm64 二进制在宿主机跑（4327 gRPC / 3200 查询），
  collector 容器转发到 `host.docker.internal:4327`；`./smoke-test.sh` **PASS**
  （trace `289311a73ecec2ae8e737f9dbbd3b88a`）。启动：`./start-local-fallback.sh`。
- 镜像恢复后：删 fallback 容器、`docker compose up -d` 回到全容器方案（原 `tempo/tempo.yaml` /
  `otel/collector-config.yaml` 未改动）。

## 启动（需镜像源可用）

```bash
cd ~/000mycodes/observability
docker compose pull           # 补齐 grafana/tempo:2.6.1
docker compose up -d          # 起 otel-collector + tempo
./smoke-test.sh               # 阶段 1 验收：发一条 trace 并从 Tempo 读回
```

停止：`docker compose down`（保留数据）；清空：`docker compose down -v`。

## 镜像拉取受阻时的 fallback（2026-11-15 起在用）

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

- 阶段 2：抽 `@tier0/observability` TS 包，env opt-in（`OTEL_EXPORTER_OTLP_ENDPOINT`
  空=不初始化），先接 zeus（复用既有 span 映射）与 agent-world。
- 阶段 3：loom 用 Python OTel SDK，同样 env opt-in。
- 阶段 4：agent-world prom-client 指标经 collector 收编。
- 统一资源属性：`service.name` / 版本 / `deployment.environment=local`。
