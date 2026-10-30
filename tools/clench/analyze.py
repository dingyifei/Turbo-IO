#!/usr/bin/env python3
"""Offline, non-trained baseline and channel-specific feasibility metrics."""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import sys

import numpy as np
from scipy import signal

# -I deliberately excludes the script directory. Load only the named sibling,
# never cwd, PYTHONPATH, or a session-supplied Python module.
sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location("_clench_decode", Path(__file__).with_name("decode.py"))
decode = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = decode
_spec.loader.exec_module(decode)

NEGATIVES = ("chew", "talk", "walk", "tap-temple", "silence")
MIN_PAIR = 0.150
MAX_PAIR = 0.600
REFRACTORY = 0.080
FILTER_EDGE = 0.030
DEFAULT_MARK_TOLERANCE = 0.350


def pair_events(events):
    """Earliest pending onset plus first legal partner; each onset used once."""
    result, pending = [], None
    for event in sorted(events):
        if pending is None:
            pending = event
        elif event - pending > MAX_PAIR + 1e-9:
            pending = event
        elif event - pending >= MIN_PAIR - 1e-9:
            result.append({"firstSeconds": pending, "secondSeconds": event})
            pending = None
        # Sub-150-ms events cannot be a partner and do not extend the window.
    return result


def match_marks(marks, predictions, tolerance=DEFAULT_MARK_TOLERANCE):
    """Maximum-cardinality ordered matching with symmetric fixed tolerance."""
    marks, predictions = sorted(marks), sorted(predictions)
    pairs, i, j = [], 0, 0
    while i < len(marks) and j < len(predictions):
        if predictions[j] < marks[i] - tolerance - 1e-9:
            j += 1
        elif marks[i] < predictions[j] - tolerance - 1e-9:
            i += 1
        else:
            pairs.append({"markSeconds": marks[i], "triggerSeconds": predictions[j],
                          "errorSeconds": predictions[j] - marks[i]})
            i += 1
            j += 1
    return pairs


def detect_segment(segment):
    """Causal 300–5000 Hz bandpass; short-energy excursion; timing-only rule."""
    fs, x = segment.rate, segment.samples
    sos = signal.butter(4, [300, 5000], btype="bandpass", fs=fs, output="sos")
    band = signal.sosfilt(sos, x)
    window = max(1, round(fs * 0.004))
    # Center the energy window to avoid attributing its smoothing delay to marks.
    energy = signal.convolve(band * band, np.ones(window) / window, mode="same")
    edge = round(fs * FILTER_EDGE)
    interior = energy[edge:len(energy) - edge]
    if not len(interior):
        return {"onsets": [], "pairs": [], "coverage": [], "threshold": None,
                "band": band, "energy": energy}
    floor = float(np.median(interior))
    mad = float(np.median(np.abs(interior - floor)))
    threshold = max(1e-10, floor * 10, floor + 12 * mad)
    active = energy > threshold
    edges = np.diff(np.r_[False, active, False].astype(np.int8))
    starts, ends = np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)
    # Join very short below-threshold holes within the same transient.
    regions = []
    for start, end in zip(starts, ends):
        if regions and start - regions[-1][1] <= round(0.004 * fs):
            regions[-1][1] = int(end)
        else:
            regions.append([int(start), int(end)])
    onsets, last = [], -math.inf
    for start, end in regions:
        # Sustained speech-like energy is not a click. This is a baseline,
        # not a claim that real speech never makes short transients.
        if (end - start) / fs > 0.045 or start < edge or end > len(x) - edge:
            continue
        t = segment.start + start / fs
        if t - last >= REFRACTORY:
            onsets.append(t)
            last = t
    lo, hi = segment.start + FILTER_EDGE + MAX_PAIR, segment.end - FILTER_EDGE
    coverage = [[lo, hi]] if hi > lo else []
    pairs = [p for p in pair_events(onsets) if lo <= p["secondSeconds"] <= hi]
    return {"onsets": onsets, "pairs": pairs, "coverage": coverage,
            "threshold": threshold, "band": band, "energy": energy}


