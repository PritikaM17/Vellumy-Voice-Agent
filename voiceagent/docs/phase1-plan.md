# Voice Health Assistant — Phase 1 Plan

## Context

We changed several ideas in conversation (embeddings, BODHI-S, removing doctor languages, a view for "who booked whom"). It got confusing. This plan pins down **one simple design** for Phase 1 and the **order to build it**. Pritika writes the code; Claude gives hints and reviews each step.

**Phase 1 goal:** Priya speaks (English) → emergency check → we suggest the right specialist (never a diagnosis) → find a free slot → book it → the dashboard shows it live.

**Decisions locked in**
- **Pipecat is the conveyor belt** for the voice part: WebRTC audio, VAD, turn-taking, interruptions, and calling our tool functions. It does *not* listen/think/speak itself — services plug into it (one line each). Database, rules, embeddings, routing and dashboard API are **our own Python/FastAPI**, not Pipecat.
- Language: **English only.** Hinglish is a later upgrade (and a good video moment).
- Matching: **BODHI-S rules + embeddings top-5 + LLM picks**.
- Rule: **the LLM understands, Python decides.** The LLM never touches the database.
- Keep it simple: no vector database, no WebSockets (dashboard polls every second), no logins (pick a fake patient from a dropdown).

**Models and services**

| Job | Pick | Backup |
|---|---|---|
| Audio connection | Pipecat **SmallWebRTC** (free, no account) | — |
| VAD | **Silero** (runs locally) | add Pipecat **smart turn** in Step 6 only if it replies too early |
| Speech → text | **Deepgram Nova-3**, English, streaming | — |
| Main LLM | **Groq `llama-3.3-70b-versatile`** (free, very fast) | **Claude Haiku 5.5** (`claude-haiku-5-5`) if tool calls are unreliable |
| Picker LLM (1 of 5) | **Groq `llama-3.1-8b-instant`** | same as main LLM |
| Text → speech | **Cartesia Sonic**, calm clear voice | Deepgram Aura-2 (one fewer account) |
| Embeddings | **fastembed `BAAI/bge-small-en-v1.5`** (local) | — |

Accounts needed: **Groq (have it), Deepgram, Cartesia.** Check Groq's models page that the model names still exist before Step 3.

**Keep the LLM swappable (rules from day one)**
1. Write tools in Pipecat's neutral format (`FunctionSchema` / `ToolsSchema`), not Groq's own format.
2. The main LLM is **one line** in `bot.py`.
3. The picker call lives in **one function**, `pick_symptom(phrase, candidates)` in `routing.py`.
4. After any switch, re-run the 10 test conversations and the evals.

Speed budget (target < ~1 s): Deepgram ~300 ms + Groq first words ~200–400 ms + Cartesia first sound ~100–200 ms. `report_symptoms` adds ~0.3–0.5 s → the agent says "Let me check that for you" first.

---

## Part A — The full workflow (one conversation)

```
Browser: Priya picks "Priya Sharma" from dropdown → clicks "Start call"
   │  audio (WebRTC, straight to Python)
   ▼
1. VAD  — is she speaking? (Silero)   ┐
2. STT  — Deepgram → text             │ Pipecat pipeline
3. SAFETY CHECK #1 (Python)           │
   red_flags phrases vs her raw words │
   match → speak fixed ER/112 message,│
           lock booking, STOP         │
4. LLM (Groq) — understands, talks,   │
   calls tools                        │
5. TTS  — Cartesia → speech back      ┘
```

**What happens when Priya says** *"My eyes have turned yellow and I keep vomiting":*

