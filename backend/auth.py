"""账号 / 登录相关。

设计说明
--------
Hanime1 是服务端渲染的站点：登录状态保存在浏览器 cookie 里，
点赞、储存、个人主页这些内容都依赖这个 cookie。

本项目的数据本来就是通过「用户自己的真实 Chrome」抓的，
所以登录也走同一条路：在**那个 Chrome 里**提交登录表单。
好处是：

- CSRF token（_token）由页面自己提供，不用我们去猜
- session cookie 由浏览器自己保存，后续所有请求自动带上
- 不需要在客户端保存密码或 cookie

密码只在提交表单的那一瞬间存在于内存里，不会写进任何文件。
"""

import json
import threading
import time

from cdp.chrome import ChromeCDP


LOGIN_URL = "https://hanime1.me/login"

# 登录状态缓存（避免每次请求都去问浏览器）
_state_lock = threading.Lock()
_state = {
    "checked_at": 0.0,
    "logged_in": False,
    "user_id": "",
    "username": "",
    "avatar": "",
}

# 登录状态缓存多久（秒）。短一点，保证用户在浏览器里手动登录/登出后能及时反映
STATE_TTL = 15


# 用一个 JS 片段一次性采集所有登录线索，避免多次往返。
#
# 为什么要多线索：只靠导航栏的 #user-modal-trigger 不可靠 ——
# 实测在 /user/{id}/playlists 这类页面上它的 href 是**空的**，
# 于是明明登录着却被判定成未登录，播放清单接口就 401 了。
#
# 可靠的线索（都实测过）：
#   1. 页面上有「登出」入口（h5.user-modal-link）—— 只有登录后才渲染，
#      这是最强信号
#   2. #user-modal-trigger 的 href 指向 /user/{id}
#   3. 当前 URL 本身就是 /user/{id}/...
#   4. 页面里同时出现 /user/{id}/saves 和 /user/{id}/edit
#
# 注意不要用「头像容器的 innerText」当用户名：
# 那个位置是图标文字（实测会拿到 arrow_drop_down / cast 这种垃圾值）。
_ACCOUNT_PROBE = """
(() => {
    const out = {
        trigger: '',
        url: location.href,
        candidates: [],
        hasLogout: false,
        avatar: '',
    };

    const t = document.querySelector('#user-modal-trigger');
    if (t) {
        out.trigger = t.getAttribute('href') || '';
        const img = t.querySelector('img');
        if (img) out.avatar = img.getAttribute('src') || '';
    }

    // 「登出」入口：只有登录后才存在
    document.querySelectorAll('.user-modal-link').forEach(e => {
        const txt = (e.innerText || '').trim();
        if (txt.indexOf('登出') !== -1 || txt.indexOf('退出') !== -1) {
            out.hasLogout = true;
        }
    });

    const ids = {};
    document.querySelectorAll('a[href*="/user/"]').forEach(a => {
        const m = (a.getAttribute('href') || '')
            .match(/\\/user\\/(\\d+)(\\/[a-z]+)?/);
        if (!m) return;
        const id = m[1];
        const sub = m[2] || '';
        ids[id] = ids[id] || new Set();
        if (sub) ids[id].add(sub.replace('/', ''));
    });

    for (const id of Object.keys(ids)) {
        out.candidates.push({id: id, subs: [...ids[id]]});
    }

    return JSON.stringify(out);
})()
"""


def _read_account(chrome):
    """从当前页面读出登录状态。

    返回 dict，字段与 _state 一致。
    """
    result = {
        "logged_in": False,
        "user_id": "",
        "username": "",
        "avatar": "",
        "url": "",
    }

    try:
        raw = chrome.evaluate(_ACCOUNT_PROBE).get("value") or "{}"
        probe = json.loads(raw)
    except Exception:
        return result

    trigger = (probe.get("trigger") or "").strip()
    current_url = (probe.get("url") or "").strip()
    has_logout = probe.get("hasLogout") is True

    user_id = ""

    # 线索 1：导航栏头像链接
    if trigger and "/login" not in trigger and "/user/" in trigger:
        user_id = trigger.rstrip("/").rsplit("/", 1)[-1]

    # 线索 2：当前就在某个用户页面上
    if not user_id and "/user/" in current_url:
        tail = current_url.split("/user/", 1)[1]
        first = tail.split("/", 1)[0].split("?", 1)[0]

        if first.isdigit():
            user_id = first

    # 线索 3：页面里有没有只有登录后才渲染的入口
    if not user_id or not has_logout:
        for candidate in probe.get("candidates") or []:
            subs = set(candidate.get("subs") or [])

            # 「稍后观看」+「账户资料」同时出现 => 已登录
            if "saves" in subs and "edit" in subs:
                if not user_id:
                    user_id = str(candidate.get("id") or "")

                has_logout = True
                break

    # 没有任何登录迹象
    if not user_id or not has_logout:
        return result

    result["logged_in"] = True
    result["user_id"] = user_id
    result["url"] = f"https://hanime1.me/user/{user_id}"
    result["avatar"] = (probe.get("avatar") or "").strip()

    # 用户名页面上不一定有（导航栏只有图标），拿不到就留空，
    # 打开个人主页时会被真实名字覆盖。
    return result


