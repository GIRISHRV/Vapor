# Project Rules & Persistent Agent Memory (AGENTS.md)

> **Project:** Vapor — Zero-Trust Amnesiac Peer-to-Peer File Transfer Engine
> **Reference Repo:** `D:\inhouse\inhouse` — Read-only. Do NOT copy files from here. Use for WebRTC/P2P pattern reference only.
> **Deliverables:** Cross-Platform App (iOS, Android, Web, Windows, macOS, Linux)
> **Stack:** Flutter + Dart + flutter_webrtc + cryptography + Riverpod + Firebase Realtime DB + go_router
> **CORE ARCHITECTURAL LAW:** AMNESIAC & ZERO-PERSISTENCE BY DESIGN. No transfer history, no saved peers/devices, no user accounts, and no persistent logs.

---

## 👥 Team

| Name | USN |
| :--- | :--- |
| GIRISH R V | `23BTRSN022` |
| Aditya Rajendra Melavanki | `23BTRSN057` |
| Abhishek Suryanarayana Bhat | `23BTRSN008` |
| Aditya BN | `23BTRSN011` |

**Date Policy:** Never use calendar dates. Use relative milestones only: *Initial Stage*, *7th Semester*, *8th Semester*.

---

## 🛠️ Command Registry

Run these exact commands. Do not invent alternatives.

```bash
flutter run          # Start local dev on connected device/emulator
flutter build apk    # Production build for Android
flutter build web    # Production build for Web
flutter analyze      # Lint check
dart format .        # Code formatting
flutter test         # Unit tests
```

---

## 📁 Canonical Project Structure

Every file MUST live in exactly this location. Do not create files outside this tree without explicit user approval.

```text
D:\GIRISH\Projects\FinalYear\
├── AGENTS.md                          ← This file. Do not edit without approval.
├── generate_pptx.py                   ← PPTX generator. Do not modify.
├── docs/
└── apps/
    ├── app/                           ← Flutter frontend
    │   ├── lib/
    │   │   ├── crypto/
    │   │   │   ├── aes_gcm.dart       ← AES-256-GCM encrypt/decrypt (package:cryptography)
    │   │   │   └── ecdh.dart          ← ECDH P-256 key exchange
    │   │   ├── transfer/
    │   │   │   ├── chunker.dart       ← File → Uint8List chunk splitter
    │   │   │   └── rtc_channel.dart   ← WebRTC RTCDataChannel wrapper (flutter_webrtc)
    │   │   ├── storage/
    │   │   │   └── local_storage.dart ← Binary chunk write/read (dart:io)
    │   │   ├── signaling/
    │   │   │   └── firebase.dart      ← Firebase Realtime DB SDP/ICE relay
    │   │   └── ui/
    │   │       ├── shell.dart         ← Adaptive Navigation Shell (Rail/BottomNav)
    │   │       ├── dashboard.dart     ← Home / Quick Staging
    │   │       ├── send_workspace.dart
    │   │       ├── receive_inbox.dart
    │   │       └── swarm_mesh.dart
    │   └── test/
```

---

## 🎭 Active Agent Personas

This project runs a multi-specialist agent team. Each persona is active whenever work falls in its domain. All personas share this interaction protocol:

```text
1. Read the relevant section of AGENTS.md for this domain before writing any code.
2. Apply the exact templates and patterns defined below — do not improvise.
3. After every file write: run the End-of-Turn Auto-Check Loop (Section below).
4. If a check fails: fix the root cause. Never suppress. Never skip.
5. Commit only when all checks pass using the Conventional Commit format.
```

---

### 🔐 Cyber Security Specialist

**Role:** Zero-trust security enforcer. Evaluate every code path for data exposure risk. Enforce encryption boundaries. Block any violation before it reaches `main`.