def click_features(segment, detection, mark, tolerance):
    """Strongest 8-ms band-energy window near mark, with local noise estimate."""
    fs = segment.rate
    lo = max(0, math.ceil((mark - tolerance - segment.start) * fs))
    hi = min(len(segment.samples), math.floor((mark + tolerance - segment.start) * fs))
    width = max(1, round(0.008 * fs))
    if hi - lo < width:
        return None
    energy = signal.convolve(detection["band"] ** 2, np.ones(width), mode="same") / fs
    peak = lo + int(np.argmax(energy[lo:hi]))
    # Noise reference: same-sized windows 80–250 ms before the peak.
    noise_lo = max(0, peak - round(0.250 * fs))
    noise_hi = max(0, peak - round(0.080 * fs))
    if noise_hi - noise_lo < width:
        return None
    noise_energy = float(np.median(energy[noise_lo:noise_hi]))
    click_energy = float(energy[peak])
    return {
        "markSeconds": mark, "peakSeconds": segment.start + peak / fs,
        "bandHz": [300, 5000], "windowSeconds": width / fs,
        "transientEnergyFS2Seconds": click_energy,
        "localNoiseEnergyFS2Seconds": noise_energy,
        "clickSnrDb": 10 * math.log10(max(click_energy, 1e-20) / max(noise_energy, 1e-20)),
        "snrDefinition": "total peak-window energy / local median noise-window energy",
        "selection": "strongest window within mark tolerance; not a classifier score",
    }


def analyze_channel(segments, marks, label, tolerance=DEFAULT_MARK_TOLERANCE):
    detections = [detect_segment(s) for s in segments]
    coverage = [interval for d in detections for interval in d["coverage"]]
    exposure = sum(hi - lo for lo, hi in coverage)
    predictions = [p for d in detections for p in d["pairs"]]
    eligible, excluded = [], []
    for mark in marks:
        # A complete tolerance interval and the detector's 600-ms lookback
        # must be observed in one run. No padding or bridging across gaps.
        if any(segment.aligned and segment.uncertainty <= tolerance
               and any(lo <= mark - tolerance - segment.uncertainty
                       and mark + tolerance + segment.uncertainty <= hi
                       for lo, hi in detection["coverage"])
               for segment, detection in zip(segments, detections)):
            eligible.append(mark)
        else:
            excluded.append({"timeSeconds": mark,
                             "reason": "unaligned, excessive alignment uncertainty, or insufficient coverage"})
    matches = match_marks(eligible, [p["secondSeconds"] for p in predictions], tolerance)
    features = []
    for mark in eligible:
        for segment, detection in zip(segments, detections):
            if segment.start <= mark - tolerance and mark + tolerance <= segment.end:
                feature = click_features(segment, detection, mark, tolerance)
                if feature is not None:
                    features.append(feature)
                break
    positive = label == "double-tap"
    negative = label in NEGATIVES
    result = {
        "decodedSeconds": sum(len(s.samples) / s.rate for s in segments),
        "analyzedExposureSeconds": exposure, "coverage": coverage,
        "onsetsSeconds": [t for d in detections for t in d["onsets"]],
        "doubleEvents": predictions,
        "totalMarks": len(marks), "eligibleMarks": len(eligible), "excludedMarks": excluded,
        "matchedDoubleTapMarks": len(matches) if positive else None,
        "matches": matches if positive else [],
        "recall": len(matches) / len(eligible) if positive and eligible else None,
        "recallStatus": "available" if positive and eligible else "unavailable",
        "markAlignmentAvailable": bool(segments) and all(
            s.aligned and s.uncertainty <= tolerance for s in segments),
        "alignmentUncertaintySeconds": max((s.uncertainty for s in segments), default=0)
            if all(s.aligned for s in segments) else None,
        "falseTriggers": len(predictions) if negative and exposure > 0 else None,
        "falseTriggersPerMinute": len(predictions) * 60 / exposure if negative and exposure > 0 else None,
        "unmatchedPositivePredictions": len(predictions) - len(matches) if positive else None,
        "clickFeatures": features, "thresholdsFS2": [d["threshold"] for d in detections],
    }
    return result


