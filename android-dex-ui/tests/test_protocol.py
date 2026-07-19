from __future__ import annotations

import json

import pytest

from android_dex_ui.protocol import RpcFault, failure, parse_request, success


def test_golden_request_and_success_envelopes():
    request = b'{"jsonrpc":"2.0","id":"abc","method":"device.list","params":{}}'
    assert parse_request(request) == ("abc", "device.list", {})
    assert json.loads(success("abc", {"devices": []})) == {
        "jsonrpc": "2.0",
        "id": "abc",
        "result": {"devices": []},
    }


def test_golden_error_is_structured_and_never_leaks_confirmation():
    encoded = failure(
        7,
        RpcFault("E-CONFIRMATION", "Confirmação não confere", "A ação foi bloqueada."),
    )
    value = json.loads(encoded)
    assert value["error"] == {
        "code": "E-CONFIRMATION",
        "title": "Confirmação não confere",
        "detail": "A ação foi bloqueada.",
        "recoverable": False,
        "actions": [],
    }
    assert "KNOX PERMANENTE" not in encoded.decode()


@pytest.mark.parametrize(
    "payload,code",
    [
        (b"not-json", "E-RPC-JSON"),
        (b'{"jsonrpc":"1.0","method":"device.list"}', "E-RPC-ENVELOPE"),
        (b'{"jsonrpc":"2.0","id":{},"method":"device.list"}', "E-RPC-ID"),
        (b'{"jsonrpc":"2.0","method":"device.list","params":[]}', "E-RPC-PARAMS"),
    ],
)
def test_invalid_envelopes_fail_closed(payload, code):
    with pytest.raises(RpcFault) as caught:
        parse_request(payload)
    assert caught.value.code == code
