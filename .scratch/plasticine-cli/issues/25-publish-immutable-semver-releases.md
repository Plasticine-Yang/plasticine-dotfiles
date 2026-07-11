# 25 — 发布不可变 SemVer Release

**What to build:** 将有效 SemVer tag 转化为一个完整、不可变的 GitHub Release，其中包含固定安装 URL 可安全使用的精确 Workstation CLI、checksum manifest 与 Bootstrap assets。

**Blocked by:** 24 — 建立完整 CI、构建与 Smoke Gates

**Status:** implemented

- [x] 有效 `vX.Y.Z` tag 启动 publication workflow；tag/version mismatch 在创建 Release 前失败。
- [x] 发布过程复用或重新运行每项必需的 CI、Tool Lock、build、checksum 与 native smoke gate。
- [x] workflow 恰好组装四个 raw Workstation CLI binaries、`checksums.txt` 和 `install.sh` 作为 Release assets。
- [x] 只有在每个必需 asset 都已生成并验证后，才创建或完成 draft Release。
- [x] 只有完整 asset set 与所有 gates 均成功后才发布 Release；失败不能留下可安装的 partial Release。
- [x] stable 与 prerelease tags 被显式分类，默认 latest-stable 安装路径永不解析到隐式 prerelease。
- [x] 固定 latest-stable Bootstrap URL 解析到已发布 stable Release 的 `install.sh` asset。
- [x] 显式版本选择只解析恰好属于该版本的 immutable assets。
- [x] workflow 永不覆盖或替换已发布的 tags 与 assets。
- [x] hosting platform 提供相关能力时，仓库指引记录必需的 immutable-release setting。
- [x] 每个二进制的 Version 输出与其 tag、commit 和 source-derived build metadata 一致。
- [x] development 或 dirty builds 永不能作为已发布 Release 进入 publication path 或隐藏 self-install path。
- [x] publication failure 保留足够 diagnostics 以定位失败 gate，同时不暴露 Secrets 或含 credential 的 proxy values。
- [x] Workflow-level tests 或安全 dry-run path 验证 stable、prerelease、missing-asset、failed-gate 与 duplicate-tag 行为，且不替换已发布 Release。
