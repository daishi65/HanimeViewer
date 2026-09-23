import json

import requests
import websocket


CDP_URL = "http://127.0.0.1:9222"


class ChromeCDP:
    def __init__(self):
        self.ws_url = self._get_page_websocket()

    def _get_page_websocket(self):
        response = requests.get(f"{CDP_URL}/json")
        targets = response.json()

        pages = [
            target
            for target in targets
            if target.get("type") == "page"
            and target.get("webSocketDebuggerUrl")
        ]

        if not pages:
            raise Exception("没有找到 Chrome page target")

        # 优先选择普通 http/https 页面
        for target in pages:
            url = target.get("url", "")

            if url.startswith("http://") or url.startswith("https://"):
                return target["webSocketDebuggerUrl"]

        # 如果没有普通网页，则使用第一个 page
        return pages[0]["webSocketDebuggerUrl"]

    def evaluate(self, expression, timeout=15):
        ws = websocket.create_connection(
            self.ws_url,
            timeout=timeout
        )

        command = {
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": expression,
                "returnByValue": True
            }
        }

        ws.send(json.dumps(command))

        try:
            while True:
                message = json.loads(ws.recv())

                if message.get("id") == 1:
                    ws.close()
                    return message["result"]["result"]
        except Exception:
            ws.close()
            raise
        
    def get_title(self):
        result = self.evaluate("document.title")
        return result.get("value")

    def get_url(self):
        result = self.evaluate("location.href")
        return result.get("value")

    def get_html(self):
        result = self.evaluate("document.documentElement.outerHTML")
        return result.get("value")

    def navigate(self, url):
        expression = f"location.href = {json.dumps(url)}"
        self.evaluate(expression)