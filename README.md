# codex-profile

A small Bash utility for managing multiple Codex profiles under `~/.codex`.

一个用于在 `~/.codex` 下管理多个 Codex 账号配置（profile）的 Bash 小工具。

## English

### Features

- Create an isolated profile directory under `~/.codex/profiles/<name>`.
- Save `config.toml` and `auth.json` for each profile.
- Switch the active Codex account by replacing `~/.codex/config.toml` and `~/.codex/auth.json` with symlinks.
- Keep `~/.codex/current` as a pointer to the active profile.
- Show usage information for 5-hour, weekly, and monthly windows when the data is available.

### Usage

```bash
./codex-profile.sh new <name>       # create a profile
./codex-profile.sh use <name>       # switch profile via symlinks
./codex-profile.sh save <name>      # save current ~/.codex auth/config into a profile
./codex-profile.sh list             # list profiles
./codex-profile.sh delete <name>    # delete a profile
./codex-profile.sh current          # show current profile symlink
./codex-profile.sh usage [name]     # show Codex 5h / weekly / monthly usage when available
```

### Create and switch profiles

Create a profile interactively:

```bash
./codex-profile.sh new work
```

The script asks for:

- API base URL, normalized to end with `/v1`.
- API key, written to the profile `auth.json`.
- Model name, written to the profile `config.toml`.

Switch to a profile:

```bash
./codex-profile.sh use work
```

This updates:

- `~/.codex/auth.json` -> `~/.codex/profiles/work/auth.json`
- `~/.codex/config.toml` -> `~/.codex/profiles/work/config.toml`
- `~/.codex/current` -> `~/.codex/profiles/work`

### Usage limits command

`usage` first tries ChatGPT's private Codex usage endpoint:

```text
https://chatgpt.com/backend-api/codex/usage
```

Because this is a private ChatGPT endpoint, API-key-only profiles usually cannot call it directly. If a profile `auth.json` contains a ChatGPT access token or session cookie, the script uses it. You can also provide a token explicitly:

```bash
CODEX_USAGE_BEARER='<chatgpt-access-token>' ./codex-profile.sh usage
```

If the endpoint is unavailable, the script falls back to the latest local Codex session JSONL snapshot in `~/.codex/sessions`, where recent Codex clients persist `rate_limits` data. The 5-hour and weekly windows are commonly reported as `primary` and `secondary`. Monthly usage is printed only when the endpoint or local snapshot actually reports a monthly/named limit.

### Environment variables

| Variable | Description |
| --- | --- |
| `CODEX_HOME` | Override the Codex home directory. Defaults to `~/.codex`. |
| `CODEX_USAGE_ENDPOINT` | Override the usage endpoint. Defaults to `https://chatgpt.com/backend-api/codex/usage`. |
| `CODEX_USAGE_BEARER` | Provide a ChatGPT bearer token for the usage endpoint. |

## 中文说明

### 功能

- 在 `~/.codex/profiles/<name>` 下为每个账号创建独立 profile。
- 每个 profile 单独保存 `config.toml` 和 `auth.json`。
- 通过软链接切换当前生效的 `~/.codex/config.toml` 和 `~/.codex/auth.json`。
- 使用 `~/.codex/current` 记录当前正在使用的 profile。
- 在数据可用时查看 Codex 的 5 小时、1 周、1 个月 usage/额度信息。

### 命令用法

```bash
./codex-profile.sh new <name>       # 创建新账号 profile
./codex-profile.sh use <name>       # 通过软链接切换账号
./codex-profile.sh save <name>      # 把当前 ~/.codex 的 auth/config 保存成 profile
./codex-profile.sh list             # 列出所有 profile
./codex-profile.sh delete <name>    # 删除 profile
./codex-profile.sh current          # 查看当前 profile 指向
./codex-profile.sh usage [name]     # 查看 Codex 5小时 / 1周 / 1个月 usage（如果可用）
```

### 创建和切换账号

交互式创建一个 profile：

```bash
./codex-profile.sh new work
```

脚本会提示你输入：

- API 基础地址：脚本会自动补齐协议并规范化为以 `/v1` 结尾。
- API Key：写入该 profile 的 `auth.json`。
- 模型名称：写入该 profile 的 `config.toml`。

切换到某个 profile：

```bash
./codex-profile.sh use work
```

切换后会更新：

- `~/.codex/auth.json` -> `~/.codex/profiles/work/auth.json`
- `~/.codex/config.toml` -> `~/.codex/profiles/work/config.toml`
- `~/.codex/current` -> `~/.codex/profiles/work`

### 查看 usage / 额度

`usage` 命令会先尝试调用 ChatGPT 的 Codex usage 私有接口：

```text
https://chatgpt.com/backend-api/codex/usage
```

注意：这是 ChatGPT 的私有接口，只有普通 API Key 的 profile 通常无法直接访问。如果 profile 的 `auth.json` 中包含 ChatGPT access token 或 session cookie，脚本会尝试使用它。你也可以通过环境变量显式传入 token：

```bash
CODEX_USAGE_BEARER='<chatgpt-access-token>' ./codex-profile.sh usage
```

如果接口不可用，脚本会回退到本地最新的 Codex session JSONL 记录（`~/.codex/sessions`）。较新的 Codex 客户端会在 session 中保存 `rate_limits` 数据。通常 5 小时窗口对应 `primary`，1 周窗口对应 `secondary`。1 个月 usage 只有在接口或本地快照实际返回 monthly/named limit 时才会显示。

### 环境变量

| 变量 | 说明 |
| --- | --- |
| `CODEX_HOME` | 覆盖 Codex 主目录，默认是 `~/.codex`。 |
| `CODEX_USAGE_ENDPOINT` | 覆盖 usage 接口，默认是 `https://chatgpt.com/backend-api/codex/usage`。 |
| `CODEX_USAGE_BEARER` | 为 usage 接口提供 ChatGPT bearer token。 |
