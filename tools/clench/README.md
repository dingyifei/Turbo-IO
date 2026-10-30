# Clench Lab offline tools (Lane T)

Local-only Phase A decoding and an intentionally simple double-tooth-tap baseline.
No device access, network, package installation, firmware changes, or feasibility
decision. Original session files are never modified. These tools do not authenticate
a capture or prove that its stop acknowledgement is genuine.

## Run using existing dependencies only

Requires Python 3.10+, NumPy and SciPy; PNG generation additionally requires
Matplotlib. Voice and LifeLog decoding use an already-installed native libopus through ctypes.
It tries the platform library finder and existing Homebrew/local library paths;
if absent, it reports undecodable audio rather than installing anything.
No ffmpeg, subprocess decoder, or downloaded model is used.

Verified locally with Python 3.13.12, NumPy 2.4.4, SciPy 1.17.1,
Matplotlib 3.10.9 and Homebrew libopus 1.6.1. The suite uses only generated fixtures
and its temporary files/cache stay under this directory and are removed.

Use absolute script paths, including under isolated Python mode:

```sh
python3 -I -B /absolute/path/tools/clench/tests.py

python3 -I -B /absolute/path/tools/clench/decode.py \
  /absolute/path/exported-session.zip --out /absolute/path/new-decoded-directory

python3 -I -B /absolute/path/tools/clench/analyze.py \
  /absolute/path/session-folder /absolute/path/another-session.zip \
  --out /absolute/path/new-analysis-directory
```

Output directories must not already exist; no overwrite or in-place option.
Output directories use mode 0700 and audio/reports/PNGs use 0600. Matplotlib's cache
is kept inside the new output, not the user's global cache. Exports, WAVs, marks,
and spectrograms can be sensitive; keep them local and remove them when done.
The tools create no listener or upload path.

Exit 0 means decoding produced audio, or analysis produced positive detector
exposure without input errors. It is **not** a feasibility verdict or a statement
that every packet decoded. Inspect all diagnostics/coverage. Exit 2 means invalid
input/output, no usable audio/exposure, or analysis input errors. A combined run
retains per-input errors and successful results in report.json; duplicate UUIDs
are errors, not additional exposure. At most 64 inputs per analysis invocation.

## Canonical session schema and bounded input

The coordination contract is authoritative:
`overnight/clench/contract.md` in turboio-inputs. Schema 1 requires:

- `manifest.json` and `envelopes.rnp`, the latter a sequence of **uint32le byte
  length + original complete business protobuf envelope**.
- `schemaVersion: 1`, UUID `sessionId`, `source: lifelog|voice`, and one of
  `double-tap|single-tap|true-clench|chew|talk|walk|tap-temple|silence`.
- ISO8601 UTC `createdAt`, nonempty `appVersion` and `appCommit`;
  unresolved common provenance placeholders are reported, never replaced.
- `clock: monotonic-seconds-from-session-start`, `durationSeconds` bounded by
  the manifest's `receiveLimitSeconds`, boolean `stopPending`/`offObserved`,
  and nonnegative `droppedPackets`. Passive LifeLog uses stop/prompt limit
  **120 seconds** and receive/storage limit **125 seconds**. The decoder reads
  declared limits (including shorter sessions), bounded by 120/125 for LifeLog
  or the legacy 25/30 voice profile; it does not hard-code all captures to 30 s.
- `marks: [{"timeSeconds": number}]`, in monotonic order, **one mark per
  performed labeled gesture**, including one mark for a double tap.
- `packets` in file order, one per stored envelope, with increasing `index`,
  monotonic `arrivalSeconds`, `business`, `type`, `envelopeBytes`,
  and required nullable integer `vpuMask` and `vadMask` (bounded to 64-bit mask values).
  Arrival and mark times must lie within actual capture duration.
  Extra properties are allowed.

Duplicate JSON keys, nonfinite numbers, noncanonical clocks, invalid types,
out-of-range times, inconsistent framing, and trailing unlisted raw bytes fail
explicitly. A malformed individual envelope or inconsistent envelope metadata is
diagnosed and excluded rather than treated as silence. Parsing ports the existing
`BusinessEnvelopeMetadata.swift` rules: at most 256 fields, bounded ten-byte
varints, checked lengths, supported skip-wire types, unique known fields 1–4.
Fields are version=1, type=2, JSON message=3, binary data=4. The native business
ID is **not in that envelope** and necessarily comes from the manifest.

