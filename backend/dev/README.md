# backend/dev — 开发调试脚本（非业务代码）

## 独立运行（打包）

App 现在可以完全独立运行，不再需要手动开调试 Chrome、也不需要在终端起 uvicorn。

### 启动链路

```
frontend.exe（Flutter）
  └─ 自己启动 hanime_backend.exe        （BackendLauncher）
       └─ 自己启动调试 Chrome            （browser.py）
            └─ Chrome 打开 hanime1.me
```

客户端启动时先显示启动页，轮询 `/api/status`，
等「后端 + 调试浏览器」都就绪才进主界面，避免一进去就满屏网络错误。

### 打包命令

```powershell
# 项目根目录
powershell -ExecutionPolicy Bypass -File frontend\scripts\package_windows.ps1
```

做三件事：PyInstaller 打后端 → Flutter 打 release → 把 exe 放到 Flutter 产物旁。
产物在 `frontend/build/windows/x64/runner/Release/`，约 45 MB，可整个拷走运行
（目标机需要有 Chrome）。

只打后端：

```powershell
.venv\Scripts\python.exe backend\build_backend.py
```

### 浏览器是怎么处理的

`browser.py` 用**独立的 user-data-dir** 启动 Chrome：

```
%LOCALAPPDATA%\HanimeViewer\chrome-profile
```

为什么不共用用户日常的 Chrome 配置：共用时如果 Chrome 已经在跑，
新进程会被合并进已有实例，**调试端口根本不会开** —— 这是最常见的失败原因。
独立配置目录同时也让登录 cookie 能持久保存，下次启动不用重新登录。

#### 窗口是隐藏的（重要）

用户要求「从头到尾只看到 frontend.exe」，所以浏览器窗口会被隐藏：

1. `--window-position=-32000,-32000` 把窗口移出屏幕
2. 再用 Win32 `ShowWindow(SW_HIDE)` 把顶层窗口真正藏起来（不进任务栏、不抢焦点）

只做第 1 步是不够的 —— 那样任务栏里还是会多一个图标。

**为什么不用无头模式（`--headless`）**：
实测 headless Chrome 打开 hanime1.me 会被 Cloudflare 拦成
`Attention Required!`，DOM 里一个视频都没有。
本项目的核心原理就是「用真实的、能过 Cloudflare 的浏览器」，
换成无头等于把这个原理也去掉。所以保留真实浏览器内核，只是让它不可见。

配套的收尾：App 退出时先请求后端 `/api/shutdown`，
由后端调用 `stop_browser()` 把这个**隐藏的**浏览器收掉
（用户看不到它，也就没法自己关，留着会白占内存）。
`stop_browser()` 只关命令行里带我们专用 profile 的 Chrome，不动用户日常的浏览器。

用不到的端口可以覆盖：

```powershell
$env:HANIME_CDP_PORT = "9333"
$env:HANIME_BROWSER  = "D:\Chrome\chrome.exe"   # 指定浏览器
```

### 打包时踩过的三个坑

1. **Windows 控制台默认 GBK，print 中文/日文标题会崩。**
   标题里出现「・」(U+30FB) 这类 GBK 编不了的字符时，
   `print` 直接抛 UnicodeEncodeError，接口变成 500。
   实测 16 次请求挂了 14 次。
   → `run_backend.py` 的 `force_utf8_output()` 在启动最前面把
   stdout/stderr reconfigure 成 UTF-8，必须在任何 print 之前调用。

2. **Chrome 111+ 拒绝带 Origin 头的 CDP WebSocket 连接**，
   返回 `403 Rejected an incoming WebSocket connection`。
   websocket-client 默认会带 Origin。
   → `_get_socket()` 里必须传 `suppress_origin=True`。

3. **PyInstaller 看不到字符串导入的模块。**
   uvicorn 的 `main:app`、以及我们自己的 `cdp` / `parser` 包，
   都要用 `--hidden-import` / `--collect-submodules` 明确列出，
   否则打出来的 exe 一跑就 ModuleNotFoundError。

### 端口

| 用途 | 默认 | 覆盖方式 |
| --- | --- | --- |
| 后端 | 8000 | `--port`（exe）或 `HANIME_BACKEND_PORT`（前端） |
| 调试浏览器 CDP | 9222 | `--cdp-port` 或 `HANIME_CDP_PORT` |

