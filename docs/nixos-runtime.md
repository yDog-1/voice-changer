# NixOSでの実行（GTX 1080 / x86_64 Linux）

このリポジトリの古いPython依存を、Flakeで固定したFHS環境内で実行します。
Docker / Podman、Conda、ホストへのCUDA Toolkitの導入は不要です。

## 前提

- Flakesが有効なNixOS（`x86_64-linux`）。
- NVIDIAドライバーが有効で、ホストで`nvidia-smi`が成功すること。
  ドライバーの共有ライブラリは`/run/opengl-driver/lib`から参照します。
- デスクトップセッションでPipeWireのPulseAudio互換機能（`pipewire-pulse`）、
  またはPulseAudioが動作していること。
- 初回のNixパッケージ、Pythonパッケージ、モデル取得のためのネット接続と空き容量。
  CUDA関連wheelとモデルを含むため、十数GB以上の余裕を推奨します。

検証したPCはRyzen 7 3700X、GTX 1080（8GB）、NVIDIAドライバー580.178.04です。

## セットアップと起動

以下の`nix run .#…`はリポジトリのルートディレクトリで実行してください。
実行用ファイル・設定・モデル・Python環境は、デフォルトで
`${XDG_DATA_HOME:-$HOME/.local/share}/voice-changer/`に配置します。
カレントディレクトリのチェックアウトには保存しません。

```sh
nix run .#setup
nix run .#doctor
nix run .#voice-changer
```

Chromeで <http://localhost:18888/> を開きます。既存のビルド済みクライアントを
利用するため、通常の実行にNode.jsやクライアントの再ビルドは不要です。
マイクの利用を許可し、ブラウザ側の入力・出力デバイスを選択してください。
サーバーは`Ctrl+C`で終了します。

`setup`は保存先にパッケージ内の実行用ファイルを配置し、`.venv/`を作成して
ロック済み依存を同期します。モデルはサーバーの初回起動時にアプリが取得し、
保存先の`server/pretrain/`と`server/model_dir/`へ保存します。
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

既存のチェックアウトとその設定・モデルを使う場合は、書き込み可能な
チェックアウトの絶対パスを`VOICE_CHANGER_ROOT`に指定してください。
この指定がある場合、実行用ファイルの自動配置は行いません。

```sh
export VOICE_CHANGER_ROOT=/absolute/path/to/voice-changer
```

既存チェックアウトのデータをデフォルトの保存先へ自動移行することはありません。

### プロファイルへのインストール

`nix profile add .`で、次の4コマンドをまとめてインストールできます。

```sh
nix profile add .
voice-changer-setup
voice-changer-doctor
voice-changer-start
```

インストール後の`setup`・`doctor`・`start`は、任意のディレクトリから実行できます。
パッケージを更新したら`voice-changer-setup`を再実行してください。
実行用ファイルと依存を更新し、既存の設定やダウンロードしたモデルは保持します。

通常の保存先は以下です（`XDG_DATA_HOME`が未設定の場合）。

| 内容 | 保存先 |
| --- | --- |
| サーバーの保存設定 | `~/.local/share/voice-changer/server/stored_setting.json` |
| モデルとスロット設定 | `~/.local/share/voice-changer/server/model_dir/` |
| 事前学習済みモデル | `~/.local/share/voice-changer/server/pretrain/` |
| Python環境 | `~/.local/share/voice-changer/.venv/` |

依存ロックの更新は開発用操作です。`voice-changer-lock`はリポジトリのルートで
実行するか、`VOICE_CHANGER_ROOT`に対象のチェックアウトを指定してください。
引数なしの`nix run`は、引き続きサーバーを起動します。

## Discordなどの通話アプリへの出力

`nix run .#voice-changer`（および引数なしの`nix run`）は、サーバー起動前に
仮想出力`VoiceChanger`（内部名`voicechanger`）を自動作成します。
さらに、そのモニター（`voicechanger.monitor`）を通常のマイクとして公開する
録音入力`Monitor of VoiceChanger`（`voicechanger_input`）を自動作成します。
出力のモニターだけではWebRTCを使うアプリのマイク一覧から除外されるため、
`module-remap-source`で独立した入力にしています。
`pactl`はNix実行環境に含まれるため、手動導入は不要です。

ブラウザ側のデバイスを使うclient device modeで、以下を選択してください。

| 設定箇所 | デバイス |
| --- | --- |
| ボイスチェンジャーの入力 | 実際のマイク |
| ボイスチェンジャーの出力 | `VoiceChanger` |
| Discordなどの入力 | `Monitor of VoiceChanger` |
| Discordなどの出力 | 普段のヘッドホン・スピーカー |

出力先は自動で切り替わりません。ブラウザに仮想出力が表示されなければページを
再読み込みするか、`pavucontrol`の「再生」タブでボイスチェンジャーの出力先を
`VoiceChanger`に変更してください。

Discordの入力一覧にモニターが表示されない場合は、マイクテストまたは通話を
開始してから、`pavucontrol`の「録音」タブで「すべてのストリーム」を表示し、
Discordに対応する録音ストリームの入力元を`Monitor of VoiceChanger`に変更します。
表示名は音声サーバーの言語設定によって異なる場合があります。

Discordの出力先を`VoiceChanger`にすると、相手の声まで送信してしまいます。
また、この接続だけでは変換後の自分の声はヘッドホンに再生されません。

既存の`voicechanger`と`voicechanger_input`は再利用するため、
アプリを繰り返し起動しても重複しません。
アプリ終了時には削除せず、音声サーバーの再起動またはログアウトまで残します。
音声サーバーへの接続やデバイス作成に失敗すると、理由を表示して起動を中止します。
`setup`、`doctor`、`lock`は音声デバイスを作成しません。

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

チェックアウト内の環境で開発する場合は、入場前に
`export VOICE_CHANGER_ROOT="$PWD"`を設定し、`nix run .#setup`を実行してください。

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
