import json
import time

import requests
import websocket


CDP_URL = "http://127.0.0.1:9222"


class ChromeCDP:

    def __init__(self):

        self.ws_url = None


    def _get_page_websocket(self):

        response = requests.get(
            f"{CDP_URL}/json"
        )

        targets = response.json()


        pages = [
            target
            for target in targets
            if target.get("type") == "page"
            and target.get("webSocketDebuggerUrl")
        ]


        if not pages:
            raise Exception(
                "没有找到 Chrome page target"
            )


        # 优先选择已经打开的网站页面
        for target in pages:

            url = target.get(
                "url",
                ""
            )


            # 排除 Chrome 自己的页面
            if (
                "127.0.0.1:9222" in url
                or
                url.startswith("chrome://")
            ):
                continue


            if (
                url.startswith("http://")
                or
                url.startswith("https://")
            ):

                print(
                    "选择网页页面:"
                )

                print(url)

                return target[
                    "webSocketDebuggerUrl"
                ]


        # 如果只有 New Tab
        # 使用第一个页面

        print(
            "当前没有网页页面，使用 New Tab"
        )


        return pages[0][
            "webSocketDebuggerUrl"
        ]



    def connect(self):

        self.ws_url = (
            self._get_page_websocket()
        )



    def evaluate(self, expression):

        if not self.ws_url:
            self.connect()


        ws = websocket.create_connection(
            self.ws_url
        )


        command = {

            "id":1,

            "method":
                "Runtime.evaluate",

            "params":{

                "expression":
                    expression,

                "returnByValue":
                    True
            }
        }


        ws.send(
            json.dumps(command)
        )


        while True:

            message = json.loads(
                ws.recv()
            )


            if message.get("id")==1:

                ws.close()

                return (
                    message
                    ["result"]
                    ["result"]
                )



    def get_title(self):

        result = self.evaluate(
            "document.title"
        )

        return result.get(
            "value"
        )


    def get_url(self):

        result = self.evaluate(
            "location.href"
        )

        return result.get(
            "value"
        )



    def get_html(self):

        html = self.evaluate(
            "document.documentElement.outerHTML"
        )


        value = html.get(
            "value"
        )


        print("================ HTML前500字符 ================")

        print(
            value[:500]
        )

        print(
            "=============================================="
        )


        return value



    def navigate(self,url):

        if not self.ws_url:

            self.connect()


        expression = (
            f"location.href = "
            f"{json.dumps(url)}"
        )


        self.evaluate(
            expression
        )


        # 等待跳转完成

        time.sleep(3)

        print(
            "跳转后 URL:"
        )

        print(
            self.get_url()
        )