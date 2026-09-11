# Bhashini API Models — Relevance & Usage Analysis for iTantra

> **Future Reference Document**  
> Source: [Bhashini Available Models Documentation](https://dibd-bhashini.gitbook.io/bhashini-apis/available-models-for-usage)

---

## Overview

Bhashini provides government-backed, hosted AI microservices for Indian languages.  
This document catalogs which Bhashini services map to iTantra's pipeline stages, potential future use cases, and key architectural constraints.

> [!CAUTION]
> **Key Architectural Constraint:** All Bhashini endpoints are **cloud-hosted APIs** requiring internet connectivity.  
> iTantra is designed as an **offline-first**, on-device transceiver for disaster and satellite mesh environments. Therefore, Bhashini models serve as **optional online fallbacks**, **benchmarking baselines**, or **validation tools**, rather than replacements for on-device ONNX models.

---

## 1. Directly Usable Models (1:1 Pipeline Mapping)

### 🎙️ ASR (Speech-to-Text)
| Service ID | Provider | Fit for iTantra |
| :--- | :--- | :--- |
| `bhashini/ai4b/conformer-asr` | **AI4Bharat** | ⭐ **Direct counterpart** to local IndicConformer. Ideal as cloud fallback or WER benchmark. |
| `bhashini/ai4b/whisper-asr` | **AI4Bharat** | Whisper-based multilingual ASR. Higher accuracy on noisy speech, higher latency. |
| `bhashini/iitm/conformer-asr` | IIT Madras | Alternative Conformer for A/B testing. |
| `bhashini/cdac/conformer-asr` | CDAC Kolkata | Regional Bengali/Odia focus. |
| `bhashini/iisc/conformer-asr` | IISc Bangalore | Kannada focus. |
| `bhashini/iitb/conformer-asr` | IIT Bombay | Marathi/Gujarati focus. |

### 🗣️ TTS (Text-to-Speech)
| Service ID | Provider | Fit for iTantra |
| :--- | :--- | :--- |
| `bhashini/ai4b/indic-tts` | **AI4Bharat** | ⭐ **Direct counterpart** to local Rasa-13 / Indic VITS. Same model family. |
| `bhashini/iitm/tts` | IIT Madras | Alternative synthesis voices for regional tone. |

### 🔀 NMT (Machine Translation)
| Service ID | Provider | Fit for iTantra |
| :--- | :--- | :--- |
| `bhashini/ai4b/nmt` | **AI4Bharat** | ⭐ **Direct counterpart** to local IndicTrans2 INT8. Full FP32 server-side model offers higher BLEU scores when online. |

### 📜 Transliteration
| Service ID | Provider | Fit for iTantra |
| :--- | :--- | :--- |
| `bhashini/ai4b/transliteration` | **AI4Bharat** | ⭐ High value for script conversion (e.g., Dravidian → Devanagari phoneme alignment). |

### 🌐 Language Detection (ALD & TLD)
| Service ID | Category | Fit for iTantra |
| :--- | :--- | :--- |
| `bhashini/iitmd/ald` | Audio Language Detection | Automatic spoken language identification from voice clip. |
| `bhashini/ai4b/tld` | Text Language Detection | Validation check on transcribed text before routing. |

---

## 2. Future / Roadmap Features

| Service ID | Category | Roadmap Value |
| :--- | :--- | :--- |
| `bhashini/ai4b/indicf5-tts` | **Voice Cloning** | Maps to future **Adaptive Codec Mode** — zero-shot cloning of sender's voice timbre. |
| `bhashini/iitg/kws` | **Keyword Spotting** | Low-power always-on trigger for emergency words ("mayday", "help"). |
| `bhashini/iisc/speaker-diarization` | Diarization | Multi-peer speaker attribution in group mesh. |
| `bhashini/iitdharwad/speaker-verification` | Biometrics | Speaker authentication before channel broadcast. |