def get_account(force=False):
    """取得当前登录状态（带短缓存）。"""
    with _state_lock:
        fresh = (
            time.monotonic() - _state["checked_at"] < STATE_TTL
        )

        if fresh and not force:
            return dict(_state)

    chrome = ChromeCDP()

    account = _read_account(chrome)

    # 用户名在导航栏里拿不到（那里只有图标），
    # 而侧边栏要显示名字，所以顺着 id 去个人主页取一次标题。
    # 有缓存，不会每次请求都抓页面。
    if account["logged_in"] and not account["username"]:
        account["username"] = _lookup_username(
            account["user_id"]
        )

    if not account["logged_in"]:
        _username_cache.clear()

    with _state_lock:
        _state.update(account)
        _state["checked_at"] = time.monotonic()

        return dict(_state)


# 用户名缓存：user_id -> 名字（页面标题里带，基本不变）
_username_cache = {}


def _lookup_username(user_id):
    """从个人主页标题里取用户名（失败返回空字符串，不影响主流程）。"""
    if not user_id:
        return ""

    cached = _username_cache.get(user_id)

    if cached is not None:
        return cached

    name = ""

    try:
        chrome = ChromeCDP()

        ready, html = chrome.navigate_and_wait(
            f"https://hanime1.me/user/{user_id}",
            ready_selector="a.video-link",
            timeout=20.0,
            min_stable=0.5,
        )

        if ready and html:
            from parser.hanime_parser import HanimeParser

            title = HanimeParser(html).get_title() or ""
            normalized = title.replace("\xa0", " ")
            candidate = (
                normalized.split(" - ", 1)[0]
                if " - " in normalized
                else normalized
            )

            for suffix in ("的首頁", "的影片", "的播放清單", "的首页"):
                if candidate.endswith(suffix):
                    candidate = candidate[: -len(suffix)]
                    break

            name = candidate.strip()
    except Exception:
        name = ""

    _username_cache[user_id] = name

    return name


