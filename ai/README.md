# MOTHERLODE AI

## Overview

MOTHERLODE has a hybrid AI setup consisting of:

* Ollama for local inference
* Qwen3 local models
* NVIDIA GTX 1050 Ti GPU acceleration (**currently unavailable**: card removed 2026-10-04, Ollama is CPU-only until it returns compute-only. See `docs/hardware/GPU.md`)
* Pi coding agent
* Cloud AI providers through Pi

The goal is to have a useful local AI system while retaining cloud models for workloads where local inference is too slow or insufficient.

---

## Hardware

```text
CPU: Intel Core i7-6700
RAM: 16 GiB
GPU: NVIDIA GeForce GTX 1050 Ti (removed 2026-10-04, untested)
VRAM: 4 GiB
OS: Debian 13 Trixie
```

---

## Local AI

### Ollama

Ollama runs locally:

```text
http://localhost:11434
```

OpenAI-compatible API:

```text
http://localhost:11434/v1
```

Verify:

```bash
curl -s http://localhost:11434/api/tags
```

or:

```bash
curl -s http://localhost:11434/v1/models
```

---

## Current Local Models

### Qwen3 4B

```text
qwen3:4b
```

Quantization:

```text
Q4_K_M
```

Size:

```text
~2.5 GB
```

Context:

```text
262,144 tokens
```

Capabilities:

```text
completion
tools
thinking
```

This is the preferred local model for interactive Pi use because it fits the 4 GB GPU much better than the 14B model.

---

### Qwen3 14B

```text
qwen3:14b
```

Quantization:

```text
Q4_K_M
```

Size:

```text
~9.3 GB
```

Context:

```text
40,960 tokens
```

Capabilities:

```text
completion
tools
thinking
```

This model is retained as a larger local option but is considerably slower on the current hardware.

---

# Pi

Pi is installed for the `ghost` user.

Executable:

```text
/home/ghost/.pi/agent/bin/pi
```

Pi configuration:

```text
~/.pi/agent/
```

Custom model configuration:

```text
~/.pi/agent/models.json
```

Authentication:

```text
~/.pi/agent/auth.json
```

`auth.json` contains credentials and MUST NOT be committed to Git.

---

## Ollama → Pi

Pi connects to Ollama using its OpenAI-compatible API.

Current configuration:

```json
{
  "providers": {
    "ollama": {
      "baseUrl": "http://localhost:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "models": [
        { "id": "qwen3:4b" },
        { "id": "qwen3:14b" }
      ]
    }
  }
}
```

This lives on the machine at:

```text
~/.pi/agent/models.json
```

The file is intentionally NOT stored in this repository as the source of truth for Pi authentication.

This repository documents the configuration so the setup can be recreated.

Pi's model configuration supports local Ollama providers through `models.json`.

---

## Checking Pi Models

Inside Pi:

```text
/model
```

Pi reloads the custom model configuration when `/model` is opened.

Expected local models:

```text
qwen3:4b [ollama]
qwen3:14b [ollama]
```

---

## Cloud AI

Pi can also authenticate with cloud providers.

Cloud credentials must remain outside Git.

The cloud model catalog is dynamic and may contain models that are not actually available to the authenticated account.

Therefore:

> Never document a cloud model as supported merely because it appears in `/model`.

Test the model first.

---

## Recommended Roles

### Local Qwen3 4B

Use for:

* fast local work
* private information
* simple coding
* troubleshooting
* shell assistance
* experiments

### Local Qwen3 14B

Use for:

* larger local reasoning tasks
* situations where keeping data local matters more than speed

### Cloud models

Use for:

* demanding coding
* long reasoning tasks
* tasks where local inference is too slow
* workloads requiring capabilities unavailable locally

---

## AI Safety Rules

AI agents working on MOTHERLODE must follow:

1. Read `AGENTS.md`.
2. Inspect the existing system before changing it.
3. Never expose secrets.
4. Never blindly modify ZFS.
5. Never blindly reinstall NVIDIA.
6. Read `docs/recovery/NVIDIA-DRIVER-INCIDENT.md` before changing NVIDIA packages.
7. Prefer small changes.
8. Verify changes after applying them.
9. Update documentation after significant changes.

