#!/usr/bin/env python3
"""Synthetic-only offline regression suite. Run: python3 -I -B /absolute/path/tests.py"""
from __future__ import annotations

import ctypes
import importlib.util
import json
import math
import os
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import uuid
import wave
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("_clench_analyze_tests", ROOT / "analyze.py")
analyze = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = analyze
spec.loader.exec_module(analyze)
decode = analyze.decode
np = analyze.np


def varint(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    return bytes(out) + bytes([value])


def envelope(payload=b"", typ=3, metadata=None):
    body = json.dumps(metadata or {}, separators=(",", ":")).encode()
    return b"\x08\x01\x10" + varint(typ) + b"\x1a" + varint(len(body)) + body + (
        b"\x22" + varint(len(payload)) + payload if payload else b"")


def manifest(label="double-tap", duration=8, source="voice", synthetic=True):
    m = {
        "schemaVersion": 1, "sessionId": str(uuid.uuid4()), "source": source,
        "label": label, "createdAt": "2026-10-29T12:34:56.123Z",
        "appVersion": "test-fixture", "appCommit": "synthetic-fixture-not-a-build",
        "clock": "monotonic-seconds-from-session-start", "marks": [], "packets": [],
        "durationSeconds": duration, "stopRequestLimitSeconds": 25, "receiveLimitSeconds": 30,
        "stopPending": False, "offObserved": False, "droppedPackets": 0,
    }
    if synthetic:
        m["synthetic"] = True
        m["audioFormat"] = {"codec": "pcm_s16le", "sampleRate": 16000,
                            "channels": ["air"], "layout": "interleaved",
                            "provenance": "synthetic"}
    return m


def synth(duration=8, clicks=(), bursts=(), channels=1, seed=17):
    rate = 16000
    rng = np.random.default_rng(seed)
    x = rng.normal(0, 0.0015, (round(duration * rate), channels))
    for time in clicks:
        # Sharp, decaying, broadband contact-like transient (not a recorded tooth).
        start = round(time * rate)
        n = round(0.008 * rate)
        click = rng.normal(0, 0.35, n) * np.exp(-np.arange(n) / (rate * 0.0015))
        if start + n <= len(x):
            x[start:start + n] += click[:, None]
    for time in bursts:
        start, n = round(time * rate), round(0.350 * rate)
        t = np.arange(n) / rate
        burst = (0.10 * np.sin(2 * np.pi * 700 * t)
                 + 0.06 * np.sin(2 * np.pi * 1400 * t)) * np.sin(np.pi * np.arange(n) / n) ** 2
        if start + n <= len(x):
            x[start:start + n] += burst[:, None]
    return np.clip(x, -1, 1)


def save_pcm(path, x, m, start=0, rate=16000):
    path.mkdir()
    raw = bytearray()
    typ = 3 if m["source"] == "voice" else 163
    for offset in range(0, len(x), 800):
        block = x[offset:offset + 800]
        pcm = np.clip(np.rint(block * 32768), -32768, 32767).astype("<i2")
        wire = envelope(pcm.tobytes(), typ)
        index = len(m["packets"])
        audio_start = start + offset / rate
        m["packets"].append({
            "index": index, "arrivalSeconds": audio_start + len(block) / rate,
            "business": 13, "type": typ, "envelopeBytes": len(wire),
            "vpuMask": None, "vadMask": None, "audioStartSeconds": audio_start,
        })
        raw += struct.pack("<I", len(wire)) + wire
    (path / "envelopes.rnp").write_bytes(raw)
    (path / "manifest.json").write_text(json.dumps(m))
    return path


def opus_manifest(source="voice", duration=8, synthetic=True):
    m = manifest(source=source, duration=duration, synthetic=False)
    if synthetic:
        m["synthetic"] = True
        m["audioFormat"] = {"codec": "opus", "sampleRate": 16000,
                            "channels": [source + "-mono-unassigned"], "layout": "mono",
                            "provenance": "synthetic"}
    return m


def encoded_packets(count=4, samples=960, padded_size=None):
    """Generated native Opus, never recorded audio. Exercise real packet TOCs."""
    decoder = decode.OpusDecoder()
    lib = decoder.lib
    decoder.close()
    lib.opus_encoder_create.argtypes = [ctypes.c_int32, ctypes.c_int, ctypes.c_int,
                                        ctypes.POINTER(ctypes.c_int)]
    lib.opus_encoder_create.restype = ctypes.c_void_p
    lib.opus_encoder_destroy.argtypes = [ctypes.c_void_p]
    lib.opus_encoder_destroy.restype = None
    # Only fixed arguments: Apple arm64 passes variadic ctl values differently.
    lib.opus_encoder_ctl.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.opus_encoder_ctl.restype = ctypes.c_int
    lib.opus_encode.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int16), ctypes.c_int,
                                ctypes.POINTER(ctypes.c_ubyte), ctypes.c_int32]
    lib.opus_encode.restype = ctypes.c_int32
    lib.opus_packet_pad.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.c_int32, ctypes.c_int32]
    lib.opus_packet_pad.restype = ctypes.c_int
    error = ctypes.c_int()
    state = lib.opus_encoder_create(16000, 1, 2048, ctypes.byref(error))
    decode.require(state and error.value == 0, "test encoder creation failed")
    packets = []
    try:
        decode.require(lib.opus_encoder_ctl(state, 4002, ctypes.c_int(24000)) == 0, "test bitrate ctl failed")
        decode.require(lib.opus_encoder_ctl(state, 4006, ctypes.c_int(0)) == 0, "test CBR ctl failed")
        for i in range(count):
            t = (np.arange(samples) + i * samples) / 16000
            pcm = (5000 * np.sin(2 * np.pi * (440 + i * 110) * t)).astype(np.int16)
            buf = (ctypes.c_ubyte * 4096)()
            size = lib.opus_encode(state, pcm.ctypes.data_as(ctypes.POINTER(ctypes.c_int16)),
                                   samples, buf, len(buf))
            decode.require(size > 0, "test encode failed")
            if padded_size is not None:
                decode.require(size <= padded_size, "test packet larger than padding target")
                decode.require(lib.opus_packet_pad(buf, size, padded_size) == 0,
                               "test packet padding failed")
                size = padded_size
            packets.append(bytes(buf[:size]))
    finally:
        lib.opus_encoder_destroy(state)
    return packets


def ogg_page(body, laces, flags, seq, granule, serial=123):
    page = bytearray(struct.pack("<4sBBQIIIB", b"OggS", 0, flags, granule, serial, seq, 0, len(laces))
                     + bytes(laces) + body)
    struct.pack_into("<I", page, 22, decode.ogg_crc(page))
    return bytes(page)