def login(email, password, timeout=30.0):
    """在真实 Chrome 里提交登录表单。

    返回 (成功与否, 账号信息, 错误信息)。
    """
    if not email or not password:
        return False, {}, "邮箱和密码不能为空"

    chrome = ChromeCDP()

    # 0. 如果浏览器当前是登录状态，先登出。
    #
    #    否则打开 /login 时服务端会发现「已经登录」而直接重定向走，
    #    我们等不到登录表单，就会误报「打不开登录页」。
    #    （这正是「退出登录后再登录」失败的根因，实测复现过。）
    try:
        current = _read_account(chrome)

        if current["logged_in"]:
            logout()
            time.sleep(1.0)
    except Exception:
        pass

    # 1. 打开登录页，拿到带 CSRF token 的表单
    ready, html = chrome.navigate_and_wait(
        LOGIN_URL,
        ready_selector="input[name='_token']",
        timeout=timeout,
        min_stable=0.3,
    )

    if not ready:
        # 超时了：说清楚当前落在哪个页面，便于排查
        try:
            landed_url = chrome.get_url() or "(未知)"
            landed_title = chrome.get_title() or ""
        except Exception:
            landed_url = "(读取失败)"
            landed_title = ""

        # 再看一眼是不是其实已经登录了（说明登出没生效）
        try:
            after = _read_account(chrome)

            if after["logged_in"]:
                return (
                    False,
                    {},
                    "浏览器当前仍是登录状态，登录页被重定向了。"
                    "请先退出登录再试。",
                )
        except Exception:
            pass

        return (
            False,
            {},
            f"打不开登录页（停留页面：{landed_url} {landed_title}）",
        )

    token = chrome.evaluate(
        "(()=>{const e=document.querySelector(\"input[name='_token']\");"
        "return e?e.value:'';})()"
    ).get("value") or ""

    if not token:
        return False, {}, "没有拿到登录页的 CSRF token"

    # 2. 填表并提交。
    #
    #    注意：不能用 form.submit()。
    #    登录表单里有一个 <button name="submit" type="submit">，
    #    这个命名元素会把 form.submit 方法遮蔽掉，
    #    导致 "form.submit is not a function"。
    #    所以这里改成点击真正的提交按钮 —— 这也更接近用户的真实操作。
    #
    #    密码通过 JSON 转义注入，避免引号/反斜杠破坏脚本。
    expression = """
    (() => {
        const form = document.querySelector("input[name='_token']").form
            || document.querySelector('form');
        if (!form) return 'no-form';

        const emailInput = form.querySelector("input[type='email'], input[name='email']");
        const passInput = form.querySelector("input[type='password'], input[name='password']");
        if (!emailInput || !passInput) return 'no-input';

        const tokenInput = form.querySelector("input[name='_token']");
        if (tokenInput) tokenInput.value = %s;

        emailInput.value = %s;
        passInput.value = %s;

        // 有些前端框架只认 input 事件，手动派发一下
        for (const el of [emailInput, passInput]) {
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
        }

        // 优先点提交按钮；实在找不到再用 requestSubmit 兜底
        const submitBtn = form.querySelector(
            "button[type='submit'], button[name='submit'], input[type='submit']"
        );

        if (submitBtn) {
            submitBtn.click();
            return 'submitted';
        }

        if (typeof form.requestSubmit === 'function') {
            form.requestSubmit();
            return 'submitted';
        }

        return 'no-submit';
    })()
    """ % (
        json.dumps(token),
        json.dumps(email),
        json.dumps(password),
    )

    try:
        submitted = chrome.evaluate(expression).get("value")
    except Exception as exc:
        return False, {}, f"提交登录表单失败：{exc}"

    if submitted != "submitted":
        return False, {}, f"登录表单结构异常（{submitted}）"

    # 3. 等页面响应。
    #
    #    登录失败时站点会重新渲染登录页，并在页面上显示错误文字
    #    （实测是 Laravel 的 "auth.failed"）。
    #    所以一旦确认「还在 /login」且错误提示已经出现，就立刻返回失败，
    #    不用把 30 秒等满。
    deadline = time.monotonic() + timeout

    while time.monotonic() < deadline:
        time.sleep(0.5)

        try:
            current = chrome.get_url() or ""
        except Exception:
            continue

        if current.rstrip("/").endswith("/login"):
            # 还在登录页：检查是否已经渲染出失败提示
            try:
                has_error = chrome.evaluate(
                    "(document.body ? document.body.innerText : '')"
                    ".indexOf('auth.failed') !== -1"
                ).get("value")
            except Exception:
                has_error = False

            if has_error:
                return False, {}, "登录失败：邮箱或密码不正确"

            continue

        account = _read_account(chrome)

        if account["logged_in"]:
            with _state_lock:
                _state.update(account)
                _state["checked_at"] = time.monotonic()

            return True, account, ""

    # 超时：再确认一次，区分「失败」和「太慢」
    time.sleep(1.0)

    account = _read_account(chrome)

    if account["logged_in"]:
        with _state_lock:
            _state.update(account)
            _state["checked_at"] = time.monotonic()

        return True, account, ""

    return False, {}, "登录失败：邮箱或密码不正确"


def logout():
    """让浏览器真正登出，并清掉本地状态缓存。

    为什么不能用 GET /logout：
    官网的登出是一个 **POST 表单**（`<form action=.../logout method=POST>`
    带 CSRF `_token`）。直接 GET 那个地址不会登出，浏览器仍然保持登录态。

    后果很隐蔽：登出没生效 -> 再点「登录」-> 打开 /login 时服务端发现
    你已经登录，会重定向走（实测落到一个 404 的 /home），
    于是 navigate_and_wait 等不到登录表单而超时，
    界面报「打不开登录页」—— 实测复现过这个现象。

    正确做法：在首页上找到那个登出表单，补上 token 之后 POST 提交。
    """
    chrome = ChromeCDP()

    try:
        # 先回到首页，保证页面上有登出表单
        try:
            chrome.navigate_and_wait(
                "https://hanime1.me/",
                ready_selector="a.video-link",
                timeout=25.0,
                min_stable=0.5,
            )
        except Exception:
            pass

        submitted = chrome.evaluate(
            """(() => {
                const forms = [...document.querySelectorAll('form')];
                const form = forms.find(f =>
                    (f.getAttribute('action') || '').indexOf('/logout') !== -1);

                if (!form) return 'no-logout-form';

                const method = (form.getAttribute('method') || 'get').toLowerCase();
                if (method !== 'post') return 'not-post';

                // 按表单原始字段原样提交（token 用的是表单里那个值）
                const body = new URLSearchParams();
                form.querySelectorAll('input[name]').forEach(i => {
                    body.append(i.name, i.value);
                });

                fetch(form.getAttribute('action'), {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: body.toString(),
                    credentials: 'same-origin',
                    redirect: 'follow',
                }).catch(() => {});

                return 'posted';
            })()"""
        ).get("value")

        # 等登录态真正失效。
        # 注意要重新加载一次页面：官网导航是 SPA，
        # 登出后旧 DOM 里的导航栏还留着登录态的痕迹，
        # 不刷新的话 _read_account 会误判成还登录着。
        for _ in range(20):
            time.sleep(0.5)

            try:
                chrome.navigate_and_wait(
                    "https://hanime1.me/",
                    ready_selector="a.video-link",
                    timeout=20.0,
                    min_stable=0.4,
                )
            except Exception:
                pass

            info = _read_account(chrome)

            if not info["logged_in"]:
                break
    except Exception:
        pass

    with _state_lock:
        _state.update({
            "checked_at": time.monotonic(),
            "logged_in": False,
            "user_id": "",
            "username": "",
            "avatar": "",
        })

    _username_cache.clear()

    return True


