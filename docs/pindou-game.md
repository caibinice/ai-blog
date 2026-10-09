# 拼豆游戏已迁移到 Games 仓库

2026-10-09 起，游戏源码、素材、关卡、测试及构建 / 发布脚本不再放在 ai-blog。

- 仓库：[caibinice/games](https://github.com/caibinice/games)，本机 `E:/codes/games`。
- 游戏规则 / 历史：[Games 拼豆说明](https://github.com/caibinice/games/blob/main/docs/pindou.md)。
- 独立开发、发布及回滚：[Games 发布手册](https://github.com/caibinice/games/blob/main/docs/deployment.md)。
- 迁移验收：[迁移记录](https://github.com/caibinice/games/blob/main/docs/migration.md)。
- 线上入口：[拼就完了](https://caibinice.com/games/pindou/)，100 关和已有 Cookie 进度保持不变。

## 发布约定

在 `E:/codes/games` 执行 `pwsh -File scripts/deploy.ps1`。
先检查、测试并构建 `dist/`，再打包到 `/opt/pindou/releases/<UTC时间>-<Git提交>/www/`，
原子切换 `/opt/pindou/www`。Nginx 继续映射 `/games/pindou/`。
真实配置在新仓库忽略的 `credentials/config.ini`，GitHub 仅存模板。

博客仅保留公共 Nginx 游戏片段、映射模板、本文及发布手册。
旧 `scripts/remote/deploy_pindou.py` 是薄兼容入口，转调 games 的完整发布链；
博客全量构建 / 部署不再打包游戏。后续博客 Nginx 更新须保留
`begin-pindou-static-game` 路由块。

原代码和相关发布说明已备份到
`E:/Documents/AI/codex/backups/games-repo-migration-20261009-220038/`。

## 本次迁移验收

- Games 首次代码提交：`3b16180dc5d79b9c71ea13c7a7e8839a9b34a1d7`，GitHub CI 通过。
- 新独立 release：`20261009142427-3b16180dc5`，北京时间 2026-10-09 22:24。
- 33 个源码 / Git 文件与迁移前备份逐字节一致，公网全部 SHA-256 相符。
- Games 55 项 Node 测试 + 8 项发布测试通过；本地手机浏览器回归通过。
- 博客 TypeScript、12 项测试、55 页生产构建通过，博客 dist 中没有拼豆目录。
- Nginx 正常；共享路由 SHA-256 保持
  `c2b3565dd358c75dfc89ec746a1c86513b8d5c7c160b1d6ca6bdec5f460f36a3`。
- 上一版：`/opt/pindou/releases/20261009053915/www`；服务器备份：
  `/opt/pindou/backups/20261009142427-3b16180dc5/`。
- 本机回滚记录：
  `E:/Documents/AI/codex/backups/games-pindou-20261009-222427-698186/rollback.json`。