前端里不再写死地址，统一走 `lib/controllers/app_config.dart`。

---

这个目录里的东西**不是** API 的一部分，只是开发时手动跑的小工具。
删掉它们不影响 HanimeViewer 后端运行。

## 里面的文件

这些都是**可复用的验证工具**，用来一键复现「CDP → 网页 → Parser」这条链路，
改动后端后跑一下就能确认没破坏东西。

| 文件 | 用途 |
| --- | --- |
| `test_cdp.py` | 最小 CDP 验证：打印当前标签页的标题和网址 |
| `test_login.py` | 查看当前标签页的登录状态相关信息 |
| `test_parser.py` | 对当前页面跑一遍 Parser |
| `test_search.py` | 打开搜索页并解析结果 |
| `test_watch.py` | 打开某个视频详情页并解析 |
| `test_playlists.py` | 解析用户的播放清单 |
| `check_quality.py` | 检查清晰度列表 |
| `check_tags.py` | 检查标签分组和 `broad` 广泛匹配 |

## 已删除的早期文件

下面这些文件原本也在这里，已确认**没有任何代码或文档引用**，属于早期开发的临时产物，
于 2026-09-26 删除：

| 文件 | 原用途 | 删除原因 |
| --- | --- | --- |
| `video_detail_test.html` | 详情页 HTML 快照（217 KB） | 离线调 Parser 用；Parser 已改从实时页面验证，且快照对应的是旧版网站结构 |
| `playlists_test.html` | 播放清单页快照（132 KB） | 同上 |
| `playlist_test.html` | 播放清单页快照（38 KB） | 同上 |
| `check_category.py` | 一次性摸清分类页结构 | 结构已摸清并写进 Parser，探查脚本不再需要 |
| `check_filters.py` | 一次性摸清筛选参数 | 同上 |
| `check_filters2.py` | 同上（第二版） | 同上 |
| `check_genre.py` | 一次性摸清 genre 页面 | 同上 |
| `check_sections.py` | 一次性摸清首页栏目结构 | 同上 |

以及项目根目录的 `cdp_test.py`：最早的 CDP 原型脚本（直接 requests + websocket 调 CDP），
功能已被 `backend/cdp/chrome.py` 和 `backend/dev/test_cdp.py` 完全覆盖。

这些文件都在 git 历史里，需要时可以用 `git show <commit>:<path>` 取回。

## 登录功能（backend/auth.py）

登录不是客户端做的，而是**在用户自己的调试 Chrome 里**完成：
后端打开 `https://hanime1.me/login`，填入邮箱密码并点击「登入」，
session cookie 由浏览器自己保存，之后所有抓取请求自动带上登录态。

这样做的好处：

- CSRF token（`_token`）由页面自己提供，不用猜
- 客户端不保存 cookie，也不在本地保存密码
- 点赞、储存、个人主页这些**依赖登录态**的页面能直接抓到

### 踩过的坑（改这块前务必看）

1. **不能用 `form.submit()`。**
   登录表单里有一个 `<button name="submit" type="submit">登入</button>`，
   这个命名元素会把 `form.submit` 方法**遮蔽**掉，
   调用时会得到 `TypeError: form.submit is not a function`。
   更坑的是 CDP 的 `Runtime.evaluate` 遇到 JS 异常时**不返回 value**，
   所以后端只会看到 `None`，报出来的错是「登录表单结构异常（None）」，
   完全看不出真正原因。
   → 现在改成 `submitBtn.click()`，也更接近用户真实操作。

2. **登录失败页面的错误文字是 `auth.failed`**（Laravel 的提示 key）。
   用它来判断「密码错了」可以立刻返回，
   否则要干等 30 秒超时（实测从 32 秒降到约 1.9 秒）。

3. **不要信 `data-target="#signUpModal"` 这个判断单独成立。**
   未登录时点赞/储存按钮带这个属性、点击只弹注册窗；
   登录后服务端会渲染出不带它的版本。`video_action()` 会先检查这一点，
   发现仍是 `needs-login` 就返回「登录状态已失效」，而不是假装成功。

### 个人中心（用户主页）的结构

个人中心首页（`/user/{id}`）是**服务端渲染**的一张长页面，结构是：