| # | Who | What happens | Database |
|---|---|---|---|
| 1 | STT | Turns voice into text | — |
| 2 | Python | Safety check #1 on raw text → no red flag | reads `red_flags` |
| 3 | LLM | Calls `report_symptoms(["yellow eyes", "vomiting"])` — short phrases | — |
| 4 | Python | Safety check #2 on the LLM's phrases (catches emergencies described in other words) | reads `red_flags` |
| 5 | Python | Embeds each phrase, finds 5 closest of 591 symptoms (numpy, in memory) | embeddings loaded at start from `symptoms` |
| 6 | Python | `pick_symptom()` — one small Groq call: "pick one of these 5, or none" → Jaundice, Vomit | — |
| 7 | Python | Routing (below) → Gastroenterologist | reads `symptom_rules`, `specialties`, `patients` |
| 8 | Python | Saves one row per symptom | writes `symptom_logs`, `tool_calls` |
| 9 | LLM | "A gastroenterologist — a doctor for stomach and liver — is the right doctor. Shall I find one?" | — |
| 10 | LLM | Priya: "tomorrow morning" → `find_slots("Gastroenterologist", "2026-10-20", "morning")` | reads `doctors`, `doctor_slots`, `appointments` |
| 11 | LLM | Reads out 2–3 times. Priya picks 10:30 → `book_appointment(slot_id=14)` | writes `appointments` |
| 12 | Browser | Dashboard polls `/api/dashboard` + `/api/tool-calls` every 1s → shows it | reads view `appointment_details` |

**Routing order inside Python (step 7)** — first match wins:
1. Emergency already found → no booking.
2. Patient under 14 → **Paediatrician**.
3. For each symptom: no confident pick, or no rule → **General Physician**.
4. Specialty doesn't fit gender (Gynaecologist for a man) → **General Physician**.
5. Symptoms point to **different** specialists → **General Physician**.
6. Otherwise → that specialist.

Each `symptom_logs` row stores a `reason` (`rule`, `child`, `gender`, `mixed`, `no_match`, `emergency`) so we can always explain *why*.

---

## Part B — Database (10 tables + 1 view)

| Table | Columns (short) | Filled by |
|---|---|---|
| `specialties` | id, name UNIQUE, plain_description, for_gender ('any'/'female'/'male') | build_rules.py |
| `symptoms` | id, snomed_id, name UNIQUE, embedding BLOB | build_rules.py |
| `symptom_rules` | symptom_id (PK → symptoms), specialty_id, vote_share | build_rules.py |
| `red_flags` | id, phrase, response_message — English phrases, hand-written | seed.py |
| `doctors` | id, name, specialty_id, fee | seed.py |
| `doctor_slots` | id, doctor_id, starts_at; UNIQUE(doctor_id, starts_at) | seed.py |
| `patients` | id, name, phone UNIQUE, date_of_birth, gender CHECK | seed.py |
| `symptom_logs` | id, patient_id, raw_text, phrase, matched_symptom_id NULL, similarity NULL, suggested_specialty_id NULL, reason, is_emergency, created_at | agent |
| `appointments` | id, patient_id, slot_id, symptom_log_id NULL, status CHECK, created_at | agent |
| `tool_calls` | id, tool_name, args_json, result_json, created_at | agent (for the tool panel + debugging) |
| **view** `appointment_details` | patient \| doctor \| specialty \| time \| status | — |

Plus: partial unique index (no double booking), and indexes named `idx_*` (`check_schema.py` only lists names starting with `idx_`).

What changed vs. the first diagram (now redrawn as v2): `body_area`/`symptom_type` gone; `symptoms` + `tool_calls` added; `for_gender` on specialties; `matched_rule_id` → `matched_symptom_id` + `reason`. Variants are **not** stored (we embed the 591 root names only).

---

## Part C — Build order (step by step)

Each step ends with something you can **run and see**. Don't start the next step until the check passes.

### Step 0 — Setup check (½ day)
- `pip install "pipecat-ai[silero,deepgram,cartesia,groq,webrtc]" fastembed numpy`
- **Risk:** Python 3.14 may lack wheels (onnxruntime). If install fails → make a new **Python 3.12 x64** venv. Decide here, not later.
- `.env` with GROQ / DEEPGRAM / CARTESIA keys. Add `data/bodhi-s/` to `voiceagent/.gitignore`.
- Rename DB in `server/db.py`: `coaching.db` → `health.db`.
- ✅ Check: `python -c "import pipecat, fastembed"` works.