# ==========================================================
# 影片操作（点赞 / 储存）
# ==========================================================
#
# 这两个按钮不是普通表单：点击后由站点自己的 JS 发请求，
# 请求里带着登录 cookie 和 CSRF token。
# 与其去逆向它的私有接口，不如就让页面自己去做 ——
# 我们在真实 Chrome 里触发一次真实点击，然后重新加载页面确认结果。
#
# 这样既不猜接口，也不会伪造请求头。

VIDEO_URL = "https://hanime1.me/watch?v={video_id}"

# 操作时页面上的按钮 id
LIKE_BUTTON_ID = "video-like-btn"
UNLIKE_BUTTON_ID = "video-unlike-btn"
SAVE_BUTTON_ID = "video-save-btn"


def _click_button(chrome, button_id):
    """在页面里触发一次真实点击。"""
    expression = (
        "(()=>{"
        f"const el=document.getElementById({json.dumps(button_id)});"
        "if(!el) return 'missing';"
        "el.click();"
        "return 'clicked';"
        "})()"
    )

    return chrome.evaluate(expression).get("value")


def video_action(video_id, action, timeout=25.0):
    """对影片执行点赞 / 取消点赞 / 储存。

    action: "like" | "unlike" | "save"

    返回 (成功, 消息, 最新状态)
    """
    account = get_account()

    if not account["logged_in"]:
        return False, "需要先登录才能使用这个功能", {}

    button_map = {
        "like": LIKE_BUTTON_ID,
        "unlike": UNLIKE_BUTTON_ID,
        "save": SAVE_BUTTON_ID,
    }

    button_id = button_map.get(action)

    if not button_id:
        return False, f"不支持的操作：{action}", {}

    url = VIDEO_URL.format(video_id=video_id)

    chrome = ChromeCDP()

    # 1. 打开影片页（登录状态下服务端会渲染出真实可用的按钮）
    ready, _ = chrome.navigate_and_wait(
        url,
        ready_selector="#video-artist-name",
        timeout=timeout,
        min_stable=0.6,
    )

    if not ready:
        return False, "打不开影片页面", {}

    # 2. 确认按钮确实可用（未登录时按钮只会弹注册窗）
    still_modal = chrome.evaluate(
        "(()=>{"
        f"const el=document.getElementById({json.dumps(button_id)});"
        "if(!el) return 'missing';"
        "const t=el.getAttribute('data-target')||'';"
        "return t.includes('signUpModal') ? 'needs-login' : 'ok';"
        "})()"
    ).get("value")

    if still_modal == "missing":
        return False, "页面上找不到这个按钮", {}

    if still_modal == "needs-login":
        # 有 cookie 但服务端仍认为是未登录：清掉缓存让前端重新检测
        with _state_lock:
            _state["checked_at"] = 0.0

        return False, "登录状态已失效，请重新登录", {}

    # 3. 点击
    clicked = _click_button(chrome, button_id)

    if clicked != "clicked":
        return False, "点击失败", {}

    # 4. 等站点自己的请求完成，然后重新加载确认结果
    time.sleep(2.0)

    ready2, html = chrome.navigate_and_wait(
        url,
        ready_selector="#video-artist-name",
        timeout=timeout,
        min_stable=0.6,
    )

    state = {}

    if ready2 and html:
        from parser.hanime_parser import HanimeParser

        parser = HanimeParser(html)
        info = parser.get_like_info()

        state = {
            "like_ratio": info["like_ratio"],
            "like_count": info["like_count"],
            "unlike_count": info["unlike_count"],
        }

    messages = {
        "like": "点赞成功",
        "unlike": "已取消点赞",
        "save": "已储存到播放清单",
    }

    return True, messages.get(action, "完成"), state
