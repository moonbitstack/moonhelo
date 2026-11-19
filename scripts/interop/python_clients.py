"""Call the running greet service from Python, the way a program in another
language would: the REST routes and the GraphQL field with the standard library,
and greet.Greeter with grpcio, over stubs generated from `src/spec/greet.proto`
when the script runs.

    moon run src/cmd/greet-server --target native &
    python3 scripts/interop/python_clients.py [--http 12000] [--grpc 12001]

Needs `grpcio` and `grpcio-tools`. Exits non-zero on the first answer that is
not the one the service owes.
"""

import argparse
import json
import pathlib
import sys
import tempfile
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROTO = ROOT / "src" / "spec" / "greet.proto"
NAME = "Python"


def call(method: str, url: str, body: dict | None = None) -> tuple[int, str]:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"content-type": "application/json"} if data is not None else {}
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.status, response.read().decode()


def say_hello(port: int, name: str) -> str:
    import grpc
    from grpc_tools import protoc

    out = tempfile.mkdtemp()
    args = ["protoc", f"-I{PROTO.parent}", f"--python_out={out}", f"--grpc_python_out={out}", str(PROTO)]
    if protoc.main(args) != 0:
        raise SystemExit("protoc could not compile greet.proto")
    sys.path.insert(0, out)
    import greet_pb2
    import greet_pb2_grpc

    # The gRPC leg binds beside the HTTP one; give it a moment if it is still coming up.
    for attempt in range(10):
        try:
            with grpc.insecure_channel(f"127.0.0.1:{port}") as channel:
                stub = greet_pb2_grpc.GreeterStub(channel)
                return stub.SayHello(greet_pb2.HelloRequest(name=name), timeout=10).message
        except grpc.RpcError as error:
            if error.code() != grpc.StatusCode.UNAVAILABLE or attempt == 9:
                raise
            time.sleep(0.5)
    raise AssertionError("unreachable")


def expect(what: str, got, want) -> None:
    print(f"{what:<16} -> {got}")
    if got != want:
        raise SystemExit(f"{what}: want {want!r}, got {got!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--http", type=int, default=12000)
    parser.add_argument("--grpc", type=int, default=12001)
    args = parser.parse_args()
    base = f"http://127.0.0.1:{args.http}"

    expect("GET /ping", call("GET", f"{base}/ping"), (200, "pong"))
    status, text = call("POST", f"{base}/users", {"name": NAME})
    user = json.loads(text)
    expect("POST /users", (status, user["name"]), (201, NAME))
    status, text = call("GET", f"{base}/users/{user['id']}")
    expect(f"GET /users/{user['id']}", (status, json.loads(text)["name"]), (200, NAME))
    status, text = call("POST", f"{base}/graphql", {"query": f'{{ greeting(name: "{NAME}") }}'})
    expect("POST /graphql", (status, json.loads(text)["data"]["greeting"]), (200, f"Hello, {NAME}"))
    expect("gRPC SayHello", say_hello(args.grpc, NAME), f"Hello, {NAME}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