```
<div class="tab-content-container">
  <div class="tab-index-rows-wrapper">        <- 一个 tab 一个
    <a class="horizontal-row-title" href=".../histories"><h3>觀看紀錄<div>查看更多</div></h3></a>
    <div>                                      <- 和标题是**兄弟**节点
      <div class="home-rows-videos-wrapper">
        <a class="video-link" href="...">      <- 每段 10 个左右
```

几个必须注意的点（都踩过）：

1. **标题和卡片是兄弟节点**，要用 `find_next_sibling`；
   用 `find_parent` 会一路上溯到包含全部 4 个栏目的大容器，
   结果每个栏目都报「40 个卡片」。
2. **标题文字里混着「查看更多」**，要先把这个 `div` 删掉再取文字
   （用复制出来的节点处理，别改原 soup）。
3. **「播放清單」栏目里的卡片不是影片**：它的 `href` 是
   `/playlist?list=xxx`，数量写在 `.stats-container` 里，
   要单独归到 `playlists`。

### tab 页和它的分页

`/user/{id}/histories`、`/likes`、`/saves`、`/playlists` 这些页面：

- 真正的内容在一个
  `<div class="specific-tab-view home-rows-videos-wrapper">` 里
- **每页 60 条**，分页链接是 `?page=N`
- 必须用 `get_tab_videos()` / `get_tab_playlists()` 限定在这个容器里解析。
  直接全页抓会出问题：这些页面**同时携带个人中心首页那 4 个栏目段的预览卡片**，
  实测 `histories` 页面上共 60 个 `a.video-link`，全页抓得到的数字看着"对"
  但其实是混在一起的。

实测页数（`get_total_pages()`）：histories 30 页、likes 21 页、
playlists 8 页、saves 1 页。所以客户端必须有翻页，
否则只能看到历史记录的第一页。

### 登录相关的接口

| 接口 | 说明 |
| --- | --- |
| `GET /api/account` | 当前登录状态（带 15 秒缓存，`?force=true` 强制刷新） |
| `POST /api/login` | body `{"email","password"}`，在浏览器里提交登录 |
| `POST /api/logout` | 让浏览器登出 |
| `GET /api/user/{id}` | 用户主页，`?tab=histories/saves/likes/playlists/uploaded&page=N` |
| `GET /api/user/{id}/home` | 个人中心首页的栏目段（每段最多 10 个） |
| `POST /api/video/{id}/action` | body `{"action":"like"/"unlike"/"save"}`，在浏览器里真实点击 |

点赞/储存成功后记得清 `detail_cache` 和 `user_cache`，
否则前端还会读到旧的点赞数。

### 用户主页的两个细节

- 页面标题的分隔符是 `\xa0-`（不换行空格）而不是普通的 `" - "`，
  直接 split 会得到一长串带后缀的名字。
- 页面上有多张头像图（导航 logo、默认头像），
  真正的用户头像要认 `src` 里含 `/image/avatar/` 且不含 `user_default_image` 的那张。

### 账号数据隔离（重要）

观看历史、搜索记录、播放进度、播放清单都必须**跟着账号走**。
早期版本用的是全局 key，导致「登录账号2，看到的还是账号1的数据」。

#### 前端：本地数据按账号加前缀

规则见 `lib/controllers/account_scope.dart`：

| 数据 | key |
| --- | --- |
| 观看历史 | `u_{userId}_watch_history` |
| 搜索记录 | `u_{userId}_search_history` |
| 播放进度 | `u_{userId}_video_position_{videoId}` |
| 未登录 | `guest_...` |

三个配套点，缺一个都会漏：

1. **换账号要丢掉已缓存的页面**。
   `MainShell._pages` 会把页面缓存在 IndexedStack 里，
   不丢的话切回观看历史还是旧账号的内容。
   见 `_resetPagesIfAccountChanged()`（同时会清 `AppCache`）。
2. **整个壳要跟着登录状态重建**。
   `MainShell.build()` 外面套了 `ValueListenableBuilder<AccountInfo>`。
3. **主题（明暗模式）故意不跟账号走** —— 那是这台设备的使用习惯。

#### 后端：播放清单不能写死账号

`/api/playlists` 以前写死 `https://hanime1.me/user/715321/playlists`
（早期测试账号）。现在改成用 `auth.get_account()` 拿当前登录账号，
未登录直接返回 401。

#### 登录检测必须多线索（踩过的坑）

只靠导航栏的 `#user-modal-trigger` 不可靠：实测在
`/user/{id}/playlists` 这类页面上它的 **href 是空的**，
于是明明登录着却被判成未登录，播放清单接口就 401。

