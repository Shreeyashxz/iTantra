import os
import urllib.request
import onnx
from onnx import helper, TensorProto

def main():
    work_dir = "converted_models"
    os.makedirs(work_dir, exist_ok=True)
    raw_model_path = os.path.join(work_dir, "raw_model.onnx")
    fixed_model_path = os.path.join(work_dir, "vits_rasa13_6in.onnx")
    tokens_path = os.path.join(work_dir, "tokens.txt")

    base_url = "https://huggingface.co/MatiasLin/sherpa-onnx-vits-rasa-13/resolve/main"

    # 1. Download tokens if missing
    if not os.path.exists(tokens_path):
        print("Downloading tokens.txt...")
        urllib.request.urlretrieve(f"{base_url}/tokens.txt", tokens_path)

    # 2. Download raw model if missing
    if not os.path.exists(raw_model_path):
        print("Downloading model.onnx (123 MB)...")
        urllib.request.urlretrieve(f"{base_url}/model.onnx", raw_model_path)

    print("Loading ONNX model...")
    model = onnx.load(raw_model_path)

    input_names = [inp.name for inp in model.graph.input]
    print(f"Original graph inputs ({len(input_names)}): {input_names}")

    if "emotion_id" in input_names:
        print("Found emotion_id input. Converting to constant...")
        # Create constant node for emotion_id = 0 (Neutral emotion)
        emotion_const = helper.make_node(
            'Constant',
            inputs=[],
            outputs=['emotion_id'],
            value=helper.make_tensor('emotion_const_tensor', TensorProto.INT64, [1], [0])
        )
        model.graph.node.insert(0, emotion_const)

        # Remove emotion_id from graph.input using protobuf remove()
        for inp in list(model.graph.input):
            if inp.name == 'emotion_id':
                model.graph.input.remove(inp)
        print("emotion_id removed from graph.input and baked as Constant node.")
    else:
        print("emotion_id was not in graph.input.")

    new_input_names = [inp.name for inp in model.graph.input]
    print(f"Updated graph inputs ({len(new_input_names)}): {new_input_names}")

    print("Verifying ONNX graph validity...")
    onnx.checker.check_model(model)

    print(f"Saving fixed 6-input model to {fixed_model_path}...")
    onnx.save(model, fixed_model_path)
    print("Conversion complete and verified successfully!")

if __name__ == "__main__":
    main()
