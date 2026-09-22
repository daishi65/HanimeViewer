import json
import requests
import websocket


CDP_URL = "http://127.0.0.1:9222"


def get_page_websocket():
    response = requests.get(f"{CDP_URL}/json")
    targets = response.json()

    for target in targets:
        if target.get("type") == "page":
            return target["webSocketDebuggerUrl"]

    raise Exception("没有找到页面")


def evaluate(expression):
    ws_url = get_page_websocket()

    ws = websocket.create_connection(ws_url)

    command = {
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {
            "expression": expression,
            "returnByValue": True
        }
    }

    ws.send(json.dumps(command))

    while True:
        message = json.loads(ws.recv())

        if message.get("id") == 1:
            ws.close()
            return message["result"]["result"]


def main():

    print("读取网页信息...\n")

    title = evaluate("document.title")

    url = evaluate("location.href")

    html = evaluate(
        "document.documentElement.outerHTML"
    )


    print("标题:")
    print(title.get("value"))

    print("\n网址:")
    print(url.get("value"))

    print("\nHTML长度:")
    print(len(html.get("value", "")))


if __name__ == "__main__":
    main()