Limits: 4096 packets/marks, 1 MiB envelope, 64 KiB each JSON/binary business field,
4 MiB manifest, 16 MiB raw file, 96 MiB archive/total declared expansion,
64 MiB combined official dumps (at most 64 files), 16 MiB official events,
256 ZIP entries, maximum 200:1 per-member compression ratio. ZIPs are read
without extraction, with exactly one session manifest (an enclosing export
directory is allowed). Unsafe/normalized paths, links, special entries,
duplicate names, encrypted members, and compression other than stored/deflate
are rejected. Required members are also bounded during decompression and checked
by zipfile's CRC implementation. The conservative ratio limit may reject highly
compressible artificial fixtures; use a folder or stored ZIP instead.
Folder inputs reject symlinks for the session itself and required files; file
opens reject FIFOs/devices as well. These are bounded offline input precautions,
not a sandbox for hostile native-code vulnerabilities in libopus.

## What can actually be decoded

**Voice, business 13 type 3:** one Opus packet in protobuf field 4, decoded at
16 kHz mono with the same 10–120 ms packet-duration constraints as
`core-probe/Sources/NativeVoiceVAD.c` and the existing assistant audio parser.
This is a source-supported **baseline decode profile**, not proof of the
physical sensor mix. Its channel is named `voice-mono-unassigned`, never
“air” or “VPU”.

**LifeLog, business 13 A3/A4 (types 163/164):** Lane R's static evidence in
`overnight/clench/re-audio.md`, sections 1 and 3, establishes the identified
recording path's **16 kHz mono Opus at configured 32 kbit/s**, an application
frame size of **240 bytes**, and **frameCount × 240** batching. The internal
eight-byte prefix is removed before the application callback; none is stripped
again here. The channel is `lifelog-mono-unassigned`.

The JSON message must contain integer `frameCount` and 64-bit integer
`vpuMask`/`vadMask` state metadata agreeing with the manifest. An optional
manifest `frameCount` or `seq` must agree too. The decoder bounds frameCount to
1–273 (the 64-KiB business-field parser limit, not a measured firmware batch
limit), checks exact payload length, and splits the data into separate 240-byte
Opus packets. Each packet is checked for a mono TOC and a **60-ms decoded
duration**, then decoded sequentially through one native decoder state.
**60 ms is an inferred expected profile** from bitrate/configuration, not an
assumption that every 240-byte input is valid. A different TOC duration, malformed
batch, or decode failure is diagnostic, not guessed PCM. A decode failure excludes
the whole envelope, discards partial batch output, and resets decoder state.

A2/type 162 is not assumed to carry audio; unsupported audio types/profiles remain
explicitly undecodable. Static evidence does not prove the physical sensor mix,
source timestamps, runtime transport behavior, or every voice recorder variant.
`vpuMask`/`vadMask` describe per-frame state; even signed all-ones masks do **not**
establish a separate VPU waveform. Their exact values are retained in reports;
no unverified mask-bit channel layout is invented. No real capture has been
tested. The separate ordinary recording converter's 48 kHz stereo assumptions
are not applied. Undecodable sessions have diagnostics, null unavailable metrics,
and no fabricated WAV/blank PNG.

**Synthetic fixtures only:** the tests explicitly identify generated
interleaved little-endian PCM with the following extension. This is not required
or interpreted as a format override for real captures:

```json
{
  "synthetic": true,
  "audioFormat": {
    "codec": "pcm_s16le",
    "sampleRate": 16000,
    "channels": ["air", "vpu"],
    "layout": "interleaved",
    "provenance": "synthetic"
  }
}
```

Synthetic PCM packets also require `audioStartSeconds`. Rates 12–48 kHz,
one to four unique explicit channels (`air`, `vpu`, `channel-0` … `channel-3`)
are supported. This lets the synthetic suite prove deinterleaving and
channel-specific metrics without making an unsupported claim about captures.

Generated native Opus fixtures can instead declare `synthetic: true` with
`audioFormat: {"codec":"opus","sampleRate":16000,"channels":["lifelog-mono-unassigned"],"layout":"mono","provenance":"synthetic"}`
(or `voice-mono-unassigned` for voice). They follow exactly the bounded native
profile and receipt-based timing, not explicit PCM timestamps. The tests generate
encoded tones through existing libopus and use valid native packet padding where
fixed 240-byte test packets are needed. They are not recordings.
Caller-supplied synthetic provenance is a test declaration, not attestation.
The report always partitions synthetic and real results; a capture-format
override is ignored outside explicitly synthetic fixtures.

## Official passive LifeLog dumps (Amendments 1/1a)

