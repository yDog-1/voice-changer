# NixOSでの実行（GTX 1080 / x86_64 Linux）

このリポジトリの古いPython依存を、Flakeで固定したFHS環境内で実行します。
Docker / Podman、Conda、ホストへのCUDA Toolkitの導入は不要です。

## 前提

- Flakesが有効なNixOS（`x86_64-linux`）。
- NVIDIAドライバーが有効で、ホストで`nvidia-smi`が成功すること。
  ドライバーの共有ライブラリは`/run/opengl-driver/lib`から参照します。
- 初回のNixパッケージ、Pythonパッケージ、モデル取得のためのネット接続と空き容量。
  CUDA関連wheelとモデルを含むため、十数GB以上の余裕を推奨します。

検証したPCはRyzen 7 3700X、GTX 1080（8GB）、NVIDIAドライバー580.178.04です。

## セットアップと起動

**リポジトリのルートディレクトリで**実行してください。

```sh
nix run .#setup
nix run .#doctor
nix run .#voice-changer
```

Chromeで <http://localhost:18888/> を開きます。既存のビルド済みクライアントを
利用するため、通常の実行にNode.jsやクライアントの再ビルドは不要です。
マイクの利用を許可し、ブラウザ側の入力・出力デバイスを選択してください。
サーバーは`Ctrl+C`で終了します。

`setup`は`.venv/`を作成してロック済み依存を同期します。モデルはサーバーの
初回起動時にアプリが取得し、`server/pretrain/`と`server/model_dir/`へ保存します。
シェルへの入場・起動時にPythonパッケージを自動インストールしません。

既存の`.venv/`がPython 3.10以外の場合は、セットアップ・起動時にエラーにします。
その環境を別の場所へ移してから`nix run .#setup`を再実行してください。

デフォルトはHTTP・`127.0.0.1:18888`です。localhostのHTTPでもブラウザの
マイクAPIを利用できます。引数はそのままサーバーへ渡せます。

```sh
nix run .#voice-changer -- -p 18889
nix run .#voice-changer -- --https true
nix run .#voice-changer -- --help
```

別の場所から起動する場合は、書き込み可能なチェックアウトの絶対パスを
`VOICE_CHANGER_ROOT`に指定してください。モデル・設定はそのチェックアウトに保存します。

## 固定するもの

| 対象 | 管理方法 |
| --- | --- |
| Python 3.10、uv、コンパイラー、音声・共有ライブラリ | `flake.nix`と`flake.lock` |
| Pythonパッケージと推移的依存 | `nix/requirements.lock`（SHA-256付き） |
| レガシー拡張のビルド依存 | `nix/build-requirements.lock`（SHA-256付き） |
| CUDA 11.7 / cuDNN 8.5 | PyTorch 2.0.1の依存wheelとしてロック |
| NVIDIAカーネルドライバー / libcuda | ホストのNixOS設定 |

ONNX Runtime GPU 1.13.1も、同じwheel内のCUDA/cuDNNライブラリを利用します。
最新版への自動更新は行いません。`pyworld`と`fairseq`などのソース配布は、
固定したNumPy・Cython・setuptools・wheelとNixのコンパイラーでビルドします。

Python環境はネット接続を伴うセットアップで構築するため、全体がNixの
サンドボックスビルドになるわけではありません。また、アプリが取得するモデルと
サンプルカタログは上流の配布URLに従い、これらのロックファイルの対象外です。

## GPU確認と開発

```sh
nix run .#doctor
```

Python・fairseq・PortAudioを確認し、PyTorchのCUDA行列積・cuDNN畳み込みと
ONNX RuntimeのCUDA推論を実行します。GPUが使えない場合は失敗として終了します。
モデルのダウンロードは不要です。

対話的な開発シェルは次のコマンドで開きます。セットアップ済みなら`.venv`と
CUDAライブラリのパスも設定されます。

```sh
nix develop
python --version
bash nix/runtime.sh start --logLevel info
```

FHS開発シェルは対話利用向けです。単発のコマンドをFHS内で実行する場合は、
`nix develop -c`ではなく次の形式を使用してください。

```sh
nix run .#runtime -- -c 'python --version'
```

依存を変更する際は、`server/requirements.txt`と追加依存の
`nix/requirements.in`、必要に応じて`nix/build-requirements.in`を編集してから実行します。

```sh
nix run .#lock
nix run .#setup
nix run .#doctor
nix flake check
```

`lock`は既存の解決結果を可能な限り維持してロックを再生成します。
Nix側を更新する場合は`nix flake update`後に同じ検証を行ってください。

## 検証範囲

上記PCでPython環境の構築、GPU診断、HTTPの`/info`と`/front/`、
初期サンプルのRVCモデル読み込み、GPU 0・`rmvpe_onnx`での合成音声変換を確認しました。
実際のマイク・スピーカーによる聴感確認や遅延調整は、使用する音声デバイスで行ってください。
