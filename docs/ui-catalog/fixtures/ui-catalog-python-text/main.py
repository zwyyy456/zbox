import asyncio
from zbox_sdk import run

preview = "Read selected text to preview the converted result."


async def handle(message, api):
    global preview
    params = message["params"]
    action = params.get("actionID")
    if action == "read":
        text = await api.call("selection.read")
        preview = text.lower() if params.get("selectedID") == "lower" else text.upper()
        preview = params.get("values", {}).get("prefix", "") + preview
    elif action == "copy":
        await api.call("clipboard.write", text=preview)
    query = params.get("query", "").lower()
    items = [{"id": "upper", "title": "Uppercase"}, {"id": "lower", "title": "Lowercase"}]
    api.show({"title": "Text Case · Python", "searchable": True,
              "items": [item for item in items if query in item["title"].lower()],
              "detail": preview,
              "fields": [{"id": "prefix", "name": "Prefix", "type": "text", "value": ""}],
              "actions": [{"id": "read", "title": "Read and Convert Selection"},
                          {"id": "copy", "title": "Copy Result"}]})


asyncio.run(run(handle))