现在 `_ACCOUNT_PROBE` 一次采集多个线索：

1. 页面上有「登出」入口（`.user-modal-link` 里含「登出」）—— 最强信号
2. `#user-modal-trigger` 的 href 指向 `/user/{id}`
3. 当前 URL 本身就是 `/user/{id}/...`
4. 页面里同时出现 `/user/{id}/saves` 和 `/user/{id}/edit`

**不要**用头像容器的 `innerText` 当用户名：那里是图标文字，
实测会拿到 `arrow_drop_down`、`cast` 这种垃圾值。
用户名改为顺着 id 去个人主页标题里取（`_lookup_username`，有缓存）。

#### 验证结果

| 账号 | 个人中心栏目 | 播放清单 |
| --- | --- | --- |
| 715321（账号1） | 4 个 | 60 个 |
| 2150661（账号2） | 1 个（觀看紀錄） | 0 个（该账号确实没有） |

两个账号看到的数字不同 —— 这就是隔离生效的直接证据。

### 关于「内置浏览器」的结论（不要再试无头模式）

用户希望不要外挂 Chrome、改成客户端内置浏览器隐藏运行。**做不到**，实测结论：

| 方案 | 结果 |
| --- | --- |
| 直接 HTTP 请求 | 200 但只有约 20KB 空壳，无 `.video-link` |
| `--headless=new` | `Attention Required! \| Cloudflare`，`a.video-link` = 0，页面 4KB |
| `--headless=new` + 真实 UA | 同上（UA 不解决问题） |
| **有头 + 窗口隐藏** | ✅ 正常拿到数据 |

原因：本项目的核心原理就是「用真实的、能过 Cloudflare 的浏览器」，
去掉有头模式等于把这个原理也去掉。

所以现在的方案是**保留真实浏览器内核，但让它完全不可见**：
`--window-position=-32000,-32000` + Win32 `ShowWindow(SW_HIDE)`。

### 侧边栏「观看记录」与个人主页一致

两者现在走**同一个接口**：

```
/api/user/{id}?tab=histories&page=N
```

- 登录时：读官网的觀看紀錄（和「个人主页 → 观看记录」是同一份数据），每页 60 条要翻页
- 未登录时：退回本地记录（`guest_watch_history`），此时才显示「清空历史」按钮
- 官网记录带的是 `duration`/`views`，本地记录带的是 `brand`/`last_watched`，
  卡片里两种字段都要兼容

### 播放清单页码

`playlist_page.dart` 以前写死 `_totalPages = 8`，还有一句
「不足 8 也按 8 算」的下限 —— 结果只有 1 页的账号也显示 8 页，
点第 2 页直接空白。

现在完全用服务端返回的 `total_pages`，并且
**只有 `_totalPages > 1` 且有数据时才显示分页条**。

实测：账号 715321 是 60 个 / 8 页（显示分页），
账号 2150661 是 0 个 / 1 页（不显示）。

### 新番预告

侧边栏新增，对应官网 `search?genre=新番預告`。

⚠️ **genre 必须用繁体「新番預告」**，简体「新番预告」返回 0 条
（实测）。值定义在 `new_release_page.dart` 的 `NewReleasePage.genre`。

### 登出必须是 POST（踩过的坑）

官网的登出是一个 **POST 表单**：

```html
<form action="https://hanime1.me/logout" method="POST">
  <input type="hidden" name="_token" value="...">
</form>
```

早期版本用 `GET /logout`，**根本不会登出**。这个 bug 的后果很隐蔽：

```
GET /logout 没登出
  -> 浏览器仍是登录态
  -> 再点「登录」时打开 /login
  -> 服务端发现已登录，直接重定向走（实测落到 404 的 /home）
  -> 等不到登录表单 -> navigate_and_wait 超时
  -> 界面报「打不开登录页，请确认调试 Chrome 正在运行」
```

报错信息和真正的原因（没登出）看起来毫无关系，很容易往「浏览器挂了」方向排查。
正确做法见 `auth.logout()`：找到登出表单、原样 POST 提交它的字段。

另外两点：

1. **登出后要重新加载页面再判断状态**。官网导航是 SPA，
   登出后旧 DOM 里还留着用户菜单，不刷新会把 `_read_account` 骗过去。
