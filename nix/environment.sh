# Shared by the FHS profile and runtime commands; sourcing has no side effects.
voice_changer_activate() {
  local venv="$1/.venv" site lib
  [[ -x "$venv/bin/python" ]] || return 0
  export VIRTUAL_ENV="$venv"
  case ":$PATH:" in
    *":$venv/bin:"*) ;;
    *) export PATH="$venv/bin:$PATH" ;;
  esac

  # The pinned PyTorch wheels supply CUDA 11 and cuDNN 8 for torch and ORT.
  site="$venv/lib/python3.10/site-packages"
  for lib in "$site"/nvidia/*/lib "$site/torch/lib"; do
    [[ -d "$lib" ]] || continue
    case ":${LD_LIBRARY_PATH:-}:" in
      *":$lib:"*) ;;
      *) export LD_LIBRARY_PATH="$lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
    esac
  done
}
