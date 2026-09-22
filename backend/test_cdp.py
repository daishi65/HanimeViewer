from cdp.chrome import ChromeCDP


def main():

    chrome = ChromeCDP()

    print("标题:")
    print(chrome.get_title())

    print()

    print("网址:")
    print(chrome.get_url())

    print()

    html = chrome.get_html()

    print("HTML长度:")
    print(len(html))


if __name__ == "__main__":
    main()