### Step 1 — Data (3–4 days)
1. `server/schema.sql` — the 10 tables + view + indexes. ✅ `python -m server.check_schema`
2. `server/build_rules.py` — BODHI CSVs → specialties (after MERGE/SKIP lists), symptoms, symptom_rules (vote: winner ≥40% **and** ≥1.5× runner-up). Prints report: "N rules, M → GP".
3. `server/embeddings.py` — `embed(texts)` and `top_k(phrase, k=5)` using fastembed `bge-small-en-v1.5`. build_rules stores each symptom's embedding.
4. `server/seed.py` — one command rebuilds everything: delete DB → schema → build_rules → fake patients (incl. 1 child, men + women), 1–2 doctors per specialty in use, slots for next 7 days, red flags.
5. Hand review: 39→~25 specialties, `plain_description` for each, top 50 common symptoms' rules, red flag list.
- ✅ Check: `python -m server.seed` prints the report; `SELECT * FROM appointment_details` works.

### Step 2 — Python logic, no voice (2–3 days)
- `server/safety.py` — `check_red_flags(text)` → message or None.
- `server/routing.py` — `match_symptoms(phrases)` (top-5 + `pick_symptom()`) and `route(patient, matches)` (the 6-step order above).
- `server/tools.py` — `report_symptoms`, `find_slots`, `book_appointment`, `cancel_appointment`, `my_appointments`. Each one logs to `tool_calls`. Reuse `get_conn`, `rows`, `one` from `server/db.py`.
- `server/main.py` — add `/api/dashboard?patient_id=`, `/api/tool-calls?after=`, and POST endpoints for each tool so you can test in `/docs`.
- ✅ Check: in `/docs`, "yellow eyes" → Gastroenterologist; book same slot twice → second fails.

### Step 3 — Make it talk (2 days)
- `server/bot.py` — bare Pipecat pipeline: SmallWebRTC → Silero VAD → Deepgram Nova-3 → Groq → Cartesia. **No tools yet.**
- Mount the WebRTC offer endpoint in `main.py`; test with Pipecat's sample browser client first.
- ✅ Check: you talk, it answers in under ~1 second.

### Step 4 — Safety + tools (3 days)
1. Safety processor (custom Pipecat FrameProcessor between STT and LLM) — test emergency first, before any tool.
2. System prompt: never diagnose, short phrases in tool calls, confirm before booking, say "let me check" before slow tools.
3. Add tools **one at a time** (Pipecat neutral format): report_symptoms → find_slots → book_appointment → cancel/my_appointments.
4. **LLM test:** 10 scripted booking conversations on Groq. Count wrong tool calls (booked without confirming, made-up slot_id, wrong tool). More than 1–2 mistakes → switch to Claude Haiku 5.5 (one line) and re-test.
- ✅ Check: full booking by voice; "I have chest pain" → ER/112 message, booking locked.

### Step 5 — Next.js page (2–3 days)
- `web/`: patient dropdown, Start/Stop call button, dashboard (symptoms + appointments), tool-call panel. Polls the two `/api/...` endpoints every second.
- ✅ Check: book by voice → appears on page within 1–2 s.

### Step 6 — Break it (1–2 days)
Interrupt mid-sentence, change mind ("actually Thursday"), slot taken, long pauses while describing symptoms (→ add smart turn if it replies too early), a child patient, a man with burning urine, mixed symptoms, emergency mid-booking.

### Step 7 — Evals + demo (2 days)
`evals/`: (a) 50 phrases → correct symptom (top-1 accuracy), (b) routing cases → correct specialty, (c) emergency phrases → **must be 100%**. Then record the demo.

---

## Folder layout at the end of Phase 1

```
voiceagent/
  data/bodhi-s/          (gitignored, CC BY-NC — credit Eka Care in README)
  docs/                  (this plan + diagrams)
  server/  main.py  db.py  schema.sql  check_schema.py
           build_rules.py  seed.py  embeddings.py
           safety.py  routing.py  tools.py  bot.py
  evals/   phrases.csv  run_evals.py
  web/     (Next.js)
```

## Later phases (not now)
- Hinglish (test Sarvam vs Deepgram for STT, Sarvam vs Cartesia for TTS)
- Phase 2: lab test booking · Phase 3: prescription upload + medicines

## Verification (end of Phase 1)
1. `python -m server.seed` → fresh DB + report.
2. `uvicorn server.main:app` + `npm run dev` in `web/`.
3. Pick patient → speak the Priya example → appointment appears on dashboard, tool panel shows 3 calls.
4. Speak an emergency phrase → fixed ER/112 message, no tool calls.
5. `python -m evals.run_evals` → emergency 100%, matching and routing scores printed.