def summarize(sessions):
    """Never pool synthetic/real, or add VPU exposure to air exposure."""
    result = {}
    for kind in ("real", "synthetic"):
        selected = [s for s in sessions if s["synthetic"] == (kind == "synthetic")]
        channel_names = sorted({name for s in selected for name in s["channels"]})
        grouped = {}
        for channel in channel_names:
            positive_n, matched = 0, 0
            excluded = 0
            negatives = {label: {"falseTriggers": 0, "analyzedExposureSeconds": 0.0}
                         for label in NEGATIVES}
            for s in selected:
                c = s["channels"].get(channel)
                if c is None:
                    continue
                if s["label"] == "double-tap":
                    positive_n += c["eligibleMarks"]
                    matched += c["matchedDoubleTapMarks"]
                    excluded += len(c["excludedMarks"])
                elif s["label"] in NEGATIVES:
                    dest = negatives[s["label"]]
                    dest["falseTriggers"] += c["falseTriggers"] or 0
                    dest["analyzedExposureSeconds"] += c["analyzedExposureSeconds"]
            for value in negatives.values():
                seconds = value["analyzedExposureSeconds"]
                value["falseTriggersPerMinute"] = value["falseTriggers"] * 60 / seconds if seconds else None
            talk_chew_seconds = sum(negatives[l]["analyzedExposureSeconds"] for l in ("talk", "chew"))
            talk_chew_triggers = sum(negatives[l]["falseTriggers"] for l in ("talk", "chew"))
            grouped[channel] = {
                "eligibleDoubleTapMarks": positive_n, "matchedDoubleTapMarks": matched,
                "excludedDoubleTapMarks": excluded,
                "recall": matched / positive_n if positive_n else None,
                "negatives": negatives,
                "talkAndChew": {
                    "falseTriggers": talk_chew_triggers,
                    "analyzedExposureSeconds": talk_chew_seconds,
                    "falseTriggersPerMinute": talk_chew_triggers * 60 / talk_chew_seconds
                    if talk_chew_seconds else None,
                    "observedTenMinuteEquivalentBlocks": talk_chew_seconds / 600,
                },
            }
        result[kind] = {"sessionCount": len(selected), "byChannel": grouped}
    result["referenceThresholds"] = {"recallAtLeast": 0.90,
        "talkOrChewFalseTriggersPerMinuteAtMost": 0.10}
    result["decision"] = "not made; synthetic data and brief/unknown coverage cannot establish feasibility"
    return result


