"""zbox protocol v1. Python 3.9+, standard library only; stdout is reserved for protocol."""
import asyncio
import json
import sys

FRAME_LIMIT = 8 * 1024 * 1024


class HostError(Exception):
    pass


class Context:
    def __init__(self, client, event_id):
        self._client = client
        self.event_id = event_id

    def _check(self):
        if self._client.event_id != self.event_id:
            raise asyncio.CancelledError()

    def show(self, view):
        self._check()
        self._client.last_view = dict(view)
        self._client.send({"method": "ui", "params": {"eventID": self.event_id, "view": view}})

    async def call(self, method, **params):
        self._check()
        client = self._client
        if len(client.pending) >= 64:
            raise HostError("Too many pending host calls")
        client.next_id += 1
        request_id = str(client.next_id)
        future = asyncio.get_running_loop().create_future()
        client.pending[request_id] = future
        try:
            client.send({"id": request_id, "method": method,
                         "params": dict(params, eventID=self.event_id)})
            result = await asyncio.wait_for(future, timeout=30)
            self._check()
            return result
        finally:
            client.pending.pop(request_id, None)


class _Client:
    def __init__(self, handler):
        self.handler = handler
        self.pending = {}
        self.next_id = 0
        self.event_id = None
        self.task = None
        self.initialized = False
        self.last_view = {}

    def send(self, message):
        encoded = json.dumps(dict(message, jsonrpc="2.0"), ensure_ascii=False,
                             allow_nan=False, separators=(",", ":")).encode("utf-8")
        if len(encoded) > FRAME_LIMIT:
            raise HostError("Protocol frame exceeds 8 MiB")
        sys.stdout.buffer.write(encoded + b"\n")
        sys.stdout.buffer.flush()

    def cancel(self):
        self.event_id = None
        if self.task is not None:
            self.task.cancel()
            self.task = None
        for future in self.pending.values():
            future.cancel()
        self.pending.clear()

    async def dispatch(self, message):
        try:
            await self.handler(message, Context(self, message["params"]["eventID"]))
        except asyncio.CancelledError:
            pass
        except Exception as error:
            if self.event_id == message["params"]["eventID"]:
                Context(self, self.event_id).show(dict(self.last_view, error=str(error)))

    def receive(self, message):
        if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
            raise HostError("Invalid host protocol envelope")
        method = message.get("method")
        params = message.get("params") or {}
        if method is None:
            future = self.pending.get(message.get("id"))
            if future is not None and not future.done():
                if "error" in message:
                    future.set_exception(HostError(message["error"]["message"]))
                elif "result" in message:
                    future.set_result(message["result"])
                else:
                    raise HostError("Missing host result")
        elif method == "initialize":
            if self.initialized or params.get("protocolVersion") != 1:
                raise HostError("Incompatible host protocol")
            self.initialized = True
            self.send({"id": message["id"], "result": {"protocolVersion": 1}})
        elif method in ("start", "query", "action"):
            event_id = params.get("eventID")
            if not self.initialized or type(event_id) is not int or event_id <= 0:
                raise HostError("Missing event identity")
            self.cancel()
            self.event_id = event_id
            self.task = asyncio.create_task(self.dispatch(message))
        elif method == "cancel":
            if params.get("eventID") == self.event_id:
                self.cancel()
        elif method == "stop":
            self.cancel()
            return False
        return True


async def run(handler):
    """Call with an async handler(message, context). No package or host internals are needed."""
    reader = asyncio.StreamReader(limit=FRAME_LIMIT + 1)
    transport, _ = await asyncio.get_running_loop().connect_read_pipe(
        lambda: asyncio.StreamReaderProtocol(reader), sys.stdin.buffer)
    client = _Client(handler)
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            if not line.endswith(b"\n") or len(line) > FRAME_LIMIT + 1:
                raise HostError("Incomplete or oversized host frame")
            if not client.receive(json.loads(line)):
                break
    finally:
        client.cancel()
        transport.close()