The current app's proven audio path is the official debug Ogg dump, captured
passively while the user starts/stops LifeLog in the official app. The offline
decoder sends nothing. An empty `packets` array and empty `envelopes.rnp` are valid.
The manifest can attach:
- `officialDump[]`: `file` beneath `official-dump/`, `sourceKind` =
  `realtime|cached|unverified`, bounded `bytes`, SHA-256, boolean
  `copyFinalized`, and **`alignment: "unaligned"`**. This manifest declaration
  stays unchanged; output alignment is derived separately.
- `officialEvents: {"state":"attached","file":"official-events.jsonl",...}`.
  Only the pinned allow-listed timestamp/tag/mask/frame/byte/count fields are
  accepted; text/payload/nested fields are not echoed into reports.
- `startWallMs` and `officialCounters[]` rows containing monotonic `t`,
  simultaneous epoch-ms `wallMs`, cumulative `realtimePackets`/
  `cachedPackets`, and `alwaysOnRunning`. Null counters are unavailable,
  not zero. Counter resets invalidate a delta, not fabricate packet loss.

Folders and wrapped ZIPs load only declared bounded sidecars. Paths, links,
file types, lengths, copy-finalized status and SHA-256 are checked. ZIPs are never
extracted. Each Ogg page's CRC, serial, sequence, continuation/lacing, headers,
granules and EOS are validated before the complete file is admitted. Parsing
follows `AlwaysOnOgg.m`'s bounded official subset: one logical Opus stream,
mapping-family 0, header channel count 1 or 2, corrected TOC-total granules or the
known legacy **960-at-48-kHz per packet plus pre-skip** clock. Arbitrary chained
streams/end-trim conventions are not guessed. The legacy clock is wrong for
60-ms packets: audio duration comes from packet TOCs, never those increments.
Native TOCs must be mono and match the inferred expected 60-ms LifeLog profile,
even when the container's template declares two channels. Each Ogg logical stream
is decoded **once with continuous Opus prediction state**. Timing-only event gaps
split the time axis, not the codec state: segments are slices of that same source
sample stream. Inconsistent overlapping aligned placements downgrade to one
file-local waveform with recall unavailable, preserving samples rather than
double-counting overlapping session intervals. OpusHead pre-skip
(48-kHz units, rounded conservatively to one 16-kHz sample) and output gain are
applied. A file is limited to 125 decoded seconds plus pre-skip and gets no PLC.

Derived alignment is explicitly one of:
- **event-wallclock**: only timestamps numerically in **1.5e12–2.5e12** are
  treated as epoch milliseconds and mapped using the nearest simultaneous
  monotonic/wall anchor. Ordered realtime event frameCounts must account for
  every Ogg packet, and the cumulative realtime-counter **delta** must agree
  with the number of batches. In addition, each actual counter activity interval
  must contain exactly its increment's worth of mapped events. Matching totals
  with incompatible activity windows/count distributions downgrade association
  and recall: delayed-counter semantics are not validated. Durations come from
  native TOCs; no counter
  value is converted into a frame/sample offset. The estimated bookkeeping
  uncertainty includes anchor-offset spread, maximum batch duration and 1 ms.
- **counters-coarse**: only a session activity window is established. Audio stays
  on a file-local clock. Uncertainty is at least 0.25 s plus batch duration;
  when batch size is unknown the whole file duration is used conservatively,
  with observed anchor drift added. Recall is unavailable.
- **none**: no defensible unique anchored correspondence. Audio is still decoded
  on a file-local clock, but recall is unavailable.

Epoch seconds, ISO strings, relative timestamps and unknown units are **not**
silently converted. Wall time maps official events only; it never replaces
monotonic marks/counter times. Anchor drift is the spread of `wallMs - 1000*t`;
without wall anchors it is unavailable, not a measured zero.

Only one uniquely identified realtime dump can supply the primary channel's
analysis. Cached/unverified history and multiple realtime files still get
separate decoded WAVs/reports, but are not pooled into session exposure. Raw
envelopes are never pooled with an official dump selected for analysis.
Unaligned audio can support file-local negative exposure, not mark recall.
Aligned marks require uncertainty no greater than the requested tolerance and
an expanded complete observation window. Excessive drift therefore makes recall
unavailable rather than producing precise-looking matches. Unaligned plots
suppress mark overlays and explicitly label their file-local clock.

These uncertainty values are minimum bookkeeping estimates, **not verified
bounds**: source/transport latency remains unknown. No actual official dump or
device session has been tested by Lane T; generated native Ogg fixtures are not
real-capture validation.

## Audio timeline, arrival gaps, and loss