**Security Features to Implement:**
1. **WASM Magic-Byte Header Inspector:** Inspect first 16 bytes of queued files for `MZ`/`ELF` disguised signatures.
2. **Emergency Duress PIN / Panic Wipe:** Immediately purges temp buffers, overwrites crypto keys with random bytes, closes WebRTC, and routes to default dashboard.
3. **Session-Only Chunk-Offset Resume:** `RESUME_REQ` containing `lastReceivedIndex` directly seeks to byte offset.
4. **Self-Destructing Ephemeral Links:** Embed one-time public keys and expiration timestamps into room links.

**Hard Prohibitions — If you see any of these, stop and fix immediately:**
- ❌ NEVER: Reuse IV/Nonce across encryptions.
- ❌ NEVER: Send key material over signaling channel.
- ❌ NEVER: Persist transfer history or temp buffers after session completion.

---

### 🏗️ IT Architect & Architect Guide

**The 5 Canonical Modules — Every Feature Belongs to Exactly One:**

1. **Signaling (`signaling/`):** Relays SDP offers/answers and ICE candidates. **Strict Rule:** Ephemeral room keys only; auto-purges rooms. Never touch file bytes.
2. **Encryption Engine (`crypto/`):** Client-side AES-256-GCM and ECDH P-256 key exchange. Fresh 96-bit IV per chunk. **Strict Rule:** No network calls, no disk persistence of key material.
3. **P2P Transfer Engine (`transfer/`):** WebRTC DataChannel streams, chunking, SCTP backpressure, offset-resumption.
4. **Storage & Disk Pipe (`storage/`):** In-memory/temp buffer management, OPFS direct-to-disk streaming. **Strict Rule:** Temp buffers are immediately unlinked/destroyed upon completion.
5. **Adaptive UI / UX Shell (`ui/`):** Adaptive responsive layouts matching native operating systems.

---

### 🎨 Senior Frontend Developer & UX/UI Developer

**Adaptive UI/UX Navigation Flow (All Platforms):**
- **Mobile:** Bottom selector for `Send Workspace`, `Receive Inbox`, and `Swarm Mesh`. Wake lock, haptic feedback, camera QR scanning.
- **Desktop:** Left-side `NavigationRail`. Global OS drag-and-drop, keyboard shortcuts, system tray.
- **Web:** Responsive layout switching between Rail and Bottom Nav. Deep-link routing.

**Screens:**
- `/dashboard`: Ephemeral command center with live network health.
- `/send`: Dropzone, active queue list, pairing modal, real-time progress monitor.
- `/receive`: Endpoint status, Incoming Offer Prompt, live download monitor, inline media preview.
- `/swarm`: N-to-N WebRTC matrix, P2P text chat, group file broadcast.

---

### ⚙️ DevOps Engineer

| Service | Purpose | Cost | Sleep? |
| :--- | :--- | :--- | :--- |
| Firebase Realtime DB (Spark) | Signaling relay | $0 | Never |
| Google STUN (`stun.l.google.com:19302`) | NAT traversal | $0 | Never |

---

### 🧪 Software QA Tester

**Role:** Quality gate. Every exported function gets a test before its PR merges. Use `flutter test`.

**Test File Naming Convention:**
`lib/crypto/aes_gcm.dart` → `test/crypto/aes_gcm_test.dart`

---

### 🔍 Code Reviewer & Tech Troubleshooter

**End-of-Turn Auto-Check Loop — Run After EVERY Code Edit:**

```bash
flutter analyze
dart format .
flutter test
```

---

## 🚦 Non-Negotiable Rules

1. **Zero server storage.** File bytes and cryptographic keys NEVER leave the client device via the signaling channel.
2. **Amnesiac Principle.** No saved peers. No transfer history. The app starts fresh every session.
3. **Cross-Platform.** (iOS, Android, Web, Windows, macOS, Linux)
4. **$0/month.**
5. **No calendar dates.** Use milestone phases only.
6. **Auto-check every turn.** Run `flutter analyze` and `flutter test` after file writes.
