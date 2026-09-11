# Open-Source Models & Techniques Catalog for iTantra

> **Future Reference & Upgrade Roadmap**  
> All models cataloged here are **open-source**, freely downloadable, and capable of running **on-device offline** (or via optional cloud fallbacks) — matching iTantra's mission for satellite/disaster mesh communications.

---

## 1. 🎙️ STT (Speech-to-Text) — Voice Input → Text

### ⭐ Currently Active: IndicConformer (AI4Bharat / NeMo)
| Property | Detail |
| :--- | :--- |
| **Full Name** | AI4Bharat IndicConformer CTC |
| **Source** | [github.com/AI4Bharat/IndicASR](https://github.com/AI4Bharat/IndicASR) / [HuggingFace: ai4bharat](https://huggingface.co/ai4bharat) |
| **Architecture** | Conformer-CTC (NeMo framework) |
| **Languages** | All 10 iTantra languages ✅ |
| **License** | MIT / CC-BY-4.0 |
| **On-Device** | ✅ ONNX export → SherpaOnnx runtime (already integrated in iTantra) |
| **Quantization** | INT8 dynamic quantization → ~80 MB per language |
| **iTantra Status** | **ACTIVE — Primary STT engine** |

### Alternative: IndicWhisper (AI4Bharat)
| Property | Detail |
| :--- | :--- |
| **Full Name** | IndicWhisper — fine-tuned OpenAI Whisper for Indic languages |
| **Source** | [HuggingFace: ai4bharat/indicwhisper](https://huggingface.co/ai4bharat) |
| **Architecture** | Whisper Encoder-Decoder (Transformer) |
| **Languages** | All 10 iTantra languages ✅ |
| **License** | MIT |
| **On-Device** | ⚠️ Possible via ONNX but **much larger** (~300 MB+ for small, ~1.5 GB for medium) |
| **Best For** | Higher accuracy on noisy audio, code-mixed speech |
| **Trade-off** | Higher latency (RTF ~0.5–0.8 vs. 0.33 for Conformer), bigger model footprint |

### Alternative: OpenAI Whisper (Original)
| Property | Detail |
| :--- | :--- |
| **Full Name** | OpenAI Whisper |
| **Source** | [github.com/openai/whisper](https://github.com/openai/whisper) |
| **Architecture** | Encoder-Decoder Transformer |
| **Languages** | 99 languages including all 10 iTantra languages ✅ |
| **License** | MIT |
| **On-Device** | Via [whisper.cpp](https://github.com/ggerganov/whisper.cpp) or SherpaOnnx |
| **Sizes** | tiny (39M), base (74M), small (244M), medium (769M), large-v3 (1.55G) |
| **Best For** | Fallback when IndicConformer accuracy is insufficient |

### Alternative: Meta MMS ASR (Massively Multilingual Speech)
| Property | Detail |
| :--- | :--- |
| **Full Name** | Meta MMS — ASR component |
| **Source** | [HuggingFace: facebook/mms-1b-all](https://huggingface.co/facebook/mms-1b-all) |
| **Architecture** | Wav2Vec2-Conformer fine-tuned on 1,100+ languages |
| **Languages** | All 10 iTantra languages ✅ (1,107 languages total) |
| **License** | CC-BY-NC 4.0 |
| **On-Device** | ⚠️ Large base model (~1 GB), but per-language adapter heads are tiny (~5 MB each) |
| **Best For** | Fallback for underrepresented languages (Odia, Bengali edge cases) |

### Alternative: Wav2Vec2-Large-XLSR (Meta)
| Property | Detail |
| :--- | :--- |
| **Source** | [HuggingFace: facebook/wav2vec2-large-xlsr-53](https://huggingface.co/facebook/wav2vec2-large-xlsr-53) |
| **Architecture** | Self-supervised Wav2Vec2 fine-tuned on 53 languages |
| **Languages** | Hindi, Bengali, Tamil, Telugu, Marathi, English ✅ (partial Indic) |
| **License** | Apache 2.0 |
| **Best For** | Research/benchmarking baseline |

---

## 2. 🗣️ TTS (Text-to-Speech) — Text → Voice Output

### ⭐ Currently Active: AI4Bharat IndicTTS / Rasa-13 (VITS)
| Property | Detail |
| :--- | :--- |
| **Full Name** | AI4Bharat IndicTTS (Rasa model family) |
| **Source** | [github.com/AI4Bharat/IndicTTS](https://github.com/AI4Bharat/IndicTTS) / [HuggingFace: ai4bharat](https://huggingface.co/ai4bharat) |
| **Architecture** | VITS (Variational Inference with adversarial learning for end-to-end TTS) |
| **Languages** | All 10 iTantra languages ✅ (13 total including Assamese, Manipuri, Bodo) |
| **License** | MIT / CC-BY-4.0 |
| **On-Device** | ✅ ONNX via SherpaOnnx (already integrated) |
| **Model Size** | ~30–50 MB per language |
| **iTantra Status** | **ACTIVE — Primary TTS engine (Rasa mode)** |

### ⭐ Currently Active: Meta MMS-TTS
| Property | Detail |
| :--- | :--- |
| **Full Name** | Meta Massively Multilingual Speech — TTS component |
| **Source** | [HuggingFace: facebook/mms-tts](https://huggingface.co/facebook/mms-tts) |
| **Architecture** | VITS fine-tuned on 1,100+ languages |
| **Languages** | All 10 iTantra languages ✅ |
| **License** | CC-BY-NC 4.0 |
| **On-Device** | ✅ ONNX via SherpaOnnx (already integrated) |
| **Model Size** | ~30 MB per language |
| **iTantra Status** | **ACTIVE — Secondary TTS engine (MMS mode, toggled via AppBar switch)** |

### Alternative: Piper TTS
| Property | Detail |
| :--- | :--- |
| **Full Name** | Piper — fast local neural text-to-speech |
| **Source** | [github.com/rhasspy/piper](https://github.com/rhasspy/piper) |
| **Architecture** | VITS / Larynx |
| **Languages** | Hindi, English, Bengali ✅ (limited Indic coverage) |
| **License** | MIT |
| **On-Device** | ✅ C++ runtime, ONNX, very fast (~RTF 0.1) |
| **Best For** | Ultra-low-latency English/Hindi fallback |

### Alternative: Coqui TTS (XTTS)
| Property | Detail |
| :--- | :--- |
| **Source** | [github.com/coqui-ai/TTS](https://github.com/coqui-ai/TTS) |
| **Architecture** | XTTS v2 (zero-shot voice cloning) |
| **Languages** | Hindi, English ✅ (limited Indic) |
| **License** | MPL-2.0 |
| **Best For** | 🔮 **Voice cloning** — preserving sender's voice timbre (future roadmap) |

### Technique: IndicF5-TTS (Voice Cloning, Bhashini)
| Property | Detail |
| :--- | :--- |
| **Full Name** | AI4Bharat IndicF5-TTS |
| **Source** | Bhashini platform / AI4Bharat research |
| **Architecture** | Flow-matching based zero-shot TTS |
| **Languages** | Multiple Indic languages |
| **Best For** | 🔮 **Roadmap Neural Codec Mode** — clone sender voice from a short reference clip |

---

## 3. 🔀 NMT (Machine Translation) — MT Toggle

### ⭐ Currently Active: IndicTrans2 (AI4Bharat)
| Property | Detail |
| :--- | :--- |
| **Full Name** | IndicTrans2 |
| **Source** | [github.com/AI4Bharat/IndicTrans2](https://github.com/AI4Bharat/IndicTrans2) / [HuggingFace: ai4bharat/indictrans2](https://huggingface.co/ai4bharat) |
| **Architecture** | Transformer (fairseq / custom) |
| **Languages** | All 10 iTantra languages ✅ (22 Indic + English, all directions) |
| **License** | MIT |
| **Sizes** | 200M (distilled), 1.1B (full) |
| **On-Device** | ✅ ONNX INT8 export (~200 MB for distilled) — already integrated |
| **iTantra Status** | **ACTIVE — used when MT toggle is ON** |

### Alternative: Meta NLLB (No Language Left Behind)
| Property | Detail |
| :--- | :--- |
| **Full Name** | Meta NLLB-200 |
| **Source** | [HuggingFace: facebook/nllb-200-distilled-600M](https://huggingface.co/facebook/nllb-200-distilled-600M) |
| **Architecture** | Transformer |
| **Languages** | 200 languages including all iTantra languages ✅ |
| **License** | CC-BY-NC 4.0 |
| **Sizes** | 600M (distilled), 1.3B, 3.3B, 54B (MoE) |
| **On-Device** | ⚠️ 600M distilled can run on-device via CTranslate2/ONNX but slower than IndicTrans2 |
| **Best For** | Fallback for language pairs where IndicTrans2 accuracy is weak |

---

## 4. 📜 Transliteration & Script Normalization

### ⭐ Currently Active: Rule-based ScriptNormalizationEngine
iTantra currently uses hand-crafted Indic script mappings in `script_normalization_engine.dart`.

### Recommended Upgrade: Aksharantar / IndicXlit (AI4Bharat)
| Property | Detail |
| :--- | :--- |
| **Full Name** | IndicXlit / Aksharantar |
| **Source** | [github.com/AI4Bharat/IndicXlit](https://github.com/AI4Bharat/IndicXlit) |
| **Architecture** | Transformer-based transliteration |
| **Languages** | All 10 iTantra languages + more ✅ |
| **License** | MIT |
| **Capability** | Neural transliteration between any Indic script pair (e.g., Tamil → Devanagari, Bengali → Latin). Far more accurate than rule-based mapping. |
| **On-Device** | ✅ Small model (~20–40 MB), ONNX exportable |
| **Recommendation** | **Replace rule-based ScriptNormalizationEngine with IndicXlit for better accuracy** |

### Tool: IndicNLP Library
| Property | Detail |
| :--- | :--- |
| **Source** | [github.com/anoopkunchukuttan/indic_nlp_library](https://github.com/anoopkunchukuttan/indic_nlp_library) |
| **License** | MIT |
| **Capability** | Script conversion, tokenization, normalization, transliteration utilities for all Indic scripts |
| **Best For** | Text preprocessing pipeline before STT/TTS |

---

## 5. 🎛️ VAD (Voice Activity Detection)

### ⭐ Currently Active: Silero VAD
| Property | Detail |
| :--- | :--- |
| **Full Name** | Silero VAD |
| **Source** | [github.com/snakers4/silero-vad](https://github.com/snakers4/silero-vad) |
| **Architecture** | Lightweight neural network (ONNX) |
| **License** | MIT |
| **On-Device** | ✅ ~2 MB model, 30ms chunk processing |
| **iTantra Status** | **ACTIVE — detects speech vs. silence during PTT hold** |

---

## 6. 🔊 Neural Audio Codecs (Future Roadmap: Voice Timbre Preservation)

These are for the **future Adaptive Codec Architecture** — preserving the sender's voice identity.

### EnCodec (Meta)
| Property | Detail |
| :--- | :--- |
| **Source** | [github.com/facebookresearch/encodec](https://github.com/facebookresearch/encodec) |
| **Architecture** | Neural audio codec (encoder + decoder + RVQ) |
| **Bitrate** | 1.5 kbps — 24 kbps (scalable) |
| **License** | MIT |
| **Best For** | Compressing audio while preserving voice timbre at 3–6 kbps |

### Lyra (Google)
| Property | Detail |
| :--- | :--- |
| **Source** | [github.com/google/lyra](https://github.com/google/lyra) |
| **Architecture** | WaveGRU neural codec |
| **Bitrate** | 3.2 kbps |
| **License** | Apache 2.0 |
| **Best For** | Ultra-low bitrate codec designed specifically for voice |

### SpeechTokenizer
| Property | Detail |
| :--- | :--- |
| **Source** | [github.com/ZhangXInFD/SpeechTokenizer](https://github.com/ZhangXInFD/SpeechTokenizer) |
| **Architecture** | Hierarchical speech tokenizer separating semantic and acoustic tokens |
| **License** | MIT |
| **Best For** | Hybrid approach — transmit semantic tokens (tiny) + optional acoustic tokens (for timbre) |

---

## 7. 🧠 Language Identification (LID)

### IndicLID (AI4Bharat)
| Property | Detail |
| :--- | :--- |
| **Source** | [github.com/AI4Bharat/IndicLID](https://github.com/AI4Bharat/IndicLID) |
| **Architecture** | FastText / Transformer classifier |
| **Languages** | 24 Indic languages + scripts ✅ |
| **License** | MIT |
| **Best For** | Auto-detect language of transcribed text (eliminate manual language selection) |

### Audio LID via Whisper
Whisper's built-in language detection (first 30 seconds) can identify spoken language from audio directly.

---

## 8. 📊 Datasets (Training / Fine-tuning)

| Dataset | Source | Use Case |
| :--- | :--- | :--- |
| **IndicVoices** | [AI4Bharat](https://github.com/AI4Bharat/IndicVoices) | 7,348 hours of natural speech across 22 Indic languages. Fine-tune STT. |
| **Shrutilipi** | [AI4Bharat](https://github.com/AI4Bharat/Shrutilipi) | Large-scale Indic ASR corpus. |
| **IndicSUPERB** | [AI4Bharat](https://github.com/AI4Bharat/IndicSUPERB) | Benchmark for evaluating Indic speech models. |
| **Samanantar** | [AI4Bharat](https://github.com/AI4Bharat/Samanantar) | 49.7M parallel sentences across 11 Indic languages. Fine-tune MT. |
| **FLEURS** (Google) | [HuggingFace: google/fleurs](https://huggingface.co/datasets/google/fleurs) | Few-shot ASR evaluation across 102 languages. |

---

## Summary Matrix: Current vs. Future Options

| Pipeline Stage | Currently Active | Open-Source Alternatives / Upgrades |
| :--- | :--- | :--- |
| **VAD** | Silero VAD ✅ | — (Silero is best-in-class for on-device) |
| **STT** | IndicConformer CTC INT8 ✅ | IndicWhisper, OpenAI Whisper, Meta MMS ASR, Wav2Vec2-XLSR |
| **MT** | IndicTrans2 INT8 ✅ | Meta NLLB-200 |
| **Script Normalization** | Rule-based mapping ⚠️ | **IndicXlit / Aksharantar** (neural, highest value upgrade) |
| **TTS** | Rasa-13 VITS + MMS-TTS ✅ | Piper, Coqui XTTS, IndicF5-TTS |
| **Audio Codec** | Text-Token Mode only | EnCodec, Lyra, SpeechTokenizer (future roadmap) |
| **Language ID** | Manual selection | IndicLID, Whisper LID (auto-detection) |