Neither voice nor LifeLog has a verified source audio timestamp in this format.
Native timing is planned offline from checked packet sample counts **before**
decoding. Contiguous envelopes arriving within a **5-ms span** form a receipt
burst (a documented reconstruction heuristic, not a firmware timing guarantee).
LifeLog frames within one envelope already share that envelope's receipt time.
A burst's start is back-anchored using every contributing packet's arrival
constraint, not just the first arrival. This preserves equal/slightly jittered
buffered arrivals without advancing later samples beyond their own receipt.

Adjacent bursts join only when their reconstructed cadence agrees within
**50 ms**. The complete buffered run may shift earlier to satisfy a later
receipt constraint, never past any packet's receipt. Timing uses integer sample
ticks and always checks the packet's decoded end against its own arrival.
A larger cadence mismatch starts a new run. These heuristics cannot distinguish
all source-clock drift, small unobserved gaps, or transport buffering; neither
zero latency nor exact physical alignment is established.

Arrival delays over 200 ms are reported independently and need not imply loss:
a sufficiently long valid batch can account for the time. Observed index/sequence
discontinuities, malformed audio, and decode failures always break analysis runs,
even if times are adjacent. A failed batch's known planned duration is not
compressed out of a run. Sequence counter meaning and rollover are not verified;
discontinuities are **not** a proven count of missing audio packets.

No packet-loss concealment, silent filler, resampling to the session duration,
or bridging of unobserved gaps is performed. Raw-envelope decoder state resets
at audio discontinuities; Ogg logical-stream prediction state stays continuous
across timing-only gaps. Raw overlaps that cannot be placed without reusing time are excluded
with diagnostics. Samples preceding session start are trimmed, never converted
into valid pre-audio exposure. WAVs are one file per channel per contiguous run;
`decode.json` records each file's absolute **session-relative** start/end.
WAV time zero alone is not a mark-alignment clock.

`knownLocalDroppedPackets` copies the manifest's local drop count.
`networkLossPackets` is null: arrival delay, absent frames and sequence/index
jumps alone cannot prove transport loss. `audioTimelineGaps` reports unobserved
reconstructed time, not a claim that the glasses recorded and lost that interval.
Unknown transport/buffering/codec latency remains a real mark-alignment
uncertainty; a sample-accurate physical tap timestamp is not claimed.

## Detector, SNR, and metric definitions

Fixed, untuned baseline:

1. Causal fourth-order Butterworth bandpass, 300 Hz–5 kHz.
2. Centered 4 ms energy smoothing. Threshold is the maximum of 10× run-median
   energy, median + 12× median absolute deviation, and a 1e-10 FS² floor.
3. Merge threshold holes up to 4 ms; accept transients lasting at most 45 ms.
   Sustained synthetic speech-like bursts are rejected, not a guarantee about
   real speech/chewing. Use an 80 ms onset refractory period.
4. Pair the earliest pending onset with its first partner **150–600 ms**
   later, endpoints inclusive. Sub-150-ms events do not extend the window;
   too-late events replace the pending event. Every onset is used at most once.
   Trigger timestamp is the second onset.

The first 30 ms and final 30 ms of each run are filter-edge exclusions. Detector
exposure additionally excludes the first 600 ms for complete double-event
lookback. Short runs therefore can have decoded audio but zero analyzed
exposure. No event is paired across runs.

Marks represent gesture completion/button press. By default a prediction may
match a mark within **±350 ms** of its second onset. `--mark-tolerance` allows
0–1 seconds; its actual value is saved. Marks are recall-eligible only when their
entire tolerance interval is inside a single detector-coverage interval.
This excludes marks before audio, near start/end or across gaps, and reports
each exclusion. Sorted one-to-one maximum-cardinality matching means one
prediction never credits two marks, and one mark never credits two predictions.
Recall = matched eligible double-tap marks / eligible double-tap marks; it is
null when none are eligible. Inspect eligible and excluded counts together;
exclusion can make observed recall look better than full-session recall.

For each eligible mark, the strongest 8 ms band-energy window within its
tolerance is reported. Transient energy is the sum of squared normalized
bandpassed samples / sample rate, units FS²·seconds. The noise reference is
median equal-window energy 80–250 ms before that peak; click SNR is
10 log10(total peak-window energy / median local noise-window energy), not a
noise-subtracted or perceptual SNR. Peak selection has an upward selection bias,
and a button-press offset can select an unrelated transient. It is a diagnostic,
not evidence of a tooth tap.

