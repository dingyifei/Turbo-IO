"""Host selector parity: every host method the addon hooks or calls, with its exact
Objective-C type encoding, read offline from the stock images (no device).

Usage: python3 -I tests/host_selectors.py <edition dir> <Runner.app> [<Runner.app> ...]

For each app: each listed method must exist in the named image with exactly the
listed encoding, and that encoding must satisfy the check the addon itself makes
before hooking or calling (the Signature()/CheckedSetter() predicates, copied below
as `accept`). The table was read from 1.0.7 (230) and confirmed equal on 1.0.11
(259); a host build where any row differs fails here, and the addon's own runtime
check would leave that hook off. Each selector must also still appear in the
addon source file named in the row, so a hook added or renamed there without a
row here fails too.
"""
import importlib.util, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('objc_methods', HERE / 'objc_methods.py')
objc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(objc)

P = 'rayneo_venus_sdk_plugin.'
R, F = 'Runner', 'Frameworks/Flutter.framework/Flutter'
# (image, class, '+'/'-', selector, exact encoding, (return chars, [argument chars...]) the addon accepts, source file)
HOOKED = [
    (R, P + 'AiResultListenerBridge', '-', 'onAsrResult:isFinish:sessionId:', 'v36@0:8@16B24@28', ('v', ['@', 'Bc', '@']), 'Addon.m'),
    (R, P + 'AiResultListenerBridge', '-', 'onNlpResult:', 'v24@0:8@16', ('v', ['@']), 'Addon.m'),
    (R, P + 'AiResultListenerBridge', '-', 'onResponseComplete', 'v16@0:8', ('v', []), 'Addon.m'),
    (R, P + 'AiResultListenerBridge', '-', 'onAudioRecordStart', 'v16@0:8', ('v', []), 'Addon.m'),
    (R, P + 'AiResultListenerBridge', '-', 'onError:message:', 'v28@0:8i16@20', ('v', ['qQlLiI@', '@']), 'NoNetworkTurnHost.m'),
    (R, P + 'AlwaysOnResultListenerBridge', '-', 'onAlwaysOnResponse:', 'v24@0:8@16', ('v', ['@']), 'Addon.m'),
    (R, P + 'RayneoNetPluginBridge', '-', 'handleMethodCall:result:', 'v32@0:8@16@?24', ('v', ['@', '@']), 'DownloadOnlySafety.m'),
    (R, 'RayNeoAppStateAdapterImpl', '-', 'isAppInForeground', 'B16@0:8', ('Bc', []), 'NoNetworkTurnHost.m'),
    (F, 'FlutterEngine', '-', 'sendOnChannel:message:binaryReply:', 'v40@0:8@16@24@?32', ('v', ['@', '@', '@']), 'DownloadOnlySafety.m'),
    (F, 'FlutterEngine', '-', 'setMessageHandlerOnChannel:binaryMessageHandler:', 'q32@0:8@16@?24', ('vqlQ', ['@', '@']), 'WireLog.m'),
    (F, 'FlutterEngine', '-', 'setMessageHandlerOnChannel:binaryMessageHandler:taskQueue:', 'q40@0:8@16@?24@32', ('vqlQ', ['@', '@', '@']), 'WireLog.m'),
]
CALLED = [
    (R, P + 'VoiceAssistantHelper', '+', 'shared', '@16@0:8', ('@', []), 'Addon.m'),
    (R, P + 'VoiceAssistantHelper', '-', 'stopWorkflow', 'v16@0:8', ('v', []), 'Addon.m'),
    (R, P + 'AlwaysOnDebugAudioController', '-', 'getStatus', '@16@0:8', ('@', []), 'AlwaysOnAudioNative.m'),
    (R, P + 'AlwaysOnDebugAudioController', '-', 'configureDumpWithArguments:', 'B24@0:8@16', ('Bc', ['@']), 'AlwaysOnAudioNative.m'),
    (F, 'FlutterEngine', '-', 'ensureSemanticsEnabled', 'v16@0:8', ('v', []), 'HomeTabBridge.m'),
    (F, 'FlutterViewController', '-', 'engine', '@16@0:8', ('@', []), 'HomeTabBridge.m'),
    (F, 'FlutterMethodCall', '+', 'methodCallWithMethodName:arguments:', '@32@0:8@16@24', ('@', ['@', '@']), 'ExperimentalOTAFlash.m'),
    (F, 'FlutterStandardTypedData', '+', 'typedDataWithBytes:', '@24@0:8@16', ('@', ['@']), 'ProtocolContext.m'),
    (F, 'FlutterStandardMethodCodec', '+', 'sharedInstance', '@16@0:8', ('@', []), 'GlassesChannelHook.m'),
    (F, 'FlutterStandardMethodCodec', '-', 'decodeEnvelope:', '@24@0:8@16', ('@', ['@']), 'GlassesChannelHook.m'),
]
# Key-value fields the voice takeover copies between official wrappers (Addon.m CopyResponse, TodoRuntime.m).
WRAPPER_FIELDS = {
    'RayNeoNlpResultWrapper': {'sub': '@', 'dialogId': '@', 'sessionId': '@', 'domain': '@', 'intent': '@', 'round': 'i',
                               'query': '@', 'spoken': '@', 'answer': '@', 'finished': 'B', 'offline': 'B', 'command': '@',
                               'hasNextRound': 'B', 'rawData': '@'},
    'NlpCommandWrapper': {'name': '@', 'params': '@'},
}
SWIFT_SYMBOLS = [('_$s23rayneo_venus_sdk_plugin28AlwaysOnDebugAudioControllerC6sharedACvpZ', 'AlwaysOnAudioNative.m')]