2. **`login()` 会先检查并主动登出**。这样即使登出没生效，
   重新登录也不会卡在「打不开登录页」上，而是自己先清理干净。

实测：修复前 `/login` 导航 30 秒超时（落到 404），
修复后 **0.98 秒**就拿到登录表单。

## 缓存与加载速度（重要）

后端现在有两层提速，改这两块之前请先读一下。

### 1. 等待页面就绪：不再用固定 `time.sleep(5)`

旧写法每个接口都是「导航 → 睡 5 秒 → 取 HTML」。实测发现：

| 页面 | 内容真正就绪 | `readyState` 变成 complete |
| --- | --- | --- |
| 首页 | 约 1.2 秒 | 约 5.2 秒 |
| 搜索页 | 约 1.4 秒 | 约 3.2 秒 |
| 详情页 | 约 1.2 秒 | 约 3.9 秒 |

也就是说固定 5 秒**既慢又不可靠**：首页要 5.2 秒才 complete，
固定睡 5 秒有时候会取到半成品。

现在改成轮询「目标元素是否出现且稳定」，目标元素是：

- 列表页（首页/搜索/筛选/播放清单）：`a.video-link`
- 详情页：`#video-artist-name`

已实测确认：提前读取的 DOM 解析结果和等 complete 之后**完全一致**
（首页 12 个栏目 × 12 个视频；详情页 playlist/sources/brand/tags 全部相同），
差异只在广告和统计请求。

如果哪天网站改版导致解析不出来，优先检查上面两个选择器是否还有效。

### 2. 内存 TTL 缓存（`backend/cache.py`）

按 URL 缓存**解析前的 HTML**，避免同一个页面反复重新加载。

| 缓存 | TTL | 用途 |
| --- | --- | --- |
| `home_cache` | 600 秒 | 首页栏目 |
| `search_cache` | 300 秒 | 搜索/筛选 |
| `detail_cache` | 180 秒 | 视频详情 |
| `tags_cache` | 1800 秒 | 标签分组 |
| `playlist_cache` | 300 秒 | 播放清单 |

详情页 TTL 故意较短：里面的视频直链带 `secure` 签名和过期时间，
缓存太久用户点播放会拿到失效地址。

调试接口：

- `GET /api/cache_stats` —— 看命中次数
- `GET /api/cache_clear` —— 手动清空

### 3. 并发安全

所有请求共用同一个 Chrome 标签页，所以 `main.py` 的
`fetch_html()` 全程持有 `_NAVIGATE_LOCK`。
如果去掉这把锁，两个并发请求会互相把页面导航走，
导致 A 请求解析到 B 请求的页面内容。

### 实测效果（2026-09-26）

| 接口 | 优化前 | 冷启动 | 命中缓存 |
| --- | --- | --- | --- |
| `/api/home_sections` | 5.2s | 1.4~2.0s | 0.15s |
| `/api/filter` | 5.2s | 1.4~1.5s | 0.12s |
| `/api/tags` | 5.1s | 1.2s | 0.06s |
| `/api/video/{id}` | 5.2s | 1.3s | 0.05s |

前端另有一层 `lib/controllers/app_cache.dart`（搜索结果 + 首页），
并且 `MainShell` 用 `IndexedStack` 保留已打开页面的 State，
所以来回切换栏目不会重新请求。

## 怎么运行

脚本里已经加好了路径引导，**从任何目录运行都可以**：

```powershell
E:\Hanime\HanimeViewer\.venv\Scripts\python.exe E:\Hanime\HanimeViewer\backend\dev\test_cdp.py
```

如果在 `backend` 目录下，也可以直接：

```powershell
cd E:\Hanime\HanimeViewer\backend
..\.venv\Scripts\python.exe dev\test_cdp.py
```

## 运行前提

1. 调试用 Chrome 已经带远程调试端口启动，`http://127.0.0.1:9222/json` 能打开。
2. 那个 Chrome 里已经打开了目标页面（脚本读的是**当前标签页**）。
   注意：像 `test_watch.py` / `test_search.py` 这类脚本会自己导航到目标网址，
   会把你的调试 Chrome 当前标签页**跳走**，跑完记得切回来。
3. 如果脚本输出中文变成乱码，是 Windows 控制台编码问题，不是脚本问题：
   在命令前加 `$env:PYTHONIOENCODING="utf-8"`。