def plot_session(decoded, analyses, out):
    # Keep matplotlib's cache inside the caller's new local output directory.
    os.environ["MPLCONFIGDIR"] = str(out / ".matplotlib")
    import matplotlib
    matplotlib.use("Agg", force=True)
    import matplotlib.pyplot as plt
    populated = [(name, segments) for name, segments in decoded.channels.items() if segments]
    if not populated:
        return None
    fig, axes = plt.subplots(len(populated), 1, figsize=(12, 3.5 * len(populated)), squeeze=False)
    for ax, (name, segments) in zip(axes[:, 0], populated):
        image = None
        for segment in segments:
            n = min(256, len(segment.samples))
            if n < 8:
                continue
            frequencies, times, spectrum = signal.spectrogram(
                segment.samples, segment.rate, nperseg=n, noverlap=n // 2, scaling="density")
            image = ax.pcolormesh(times + segment.start, frequencies,
                                 10 * np.log10(np.maximum(spectrum, 1e-16)),
                                 shading="auto", cmap="magma", vmin=-100, vmax=-20)
        aligned = all(s.aligned for s in segments)
        if aligned:
            for mark in decoded.manifest["marks"]:
                ax.axvline(mark["timeSeconds"], color="cyan", linewidth=1, alpha=0.8)
        for p in analyses[name]["doubleEvents"]:
            ax.axvline(p["secondSeconds"], color="lime", linestyle="--", linewidth=1)
        ax.set(xlim=(0, decoded.manifest["durationSeconds"] or 1), ylim=(0, 6000),
               xlabel="Approximate session seconds" if aligned else "File-local seconds (marks unaligned)",
               ylabel="Hz", title=f"{name}: {decoded.manifest['label']} (dashed triggers)")
        if image is not None:
            fig.colorbar(image, ax=ax, label="dB FS²/Hz")
    fig.suptitle("SYNTHETIC fixture" if decoded.manifest.get("synthetic") else
                 "Capture: reconstructed timeline; source/transport latency unknown")
    fig.tight_layout()
    filename = out / "spectrogram.png"
    fig.savefig(filename, dpi=130)
    plt.close(fig)
    os.chmod(filename, 0o600)
    return filename.name


def analyze_session(decoded, tolerance=DEFAULT_MARK_TOLERANCE):
    marks = [mark["timeSeconds"] for mark in decoded.manifest["marks"]]
    return {
        "sessionId": decoded.manifest["sessionId"], "label": decoded.manifest["label"],
        "synthetic": decoded.manifest.get("synthetic", False),
        "channels": {channel: analyze_channel(segments, marks, decoded.manifest["label"], tolerance)
                     for channel, segments in decoded.channels.items()},
        "decode": decoded.report,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sessions", nargs="+", type=Path)
    parser.add_argument("--out", required=True, type=Path, help="new private output directory")
    parser.add_argument("--mark-tolerance", type=float, default=DEFAULT_MARK_TOLERANCE)
    args = parser.parse_args()
    try:
        decode.require(0 <= args.mark_tolerance <= 1 and math.isfinite(args.mark_tolerance),
                       "mark tolerance must be 0–1 seconds")
        decode.require(len(args.sessions) <= 64, "at most 64 sessions per invocation")
        out = decode.new_output(args.out)
        sessions, errors, seen = [], [], set()
        for path in args.sessions:
            try:
                decoded = decode.decode_session(path)
                # Canonicalize UUIDs for both deduplication and output paths.
                session_id = str(decode.uuid.UUID(decoded.manifest["sessionId"]))
                decode.require(session_id not in seen, "duplicate sessionId (would double-count metrics)")
                seen.add(session_id)
                session_out = decode.new_output(out / session_id)
                decode.write_decoded(decoded, session_out)
                report = analyze_session(decoded, args.mark_tolerance)
                report["spectrogram"] = plot_session(decoded, report["channels"], session_out)
                decode.write_json(session_out / "analysis.json", report)
                sessions.append(report)
            except (decode.SessionError, OSError, EOFError) as exc:
                errors.append({"input": str(path), "error": str(exc)})
        result = {
            "parameters": {"bandHz": [300, 5000], "pairSeconds": [MIN_PAIR, MAX_PAIR],
                "refractorySeconds": REFRACTORY, "markToleranceSeconds": args.mark_tolerance,
                "filterEdgeExcludedSeconds": FILTER_EDGE,
                "lookbackExcludedSeconds": MAX_PAIR},
            "summary": summarize(sessions), "sessions": sessions, "errors": errors,
            "limitations": [
                "Marks are user button times; source timing and voice/LifeLog transport latency are unknown.",
                "Recall denominator excludes unobserved marks; inspect excluded marks, not just recall.",
                "False-trigger rates use actual per-channel detector exposure, not capture duration.",
                "Voice/LifeLog mono is sensor-unassigned; vpuMask/vadMask are state metadata, not VPU audio.",
                "LifeLog profile has static evidence and packet-TOC checks, not real-capture validation.",
                "Official Ogg alignment is derived; unanchored/coarse or excessive-drift recall is unavailable.",
                "Official counters are cumulative batches; deltas never establish frame/sample offsets.",
                "No synthetic/real pooling and no cross-channel pooled pseudo-exposure.",
                "Fixed energy baseline is not trained or validated on real tooth taps.",
                "No go/no-go decision; thresholds are reference values only.",
            ],
        }
        decode.write_json(out / "report.json", result)
        print(json.dumps({"summary": result["summary"], "errors": errors}, indent=2, allow_nan=False))
        usable = any(c["analyzedExposureSeconds"] > 0 for s in sessions for c in s["channels"].values())
        return 0 if usable and not errors else 2
    except (decode.SessionError, OSError) as exc:
        print(f"analyze: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
