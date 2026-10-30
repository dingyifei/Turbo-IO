#!/usr/bin/env python3
"""Bounded, local-only Clench Lab envelope decoder. See README.md for assumptions."""
from __future__ import annotations

import argparse
import ctypes
import ctypes.util
from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
import uuid
import wave
import zipfile
import zlib

import numpy as np

MAX_MANIFEST = 4 * 1024 * 1024
MAX_RAW = 16 * 1024 * 1024
MAX_ARCHIVE = 96 * 1024 * 1024
MAX_DUMPS = 64 * 1024 * 1024
MAX_EVENTS = 16 * 1024 * 1024
MAX_ENVELOPE = 1024 * 1024
MAX_PACKETS = 4096
LABELS = {"double-tap", "single-tap", "true-clench", "chew", "talk",
          "walk", "tap-temple", "silence"}
ARRIVAL_TOLERANCE = 0.050
BATCH_ARRIVAL_TOLERANCE = 0.005
LIFELOG_FRAME_BYTES = 240
MAX_LIFELOG_FRAMES = 65536 // LIFELOG_FRAME_BYTES


class SessionError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise SessionError(message)


def integer(value, low=0, high=2**32 - 1):
    return type(value) is int and low <= value <= high


def number(value, low=0, high=30):
    return (type(value) in (int, float) and low <= value <= high
            and math.isfinite(value))


def json_object(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result
    def finite_float(token):
        value = float(token)
        require(math.isfinite(value), "non-finite JSON number (exponent overflow)")
        return value

    try:
        value = json.loads(data, object_pairs_hook=unique, parse_float=finite_float,
                           parse_constant=lambda _: (_ for _ in ()).throw(
                               SessionError("non-finite JSON number")))
        require(isinstance(value, dict), "expected JSON object")
        return value
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise SessionError(f"invalid JSON: {exc}") from exc


def bounded_file(path, limit, dir_fd=None):
    # No symlinks, FIFOs, sockets, or devices, including a replacement at open.
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    fd = os.open(path, flags, dir_fd=dir_fd)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode), "input must be a regular file")
        require(info.st_size <= limit, "input exceeds size limit")
        data = stream.read(limit + 1)
        require(len(data) <= limit, "input grew beyond size limit")
        return data


def sidecar_specs(m):
    dumps = m.get("officialDump", [])
    require(isinstance(dumps, list) and len(dumps) <= 64, "invalid officialDump")
    names, total = {}, 0
    for item in dumps:
        require(isinstance(item, dict), "invalid officialDump entry")
        name = item.get("file")
        require(isinstance(name, str) and bool(re.fullmatch(
            r"official-dump/[A-Za-z0-9_-][A-Za-z0-9_.-]*\.(?:ogg|opus)", name))
            and ".." not in name, "unsafe official dump path")
        require(name not in names, "duplicate official dump")
        require(item.get("sourceKind") in ("realtime", "cached", "unverified"),
                "invalid official dump sourceKind")
        require(integer(item.get("bytes"), 1, MAX_DUMPS), "invalid official dump bytes")
        require(isinstance(item.get("sha256"), str)
                and bool(re.fullmatch(r"[0-9a-fA-F]{64}", item["sha256"])),
                "invalid official dump sha256")
        require(type(item.get("copyFinalized")) is bool, "invalid copyFinalized")
        require(item.get("alignment") == "unaligned", "official dump alignment must be unaligned")
        total += item["bytes"]
        require(total <= MAX_DUMPS, "official dumps exceed 64 MiB")
        names[name] = item["bytes"]
    events = m.get("officialEvents")
    if events is not None:
        require(isinstance(events, dict), "invalid officialEvents")
        if events.get("state") == "attached":
            require(events.get("file") == "official-events.jsonl", "unsafe official events path")
            names["official-events.jsonl"] = MAX_EVENTS
    return names


def read_input(path, sidecars=False):
    path = Path(path)
    require(not path.is_symlink(), "session path must not be a symlink")
    if path.is_dir():
        root_fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        dump_fd = None
        try:
            manifest = bounded_file("manifest.json", MAX_MANIFEST, dir_fd=root_fd)
            raw = bounded_file("envelopes.rnp", MAX_RAW, dir_fd=root_fd)
            if not sidecars:
                return manifest, raw
            specs = sidecar_specs(json_object(manifest))
            extras = {}
            if any(name.startswith("official-dump/") for name in specs):
                folder = path / "official-dump"
                require(not folder.is_symlink() and folder.is_dir(), "unsafe official dump directory")
                dump_fd = os.open("official-dump", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                  dir_fd=root_fd)
            for name, limit in specs.items():
                if name.startswith("official-dump/"):
                    extras[name] = bounded_file(PurePosixPath(name).name, limit, dir_fd=dump_fd)
                else:
                    extras[name] = bounded_file(name, limit, dir_fd=root_fd)
            return manifest, raw, extras
        finally:
            if dump_fd is not None:
                os.close(dump_fd)
            os.close(root_fd)
    # Keep the archive itself bounded before zipfile constructs its directory.
    import io
    archive = bounded_file(path, MAX_ARCHIVE)
    try:
        with zipfile.ZipFile(io.BytesIO(archive)) as z:
            entries = z.infolist()
            require(len(entries) <= 256, "too many ZIP entries")
            names, total = set(), 0
            for entry in entries:
                name = entry.filename
                require(entry.orig_filename == name, "ZIP filename normalization rejected")
                require(name and "\\" not in name and "\x00" not in name
                        and not name.startswith("/") and ":" not in name
                        and all(p not in ("..", ".") for p in name.rstrip("/").split("/"))
                        and "//" not in name, "unsafe ZIP path")
                require(name not in names, "duplicate ZIP entry")
                names.add(name)
                mode = entry.external_attr >> 16
                require(not stat.S_ISLNK(mode), "ZIP symlink rejected")
                require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR),
                        "special ZIP entry rejected")
                require(not entry.flag_bits & 1, "encrypted ZIP rejected")
                require(entry.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
                        "unsupported ZIP compression")
                total += entry.file_size
                require(entry.file_size <= MAX_DUMPS and total <= MAX_ARCHIVE,
                        "ZIP expansion exceeds limit")
                require(entry.file_size <= max(1, entry.compress_size) * 200,
                        "ZIP compression ratio exceeds limit")
            candidates = [e for e in entries if PurePosixPath(e.filename).name
                          == "manifest.json" and not e.is_dir()]
            require(len(candidates) == 1, "ZIP must contain exactly one session manifest")
            manifest = candidates[0]
            prefix = manifest.filename[:-len("manifest.json")]
            raw_name = prefix + "envelopes.rnp"
            require(raw_name in names, "ZIP session has no envelopes.rnp")
            require(manifest.file_size <= MAX_MANIFEST, "manifest exceeds limit")

            def read_member(name, limit):
                with z.open(name) as stream:
                    data = stream.read(limit + 1)
                    require(len(data) <= limit, "ZIP member exceeds read limit")
                    return data
            manifest_bytes = read_member(manifest.filename, MAX_MANIFEST)
            raw = read_member(raw_name, MAX_RAW)
            if not sidecars:
                return manifest_bytes, raw
            specs = sidecar_specs(json_object(manifest_bytes))
            extras = {}
            for name, limit in specs.items():
                require(prefix + name in names, "missing official sidecar")
                extras[name] = read_member(prefix + name, limit)
            return manifest_bytes, raw, extras
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError, zlib.error, UnicodeError) as exc:
        raise SessionError(f"invalid ZIP: {exc}") from exc


