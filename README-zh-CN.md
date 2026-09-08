# 🪟 Tiny11 中文一键制作器（本分支特色）

> 基于 [kelexine/tiny11-automated](https://github.com/kelexine/tiny11-automated) 的分支改造。
> **本分支两大特色：**
> 1. **全中文手册**（本文件 + 各脚本中文注释）
> 2. **免找下载链接**——用 **UUP dump** 自动取料、合成 ISO、再做精简，用户只需在界面点几个选项。

---

## ✨ 为什么有这个分支

原项目需要你**先有一个 Windows 11 ISO 的下载链接**（`windows_iso_url`）才能构建。很多新手卡在"去哪找官方 ISO 直链"上。

本分支帮你绕开这一环：直接对接 **UUP dump**（它内部用的是**微软官方永久 CDN 直链**），自动下载 UUP 文件并在本地/云上合成完整的 Windows 11 ISO，随后执行 tiny11 标准精简。你只要选 **版本 / 语言 / 版本** 三个选项即可。

> 💡 需要 ISO 直链的老用户，原工作流（`Build and Release Tiny11 / Core / Nano11`）原样保留，你仍可继续用。

---

## 🚀 快速开始（推荐：GitHub Actions 云端构建）

### 第 1 步：Fork 本仓库
点右上角 **Fork**，得到你自己的仓库。

### 第 2 步：进入 Actions 并运行
1. 在你自己仓库的 **Actions** 标签页，选择 **`Build Tiny11 (UUP - 无需下载链接)`**。
2. 点 **Run workflow**，按需选择：

| 输入项 | 说明 | 常用值 |
|---|---|---|
| **Windows 版本** | 系统大版本 | `26H2`（最新预览版）/ `25H2`（推荐，稳定）/ `24H2` |
| **语言** | 系统语言 | `zh-cn`（简体中文，默认）/ `zh-tw` / `en-us` / `ja-jp` 等 |
| **版本** | 系统版本（SKU） | `pro`（专业版，默认）/ `home` / `education` / `enterprise` |
| **UUP build id**（可选·高级） | 留空自动解析；想追最新可自己填 | 留空即可 |
| **包含更新** | 合成时打上最新累积更新 | `true` |
| **调试** | 保留中间临时文件 | `false` |

3. 点绿色 **Run workflow**，点击运行进入运行页。

### 第 3 步：等待并下载
- 全程约 **2–4 小时**（UUP 合成 ISO + tiny11 标准精简）。
- 完成后在运行页下方 **Artifacts** 下载 `tiny11-<版本>-<语言>-<版本>.zip`，解压即得 `.iso`。

---

## 💻 本地构建（不用 GitHub，可选）

需要：**Windows 10/11**、PowerShell 5.1+、管理员权限、≥40GB 空闲磁盘。

```powershell
# 以管理员身份打开 PowerShell
Set-ExecutionPolicy Bypass -Scope Process

# 一键制作：26H2 简体中文 专业版
.\scripts\build-tiny11-local.ps1 -Version 26H2 -Language zh-cn -Edition pro

# 其它示例
.\scripts\build-tiny11-local.ps1 -Version 25H2 -Edition enterprise   # 企业版
.\scripts\build-tiny11-local.ps1 -Version 24H2 -Language en-us -Edition home
```

> 等价于 Actions 的 UUP 流程，只是跑在你本机。生成物在当前目录 `tiny11-*.iso`。

也可以分步手动：
```powershell
# 只解析并下载 UUP 下载包（预览解析结构用 -DryRun）
.\scripts\uup-resolve.ps1 -Version 26H2 -Language zh-cn -Edition pro -DryRun
```

---

## 🔍 UUP「自动取料」是怎么工作的

脚本 [`scripts/uup-resolve.ps1`](scripts/uup-resolve.ps1) 采用**混合式构建 ID 解析**：

1. 若手动填了 `UUP_BUILD_ID` → 直接用；
2. 否则**优先尝试实时抓 UUP dump 最新构建**；被 Cloudflare 拦截/失败时静默回退；
3. 回退到仓库内 `[config/builds.json](config/builds.json)` 的**快照映射**（版本 → build id）。

> 快照需随新构建适度更新；日常使用无需打理，留空用快照即可。

---

## 🧩 版本（SKU）与索引说明

tiny11 脚本会**自动校正** Home/Education/Pro 的 wim 图像索引，所以：
- `home` → 索引 1、`education` → 4、`pro` → 6，**自动对准**。
- `enterprise`（企业版）是 UUP 合成出的**附加版本**，tiny11 无内置映射，流程会**额外读取 wim 图像名自动定位企业版索引**后再精简：**企业版流程稍慢，且较实验性**。

---

## ❓ 常见问题（FAQ）

**Q：构建很慢，正常吗？**
正常。DNG 取料 ~30–60 分钟，tiny11 标准精简 45–80 分钟，总 2–4 小时属预期。公共仓库 GitHub Actions 免费额度为 2000 分钟/月，够用。

**Q：用了企业版，结果对不对？**
企业版走"读 wim 图像名定位索引"的附加逻辑，多数情况是正确的；但企业版属实验性，若精简后版本不对，请检查运行日志中"企业版图像索引"那一条。

**Q：找不到最新构建，怎么办？**
在运行参数里填 `UUP_BUILD_ID`（UUP dump 该构建页 URL 中的 uuid）即可强制指定。

**Q：实体机安装报 `0x8007000B`？**
那是精简掉 WinRE 导致的恢复环境问题，与 Wim 无关；正式安装请优先用 ISO 全新安装或实体机场景需保留 WinRE（本分支当前默认标准版精简，多数场景无碍）。

---

## ⚖️ 免责声明

- 本工具**仅供学习与测试**，使用精简版 Windows **需自备合法授权**；修改版可能违反微软条款，后果自负。
- 精简越狠，功能越可能缺失（Core/Nano 尤其）。当前本分支首版仅开放 **Standard（标准）** 档位。
- 参考上游：Language: MIT · 上游仓库：[kelexine/tiny11-automated](https://github.com/kelexine/tiny11-automated)