False triggers/minute = all double-event predictions on each named negative
label × 60 / **actual analyzed channel exposure in seconds**, not wall-clock
capture duration. Missing/undecodable exposure yields null, not a zero-error
result. Counts/exposure are summed before combined rates are calculated.
Reports give each channel separately and each negative label separately,
plus exposure-weighted talk+chew. Independent channels are never added together
to manufacture more observation time. Single-tap and true-clench are comparison
labels, not included in the requested negative-rate aggregation.

## Outputs and interpretation

- `decode.json`: capture/profile provenance, diagnostics, known local drops,
  observed gaps/discontinuities, decoded envelope/frame counts, per-envelope
  `packetTiming` receipt constraints, `packetStateMetadata` masks/count/sequence,
  per-run sample counts/times and WAV filenames.
- One mono WAV per decoded channel/run, no padded gaps. Official files also get
  separately named `official-NNN-lifelog-mono-unassigned-NNN.wav` files and
  `officialDumps[]` entries with container/granule, clock, alignment/uncertainty
  and per-file error metadata. `officialDecodedFrames` is separate from raw
  envelope `decodedPackets`; counter deltas and mapped event times are reported.
- `analysis.json` per session: analyzed coverage, onsets, double events,
  one-to-one matches, exclusions, SNR/band-energy diagnostics, recall and rates.
- `spectrogram.png` per decodable session: session-relative spectrograms,
  cyan ground-truth marks and green dashed trigger times. Gaps stay blank.
- Combined `report.json`: per-session results/errors and exposure-weighted
  per-channel summaries, with synthetic and real results strictly separated.

The reference thresholds are **recall ≥90%** and **≤0.1 false triggers/minute
during talking or chewing**. They are printed, never adjudicated by these tools.
A zero-error short clip is not statistical proof of that rate. Several
30-second captures are needed even to accumulate ten minutes per negative;
a held-out, representative user dataset and independent review are necessary.
No user-captured data has been analyzed by this lane.

## Offline tests

`tests.py` generates noise, contact-like clicks, speech-like bursts, explicit
two-channel fixtures, real-profile libopus silence packets (synthetic source
bytes), malformed envelopes/manifests and hostile ZIP metadata. Tests cover:

- Onset/double timing bounds, nonreuse/refractory, click recall and noise/burst rejection.
- One-to-one matching, late audio, excluded marks, discontinuous/short exposure,
  exact false-trigger denominators and null missing-data metrics.
- Deinterleaving, independent per-channel/synthetic-vs-real aggregation, and no
  VPU claim from a mask; unverified capture format overrides are ignored.
- Native local voice/LifeLog decoding if libopus exists; 100 buffered voice
  packets retain all 32,000 samples/2 seconds and positive exposure under equal,
  within-burst-jittered, and cadence-jittered arrivals, with no packet ending
  after its own receipt.
- Generated valid fixed-size native LifeLog packets, A3/A4 batching, exact
  sequential frame output, TOC duration/mono checks, malformed counts/lengths/
  metadata, whole-batch decode-error exclusion, prediction-state resets, and
  conservative gaps/sequence/index boundaries.
- WAV sample/time preservation, private file modes, folder/ZIP equivalence,
  native decode/analysis CLI output and synthetic/real provenance separation.
- Framing/JSON/protobuf bounds, provenance/clock/type validation, ZIP traversal,
  symlinks, duplicate/multiple manifests, compression bombs and file limits.
- Huge integers in numeric fields become validation errors without float overflow.
  Corrupt deflate streams and malformed UTF-8 ZIP names become SessionError at
  the ZIP boundary. JSON exponent overflow is rejected by the float parser even
  in nested/ignored metadata, before infinity can enter reports. Standalone
  CLI errors have no traceback, and combined reports retain valid sessions
  alongside per-input errors.
- End-to-end isolated CLI, PNG/JSON output, duplicate-session protection and
  refusal to overwrite prior output.
- Passive 120/125-second limits and empty raw packets; generated official Ogg
  legacy/corrected granules, pre-skip, lacing/continuation, malformed CRC/EOS/
  serial/sequence, fixed-size TOC mismatches, safe folder/ZIP sidecars and CLI
  WAV/PNG/combined-report output.
- Official epoch-ms event/anchor alignment, cumulative nonzero counter baselines,
  counter resets/count mismatches, unknown timestamp units, unaligned/coarse
  recall suppression, wall-clock drift uncertainty and cached/duplicate-file
  non-pooling. Integrity, allow-list, symlink/path and huge-sidecar-number bounds.

Native-success tests skip if local libopus is absent; on the measured local run none skipped.
Synthetic performance demonstrates implementation behavior, not real feasibility.
