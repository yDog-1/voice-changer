"""Exercise CUDA in torch and ONNX Runtime without downloading model weights."""

import sys

import fairseq
import numpy as np
import onnx
import onnxruntime as ort
import pyworld
import sounddevice
import torch
from onnx import TensorProto, helper


def check_torch_cuda():
    print(f"PyTorch {torch.__version__}, CUDA {torch.version.cuda}", flush=True)
    if not torch.cuda.is_available():
        raise RuntimeError("PyTorch cannot access the NVIDIA GPU")
    print(f"GPU: {torch.cuda.get_device_name(0)}", flush=True)
    matrix = torch.arange(16, dtype=torch.float32, device="cuda").reshape(4, 4)
    torch.testing.assert_close((matrix @ matrix).cpu(), matrix.cpu() @ matrix.cpu())
    # Also exercise cuDNN, not just the CUDA driver/cuBLAS.
    layer = torch.nn.Conv1d(1, 2, 3).cuda()
    if not torch.isfinite(layer(torch.ones(1, 1, 16, device="cuda"))).all():
        raise RuntimeError("cuDNN convolution produced non-finite values")
    torch.cuda.synchronize()
    print(f"PyTorch CUDA/cuDNN {torch.backends.cudnn.version()}: OK", flush=True)


def check_onnx_cuda():
    graph = helper.make_graph(
        [helper.make_node("MatMul", ["x", "x"], ["y"])],
        "cuda-check",
        [helper.make_tensor_value_info("x", TensorProto.FLOAT, [4, 4])],
        [helper.make_tensor_value_info("y", TensorProto.FLOAT, [4, 4])],
    )
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)])
    model.ir_version = 8
    onnx.checker.check_model(model)
    options = ort.SessionOptions()
    options.add_session_config_entry("session.disable_cpu_ep_fallback", "1")
    session = ort.InferenceSession(
        model.SerializeToString(), options, providers=["CUDAExecutionProvider"]
    )
    if session.get_providers()[0] != "CUDAExecutionProvider":
        raise RuntimeError("ONNX Runtime fell back to CPU")
    session.disable_fallback()
    matrix = np.arange(16, dtype=np.float32).reshape(4, 4)
    np.testing.assert_allclose(session.run(None, {"x": matrix})[0], matrix @ matrix)
    print(f"ONNX Runtime {ort.__version__} CUDA inference: OK", flush=True)


def main():
    print(f"Python {sys.version.split()[0]}, fairseq {fairseq.__version__}", flush=True)
    print(f"pyworld {pyworld.__version__}", flush=True)
    print(f"PortAudio: {sounddevice.get_portaudio_version()[1]}", flush=True)
    check_torch_cuda()
    check_onnx_cuda()


if __name__ == "__main__":
    main()