def ogg_fixture(frames, legacy=True, pre_skip=312, declared_channels=2):
    head = b"OpusHead" + struct.pack("<BBHIhB", 1, declared_channels, pre_skip, 48000, 0, 0)
    pages = [ogg_page(head, [19], 2, 0, 0), ogg_page(b"OpusTags", [8], 0, 1, 0)]
    inspector, total = decode.OpusDecoder(), 0
    try:
        for i, frame in enumerate(frames):
            total += inspector.sample_count(frame) * 3
            gp = (i + 1) * 960 + pre_skip if legacy else total
            laces = [255] * (len(frame) // 255) + [len(frame) % 255]
            pages.append(ogg_page(frame, laces, 4 if i == len(frames) - 1 else 0, i + 2, gp))
    finally:
        inspector.close()
    return b"".join(pages)


class OfflineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix=".test-", dir=ROOT)
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def put_wire(self, m, wires, arrivals=None, name="session"):
        folder = self.root / name
        folder.mkdir()
        raw = bytearray()
        for i, wire in enumerate(wires):
            typ, metadata, _ = decode.parse_envelope(wire)
            m["packets"].append({
                "index": i, "arrivalSeconds": arrivals[i] if arrivals else 1 + i * 0.02,
                "business": 13, "type": typ, "envelopeBytes": len(wire),
                "vpuMask": metadata.get("vpuMask"), "vadMask": metadata.get("vadMask"),
            })
            for key in ("frameCount", "seq"):
                if key in metadata:
                    m["packets"][-1][key] = metadata[key]
            raw += struct.pack("<I", len(wire)) + wire
        (folder / "envelopes.rnp").write_bytes(raw)
        (folder / "manifest.json").write_text(json.dumps(m))
        return folder

    def native_packets(self, **kwargs):
        try:
            return encoded_packets(**kwargs)
        except decode.SessionError as exc:
            if "unavailable" in str(exc):
                self.skipTest("local libopus unavailable")
            raise

    def run_cli(self, script, *args):
        return subprocess.run([sys.executable, "-I", "-B", str(ROOT / script),
                               *map(str, args)], text=True, capture_output=True, timeout=90)

    def put_official(self, frames, name="official", legacy=True, timestamps="epoch-ms",
                     source_kind="realtime", drift=0, counters=True):
        m = opus_manifest(source="lifelog", duration=8)
        m["stopRequestLimitSeconds"], m["receiveLimitSeconds"] = 120, 125
        wall = 1793275200000
        m["startWallMs"] = wall
        if counters:
            m["officialCounters"] = [
                {"t": 0, "wallMs": wall + drift * 1000, "realtimePackets": 10000,
                 "cachedPackets": 20000, "alwaysOnRunning": True},
                {"t": 8, "wallMs": wall + 8000, "realtimePackets": 10000 + len(frames),
                 "cachedPackets": 20000, "alwaysOnRunning": False}]
        folder = self.put_wire(m, [], name=name)
        (folder / "official-dump").mkdir()
        data = ogg_fixture(frames, legacy=legacy)
        filename = "official-dump/00-" + source_kind + ".ogg"
        (folder / filename).write_bytes(data)
        m["officialDump"] = [{"file": filename, "sourceKind": source_kind, "bytes": len(data),
            "sha256": decode.hashlib.sha256(data).hexdigest(), "copyFinalized": True,
            "alignment": "unaligned"}]
        times, elapsed = [], 1.0
        inspector = decode.OpusDecoder()
        try:
            for frame in frames:
                elapsed += inspector.sample_count(frame) / 16000
                timestamp = wall + round(elapsed * 1000)
                if timestamps == "epoch-seconds":
                    timestamp /= 1000
                times.append({"eventTs": timestamp, "source": source_kind, "frameCount": 1,
                              "vpuMask": 1, "vadMask": 1})
        finally:
            inspector.close()
        m["officialEvents"] = {"state": "attached", "file": "official-events.jsonl", "count": len(times)}
        (folder / "official-events.jsonl").write_text(
            "".join(json.dumps(row) + "\n" for row in times))
        m["marks"] = [{"timeSeconds": 2.5}]
        self.rewrite_manifest(folder, m)
        return folder, m

    def rewrite_manifest(self, folder, m):
        (folder / "manifest.json").write_text(json.dumps(m))

    def make_zip(self, name="session.zip", entries=None):
        path = self.root / name
        with zipfile.ZipFile(path, "w") as z:
            for key, data in (entries or {}).items():
                z.writestr(key, data)
        return path

    def test_clicks_noise_detector_recall_and_snr(self):
        m = manifest()
        m["marks"] = [{"timeSeconds": 2.32}, {"timeSeconds": 5.32}]
        folder = save_pcm(self.root / "clicks", synth(clicks=[2, 2.3, 5, 5.3]), m)
        decoded = decode.decode_session(folder)
        report = analyze.analyze_session(decoded)["channels"]["air"]
        self.assertEqual(report["eligibleMarks"], 2)
        self.assertEqual(report["matchedDoubleTapMarks"], 2)
        self.assertEqual(report["recall"], 1)
        self.assertEqual(len(report["doubleEvents"]), 2)
        self.assertAlmostEqual(report["analyzedExposureSeconds"], 8 - 0.66)
        self.assertEqual(len(report["clickFeatures"]), 2)
        for feature in report["clickFeatures"]:
            self.assertGreater(feature["clickSnrDb"], 15)
            self.assertGreater(feature["transientEnergyFS2Seconds"], 0)

    def test_noise_and_speech_like_bursts_are_not_synthetic_clicks(self):
        for label, data in [("silence", synth()), ("talk", synth(bursts=[1, 1.4, 3, 3.4, 5]))]:
            with self.subTest(label=label):
                folder = save_pcm(self.root / label, data, manifest(label=label))
                report = analyze.analyze_session(decode.decode_session(folder))["channels"]["air"]
                self.assertEqual(report["falseTriggers"], 0)
                self.assertEqual(report["falseTriggersPerMinute"], 0)
                self.assertGreater(report["analyzedExposureSeconds"], 0)

    def test_double_rule_edges_refractory_and_nonreuse(self):
        for separation in (0.150, 0.300, 0.600):
            self.assertEqual(len(analyze.pair_events([1, 1 + separation])), 1)
        for separation in (0.149, 0.601):
            self.assertEqual(analyze.pair_events([1, 1 + separation]), [])
        self.assertEqual(len(analyze.pair_events([1, 1.3, 1.6])), 1)
        self.assertEqual(len(analyze.pair_events([1, 1.01, 1.3])), 1)
        segment = decode.Segment(0, synth(clicks=[2, 2.03, 2.3])[:, 0], 16000)
        events = analyze.detect_segment(segment)["onsets"]
        self.assertTrue(all(b - a >= analyze.REFRACTORY for a, b in zip(events, events[1:])))

    def test_one_to_one_maximum_matching(self):
        self.assertEqual(len(analyze.match_marks([1, 1.1], [1.05], 0.1)), 1)
        self.assertEqual(len(analyze.match_marks([1], [0.95, 1.05], 0.1)), 1)
        self.assertEqual(len(analyze.match_marks([1, 1.2], [0.9, 1.1], 0.15)), 2)
        self.assertEqual(analyze.match_marks([1], [1.351]), [])

    def test_late_audio_marks_and_actual_exposure(self):
        m = manifest(duration=10)
        m["marks"] = [{"timeSeconds": 1}, {"timeSeconds": 5.3}, {"timeSeconds": 9.9}]
        folder = save_pcm(self.root / "late", synth(duration=4, clicks=[1, 1.3]), m, start=4)
        decoded = decode.decode_session(folder)
        report = analyze.analyze_session(decoded)["channels"]["air"]
        self.assertEqual(report["eligibleMarks"], 1)
        self.assertEqual(len(report["excludedMarks"]), 2)
        self.assertEqual(report["matchedDoubleTapMarks"], 1)
        self.assertAlmostEqual(report["decodedSeconds"], 4)
        self.assertAlmostEqual(report["analyzedExposureSeconds"], 3.34)
        self.assertAlmostEqual(decoded.channels["air"][0].start, 4)

    def test_gaps_never_count_as_silence_or_pair_across_runs(self):
        segments = [decode.Segment(2, synth(duration=2, clicks=[1.85])[:, 0], 16000),
                    decode.Segment(4.1, synth(duration=2, clicks=[0.05])[:, 0], 16000)]
        report = analyze.analyze_channel(segments, [4.0], "double-tap")
        self.assertEqual(report["eligibleMarks"], 0)
        self.assertEqual(report["doubleEvents"], [])
        self.assertAlmostEqual(report["analyzedExposureSeconds"], 2 * (2 - 0.66))
        short = analyze.analyze_channel([decode.Segment(0, np.zeros(800), 16000)], [], "silence")
        self.assertEqual(short["analyzedExposureSeconds"], 0)
        self.assertIsNone(short["falseTriggersPerMinute"])

    def test_false_trigger_rate_uses_exposure_not_duration(self):
        m = manifest(label="chew", duration=30)
        folder = save_pcm(self.root / "negative", synth(duration=4, clicks=[1, 1.3]), m, start=10)
        report = analyze.analyze_session(decode.decode_session(folder))
        channel = report["channels"]["air"]
        self.assertEqual(channel["falseTriggers"], 1)
        self.assertAlmostEqual(channel["falseTriggersPerMinute"], 60 / 3.34)
        grouped = analyze.summarize([report])["synthetic"]["byChannel"]["air"]
        self.assertAlmostEqual(grouped["negatives"]["chew"]["falseTriggersPerMinute"], 60 / 3.34)
        self.assertIsNone(grouped["negatives"]["talk"]["falseTriggersPerMinute"])
        self.assertIsNone(grouped["recall"])

    def test_explicit_interleaving_and_no_sensor_pooling(self):
        m = manifest()
        m["audioFormat"]["channels"] = ["air", "vpu"]
        m["marks"] = [{"timeSeconds": 2.3}]
        air = synth()
        vpu = synth(clicks=[2, 2.3], seed=99)
        folder = save_pcm(self.root / "channels", np.c_[air, vpu], m)
        decoded = decode.decode_session(folder)
        self.assertTrue(decoded.report["independentVpuEstablished"])
        self.assertFalse(np.array_equal(decoded.channels["air"][0].samples,
                                        decoded.channels["vpu"][0].samples))
        report = analyze.analyze_session(decoded)
        summary = analyze.summarize([report])
        self.assertEqual(summary["real"]["byChannel"], {})
        grouped = summary["synthetic"]["byChannel"]
        self.assertEqual(grouped["air"]["recall"], 0)
        self.assertEqual(grouped["vpu"]["recall"], 1)
        self.assertNotIn("overall", grouped)

    def test_mask_cannot_make_invalid_lifelog_audio_decodable_or_establish_vpu(self):
        m = manifest(source="lifelog", synthetic=False)
        wire = envelope(bytes(240), 163, {"frameCount": 1, "vpuMask": 1, "vadMask": 1})
        decoded = decode.decode_session(self.put_wire(m, [wire]))
        self.assertFalse(decoded.report["independentVpuEstablished"])
        self.assertEqual(decoded.report["decodedPackets"], 0)
        self.assertEqual(decoded.report["undecodablePackets"], 1)
        self.assertTrue(any("TOC" in d for d in decoded.report["diagnostics"]))
        report = analyze.analyze_session(decoded)
        channel = report["channels"]["lifelog-mono-unassigned"]
        self.assertEqual(channel["analyzedExposureSeconds"], 0)
        self.assertIsNone(channel["recall"])

    def test_signed_mask_metadata_is_preserved_without_sensor_inference(self):
        m = manifest(source="lifelog", synthetic=False)
        wire = envelope(bytes(240), 163, {"vpuMask": -1, "vadMask": -1})
        decoded = decode.decode_session(self.put_wire(m, [wire]))
        self.assertFalse(decoded.report["independentVpuEstablished"])
        self.assertEqual(decoded.report["decodedPackets"], 0)
        self.assertFalse(any("disagrees" in d for d in decoded.report["diagnostics"]))

    def test_unknown_format_override_not_applied_to_capture(self):
        m = manifest(source="lifelog")
        m.pop("synthetic")
        decoded = decode.decode_session(self.put_wire(m, [envelope(bytes(240), 163)]))
        self.assertEqual(decoded.report["decodedPackets"], 0)
        self.assertTrue(any("override ignored" in d for d in decoded.report["diagnostics"]))

    def test_native_voice_baseline_and_arrival_gaps_are_not_loss(self):
        try:
            decoder = decode.OpusDecoder()
        except decode.SessionError:
            self.skipTest("local libopus unavailable")
        try:
            self.assertEqual(decoder.decode(b"\xf8\xff\xfe").shape, (320, 1))
        finally:
            decoder.close()
        m = manifest(duration=8, synthetic=False)
        m["droppedPackets"] = 2
        wires = [envelope(b"\xf8\xff\xfe", metadata={"vpuMask": 1})] * 4
        folder = self.put_wire(m, wires, [3.02, 3.04, 3.06, 4.02])
        decoded = decode.decode_session(folder)
        self.assertEqual(decoded.report["decodedPackets"], 4)
        self.assertEqual(len(decoded.channels["voice-mono-unassigned"]), 2)
        self.assertAlmostEqual(decoded.channels["voice-mono-unassigned"][0].start, 3)
        self.assertEqual(len(decoded.report["arrivalGaps"]), 1)
        self.assertEqual(decoded.report["knownLocalDroppedPackets"], 2)
        self.assertIsNone(decoded.report["networkLossPackets"])
        self.assertFalse(decoded.report["independentVpuEstablished"])

    def test_native_state_resets_before_even_modest_audio_gap(self):
        from unittest.mock import patch
        instances = []

        class FakeOpus:
            def __init__(self):
                instances.append(self)
                self.decoded = 0
                self.closed = False

            def sample_count(self, payload):
                return 320

            def decode(self, payload):
                self.decoded += 1
                return np.zeros((320, 1))

            def close(self):
                self.closed = True

        m = manifest(synthetic=False)
        folder = self.put_wire(m, [envelope(b"test")] * 3, [1.02, 1.10, 1.12])
        with patch.object(decode, "OpusDecoder", FakeOpus):
            decoded = decode.decode_session(folder)
        self.assertEqual(len(instances), 3)  # TOC inspector plus two decode runs
        self.assertEqual([d.decoded for d in instances], [0, 1, 2])
        self.assertTrue(all(d.closed for d in instances))
        self.assertEqual(len(decoded.channels["voice-mono-unassigned"]), 2)
        self.assertAlmostEqual(decoded.report["audioTimelineGaps"][0]["endSeconds"], 1.08)

    def test_native_voice_buffered_batches_preserve_all_audio_and_receipt_bounds(self):
        self.native_packets(count=1, samples=320)  # require native dependency, no fake decoder
        for pattern in ("equal", "within-batch-jitter", "batch-cadence-jitter"):
            with self.subTest(pattern=pattern):
                m = opus_manifest(duration=2.1, synthetic=False)
                arrivals = []
                for i in range(100):
                    jitter = 0
                    if pattern == "within-batch-jitter":
                        jitter = (i % 5) * 0.0005
                    elif pattern == "batch-cadence-jitter":
                        jitter = (0.004, 0.001, 0.003, 0)[(i // 5) % 4]
                    arrivals.append(0.1 * (i // 5 + 1) + jitter)
                wires = [envelope(b"\xf8\xff\xfe", metadata={"seq": i}) for i in range(100)]
                folder = self.put_wire(m, wires, arrivals, name=pattern)
                decoded = decode.decode_session(folder)
                self.assertEqual(decoded.report["decodedPackets"], 100)
                self.assertEqual(decoded.report["undecodablePackets"], 0)
                self.assertEqual(decoded.report["decodedFrames"], 100)
                segments = decoded.channels["voice-mono-unassigned"]
                self.assertEqual(len(segments), 1)
                self.assertEqual(len(segments[0].samples), 32000)
                self.assertAlmostEqual(segments[0].end - segments[0].start, 2)
                channel = analyze.analyze_session(decoded)["channels"]["voice-mono-unassigned"]
                self.assertAlmostEqual(channel["analyzedExposureSeconds"], 1.34)
                self.assertEqual(len(decoded.report["packetTiming"]), 100)
                for i, timing in enumerate(decoded.report["packetTiming"]):
                    self.assertEqual(timing["sampleCount"], 320)
                    self.assertLessEqual(timing["endSeconds"], arrivals[i] + 1e-12)
                    if i:
                        self.assertAlmostEqual(timing["startSeconds"],
                                               decoded.report["packetTiming"][i - 1]["endSeconds"])

    def test_native_lifelog_decodes_frames_sequentially_for_a3_and_a4(self):
        frames = self.native_packets(count=6, padded_size=240)
        m = opus_manifest(source="lifelog", duration=2)
        wires = [envelope(b"".join(frames[i:i + 3]), typ,
                          {"frameCount": 3, "vpuMask": -1, "vadMask": 5, "seq": 10 + i // 3})
                 for i, typ in ((0, 163), (3, 164))]
        decoded = decode.decode_session(self.put_wire(m, wires, [1.18, 1.36]))
        self.assertEqual(decoded.report["decodedPackets"], 2)
        self.assertEqual(decoded.report["decodedFrames"], 6)
        self.assertEqual(decoded.report["undecodablePackets"], 0)
        self.assertEqual(list(decoded.channels), ["lifelog-mono-unassigned"])
        self.assertFalse(decoded.report["independentVpuEstablished"])
        segments = decoded.channels["lifelog-mono-unassigned"]
        self.assertEqual(len(segments), 1)
        self.assertEqual(len(segments[0].samples), 5760)
        self.assertAlmostEqual(segments[0].start, 1, delta=1 / 16000)
        reference = decode.OpusDecoder()
        try:
            expected = np.concatenate([reference.decode(frame)[:, 0] for frame in frames])
        finally:
            reference.close()
        np.testing.assert_array_equal(segments[0].samples, expected)
        self.assertEqual(decoded.report["packetStateMetadata"][0]["vpuMask"], -1)
        self.assertEqual(decoded.report["packetStateMetadata"][1]["vadMask"], 5)
        self.assertEqual(decoded.report["codecProfile"]["configuredBitrate"], 32000)
        self.assertEqual(decoded.report["codecProfile"]["expectedFrameSeconds"], 0.060)
        self.assertEqual(analyze.summarize([analyze.analyze_session(decoded)])
                         ["real"]["sessionCount"], 0)

    def test_lifelog_batches_validate_lengths_counts_metadata_and_toc(self):
        frame = self.native_packets(count=1, padded_size=240)[0]
        wrong_duration = self.native_packets(count=1, samples=320, padded_size=240)[0]
        base = {"frameCount": 1, "vpuMask": 1, "vadMask": 1}
        cases = []
        for value in (None, 0, -1, True, 1.5, "1", 10**400, decode.MAX_LIFELOG_FRAMES + 1):
            meta = {**base, "frameCount": value}
            cases.append(("count-" + str(value)[:8], frame, meta, 163))
        cases += [("missing-count", frame, {"vpuMask": 1, "vadMask": 1}, 163),
                  ("short", frame[:-1], base, 163), ("long", frame + b"x", base, 164),
                  ("count-too-large", frame, {**base, "frameCount": 2}, 163),
                  ("count-too-small", frame * 2, base, 164),
                  ("empty", b"", base, 163), ("toc-20ms", wrong_duration, base, 163),
                  ("toc-stereo", bytes([frame[0] | 4]) + frame[1:], base, 164),
                  ("unknown-type", frame, base, 165),
                  ("missing-vpu", frame, {"frameCount": 1, "vadMask": 1}, 163),
                  ("missing-vad", frame, {"frameCount": 1, "vpuMask": 1}, 164),
                  ("mask-bool", frame, {**base, "vpuMask": True}, 163),
                  ("mask-overflow", frame, {**base, "vadMask": 2**64}, 164),
                  ("seq-bool", frame, {**base, "seq": True}, 163)]
        for i, (name, payload, metadata, typ) in enumerate(cases):
            with self.subTest(case=name):
                m = opus_manifest(source="lifelog")
                folder = self.put_wire(m, [envelope(payload, typ, metadata)], name=f"bad-{i}")
                # Invalid optional manifest values are session errors; corrupt
                # envelope-only metadata is an isolated packet diagnostic.
                for key in ("frameCount", "seq"):
                    m["packets"][0].pop(key, None)
                if not decode.integer(metadata.get("vpuMask"), -(2**63), 2**64 - 1):
                    m["packets"][0]["vpuMask"] = None
                if not decode.integer(metadata.get("vadMask"), -(2**63), 2**64 - 1):
                    m["packets"][0]["vadMask"] = None
                self.rewrite_manifest(folder, m)
                decoded = decode.decode_session(folder)
                self.assertEqual(decoded.report["decodedPackets"], 0)
                self.assertEqual(decoded.report["undecodablePackets"], 1)
                self.assertFalse(decoded.report["independentVpuEstablished"])
        for key, value in (("frameCount", 2), ("vpuMask", 0), ("vadMask", 0), ("seq", 4)):
            with self.subTest(mismatch=key):
                m = opus_manifest(source="lifelog")
                wire = envelope(frame, 163, {**base, "seq": 3})
                folder = self.put_wire(m, [wire], name="mismatch-" + key)
                m["packets"][0][key] = value
                self.rewrite_manifest(folder, m)
                decoded = decode.decode_session(folder)
                self.assertEqual(decoded.report["undecodablePackets"], 1)
                self.assertTrue(any("disagrees" in d for d in decoded.report["diagnostics"]))

    def test_lifelog_decode_error_excludes_whole_batch_and_resets_without_plc(self):
        good = self.native_packets(count=1, padded_size=240)[0]
        corrupt = b"\xfb\x03" + bytes(238)  # TOC says 60 ms, body is not valid Opus
        probe = decode.OpusDecoder()
        try:
            self.assertEqual(probe.sample_count(corrupt), 960)
            with self.assertRaises(decode.SessionError):
                probe.decode(corrupt)
        finally:
            probe.close()
        m = opus_manifest(source="lifelog", duration=2)
        wires = [envelope(payload, 163, {"frameCount": count, "vpuMask": 0, "vadMask": 1})
                 for payload, count in ((good, 1), (good + corrupt, 2), (good, 1))]
        decoded = decode.decode_session(self.put_wire(m, wires, [1.06, 1.18, 1.24]))
        self.assertEqual(decoded.report["decodedPackets"], 2)
        self.assertEqual(decoded.report["undecodablePackets"], 1)
        self.assertEqual(decoded.report["decodedFrames"], 2)
        segments = decoded.channels["lifelog-mono-unassigned"]
        self.assertEqual(len(segments), 2)
        self.assertEqual(sum(len(s.samples) for s in segments), 1920)
        self.assertAlmostEqual(segments[1].start - segments[0].end, 0.12)
        fresh = decode.OpusDecoder()
        try:
            np.testing.assert_array_equal(segments[1].samples, fresh.decode(good)[:, 0])
        finally:
            fresh.close()
        self.assertIsNone(decoded.report["networkLossPackets"])
        self.assertEqual(analyze.analyze_session(decoded)["channels"]
                         ["lifelog-mono-unassigned"]["analyzedExposureSeconds"], 0)

    def test_native_sequence_and_index_breaks_never_join_even_adjacent_audio(self):
        frame = self.native_packets(count=1, samples=320)[0]
        for kind in ("seq", "index"):
            with self.subTest(kind=kind):
                m = opus_manifest()
                wires = [envelope(frame, metadata={"seq": seq}) for seq in (0, 2)]
                if kind == "index":
                    wires = [envelope(frame)] * 2
                folder = self.put_wire(m, wires, [1.02, 1.04], name=kind)
                if kind == "index":
                    m["packets"][1]["index"] = 2
                    self.rewrite_manifest(folder, m)
                decoded = decode.decode_session(folder)
                self.assertEqual(decoded.report["decodedPackets"], 2)
                self.assertEqual(len(decoded.channels["voice-mono-unassigned"]), 2)
                field = "sequenceDiscontinuities" if kind == "seq" else "indexDiscontinuities"
                self.assertEqual(len(decoded.report[field]), 1)
                self.assertEqual(sum(len(s.samples) for s in
                                     decoded.channels["voice-mono-unassigned"]), 640)

    def test_native_lifelog_folder_zip_and_cli_outputs(self):
        frames = self.native_packets(count=24, padded_size=240)
        m = opus_manifest(source="lifelog", duration=2)
        wires = [envelope(b"".join(frames[i:i + 6]), 163 if i % 12 == 0 else 164,
                          {"frameCount": 6, "vpuMask": 21, "vadMask": 63, "seq": i // 6})
                 for i in range(0, len(frames), 6)]
        folder = self.put_wire(m, wires, [0.41 + i * 0.36 for i in range(4)])
        zipped = self.make_zip(entries={"export/" + name: (folder / name).read_bytes()
                                       for name in ("manifest.json", "envelopes.rnp")})
        folder_decoded, zip_decoded = decode.decode_session(folder), decode.decode_session(zipped)
        self.assertEqual(folder_decoded.report, zip_decoded.report)
        for i, path in enumerate((folder, zipped)):
            out = self.root / f"decoded-{i}"
            result = self.run_cli("decode.py", path, "--out", out)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((out / "decode.json").read_text())
            self.assertEqual(report["decodedPackets"], 4)
            self.assertEqual(report["decodedFrames"], 24)
            self.assertEqual(report["packetStateMetadata"][0]["vpuMask"], 21)
            with wave.open(str(out / "lifelog-mono-unassigned-000.wav")) as stream:
                self.assertEqual(stream.getnframes(), 23040)
                self.assertEqual(stream.getframerate(), 16000)
                self.assertEqual(stream.getnchannels(), 1)
        out = self.root / "analyzed"
        result = self.run_cli("analyze.py", zipped, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads((out / "report.json").read_text())
        self.assertEqual(report["summary"]["synthetic"]["sessionCount"], 1)
        self.assertEqual(report["summary"]["real"]["sessionCount"], 0)
        self.assertGreater(report["sessions"][0]["channels"]["lifelog-mono-unassigned"]
                           ["analyzedExposureSeconds"], 0)
        self.assertEqual((out / m["sessionId"] / "spectrogram.png").read_bytes()[:8],
                         b"\x89PNG\r\n\x1a\n")

    def test_passive_lifelog_manifest_limits_are_declared_and_bounded(self):
        m = opus_manifest(source="lifelog", duration=124.9)
        m["stopRequestLimitSeconds"], m["receiveLimitSeconds"] = 120, 125
        self.assertIs(decode.validate_manifest(m), m)
        for key, value in (("durationSeconds", 125.1), ("receiveLimitSeconds", 126),
                           ("stopRequestLimitSeconds", 125), ("receiveLimitSeconds", True)):
            with self.subTest(key=key):
                bad = dict(m)
                bad[key] = value
                with self.assertRaises(decode.SessionError):
                    decode.validate_manifest(bad)
        m["source"] = "voice"
        with self.assertRaises(decode.SessionError):
            decode.validate_manifest(m)
        m = opus_manifest(source="lifelog", duration=41)
        m["stopRequestLimitSeconds"], m["receiveLimitSeconds"] = 40, 45
        self.assertIs(decode.validate_manifest(m), m)  # honor shorter declared caps too

    def test_official_ogg_legacy_granules_use_toc_preskip_not_20ms_clock(self):
        frames = self.native_packets(count=60, padded_size=240)
        for legacy in (True, False):
            with self.subTest(legacy=legacy):
                folder, m = self.put_official(frames, name="legacy-" + str(legacy), legacy=legacy)
                original = (folder / m["officialDump"][0]["file"]).read_bytes()
                decoded = decode.decode_session(folder)
                row = decoded.report["officialDumps"][0]
                self.assertNotIn("error", row)
                self.assertEqual(row["decodedFrames"], 60)
                self.assertEqual(row["ogg"]["granuleMode"],
                                 "official-legacy-20ms" if legacy else "toc-correct")
                self.assertEqual(row["ogg"]["declaredChannels"], 2)
                self.assertEqual(row["alignment"]["method"], "event-wallclock")
                self.assertFalse(row["alignment"]["exactPacketTiming"])
                self.assertAlmostEqual(row["alignment"]["uncertaintySeconds"], 0.061)
                self.assertEqual(decoded.report["officialCounters"]["realtimePackets"]["delta"], 60)
                segments = decoded.channels["lifelog-mono-unassigned"]
                self.assertEqual(len(segments), 1)
                self.assertEqual(len(segments[0].samples), 60 * 960 - 104)
                reference = decode.OpusDecoder()
                try:
                    expected = np.concatenate([reference.decode(f)[:, 0] for f in frames])[104:]
                finally:
                    reference.close()
                np.testing.assert_array_equal(segments[0].samples, expected)
                self.assertAlmostEqual(row["decodedSeconds"], 3.6 - 104 / 16000)
                analyzed = analyze.analyze_session(decoded)["channels"]["lifelog-mono-unassigned"]
                self.assertEqual(analyzed["eligibleMarks"], 1)
                self.assertEqual(analyzed["recallStatus"], "available")
                self.assertEqual((folder / m["officialDump"][0]["file"]).read_bytes(), original)
                self.assertEqual(m["officialDump"][0]["alignment"], "unaligned")

    def test_official_timing_only_gap_preserves_logical_opus_stream_samples(self):
        frames = self.native_packets(count=40, padded_size=240)
        folder, m = self.put_official(frames, legacy=False)
        events = [json.loads(line) for line in (folder / "official-events.jsonl").read_text().splitlines()]
        for event in events[20:]:
            event["eventTs"] += 1000
        (folder / "official-events.jsonl").write_text("".join(json.dumps(e) + "\n" for e in events))
        decoded = decode.decode_session(folder)
        row = decoded.report["officialDumps"][0]
        self.assertEqual(row["alignment"]["method"], "event-wallclock")
        segments = decoded.channels["lifelog-mono-unassigned"]
        self.assertEqual(len(segments), 2)
        self.assertAlmostEqual(segments[1].start - segments[0].end, 1, delta=1 / 16000 + 1e-9)
        reference = decode.OpusDecoder()
        try:
            expected = np.concatenate([reference.decode(f)[:, 0] for f in frames])[104:]
        finally:
            reference.close()
        actual = np.concatenate([s.samples for s in segments])
        self.assertEqual(len(actual), 38296)
        np.testing.assert_array_equal(actual, expected)
        out = decode.new_output(self.root / "gap-output")
        decode.write_decoded(decoded, out)
        wav_pcm = []
        for segment in row["segments"]:
            with wave.open(str(out / segment["wav"])) as stream:
                wav_pcm.append(np.frombuffer(stream.readframes(stream.getnframes()), dtype="<i2"))
        np.testing.assert_array_equal(np.concatenate(wav_pcm), np.rint(expected * 32768).astype("<i2"))
        self.assertIsNone(decoded.report["networkLossPackets"])

    def test_official_overlapping_event_placement_downgrades_without_losing_samples(self):
        frames = self.native_packets(count=40, padded_size=240)
        folder, m = self.put_official(frames, legacy=False)
        wall = m["startWallMs"]
        events = [{"eventTs": wall + ms, "source": "realtime", "frameCount": 20}
                  for ms in (3000, 3100)]
        (folder / "official-events.jsonl").write_text("".join(json.dumps(e) + "\n" for e in events))
        m["officialCounters"][-1]["realtimePackets"] = 10002
        self.rewrite_manifest(folder, m)
        decoded = decode.decode_session(folder)
        row = decoded.report["officialDumps"][0]
        self.assertEqual(row["clock"], "file-local")
        self.assertIn("overlapping", row["alignment"]["associationRejected"])
        self.assertNotEqual(row["alignment"]["method"], "event-wallclock")
        segments = decoded.channels["lifelog-mono-unassigned"]
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0].start, 0)
        self.assertEqual(len(segments[0].samples), 38296)
        reference = decode.OpusDecoder()
        try:
            expected = np.concatenate([reference.decode(f)[:, 0] for f in frames])[104:]
        finally:
            reference.close()
        np.testing.assert_array_equal(segments[0].samples, expected)
        channel = analyze.analyze_session(decoded)["channels"]["lifelog-mono-unassigned"]
        self.assertIsNone(channel["recall"])
        self.assertEqual(channel["recallStatus"], "unavailable")
        self.assertAlmostEqual(channel["analyzedExposureSeconds"], len(expected) / 16000 - 0.66)

    def test_official_counter_activity_windows_must_agree_not_just_total_delta(self):
        frames = self.native_packets(count=60, padded_size=240)
        for mode in ("delayed-window", "wrong-window-counts", "matching-window-counts"):
            with self.subTest(mode=mode):
                folder, m = self.put_official(frames, name=mode)
                wall = m["startWallMs"]
                if mode == "delayed-window":
                    row = {"t": 5, "wallMs": wall + 5000, "realtimePackets": 10000,
                           "cachedPackets": 20000, "alwaysOnRunning": True}
                else:
                    row = {"t": 2.2, "wallMs": wall + 2200,
                           "realtimePackets": 10020 if mode == "matching-window-counts" else 10010,
                           "cachedPackets": 20000, "alwaysOnRunning": True}
                m["officialCounters"].insert(1, row)
                self.rewrite_manifest(folder, m)
                decoded = decode.decode_session(folder)
                alignment = decoded.report["officialDumps"][0]["alignment"]
                self.assertEqual(decoded.report["officialCounters"]["realtimePackets"]["delta"], 60)
                channel = analyze.analyze_session(decoded)["channels"]["lifelog-mono-unassigned"]
                if mode == "matching-window-counts":
                    self.assertEqual(alignment["method"], "event-wallclock")
                    self.assertEqual(channel["recallStatus"], "available")
                else:
                    self.assertNotEqual(alignment["method"], "event-wallclock")
                    self.assertIn("activity-window", alignment["associationRejected"])
                    self.assertIsNone(channel["recall"])
                    self.assertFalse(channel["markAlignmentAvailable"])
                    self.assertEqual(len(decoded.channels["lifelog-mono-unassigned"]), 1)
                    self.assertEqual(len(decoded.channels["lifelog-mono-unassigned"][0].samples), 57496)

    def test_official_ogg_continuation_and_rejection_of_corrupt_structure(self):
        frame = self.native_packets(count=1, padded_size=700)[0]
        head = b"OpusHead" + struct.pack("<BBHIhB", 1, 1, 312, 16000, 0, 0)
        prefix = ogg_page(head, [19], 2, 0, 0) + ogg_page(b"OpusTags", [8], 0, 1, 0)
        continued = (prefix + ogg_page(frame[:255], [255], 0, 2, 2**64 - 1)
                     + ogg_page(frame[255:], [255, 190], 5, 3, 1272))
        packets, counts, _ = decode.ogg_packets(continued)
        self.assertEqual(packets, [frame])
        self.assertEqual(counts, [960])
        valid = ogg_fixture([frame])
        corrupted = bytearray(valid)
        corrupted[-1] ^= 1
        cases = [bytes(corrupted), valid[:-1], valid + b"x", prefix,
                 prefix + ogg_page(frame, [255, 255, 190], 4, 2, 12345),
                 prefix + ogg_page(frame, [255, 255, 190], 0, 2, 1272),
                 prefix + ogg_page(frame, [255, 255, 190], 4, 9, 1272),
                 prefix + ogg_page(frame, [255, 255, 190], 5, 2, 1272),
                 prefix + ogg_page(frame, [255, 255, 190], 6, 2, 1272),
                 prefix + ogg_page(frame, [255, 255, 190], 4, 2, 1272, serial=999),
                 ogg_fixture([frame], pre_skip=65535)]
        for i, data in enumerate(cases):
            with self.subTest(case=i):
                with self.assertRaises(decode.SessionError):
                    decode.ogg_packets(data)

    def test_official_unanchored_events_and_counter_only_recall_unavailable(self):
        frames = self.native_packets(count=60, padded_size=240)
        for mode in ("epoch-seconds", "no-anchors", "no-counters"):
            with self.subTest(mode=mode):
                folder, m = self.put_official(frames, name=mode,
                    timestamps="epoch-seconds" if mode == "epoch-seconds" else "epoch-ms",
                    counters=mode != "no-counters")
                if mode == "no-anchors":
                    m.pop("startWallMs")
                    for row in m["officialCounters"]:
                        row.pop("wallMs")
                    self.rewrite_manifest(folder, m)
                decoded = decode.decode_session(folder)
                alignment = decoded.report["officialDumps"][0]["alignment"]
                self.assertIn(alignment["method"], ("counters-coarse", "none"))
                if alignment["method"] == "counters-coarse":
                    self.assertGreaterEqual(alignment["uncertaintySeconds"], 0.25 + 3.6 - 1e-9)
                channel = analyze.analyze_session(decoded)["channels"]["lifelog-mono-unassigned"]
                self.assertIsNone(channel["recall"])
                self.assertEqual(channel["recallStatus"], "unavailable")
                self.assertEqual(channel["eligibleMarks"], 0)
                self.assertFalse(channel["markAlignmentAvailable"])
                self.assertGreater(channel["analyzedExposureSeconds"], 0)
                if mode != "no-counters":
                    self.assertEqual(decoded.report["officialEvents"]["unanchoredCount"], 60)

    def test_official_lifelog_checks_inferred_duration_against_native_toc(self):
        frames = self.native_packets(count=5, samples=320, padded_size=240)
        folder, _ = self.put_official(frames, legacy=False)
        decoded = decode.decode_session(folder)
        self.assertEqual(decoded.report["officialDecodedFrames"], 0)
        self.assertIn("60-ms", decoded.report["officialDumps"][0]["error"])
        self.assertFalse(any(decoded.channels.values()))

    def test_official_counter_deltas_resets_and_event_mismatch_prevent_false_alignment(self):
        frames = self.native_packets(count=20, padded_size=240)
        for mode in ("counter-reset", "counter-mismatch", "frame-count-mismatch"):
            with self.subTest(mode=mode):
                folder, m = self.put_official(frames, name=mode)
                if mode == "counter-reset":
                    m["officialCounters"][-1]["realtimePackets"] = 1
                elif mode == "counter-mismatch":
                    m["officialCounters"][-1]["realtimePackets"] += 1
                else:
                    events = [json.loads(line) for line in
                              (folder / "official-events.jsonl").read_text().splitlines()]
                    events[0]["frameCount"] = 2
                    (folder / "official-events.jsonl").write_text(
                        "".join(json.dumps(e) + "\n" for e in events))
                self.rewrite_manifest(folder, m)
                decoded = decode.decode_session(folder)
                alignment = decoded.report["officialDumps"][0]["alignment"]
                self.assertNotEqual(alignment["method"], "event-wallclock")
                self.assertEqual(decoded.report["officialDecodedFrames"], 20)
                channel = analyze.analyze_session(decoded)["channels"]["lifelog-mono-unassigned"]
                self.assertIsNone(channel["recall"])
                self.assertFalse(channel["markAlignmentAvailable"])
                if mode == "counter-reset":
                    stats = decoded.report["officialCounters"]["realtimePackets"]
                    self.assertTrue(stats["resetObserved"])
                    self.assertIsNone(stats["delta"])

    def test_official_wallclock_drift_counts_toward_uncertainty_and_disables_recall(self):
        frames = self.native_packets(count=60, padded_size=240)
        folder, _ = self.put_official(frames, drift=1)
        decoded = decode.decode_session(folder)
        row = decoded.report["officialDumps"][0]
        self.assertNotIn("error", row)
        self.assertEqual(row["alignment"]["method"], "event-wallclock")
        self.assertEqual(row["alignment"]["anchorDriftSeconds"], 1)
        self.assertGreater(row["alignment"]["uncertaintySeconds"], 1)
        analyzed = analyze.analyze_session(decoded)["channels"]["lifelog-mono-unassigned"]
        self.assertIsNone(analyzed["recall"])
        self.assertEqual(analyzed["recallStatus"], "unavailable")
        self.assertFalse(analyzed["markAlignmentAvailable"])

    def test_official_cached_and_multiple_files_never_manufacture_session_exposure(self):
        frames = self.native_packets(count=20, padded_size=240)
        folder, m = self.put_official(frames, source_kind="cached")
        decoded = decode.decode_session(folder)
        self.assertEqual(decoded.report["officialDecodedFrames"], 20)
        self.assertEqual(decoded.report["officialDumps"][0]["alignment"]["method"], "none")
        self.assertFalse(any(decoded.channels.values()))
        self.assertFalse(decoded.report["independentVpuEstablished"])
        out = decode.new_output(self.root / "cached-output")
        decode.write_decoded(decoded, out)
        self.assertTrue((out / "official-000-lifelog-mono-unassigned-000.wav").exists())
        # Duplicate realtime files cannot each claim the same marks/exposure.
        folder, m = self.put_official(frames, name="multiple")
        item = dict(m["officialDump"][0])
        item["file"] = "official-dump/01-realtime.ogg"
        (folder / item["file"]).write_bytes((folder / m["officialDump"][0]["file"]).read_bytes())
        m["officialDump"].append(item)
        self.rewrite_manifest(folder, m)
        decoded = decode.decode_session(folder)
        self.assertEqual(decoded.report["officialDecodedFrames"], 40)
        self.assertFalse(any(decoded.channels.values()))
        self.assertTrue(all(r["alignment"]["method"] == "none" for r in decoded.report["officialDumps"]))

    def test_official_sidecar_integrity_allowlist_paths_and_huge_numbers(self):
        frames = self.native_packets(count=2, padded_size=240)
        for i, (key, value) in enumerate((("sha256", "0" * 64), ("bytes", 1),
                                          ("copyFinalized", False))):
            folder, m = self.put_official(frames, name=f"integrity-{i}")
            m["officialDump"][0][key] = value
            self.rewrite_manifest(folder, m)
            if key == "bytes":
                with self.assertRaises(decode.SessionError):
                    decode.decode_session(folder)  # declared read bound rejects before hashing
                continue
            decoded = decode.decode_session(folder)
            self.assertEqual(decoded.report["officialDecodedFrames"], 0)
            self.assertEqual(len(decoded.report["officialDumps"]), 1)
            self.assertIn("error", decoded.report["officialDumps"][0])
        for i, name in enumerate(("../escape.ogg", "/escape.ogg", "official-dump/../x.ogg",
                                  "official-dump/a/b.ogg", "official-dump/a\\b.ogg")):
            folder, m = self.put_official(frames, name=f"unsafe-{i}")
            m["officialDump"][0]["file"] = name
            self.rewrite_manifest(folder, m)
            with self.assertRaises(decode.SessionError):
                decode.decode_session(folder)
        folder, m = self.put_official(frames, name="symlink")
        (folder / "official-dump").rename(folder / "saved-dumps")
        (folder / "official-dump").symlink_to(folder / "saved-dumps", target_is_directory=True)
        with self.assertRaises(decode.SessionError):
            decode.decode_session(folder)
        for i, event in enumerate(({"eventTs": 1793275201000, "text": "not retained"},
                                    {"eventTs": 10**400}, {"frameCount": 10**400})):
            folder, _ = self.put_official(frames, name=f"events-{i}")
            (folder / "official-events.jsonl").write_text(json.dumps(event) + "\n")
            with self.assertRaises(decode.SessionError):
                decode.decode_session(folder)
        for i, field in enumerate(("startWallMs", "t", "wallMs", "realtimePackets")):
            folder, m = self.put_official(frames, name=f"anchor-{i}")
            if field == "startWallMs":
                m[field] = 10**400
            else:
                m["officialCounters"][0][field] = 10**400
            self.rewrite_manifest(folder, m)
            with self.assertRaises(decode.SessionError):
                decode.decode_session(folder)

    def test_official_empty_packets_folder_zip_cli_wav_png_and_combined_errors(self):
        frames = self.native_packets(count=60, padded_size=240)
        folder, m = self.put_official(frames)
        files = ["manifest.json", "envelopes.rnp", "official-events.jsonl", m["officialDump"][0]["file"]]
        zipped = self.make_zip(entries={"export/" + name: (folder / name).read_bytes() for name in files})
        self.assertEqual(decode.decode_session(folder).report, decode.decode_session(zipped).report)
        for i, path in enumerate((folder, zipped)):
            out = self.root / f"official-decode-{i}"
            result = self.run_cli("decode.py", path, "--out", out)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((out / "decode.json").read_text())
            self.assertEqual(report["decodedPackets"], 0)
            self.assertEqual(report["officialDecodedFrames"], 60)
            wav = out / report["officialDumps"][0]["segments"][0]["wav"]
            with wave.open(str(wav)) as stream:
                self.assertEqual(stream.getnframes(), 57496)
                self.assertEqual(stream.getframerate(), 16000)
                self.assertEqual(stream.getnchannels(), 1)
            self.assertEqual(stat.S_IMODE(wav.stat().st_mode), 0o600)
        out = self.root / "official-analysis"
        result = self.run_cli("analyze.py", zipped, "--out", out)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads((out / "report.json").read_text())
        self.assertEqual(report["summary"]["synthetic"]["sessionCount"], 1)
        self.assertEqual((out / m["sessionId"] / "spectrogram.png").read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        bad_folder, bad = self.put_official(frames, name="bad-sidecar")
        bad["officialDump"][0]["file"] = "../escape.ogg"
        self.rewrite_manifest(bad_folder, bad)
        out = self.root / "official-combined"
        result = self.run_cli("analyze.py", bad_folder, zipped, "--out", out)
        self.assertEqual(result.returncode, 2, result.stderr)
        report = json.loads((out / "report.json").read_text())
        self.assertEqual(len(report["errors"]), 1)
        self.assertEqual(len(report["sessions"]), 1)

    def test_bad_opus_is_diagnostic_not_plc(self):
        m = manifest(synthetic=False)
        decoded = decode.decode_session(self.put_wire(m, [envelope(bytes(5000))]))
        self.assertEqual(decoded.report["decodedPackets"], 0)
        self.assertEqual(decoded.report["undecodablePackets"], 1)

    def test_decode_wav_is_per_run_and_preserves_time(self):
        folder = save_pcm(self.root / "input", synth(duration=1), manifest(duration=6), start=3)
        decoded = decode.decode_session(folder)
        out = decode.new_output(self.root / "out")
        decode.write_decoded(decoded, out)
        with wave.open(str(out / "air-000.wav")) as stream:
            self.assertEqual(stream.getnchannels(), 1)
            self.assertEqual(stream.getframerate(), 16000)
            self.assertEqual(stream.getnframes(), 16000)
        self.assertEqual(decoded.report["channels"]["air"]["segments"][0]["startSeconds"], 3)
        self.assertEqual(stat.S_IMODE(out.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((out / "air-000.wav").stat().st_mode), 0o600)

    def test_manifest_invalid_values_and_noncanonical_time(self):
        for key, value in [("schemaVersion", True), ("label", []), ("clock", "wall-clock"),
                           ("durationSeconds", float("inf")), ("durationSeconds", 31),
                           ("stopPending", 0), ("receiveLimitSeconds", True),
                           ("createdAt", "2026-10-29T12:34:56"),
                           ("createdAt", "2026-02-30T12:34:56Z"),
                           ("sessionId", "../outside"), ("droppedPackets", -1),
                           ("marks", [{"timeSeconds": True}]),
                           ("marks", [{"timeSeconds": 20}]),
                           ("marks", [{"timeSeconds": 2}, {"timeSeconds": 1}])]:
            with self.subTest(key=key, value=value):
                m = manifest()
                m[key] = value
                with self.assertRaises(decode.SessionError):
                    decode.validate_manifest(m)
        for data in (b'{"a":1,"a":2}', b'{"a":NaN}', b'[]', b'\xff'):
            with self.assertRaises(decode.SessionError):
                decode.json_object(data)

    def test_huge_numeric_fields_are_validation_errors_not_float_overflow(self):
        for value in (10**400, -(10**400), float("inf"), float("-inf"), float("nan"), True):
            self.assertFalse(decode.number(value))
        required = ("schemaVersion", "durationSeconds", "stopRequestLimitSeconds",
                    "receiveLimitSeconds", "droppedPackets")
        packet_fields = ("index", "arrivalSeconds", "business", "type", "envelopeBytes",
                         "vpuMask", "vadMask", "seq", "frameCount", "audioStartSeconds")
        for field in (*required, "mark", *("packet." + key for key in packet_fields)):
            with self.subTest(field=field):
                m = manifest()
                m["packets"] = [{"index": 0, "arrivalSeconds": 1, "business": 13, "type": 3,
                                 "envelopeBytes": 10, "vpuMask": None, "vadMask": None}]
                if field == "mark":
                    m["marks"] = [{"timeSeconds": 10**400}]
                elif field.startswith("packet."):
                    m["packets"][0][field.split(".")[1]] = 10**400
                else:
                    m[field] = 10**400
                with self.assertRaises(decode.SessionError):
                    decode.validate_manifest(m)

    def test_huge_numeric_cli_errors_retain_valid_sessions(self):
        good = save_pcm(self.root / "valid", synth(duration=1), manifest(duration=2))
        bad_inputs = []
        for field in ("duration", "arrival", "mark", "audioStart"):
            m = manifest()
            folder = self.put_wire(m, [envelope(b"xx")], name="huge-" + field)
            if field == "duration":
                m["durationSeconds"] = 10**400
            elif field == "mark":
                m["marks"] = [{"timeSeconds": 10**400}]
            else:
                key = "arrivalSeconds" if field == "arrival" else "audioStartSeconds"
                m["packets"][0][key] = 10**400
            self.rewrite_manifest(folder, m)
            bad_inputs.append(folder)
            result = self.run_cli("decode.py", folder, "--out", self.root / ("out-" + field))
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("Traceback", result.stderr)
            self.assertNotIn("OverflowError", result.stderr)
        out = self.root / "combined-huge"
        result = self.run_cli("analyze.py", *bad_inputs, good, "--out", out)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        report = json.loads((out / "report.json").read_text())
        self.assertEqual(len(report["errors"]), 4)
        self.assertEqual(len(report["sessions"]), 1)
        self.assertEqual(report["summary"]["synthetic"]["sessionCount"], 1)
        self.assertGreater(report["sessions"][0]["channels"]["air"]["analyzedExposureSeconds"], 0)

    def test_zip_malformed_utf8_names_are_session_errors_and_cli_preserves_valid(self):
        good = save_pcm(self.root / "valid", synth(duration=1), manifest(duration=2))
        bad = []
        for mode in ("central", "local"):
            archive = self.make_zip(name=mode + ".zip", entries={
                name: (good / name).read_bytes() for name in ("manifest.json", "envelopes.rnp")})
            raw = bytearray(archive.read_bytes())
            if mode == "central":
                offset = raw.index(b"PK\x01\x02")
                flag_at, name_at = offset + 8, offset + 46
            else:
                offset = raw.index(b"PK\x03\x04")
                flag_at, name_at = offset + 6, offset + 30
            flags = struct.unpack_from("<H", raw, flag_at)[0]
            struct.pack_into("<H", raw, flag_at, flags | 0x800)
            raw[name_at] = 0xff
            archive.write_bytes(raw)
            bad.append(archive)
            with self.assertRaisesRegex(decode.SessionError, "invalid ZIP"):
                decode.read_input(archive)
            result = self.run_cli("decode.py", archive, "--out", self.root / ("out-" + mode))
            self.assertEqual(result.returncode, 2)
            self.assertIn("invalid ZIP", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
        out = self.root / "utf8-combined"
        result = self.run_cli("analyze.py", bad[0], good, bad[1], "--out", out)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        report = json.loads((out / "report.json").read_text())
        self.assertEqual(len(report["errors"]), 2)
        self.assertEqual(len(report["sessions"]), 1)
        self.assertGreater(report["sessions"][0]["channels"]["air"]["analyzedExposureSeconds"], 0)

    def test_json_exponent_overflow_rejects_nested_metadata_before_reporting(self):
        for body in (b'{"frameCount":1e400}', b'{"nested":{"values":[-1e400]}}',
                     b'{"nested":[[1e400]]}'):
            with self.subTest(body=body):
                with self.assertRaisesRegex(decode.SessionError, "non-finite JSON"):
                    decode.json_object(body)
        self.assertEqual(decode.json_object(b'{"finite":1e308}')["finite"], 1e308)
        good = save_pcm(self.root / "valid", synth(duration=1), manifest(duration=2))
        bad_packets = []
        for i, body in enumerate((b'{"frameCount":1e400}', b'{"nested":{"values":[-1e400]}}')):
            m = opus_manifest(synthetic=False)
            frame = b"\xf8\xff\xfe"
            folder = self.put_wire(m, [envelope(frame)], name=f"overflow-packet-{i}")
            wire = (b"\x08\x01\x10\x03\x1a" + varint(len(body)) + body
                    + b"\x22" + varint(len(frame)) + frame)
            m["packets"][0]["envelopeBytes"] = len(wire)
            (folder / "envelopes.rnp").write_bytes(struct.pack("<I", len(wire)) + wire)
            self.rewrite_manifest(folder, m)
            decoded = decode.decode_session(folder)
            self.assertEqual(decoded.report["decodedPackets"], 0)
            self.assertEqual(decoded.report["undecodablePackets"], 1)
            self.assertTrue(any("non-finite JSON" in d for d in decoded.report["diagnostics"]))
            result = self.run_cli("decode.py", folder, "--out", self.root / f"overflow-out-{i}")
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            bad_packets.append(folder)
        # Nested manifest metadata must fail parsing even when it is otherwise
        # an ignored extension; the serializer must never receive infinity.
        bad_manifest = self.put_wire(manifest(), [], name="overflow-manifest")
        path = bad_manifest / "manifest.json"
        path.write_text(path.read_text()[:-1] + ',"extra":{"value":1e400}}')
        out = self.root / "overflow-combined"
        result = self.run_cli("analyze.py", *bad_packets, bad_manifest, good, "--out", out)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        report = json.loads((out / "report.json").read_text(), parse_constant=lambda _: self.fail("non-finite output"))
        self.assertEqual(len(report["errors"]), 1)
        self.assertEqual(len(report["sessions"]), 3)
        self.assertTrue(any(s["channels"].get("air", {}).get("analyzedExposureSeconds", 0) > 0
                            for s in report["sessions"]))
        rejected_packets = [s for s in report["sessions"] if not s["synthetic"]]
        self.assertEqual(len(rejected_packets), 2)
        self.assertTrue(all(s["decode"]["decodedPackets"] == 0 for s in rejected_packets))
        for session in report["sessions"]:
            json.dumps(session, allow_nan=False)

    def test_corrupt_deflate_is_session_error_and_cli_preserves_valid_inputs(self):
        good = save_pcm(self.root / "valid", synth(duration=1), manifest(duration=2))
        bad_inputs = []
        for member in ("manifest.json", "envelopes.rnp"):
            archive = self.root / ("corrupt-" + member + ".zip")
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as z:
                for name in ("manifest.json", "envelopes.rnp"):
                    z.writestr(name, (good / name).read_bytes())
            with zipfile.ZipFile(archive) as z:
                info = z.getinfo(member)
                raw = bytearray(archive.read_bytes())
                name_len, extra_len = struct.unpack_from("<HH", raw, info.header_offset + 26)
                start = info.header_offset + 30 + name_len + extra_len
                raw[start] = (raw[start] & ~7) | 7  # forbidden deflate BTYPE=3
            archive.write_bytes(raw)
            bad_inputs.append(archive)
            with self.assertRaisesRegex(decode.SessionError, "invalid ZIP"):
                decode.read_input(archive)
            result = self.run_cli("decode.py", archive, "--out", self.root / ("out-" + member))
            self.assertEqual(result.returncode, 2)
            self.assertIn("invalid ZIP", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
        out = self.root / "combined-deflate"
        result = self.run_cli("analyze.py", bad_inputs[0], good, bad_inputs[1], "--out", out)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        report = json.loads((out / "report.json").read_text())
        self.assertEqual(len(report["errors"]), 2)
        self.assertTrue(all("invalid ZIP" in e["error"] for e in report["errors"]))
        self.assertEqual(len(report["sessions"]), 1)
        self.assertGreater(report["sessions"][0]["channels"]["air"]["analyzedExposureSeconds"], 0)
        self.assertTrue((out / report["sessions"][0]["sessionId"] / "air-000.wav").exists())

    def test_protobuf_unknown_fields_and_malformed_input(self):
        wire = envelope(b"audio", metadata={"vpuMask": 0})
        self.assertEqual(decode.parse_envelope(wire)[2], b"audio")
        unknown = b"\x28\x01\x31" + bytes(8) + b"\x3a\x01x\x45" + bytes(4)
        self.assertEqual(decode.parse_envelope(wire + unknown)[2], b"audio")
        for suffix in (b"\x08\x01", b"\x0a\x00", b"\x00", b"\x2b",
                       b"\x2a\x7f", b"\x28" + b"\x80" * 10,
                       b"\x28" + b"\xff" * 9 + b"\x02"):
            with self.subTest(suffix=suffix):
                with self.assertRaises(decode.SessionError):
                    decode.parse_envelope(wire + suffix)
        with self.assertRaises(decode.SessionError):
            decode.parse_envelope(wire + b"\x28\x00" * 257)

    def test_framing_truncation_and_manifest_file_disagreement(self):
        for raw in (b"\x01", struct.pack("<I", 0), struct.pack("<I", 2**31),
                    struct.pack("<I", 100) + b"x"):
            folder = self.root / str(len(list(self.root.iterdir())))
            folder.mkdir()
            m = manifest(synthetic=False)
            m["packets"] = [{"index": 0, "arrivalSeconds": 1, "business": 13, "type": 3,
                             "envelopeBytes": 10, "vpuMask": None, "vadMask": None}]
            (folder / "manifest.json").write_text(json.dumps(m))
            (folder / "envelopes.rnp").write_bytes(raw)
            with self.assertRaises(decode.SessionError):
                decode.decode_session(folder)
        folder = self.put_wire(manifest(synthetic=False), [envelope(b"123")])
        with (folder / "envelopes.rnp").open("ab") as f:
            f.write(b"extra")
        with self.assertRaises(decode.SessionError):
            decode.decode_session(folder)

    def test_manifest_packet_mismatch_diagnostic(self):
        m = manifest(synthetic=False)
        folder = self.put_wire(m, [envelope(b"123")])
        m["packets"][0]["type"] = 99
        self.rewrite_manifest(folder, m)
        decoded = decode.decode_session(folder)
        self.assertEqual(decoded.report["decodedPackets"], 0)
        self.assertTrue(any("disagrees" in d for d in decoded.report["diagnostics"]))

    def test_folder_symlink_and_fifo_rejected(self):
        m = manifest(synthetic=False)
        folder = self.put_wire(m, [])
        alias = self.root / "alias"
        alias.symlink_to(folder, target_is_directory=True)
        with self.assertRaises(decode.SessionError):
            decode.decode_session(alias)
        (folder / "envelopes.rnp").unlink()
        (folder / "envelopes.rnp").symlink_to(folder / "manifest.json")
        with self.assertRaises(OSError):
            decode.decode_session(folder)
        fifo = self.root / "fifo"
        os.mkfifo(fifo)
        with self.assertRaises(decode.SessionError):
            decode.bounded_file(fifo, 1024)

    def test_zip_valid_wrapped_session_and_unsafe_names(self):
        folder = save_pcm(self.root / "input", synth(duration=1), manifest(duration=2))
        entries = {"export/session/" + name: (folder / name).read_bytes()
                   for name in ("manifest.json", "envelopes.rnp")}
        zipped = self.make_zip(entries=entries)
        self.assertEqual(decode.decode_session(zipped).report["decodedPackets"], 20)
        for i, name in enumerate(("../escape", "/escape", "x/../escape", "C:/escape",
                                  "x\\escape", "./escape", "x//escape")):
            with self.subTest(name=name):
                with self.assertRaises(decode.SessionError):
                    decode.read_input(self.make_zip(f"bad{i}.zip", {**entries, name: b"x"}))

    def test_zip_symlink_duplicate_multiple_sessions_and_bomb(self):
        for kind in ("symlink", "duplicate", "multiple", "bomb", "many"):
            archive = self.root / f"{kind}.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("manifest.json", b"{}")
                z.writestr("envelopes.rnp", b"")
                if kind == "symlink":
                    entry = zipfile.ZipInfo("link")
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    z.writestr(entry, "target")
                elif kind == "duplicate":
                    import warnings
                    with warnings.catch_warnings():
                        warnings.simplefilter("ignore")
                        z.writestr("manifest.json", b"{}")
                elif kind == "multiple":
                    z.writestr("other/manifest.json", b"{}")
                elif kind == "bomb":
                    z.writestr("bomb", bytes(1024 * 1024), compress_type=zipfile.ZIP_DEFLATED)
                else:
                    for i in range(256):
                        z.writestr(f"sidecar-{i}", b"")
            with self.subTest(kind=kind):
                with self.assertRaises(decode.SessionError):
                    decode.read_input(archive)

    def test_oversized_input_rejected_before_read(self):
        path = self.root / "huge"
        with path.open("wb") as stream:
            stream.truncate(decode.MAX_ARCHIVE + 1)
        with self.assertRaises(decode.SessionError):
            decode.read_input(path)

    def test_cli_end_to_end_png_json_and_duplicate_protection(self):
        m = manifest()
        m["marks"] = [{"timeSeconds": 2.3}]
        folder = save_pcm(self.root / "input", synth(clicks=[2, 2.3]), m)
        out = self.root / "analysis"
        command = [sys.executable, "-I", "-B", str(ROOT / "analyze.py"),
                   str(folder), "--out", str(out)]
        result = subprocess.run(command, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads((out / "report.json").read_text())
        self.assertEqual(report["summary"]["synthetic"]["sessionCount"], 1)
        self.assertEqual(report["summary"]["real"]["sessionCount"], 0)
        image = out / m["sessionId"] / "spectrogram.png"
        self.assertEqual(image.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        duplicate_out = self.root / "duplicate"
        result = subprocess.run(
            [sys.executable, "-I", "-B", str(ROOT / "analyze.py"), str(folder), str(folder),
             "--out", str(duplicate_out)], text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 2)
        report = json.loads((duplicate_out / "report.json").read_text())
        self.assertEqual(len(report["sessions"]), 1)
        self.assertIn("duplicate sessionId", report["errors"][0]["error"])
        result = subprocess.run(command, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 2)  # never overwrite prior output


if __name__ == "__main__":
    unittest.main(verbosity=2)
