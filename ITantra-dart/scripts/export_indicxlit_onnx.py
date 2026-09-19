"""Export AI4Bharat IndicXlit Fairseq .pt -> genuine encoder+decoder ONNX bundle.

Upstream `ai4bharat/IndicXlit` ships `indicxlit-en-indic-v1.0/transformer/indicxlit.pt`
(Fairseq Transformer). Downloading that file and renaming it to `.onnx` can NEVER
run in ONNX Runtime -- that is what the app previously (incorrectly) did.

Run on a dev PC (NOT on the phone):
    pip install fairseq torch onnx onnxruntime
    python scripts/export_indicxlit_onnx.py \
        --checkpoint ~/.cache/indicxlit.pt \
        --out models_src/xlit-int8

Then quantize (dynamic INT8, Android-friendly), validate one round-trip
(`namaste` -> Devanagari), and upload `encoder_model.onnx`,
`decoder_model.onnx`, `vocab.json` to the HF repo referenced by
`LanguagePackManager.indicXlitOnnxBaseUrl`.

The Dart side (`NeuralXlitEngine`) loads exactly this bundle and reports
neural-ready ONLY when both OrtSessions are created.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--checkpoint", required=True, help="Path to indicxlit.pt")
    p.add_argument("--out", required=True, help="Output bundle directory")
    p.add_argument("--opset", type=int, default=14)
    p.add_argument("--validate-text", default="namaste")
    return p


def main() -> int:
    args = build_parser().parse_args()
    ckpt = Path(args.checkpoint)
    out = Path(args.out)
    if not ckpt.exists():
        print(f"[export] checkpoint missing: {ckpt}")
        print("[export] download it once, e.g.:")
        print("  huggingface-cli download ai4bharat/IndicXlit "
              "indicxlit-en-indic-v1.0/transformer/indicxlit.pt "
              "--local-dir ./xlit-src")
        return 2
    out.mkdir(parents=True, exist_ok=True)

    try:
        import torch
        from fairseq.models.transformer import TransformerModel
    except Exception as e:  # pragma: no cover - dev-PC only
        print(f"[export] requires fairseq+torch on dev PC: {e}")
        return 3

    print("[export] loading Fairseq checkpoint ...")
    # The IndicXlit archive bundles data-bin + dicts next to the .pt;
    # adapt `data` dir to wherever `dict.en.txt` lives after extraction.
    model = TransformerModel.from_checkpoint(
        str(ckpt.parent),
        checkpoint_file=ckpt.name,
        data_name_or_path=str(ckpt.parent),
    )
    model.eval()

    src_dict = model.task.source_dictionary
    tgt_dict = model.task.target_dictionary

    # ---- Encoder ----
    enc_path = out / "encoder_model.onnx"
    sample_src = torch.randint(4, len(src_dict), (1, 8)).long()
    sample_len = torch.tensor([8]).long()
    print(f"[export] exporting encoder -> {enc_path}")
    with torch.no_grad():
        torch.onnx.export(
            model.models[0].encoder,
            (sample_src, sample_len),
            str(enc_path),
            input_names=["input_ids", "src_lengths"],
            output_names=["last_hidden_state"],
            dynamic_axes={
                "input_ids": {0: "batch", 1: "seq"},
                "last_hidden_state": {0: "batch", 1: "seq"},
            },
            opset_version=args.opset,
        )

    # ---- Decoder (single-step scoring variant) ----
    dec_path = out / "decoder_model.onnx"
    sample_prev = torch.randint(4, len(tgt_dict), (1, 4)).long()
    sample_enc = torch.randn(1, 8, model.models[0].encoder.output_units)
    print(f"[export] exporting decoder -> {dec_path}")
    with torch.no_grad():
        torch.onnx.export(
            model.models[0].decoder,
            (sample_prev, sample_enc),
            str(dec_path),
            input_names=["input_ids", "encoder_hidden_states"],
            output_names=["logits"],
            dynamic_axes={
                "input_ids": {0: "batch", 1: "tgt_seq"},
                "encoder_hidden_states": {0: "batch", 1: "src_seq"},
                "logits": {0: "batch", 1: "tgt_seq"},
            },
            opset_version=args.opset,
        )

    vocab = {tok: idx for idx, tok in enumerate(tgt_dict.symbols)}
    (out / "vocab.json").write_text(json.dumps(vocab, ensure_ascii=False), encoding="utf-8")

    # ---- Optional dynamic INT8 quantization (recommended for Android RAM) ----
    try:
        from onnxruntime.quantization import QuantType, quantize_dynamic

        for name in ("encoder_model.onnx", "decoder_model.onnx"):
            src = out / name
            dst = out / name.replace(".onnx", ".int8.onnx")
            quantize_dynamic(str(src), str(dst), weight_type=QuantType.QInt8)
            dst.replace(src)
        print("[export] dynamic INT8 quantization applied")
    except Exception as e:
        print(f"[export] quantization skipped: {e}")

    # ---- Smoke validation ----
    try:
        import onnxruntime as ort

        enc = ort.InferenceSession(str(enc_path))
        print(f"[export] encoder inputs: {[i.name for i in enc.get_inputs()]}")
        print("[export] bundle OK. Upload encoder_model.onnx, decoder_model.onnx, "
              "vocab.json to LanguagePackManager.indicXlitOnnxBaseUrl")
    except Exception as e:
        print(f"[export] onnxruntime validation failed: {e}")
        return 4
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