def validate_manifest(m):
    require(type(m.get("schemaVersion")) is int and m["schemaVersion"] == 1,
            "unsupported schemaVersion")
    try:
        require(isinstance(m.get("sessionId"), str), "missing sessionId")
        uuid.UUID(m["sessionId"])
    except (ValueError, AttributeError) as exc:
        raise SessionError("invalid sessionId UUID") from exc
    require(m.get("source") in ("voice", "lifelog"), "invalid source")
    require(isinstance(m.get("label"), str) and m["label"] in LABELS, "invalid label")
    created = m.get("createdAt")
    require(isinstance(created, str) and bool(re.fullmatch(
        r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|\+00:00)", created)),
        "createdAt must be ISO8601 UTC")
    try:
        datetime.fromisoformat(created.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SessionError("invalid createdAt") from exc
    for key in ("appVersion", "appCommit"):
        require(isinstance(m.get(key), str) and bool(m[key].strip()), f"missing {key}")
    require(m.get("clock") == "monotonic-seconds-from-session-start", "unsupported clock")
    maximum = 125 if m["source"] == "lifelog" else 30
    require(number(m.get("receiveLimitSeconds"), 1, maximum), "invalid receiveLimitSeconds")
    require(number(m.get("stopRequestLimitSeconds"), 1,
                   min(m["receiveLimitSeconds"], 120 if m["source"] == "lifelog" else 25))
            and m["stopRequestLimitSeconds"] < m["receiveLimitSeconds"],
            "invalid stopRequestLimitSeconds")
    require(number(m.get("durationSeconds"), 0, m["receiveLimitSeconds"]),
            "invalid durationSeconds (exceeds declared receive limit)")
    for key in ("stopPending", "offObserved"):
        require(type(m.get(key)) is bool, f"invalid {key}")
    require(integer(m.get("droppedPackets")), "invalid droppedPackets")
    duration = m["durationSeconds"]
    require(isinstance(m.get("marks"), list) and len(m["marks"]) <= 4096, "invalid marks")
    last = -1.0
    for mark in m["marks"]:
        require(isinstance(mark, dict) and number(mark.get("timeSeconds"), 0, duration),
                "invalid mark timeSeconds")
        require(mark["timeSeconds"] >= last, "marks not in monotonic order")
        last = mark["timeSeconds"]
    require(isinstance(m.get("packets"), list) and len(m["packets"]) <= MAX_PACKETS,
            "invalid packets")
    last_index, last_time = -1, -1.0
    for p in m["packets"]:
        require(isinstance(p, dict), "invalid packet metadata")
        require(integer(p.get("index")) and p["index"] > last_index, "invalid packet index order")
        require(number(p.get("arrivalSeconds"), 0, duration)
                and p["arrivalSeconds"] >= last_time, "invalid packet arrivalSeconds")
        require(integer(p.get("business"), 0, 255) and integer(p.get("type")),
                "invalid business/type")
        require(integer(p.get("envelopeBytes"), 1, MAX_ENVELOPE), "invalid envelopeBytes")
        for key in ("vpuMask", "vadMask"):
            require(key in p and (p[key] is None or integer(p[key], -(2**63), 2**64 - 1)),
                    f"invalid {key}")
        for key, high in (("seq", 2**32 - 1), ("frameCount", MAX_LIFELOG_FRAMES)):
            require(key not in p or integer(p[key], 0, high), f"invalid packet {key}")
        require("audioStartSeconds" not in p or number(p["audioStartSeconds"], 0, duration),
                "invalid packet audioStartSeconds")
        last_index, last_time = p["index"], p["arrivalSeconds"]
    require("synthetic" not in m or type(m["synthetic"]) is bool, "invalid synthetic flag")
    return m


def parse_envelope(packet):
    """Port of BusinessEnvelopeMetadata.inspect's bounded protobuf rules."""
    require(0 < len(packet) <= MAX_ENVELOPE, "invalid envelope size")
    offset, fields, known = 0, 0, {}

    def varint():
        nonlocal offset
        value = 0
        for i in range(10):
            require(offset < len(packet), "truncated protobuf varint")
            byte = packet[offset]
            offset += 1
            require(i != 9 or byte <= 1, "protobuf varint overflow")
            value |= (byte & 127) << (i * 7)
            if byte < 128:
                return value
        raise SessionError("protobuf varint overflow")

    def take(length):
        nonlocal offset
        require(length <= len(packet) - offset, "truncated protobuf field")
        result = packet[offset:offset + length]
        offset += length
        return result

    while offset < len(packet):
        fields += 1
        require(fields <= 256, "too many protobuf fields")
        tag = varint()
        field, wire = tag >> 3, tag & 7
        require(0 < field <= 0x1fffffff, "invalid protobuf field")
        if field <= 4:
            require(field not in known, "duplicate protobuf singular field")
            require(wire == (0 if field <= 2 else 2), "wrong protobuf wire type")
            value = varint() if wire == 0 else take(varint())
            require(field > 2 or value <= 0xffffffff, "protobuf scalar overflow")
            known[field] = value
        elif wire == 0:
            varint()
        elif wire in (1, 5):
            take(8 if wire == 1 else 4)
        elif wire == 2:
            take(varint())
        else:
            raise SessionError("unsupported protobuf wire type")
    require(known.get(1) == 1 and 2 in known, "unsupported envelope version/missing type")
    require(len(known.get(3, b"")) <= 65536 and len(known.get(4, b"")) <= 65536,
            "business payload exceeds limit")
    return known[2], json_object(known[3]) if known.get(3) else {}, known.get(4, b"")


class OpusDecoder:
    """Only native libopus already installed locally. Never downloads or invokes a shell."""
    def __init__(self):
        candidates = [ctypes.util.find_library("opus"),
                      "/opt/homebrew/lib/libopus.dylib", "/usr/local/lib/libopus.dylib"]
        self.lib = None
        for name in candidates:
            if not name:
                continue
            try:
                self.lib = ctypes.CDLL(name)
                break
            except OSError:
                pass
        require(self.lib is not None, "local libopus unavailable; native Opus remains undecodable")
        lib = self.lib
        lib.opus_decoder_create.argtypes = [ctypes.c_int32, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
        lib.opus_decoder_create.restype = ctypes.c_void_p
        lib.opus_decoder_destroy.argtypes = [ctypes.c_void_p]
        lib.opus_decoder_destroy.restype = None
        lib.opus_packet_get_nb_samples.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32]
        lib.opus_packet_get_nb_samples.restype = ctypes.c_int
        lib.opus_packet_get_nb_channels.argtypes = [ctypes.c_char_p]
        lib.opus_packet_get_nb_channels.restype = ctypes.c_int
        lib.opus_decode.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int32,
                                   ctypes.POINTER(ctypes.c_int16), ctypes.c_int, ctypes.c_int]
        lib.opus_decode.restype = ctypes.c_int
        error = ctypes.c_int()
        self.state = lib.opus_decoder_create(16000, 1, ctypes.byref(error))
        require(self.state and error.value == 0, "libopus decoder creation failed")

    def close(self):
        if self.state:
            self.lib.opus_decoder_destroy(self.state)
            self.state = None

    def sample_count(self, payload):
        require(0 < len(payload) <= 4096, "invalid Opus packet size")
        require(self.lib.opus_packet_get_nb_channels(payload) == 1,
                "Opus TOC disagrees with mono profile")
        count = self.lib.opus_packet_get_nb_samples(payload, len(payload), 16000)
        require(0 < count <= 1920 and count % 160 == 0,
                "unsupported Opus duration (expected 10–120 ms)")
        return count

    def decode(self, payload):
        count = self.sample_count(payload)
        pcm = (ctypes.c_int16 * 1920)()
        result = self.lib.opus_decode(self.state, payload, len(payload), pcm, 1920, 0)
        require(result == count, "libopus packet decode failed")
        return np.ctypeslib.as_array(pcm)[:count].astype(np.float64)[:, None] / 32768


@dataclass
class Segment:
    start: float
    samples: np.ndarray
    rate: int
    aligned: bool = True
    uncertainty: float = 0.0

    @property
    def end(self):
        return self.start + len(self.samples) / self.rate


@dataclass
class Decoded:
    manifest: dict
    channels: dict[str, list[Segment]]
    report: dict
    official_audio: list | None = None


def synthetic_format(m):
    f = m.get("audioFormat")
    require(isinstance(f, dict) and f.get("provenance") == "synthetic",
            "synthetic fixtures require explicit audioFormat provenance")
    if f.get("codec") == "opus":
        channel = m["source"] + "-mono-unassigned"
        require(f.get("layout") == "mono" and f.get("channels") == [channel]
                and type(f.get("sampleRate")) is int and f["sampleRate"] == 16000,
                "synthetic Opus must use the bounded native mono 16 kHz profile")
        return [channel], 16000
    require(f.get("codec") == "pcm_s16le" and f.get("layout") == "interleaved",
            "synthetic PCM requires explicit interleaved s16le audioFormat")
    channels, rate = f.get("channels"), f.get("sampleRate")
    allowed = {"air", "vpu", "channel-0", "channel-1", "channel-2", "channel-3"}
    require(isinstance(channels, list) and 1 <= len(channels) <= 4
            and all(isinstance(c, str) and c in allowed for c in channels)
            and len(set(channels)) == len(channels), "invalid synthetic channels")
    require(integer(rate, 12000, 48000), "invalid synthetic sampleRate")
    return channels, rate


def native_timing(entries, rate):
    """Plan before decoding: a receipt burst is not a source-time discontinuity.

    Each <=5-ms burst is back-anchored by ALL its packet receipt constraints.
    Adjacent bursts join only within the 50-ms cadence tolerance. A joined run
    can move earlier (never later than any receipt constraint). No samples or
    durations are invented; index/sequence/parser boundaries are never joined.
    Integer sample ticks avoid accumulating floating-point duration error.
    """
    batches = []
    for entry in entries:
        arrival = entry["packet"]["arrivalSeconds"]
        if (not batches or entry["boundary"]
                or arrival - batches[-1][0]["packet"]["arrivalSeconds"]
                > BATCH_ARRIVAL_TOLERANCE + 1e-9):
            batches.append([])
        batches[-1].append(entry)
    runs = []
    for batch in batches:
        count, anchor = 0, None
        for entry in batch:
            count += entry["count"]
            receipt_tick = math.floor(entry["packet"]["arrivalSeconds"] * rate)
            constraint = receipt_tick - count
            anchor = constraint if anchor is None else min(anchor, constraint)
        boundary = batch[0]["boundary"] or not runs
        if not boundary:
            previous = runs[-1]
            delta = anchor - (previous["start"] + previous["count"])
            boundary = abs(delta) > round(ARRIVAL_TOLERANCE * rate)
        if boundary:
            runs.append({"start": anchor, "count": count, "entries": list(batch)})
        else:
            # Shifting the complete buffered run preserves every earlier receipt
            # constraint, unlike advancing a per-packet clock past its arrival.
            previous["start"] = min(previous["start"], anchor - previous["count"])
            previous["count"] += count
            previous["entries"].extend(batch)
    for run in runs:
        tick = run["start"]
        for i, entry in enumerate(run["entries"]):
            entry["start"] = tick / rate
            entry["boundary"] = i == 0
            tick += entry["count"]


def native_frames(source, typ, metadata, payload, packet):
    if source == "voice":
        require(typ == 3, "undecodable: unsupported voice audio type/profile")
        return [payload]
    require(typ in (163, 164), "undecodable: unsupported LifeLog audio type/profile")
    count = metadata.get("frameCount")
    require(integer(count, 1, MAX_LIFELOG_FRAMES), "invalid LifeLog frameCount")
    require(len(payload) == count * LIFELOG_FRAME_BYTES,
            "LifeLog payload length must equal frameCount * 240")
    if "frameCount" in packet:
        require(integer(packet["frameCount"], 1, MAX_LIFELOG_FRAMES)
                and packet["frameCount"] == count,
                "manifest frameCount disagrees with envelope")
    for mask in ("vpuMask", "vadMask"):
        require(integer(metadata.get(mask), -(2**63), 2**64 - 1),
                f"LifeLog requires 64-bit {mask} state metadata")
    return [payload[i:i + LIFELOG_FRAME_BYTES]
            for i in range(0, len(payload), LIFELOG_FRAME_BYTES)]


def decode_session(path):
    manifest_bytes, raw, extras = read_input(path, sidecars=True)
    m = validate_manifest(json_object(manifest_bytes))
    synthetic = m.get("synthetic", False)
    channels, rate = (synthetic_format(m) if synthetic else
                      ([m["source"] + "-mono-unassigned"], 16000))
    explicit_pcm = synthetic and m["audioFormat"]["codec"] == "pcm_s16le"
    report = {
        "sessionId": m["sessionId"], "source": m["source"], "label": m["label"],
        "capture": {key: m[key] for key in ("createdAt", "appVersion", "appCommit", "clock",
            "durationSeconds", "stopRequestLimitSeconds", "receiveLimitSeconds",
            "stopPending", "offObserved")},
        "synthetic": synthetic, "diagnostics": [], "arrivalGaps": [],
        "indexDiscontinuities": [], "sequenceDiscontinuities": [],
        "knownLocalDroppedPackets": m["droppedPackets"], "networkLossPackets": None,
        "audioTimelineGaps": [], "decodedPackets": 0, "undecodablePackets": 0,
        "decodedFrames": 0, "packetTiming": [], "packetStateMetadata": [],
        "timing": ("explicit synthetic audioStartSeconds" if explicit_pcm else
                   "batch-aware receipt-constrained sample clock; not source timestamps"),
        "arrivalJitterToleranceSeconds": ARRIVAL_TOLERANCE,
        "receiptBatchToleranceSeconds": BATCH_ARRIVAL_TOLERANCE,
        "independentVpuEstablished": bool(explicit_pcm and "vpu" in channels),
        "codecProfile": ({"codec": "pcm_s16le", "provenance": "synthetic"}
                         if explicit_pcm else {
            "codec": "opus", "sampleRate": 16000, "channels": 1,
            "provenance": "static/source-supported baseline; no real-capture validation",
            "evidence": "Lane R re-audio.md sections 1 and 3; existing voice decoder",
            "configuredBitrate": 32000 if m["source"] == "lifelog" else None,
            "frameBytes": LIFELOG_FRAME_BYTES if m["source"] == "lifelog" else None,
            "expectedFrameSeconds": 0.060 if m["source"] == "lifelog" else None,
            "durationValidation": "each packet TOC and native decode, not byte-count inference",
        }),
    }
    diagnostics = report["diagnostics"]
    if m.get("audioFormat") is not None and not synthetic:
        diagnostics.append("Capture audioFormat override ignored: only bounded evidenced profiles are used.")
    if m["appCommit"].strip().lower() in {"unknown", "unset", "development", "dirty", "n/a"}:
        diagnostics.append("appCommit provenance is unresolved.")
    if not explicit_pcm:
        diagnostics.append("Mono output is sensor-unassigned, not an independent air/VPU channel. "
                           "vpuMask/vadMask are state metadata only.")
        diagnostics.append("Source timestamps and transport/buffering latency are unknown; "
                           "mark alignment is approximate. No real capture validated this profile.")
    output = {c: [] for c in channels}
    offset, previous_arrival, previous_index, previous_seq = 0, None, None, None
    boundary, decoder = True, None
    entries, runs = [], []

    def fail_audio(index, message):
        nonlocal boundary
        report["undecodablePackets"] += 1
        diagnostics.append(f"packet {index}: {message}")
        boundary = True

    try:
        # Validate framing/metadata and inspect durations before assigning times.
        # This buffers only bounded packet data, not unbounded decoded PCM.
        for p in m["packets"]:
            require(offset + 4 <= len(raw), "truncated envelope length prefix")
            size = struct.unpack_from("<I", raw, offset)[0]
            offset += 4
            require(0 < size <= MAX_ENVELOPE and offset + size <= len(raw),
                    "invalid/truncated envelope length")
            require(size == p["envelopeBytes"], "manifest envelopeBytes mismatch")
            packet = raw[offset:offset + size]
            offset += size
            arrival, index = p["arrivalSeconds"], p["index"]
            if previous_arrival is not None and arrival - previous_arrival > 0.2:
                report["arrivalGaps"].append({"afterIndex": previous_index,
                    "beforeIndex": index, "seconds": arrival - previous_arrival,
                    "meaning": "arrival delay, NOT proven audio loss"})
            if previous_index is not None and index != previous_index + 1:
                report["indexDiscontinuities"].append([previous_index, index])
                boundary = True
            previous_arrival, previous_index = arrival, index
            try:
                typ, metadata, payload = parse_envelope(packet)
                require(typ == p["type"], "manifest type disagrees with envelope")
                for mask in ("vpuMask", "vadMask"):
                    if mask in metadata:
                        require((metadata[mask] is None or
                                 integer(metadata[mask], -(2**63), 2**64 - 1))
                                and type(metadata[mask]) is type(p[mask])
                                and metadata[mask] == p[mask],
                                f"manifest {mask} disagrees with envelope")
                for key in ("seq", "frameCount"):
                    if key in metadata and key in p:
                        require(type(metadata[key]) is type(p[key]) and metadata[key] == p[key],
                                f"manifest {key} disagrees with envelope")
                seq = metadata.get("seq", p.get("seq"))
                if "seq" in metadata or "seq" in p:
                    require(integer(seq), "invalid sequence metadata")
                    if previous_seq is not None and seq != previous_seq + 1:
                        report["sequenceDiscontinuities"].append([previous_seq, seq])
                        boundary = True
                    previous_seq = seq
                report["packetStateMetadata"].append({
                    "index": index, "vpuMask": p["vpuMask"], "vadMask": p["vadMask"],
                    "frameCount": metadata.get("frameCount"), "seq": seq,
                })
                is_audio = typ == 3 if m["source"] == "voice" else typ in (163, 164)
                if not payload and not is_audio:
                    continue
                require(p["business"] == 13, "unknown audio business")
                if explicit_pcm:
                    require(typ == (3 if m["source"] == "voice" else 163),
                            "unsupported synthetic audio type")
                    require(payload and len(payload) % (2 * len(channels)) == 0,
                            "empty/partial PCM sample frame")
                    require(number(p.get("audioStartSeconds"), 0, m["durationSeconds"]),
                            "synthetic packet requires audioStartSeconds")
                    entries.append({"packet": p, "payload": payload,
                        "count": len(payload) // (2 * len(channels)),
                        "start": float(p["audioStartSeconds"]), "boundary": boundary})
                else:
                    frames = native_frames(m["source"], typ, metadata, payload, p)
                    if decoder is None:
                        decoder = OpusDecoder()
                    counts = [decoder.sample_count(frame) for frame in frames]
                    if m["source"] == "lifelog":
                        require(all(count == 960 for count in counts),
                                "LifeLog Opus TOC disagrees with inferred 60-ms profile")
                    entries.append({"packet": p, "frames": frames, "count": sum(counts),
                                    "boundary": boundary})
                boundary = False
            except SessionError as exc:
                fail_audio(index, str(exc))
        require(offset == len(raw), "extra envelopes/bytes absent from manifest")
        if not explicit_pcm:
            native_timing(entries, rate)

        previous_end, boundary = None, True
        for entry in entries:
            p = entry["packet"]
            index, start = p["index"], entry["start"]
            boundary = boundary or entry["boundary"]
            try:
                end = start + entry["count"] / rate
                require(end <= m["durationSeconds"] + 1e-9,
                        "audio extends past capture duration")
                require(end > 0, "audio entirely before session start")
                if not explicit_pcm:
                    require(end <= p["arrivalSeconds"] + 1e-9,
                            "audio extends past its own arrival")
                if previous_end is not None:
                    require(start >= previous_end - 0.5 / rate,
                            "overlapping/unplaceable audio: preserved raw, excluded from analysis")
                    if start - previous_end > 1 / rate:
                        boundary = True
                if explicit_pcm:
                    pcm = np.frombuffer(entry["payload"], dtype="<i2").reshape(-1, len(channels))
                    pcm = pcm.astype(np.float64) / 32768
                else:
                    if boundary and decoder is not None:
                        decoder.close()
                        decoder = None
                    if decoder is None:
                        decoder = OpusDecoder()
                    # Every 240-byte LifeLog frame is a separate Opus packet.
                    # A failure excludes the entire envelope and resets prediction
                    # state; its planned time is not compressed out or PLC-filled.
                    pcm = np.concatenate([decoder.decode(frame) for frame in entry["frames"]])
                require(len(pcm) == entry["count"] and len(pcm) > 0, "empty/invalid decoded audio")
                if start < 0:
                    trim = int(math.ceil(-start * rate - 1e-9))
                    pcm = pcm[trim:]
                    start += trim / rate
                    diagnostics.append(f"packet {index}: trimmed audio preceding session start")
                require(len(pcm) > 0, "audio entirely before session start")
                if previous_end is not None and start - previous_end > 1 / rate:
                    report["audioTimelineGaps"].append({"startSeconds": previous_end,
                        "endSeconds": start, "meaning": "unobserved audio time, NOT proven network loss"})
                if runs and not boundary and abs(start - previous_end) <= 0.5 / rate:
                    runs[-1][1].append(pcm)
                else:
                    runs.append([start, [pcm]])
                previous_end = start + len(pcm) / rate
                boundary = False
                report["decodedPackets"] += 1
                report["decodedFrames"] += 1 if explicit_pcm else len(entry["frames"])
                report["packetTiming"].append({"index": index, "arrivalSeconds": p["arrivalSeconds"],
                    "startSeconds": start, "endSeconds": previous_end, "sampleCount": len(pcm),
                    "frameCount": 1 if explicit_pcm else len(entry["frames"])})
            except SessionError as exc:
                fail_audio(index, str(exc))
    finally:
        if decoder is not None:
            decoder.close()
    for start, chunks in runs:
        samples = np.concatenate(chunks)
        for i, channel in enumerate(channels):
            output[channel].append(Segment(start, samples[:, i].copy(), rate))
    report["channels"] = {}
    for channel, segments in output.items():
        report["channels"][channel] = {
            "sampleRate": rate, "decodedSeconds": sum(len(s.samples) / rate for s in segments),
            "segments": [{"startSeconds": s.start, "endSeconds": s.end,
                          "sampleCount": len(s.samples)} for s in segments],
        }
    if not any(output.values()):
        diagnostics.append("No decodable audio; exposure and metrics unavailable (not zero-error success).")
    decoded = Decoded(m, output, report)
    decode_official(decoded, extras)
    return decoded


# Ogg uses its own non-reflected CRC (not zip/zlib CRC32).
def ogg_crc(data):
    table = []
    for value in range(256):
        crc = value << 24
        for _ in range(8):
            crc = ((crc << 1) ^ (0x04c11db7 if crc & 0x80000000 else 0)) & 0xffffffff
        table.append(crc)
    crc = 0
    for byte in data:
        crc = ((crc << 8) & 0xffffffff) ^ table[(crc >> 24) ^ byte]
    return crc


def ogg_packets(data):
    """Bounded port of AlwaysOnOgg.m Scan; accepts corrected or legacy granules.

    The official legacy clock increments 960 at 48 kHz per packet plus pre-skip,
    even when the TOC is 60 ms. Never use that clock as decoded audio duration.
    No on-disk repair or external process is performed.
    """
    offset, serial, sequence, pending = 0, None, 0, bytearray()
    packets, counts = [], []
    legacy, correct, eos, total = True, True, False, 0
    head = None
    inspector = OpusDecoder()
    try:
        while offset < len(data):
            require(sequence < 100000 and not eos, "invalid Ogg page count/trailing data")
            require(offset + 27 <= len(data), "truncated Ogg header")
            h = data[offset:offset + 27]
            require(h[:4] == b"OggS" and h[4] == 0 and h[5] & ~7 == 0, "invalid Ogg header")
            flags, gp, stream, seq = h[5], *struct.unpack_from("<QII", h, 6)
            require(bool(flags & 1) == bool(pending), "invalid Ogg continuation")
            if serial is None:
                require(flags & 2 and seq == 0, "missing Ogg BOS")
                serial = stream
            else:
                require(not flags & 2, "chained Ogg streams unsupported")
            require(stream == serial and seq == sequence, "Ogg serial/sequence discontinuity")
            sequence += 1
            n = h[26]
            require(offset + 27 + n <= len(data), "truncated Ogg lacing")
            laces = data[offset + 27:offset + 27 + n]
            end = offset + 27 + n + sum(laces)
            require(end <= len(data), "truncated Ogg body")
            page = bytearray(data[offset:end])
            expected = struct.unpack_from("<I", page, 22)[0]
            page[22:26] = bytes(4)
            require(ogg_crc(page) == expected, "invalid Ogg CRC")
            at, completed = offset + 27 + n, 0
            for size in laces:
                pending.extend(data[at:at + size])
                at += size
                require(len(pending) <= 65536, "Ogg packet exceeds limit")
                if size == 255:
                    continue
                packet = bytes(pending)
                pending.clear()
                if head is None:
                    require(len(packet) == 19 and packet[:8] == b"OpusHead"
                            and packet[8] == 1 and packet[9] in (1, 2) and packet[18] == 0,
                            "unsupported Ogg OpusHead")
                    head = {"declaredChannels": packet[9],
                            "preSkip48k": struct.unpack_from("<H", packet, 10)[0],
                            "inputRate": struct.unpack_from("<I", packet, 12)[0],
                            "gainQ8": struct.unpack_from("<h", packet, 16)[0]}
                elif not packets:
                    require(packet[:8] == b"OpusTags", "missing OpusTags")
                    packets.append(None)  # metadata is not copied into reports
                else:
                    count = inspector.sample_count(packet)
                    total += count * 3
                    require(total <= 125 * 48000 + head["preSkip48k"],
                            "official Ogg exceeds bounded 125-second audio limit")
                    packets.append(packet)
                    counts.append(count)
                    completed += 1
            eos = bool(flags & 4)
            if completed:
                legacy = legacy and gp == len(counts) * 960 + head["preSkip48k"]
                correct = correct and gp == total
            else:
                require(gp == (2**64 - 1 if pending else 0), "invalid Ogg metadata granule")
            if eos:
                require(counts and not pending, "invalid Ogg EOS")
            offset = end
        require(eos and counts and not pending and (legacy or correct),
                "missing EOS or unsupported/inconsistent Ogg granules")
        require(total > head["preSkip48k"], "Ogg contains no audio after pre-skip")
        head["granuleMode"] = "toc-correct" if correct else "official-legacy-20ms"
        head["durationFrom"] = "native packet TOC; never legacy granule increments"
        return packets[1:], counts, head
    finally:
        inspector.close()


EVENT_TIME_KEYS = ("eventTsMs", "eventTs", "timestampMs", "timestamp", "tsMs", "ts", "timeMs", "time")
EVENT_TAG_KEYS = {"type", "event", "eventType", "source", "kind", "taskId"}
EVENT_COUNT_KEYS = {"vpuMask", "vadMask", "vpuOn", "vadStart", "hasVpuVad", "frameCount", "frames",
                    "bytes", "byteCount", "dataBytes", "audioBytes", "packetBytes", "encodedBytes",
                    "opusBytes", "packetCount", "packets", "realtimePackets", "cachedPackets",
                    "seq", "sequence", "index"}


def official_metadata(m, extras):
    anchors = []
    if "startWallMs" in m:
        require(number(m["startWallMs"], 1.5e12, 2.5e12), "invalid startWallMs")
        anchors.append((0.0, m["startWallMs"]))
    counters = m.get("officialCounters", [])
    require(isinstance(counters, list) and len(counters) <= 1024, "invalid officialCounters")
    last = -1
    for row in counters:
        require(isinstance(row, dict) and number(row.get("t"), 0, m["durationSeconds"])
                and row["t"] >= last, "invalid official counter time")
        last = row["t"]
        for key in ("realtimePackets", "cachedPackets"):
            require(row.get(key) is None or integer(row[key], 0, 2**63 - 1),
                    "invalid official batch counter")
        require(row.get("alwaysOnRunning") is None or type(row["alwaysOnRunning"]) is bool,
                "invalid official running state")
        if "wallMs" in row:
            require(number(row["wallMs"], 1.5e12, 2.5e12), "invalid counter wallMs")
            anchors.append((row["t"], row["wallMs"]))
    offsets = [wall - 1000 * t for t, wall in anchors]
    drift = (max(offsets) - min(offsets)) / 1000 if offsets else None
    stats = {}
    for key in ("realtimePackets", "cachedPackets"):
        rows = [r for r in counters if r.get(key) is not None]
        reset = any(b[key] < a[key] for a, b in zip(rows, rows[1:]))
        windows = [[a["t"], b["t"]] for a, b in zip(rows, rows[1:]) if b[key] > a[key]]
        stats[key] = {"delta": rows[-1][key] - rows[0][key] if len(rows) >= 2 and not reset else None,
                      "resetObserved": reset, "activityWindows": windows,
                      "activityBatches": [
                          {"startSeconds": a["t"], "endSeconds": b["t"], "delta": b[key] - a[key]}
                          for a, b in zip(rows, rows[1:]) if b[key] > a[key]]}
    data = extras.get("official-events.jsonl", b"")
    require(len(data) <= MAX_EVENTS, "official events exceed limit")
    lines = data.splitlines()
    require(len(lines) <= 100000, "too many official events")
    events = []
    for line in lines:
        if not line:
            continue
        require(len(line) <= 65536, "official event line exceeds limit")
        event = json_object(line)
        require(set(event) <= set(EVENT_TIME_KEYS) | EVENT_TAG_KEYS | EVENT_COUNT_KEYS,
                "official event contains non-allow-listed fields")
        for key, value in event.items():
            if key in EVENT_COUNT_KEYS:
                require(type(value) is bool or integer(value, -(2**63), 2**64 - 1),
                        "invalid official event numeric field")
            elif key in EVENT_TAG_KEYS:
                require((isinstance(value, str) and len(value) <= 64) or integer(value),
                        "invalid official event tag")
            else:
                require(number(value, 0, 2**63 - 1) or (isinstance(value, str) and len(value) <= 40),
                        "invalid official event timestamp")
        timestamp = next((event[k] for k in EVENT_TIME_KEYS if k in event), None)
        mapped = None
        if anchors and number(timestamp, 1.5e12, 2.5e12):
            t, wall = min(anchors, key=lambda a: abs(a[1] - timestamp))
            mapped = t + (timestamp - wall) / 1000
        # Only the pinned epoch-ms range is mapped. No epoch-second/ISO guessing.
        events.append({"fields": event, "sessionSeconds": mapped})
    return events, stats, drift


def official_alignment(m, item, events, stats, drift, frames, counts, unique_realtime):
    duration = sum(counts) / 16000
    relevant = [e for e in events if any(
        isinstance(e["fields"].get(k), str) and "realtime" in e["fields"][k].lower()
        and "cached" not in e["fields"][k].lower() for k in ("source", "type", "kind", "event"))]
    valid = [e for e in relevant if e["sessionSeconds"] is not None
             and number(e["sessionSeconds"], 0, m["durationSeconds"])
             and integer(e["fields"].get("frameCount"), 1, MAX_LIFELOG_FRAMES)]
    delta = stats["realtimePackets"]["delta"]
    rejection = None
    if (item["sourceKind"] == "realtime" and unique_realtime and valid
            and len(valid) == len(relevant) and delta == len(valid)
            and sum(e["fields"]["frameCount"] for e in valid) == len(frames)
            and all(a["sessionSeconds"] <= b["sessionSeconds"] for a, b in zip(valid, valid[1:]))):
        entries, at, max_batch = [], 0, 0
        for e in valid:
            n = e["fields"]["frameCount"]
            count = sum(counts[at:at + n])
            entries.append({"packet": {"arrivalSeconds": e["sessionSeconds"]},
                            "frames": frames[at:at + n], "count": count, "boundary": not entries})
            max_batch = max(max_batch, count / 16000)
            at += n
        native_timing(entries, 16000)
        # Total counter delta alone is insufficient: each observed activity
        # interval must contain exactly its increment's worth of mapped events.
        # No delayed-counter semantics or cross-window latency is established.
        activity = stats["realtimePackets"]["activityBatches"]
        window_counts = []
        for window in activity:
            lo, hi = window["startSeconds"], window["endSeconds"]
            # A shared boundary belongs to the earlier interval. Only t=0 is
            # included at the lower bound; allow nanosecond arithmetic noise.
            window_counts.append(sum(
                (e["sessionSeconds"] >= 0 if lo == 0 else e["sessionSeconds"] > lo + 1e-9)
                and e["sessionSeconds"] <= hi + 1e-9 for e in valid))
        windows_agree = (window_counts == [w["delta"] for w in activity]
                         and sum(window_counts) == len(valid))
        if not windows_agree:
            rejection = "event/counter activity-window disagreement; delayed-counter semantics unverified"
        elif any(b["start"] < a["start"] + a["count"] / 16000 - 0.5 / 16000
                 for a, b in zip(entries, entries[1:])):
            rejection = "overlapping official sample placement"
        else:
            alignment = {"method": "event-wallclock",
                         "uncertaintySeconds": (drift or 0) + max_batch + 0.001,
                         "anchorDriftSeconds": drift, "exactPacketTiming": False,
                         "basis": "ordered batches agree with Ogg packets and individual counter activity windows",
                         "transportLatencyKnown": False}
            return alignment, entries
    windows = stats["realtimePackets"]["activityWindows"]
    # Counters identify only activity windows, NEVER frame/sample offsets.
    if item["sourceKind"] == "realtime" and unique_realtime and windows and delta is not None:
        alignment = {"method": "counters-coarse", "uncertaintySeconds": (drift or 0) + 0.25 + duration,
                     "anchorDriftSeconds": drift, "exactPacketTiming": False,
                     "basis": "counter activity only; batch duration unknown, bounded by whole file",
                     "sessionActivityWindowSeconds": [windows[0][0], windows[-1][1]],
                     "audioPlacement": "file-local; activity window only",
                     "transportLatencyKnown": False}
    else:
        alignment = {"method": "none", "uncertaintySeconds": None, "anchorDriftSeconds": drift,
                     "exactPacketTiming": False, "basis": "no unique, anchored realtime batch correspondence",
                     "transportLatencyKnown": False}
    if rejection is not None:
        alignment["associationRejected"] = rejection
    return alignment, [{"frames": frames, "count": sum(counts), "start": 0, "boundary": True}]


def decode_official(decoded, extras):
    m, report = decoded.manifest, decoded.report
    events, stats, drift = official_metadata(m, extras)
    report["officialCounters"] = stats
    report["officialEvents"] = {"count": len(events),
        "anchoredCount": sum(e["sessionSeconds"] is not None for e in events),
        "unanchoredCount": sum(e["sessionSeconds"] is None for e in events),
        "anchorDriftSeconds": drift,
        "mappedTimesSeconds": [e["sessionSeconds"] for e in events],
        "stateMetadata": [{"vpuMask": e["fields"].get("vpuMask"),
                           "vadMask": e["fields"].get("vadMask"),
                           "frameCount": e["fields"].get("frameCount")} for e in events]}
    report["officialDumps"], decoded.official_audio = [], []
    report["officialDecodedFrames"] = 0
    dumps = m.get("officialDump", [])
    require(not dumps or m["source"] == "lifelog", "official dumps require source lifelog")
    unique_realtime = sum(i["sourceKind"] == "realtime" for i in dumps) == 1
    for i, item in enumerate(dumps):
        row = {"file": item["file"], "sourceKind": item["sourceKind"],
               "channel": "lifelog-mono-unassigned", "segments": [], "decodedFrames": 0}
        report["officialDumps"].append(row)
        try:
            data = extras[item["file"]]
            require(len(data) == item["bytes"], "official dump byte count mismatch")
            require(hashlib.sha256(data).hexdigest() == item["sha256"].lower(),
                    "official dump SHA-256 mismatch")
            require(item["copyFinalized"], "official dump copy is not finalized")
            frames, counts, head = ogg_packets(data)
            require(all(count == 960 for count in counts),
                    "official LifeLog TOC disagrees with inferred 60-ms profile")
            alignment, entries = official_alignment(m, item, events, stats, drift, frames, counts,
                                                     unique_realtime)
            alignment["uncertaintyIsVerifiedBound"] = False
            alignment["uncertaintyBasis"] = (
                "minimum batch/clock bookkeeping uncertainty; transport/source latency unbounded")
            aligned = alignment["method"] == "event-wallclock"
            uncertainty = alignment["uncertaintySeconds"]
            # Codec state belongs to the Ogg logical stream, NOT the inferred
            # event timeline. Decode once continuously, then slice the immutable
            # source sample clock into timing segments without re-decoding.
            decoder = OpusDecoder()
            try:
                source_pcm = np.concatenate([decoder.decode(frame)[:, 0] for frame in frames])
            finally:
                decoder.close()
            require(len(source_pcm) == sum(counts), "Ogg native sample count mismatch")
            source_pcm *= 10 ** (head["gainQ8"] / (20 * 256))
            skip = math.ceil(head["preSkip48k"] / 3)
            segments, chunks, run_start, at = [], [], None, 0
            for entry in entries:
                if entry["boundary"] and chunks:
                    segments.append(Segment(run_start, np.concatenate(chunks), 16000,
                                            aligned, uncertainty or 0))
                    chunks = []
                begin, end = max(at, skip), at + entry["count"]
                trim = max(0, begin - at)
                at = end
                start = entry["start"]
                if aligned:
                    start += trim / 16000
                    before = max(0, math.ceil(-start * 16000 - 1e-9))
                    begin += before
                    start += before / 16000
                    end = min(end, begin + max(
                        0, math.floor((m["durationSeconds"] - start) * 16000 + 1e-8)))
                else:
                    start = 0  # pre-skip removed; unaligned time is file-local
                pcm = source_pcm[begin:end]
                if not len(pcm):
                    continue
                if not chunks:
                    run_start = start
                chunks.append(pcm)
            if chunks:
                segments.append(Segment(run_start, np.concatenate(chunks), 16000,
                                        aligned, uncertainty or 0))
            require(segments, "official dump has no samples within session bounds")
            # No output is admitted until the complete Ogg/native decode succeeds.
            row.update({"alignment": alignment, "ogg": head, "decodedFrames": len(frames),
                        "decodedSeconds": sum(len(s.samples) / 16000 for s in segments),
                        "clock": "approximate-session" if aligned else "file-local"})
            row["segments"] = [{"startSeconds": s.start, "endSeconds": s.end,
                                "sampleCount": len(s.samples)} for s in segments]
            decoded.official_audio.extend((i, s) for s in segments)
            report["officialDecodedFrames"] += len(frames)
            if unique_realtime and item["sourceKind"] == "realtime":
                # Never pool raw envelopes, duplicate dumps or cached history.
                decoded.channels = {"lifelog-mono-unassigned": segments}
                report["analysisSource"] = item["file"]
                report["timing"] = "official Ogg " + row["clock"] + "; derived alignment, not source timestamps"
                report["independentVpuEstablished"] = False
                report["codecProfile"] = {
                    "codec": "opus", "sampleRate": 16000, "channels": 1,
                    "provenance": "official Ogg with static LifeLog expected profile; no real-capture validation",
                    "configuredBitrate": 32000, "expectedFrameSeconds": 0.060,
                    "durationValidation": "each packet TOC and native decode",
                    "containerDeclaredChannels": head["declaredChannels"]}
                report["channels"] = {"lifelog-mono-unassigned": {
                    "sampleRate": 16000, "decodedSeconds": row["decodedSeconds"],
                    "segments": [dict(s) for s in row["segments"]],
                    "clock": row["clock"], "alignment": alignment}}
        except SessionError as exc:
            row["error"] = str(exc)
            report["diagnostics"].append(f"official dump {i}: {exc}")
    if report["officialDecodedFrames"]:
        report["diagnostics"] = [d for d in report["diagnostics"]
                                 if not d.startswith("No decodable audio;")]
        report["diagnostics"].append(
            "Official dump alignment is derived and approximate, never exact packet timing. "
            "Cached/unverified/multiple realtime files are not pooled into session exposure.")


def write_json(path, value):
    with open(path, "x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")
    os.chmod(path, 0o600)


def new_output(path):
    path = Path(path)
    path.mkdir(mode=0o700, parents=True, exist_ok=False)
    return path


def write_decoded(decoded, out):
    dump_indexes = {}
    for file_index, segment in decoded.official_audio or []:
        index = dump_indexes.get(file_index, 0)
        dump_indexes[file_index] = index + 1
        filename = f"official-{file_index:03d}-lifelog-mono-unassigned-{index:03d}.wav"
        with wave.open(str(out / filename), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(segment.rate)
            pcm = np.clip(np.rint(segment.samples * 32768), -32768, 32767).astype("<i2")
            stream.writeframes(pcm.tobytes())
        os.chmod(out / filename, 0o600)
        decoded.report["officialDumps"][file_index]["segments"][index]["wav"] = filename
    for channel, segments in decoded.channels.items():
        for i, segment in enumerate(segments):
            filename = f"{channel}-{i:03d}.wav"
            with wave.open(str(out / filename), "wb") as stream:
                stream.setnchannels(1)
                stream.setsampwidth(2)
                stream.setframerate(segment.rate)
                pcm = np.clip(np.rint(segment.samples * 32768), -32768, 32767).astype("<i2")
                stream.writeframes(pcm.tobytes())
            os.chmod(out / filename, 0o600)
            decoded.report["channels"][channel]["segments"][i]["wav"] = filename
    write_json(out / "decode.json", decoded.report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path)
    parser.add_argument("--out", type=Path, required=True, help="new private output directory")
    args = parser.parse_args()
    try:
        decoded = decode_session(args.session)
        write_decoded(decoded, new_output(args.out))
        print(json.dumps(decoded.report, indent=2, allow_nan=False))
        return 0 if decoded.report["decodedPackets"] or decoded.report["officialDecodedFrames"] else 2
    except (SessionError, OSError, EOFError) as exc:
        print(f"decode: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