def parse(types):
    """'v36@0:8@16B24@28' -> ('v', ['@', ':', '@', 'B', '@']) first characters only."""
    out, i = [], 0
    while i < len(types):
        c = types[i]
        if c in 'rnNoORV':  # qualifiers
            i += 1
            continue
        out.append(c)
        i += 1
        if c == '@' and i < len(types) and types[i] == '?':
            i += 1
        if c == '^':
            i += 1
        while i < len(types) and types[i].isdigit():
            i += 1
    return out[0], out[1:]


def accepted(types, accept):
    ret, args = parse(types)
    want_ret, want_args = accept
    if ret not in want_ret or args[:2] != ['@', ':'] or len(args) - 2 != len(want_args):
        return False
    return all(a in allowed for a, allowed in zip(args[2:], want_args))


def main():
    edition, apps = Path(sys.argv[1]), [Path(a) for a in sys.argv[2:]]
    assert apps, 'usage: host_selectors.py <edition> <Runner.app>...'
    rows = HOOKED + CALLED
    for image, cls, kind, sel, types, accept, source in rows:
        assert accepted(types, accept), f'table row {cls} {sel}: {types} fails the addon check {accept}'
        text = (edition / source).read_text()
        assert f'"{sel}"' in text or f'@selector({sel})' in text, f'{sel} no longer appears in {source}'
    for symbol, source in SWIFT_SYMBOLS:
        assert symbol.lstrip('_') in (edition / source).read_text(), f'{symbol} no longer appears in {source}'
    for app in apps:
        tables = {}
        for image in (R, F):
            tables[image] = objc.methods(str(app / image))
        for image, cls, kind, sel, types, _accept, _source in rows:
            got = tables[image].get((cls, kind, sel))
            assert got == types, f'{app.name}: {kind}[{cls} {sel}] is {got!r}, expected {types!r}'
        for cls, fields in WRAPPER_FIELDS.items():
            for field, t in fields.items():
                getter = tables[R].get((cls, '-', field))
                setter = tables[R].get((cls, '-', 'set' + field[0].upper() + field[1:] + ':'))
                assert getter and parse(getter)[0] == t, f'{app.name}: {cls}.{field} getter {getter!r}'
                assert setter and parse(setter) == ('v', ['@', ':', t]), f'{app.name}: {cls}.{field} setter {setter!r}'
        symbols = subprocess.run(['nm', '-g', str(app / R)], capture_output=True, text=True, check=True).stdout
        for symbol, _source in SWIFT_SYMBOLS:
            assert any(line.split()[-1:] == [symbol] for line in symbols.splitlines()), f'{app.name}: missing {symbol}'
        count = len(rows) + sum(2 * len(f) for f in WRAPPER_FIELDS.values()) + len(SWIFT_SYMBOLS)
        print(f'PASS {app}: {count} host methods, wrapper fields and symbols with the expected encodings')


if __name__ == '__main__':
    main()
