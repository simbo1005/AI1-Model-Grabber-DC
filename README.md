# dsnn AI1 Model Grabber

A lightweight, single-page workflow launcher that runs next to stock ComfyUI on
RunPod.

## What is included

- Stock `runpod/comfyui:cuda12.8`, pinned to a known image digest.
- ComfyUI on port `8188`.
- JupyterLab on port `8888`.
- dsnn Model Grabber on port `3000`.
- Hugging Face CLI downloads (with a toggleable Xet engine) plus native `wget` downloads for other sources, with resumable `.part` files and visible progress.
- Expandable workflow tiles with per-resource selection, live selected-size totals,
  and workflow-specific model groups.
- Workflow and custom-node installation from a declarative JSON catalog.
- Bounded, cancellable Git and pip operations so a stalled custom-node install cannot hang indefinitely.
- Docker-warmed custom-node dependencies and prebuilt `dlib` for faster FaceAnalysis setup.
- Redacted timing diagnostics at `/api/diagnostics/report` for support and troubleshooting.
- A Custom Models queue for direct downloads into any ComfyUI model folder.
- A button that routes from the launcher to the matching RunPod ComfyUI proxy.
- Optional launcher updates from GitHub at container startup.

The current catalog contains six production installers:

- Krea 2 Extended (approximately 84.9 GB with every optional resource selected)
- Image Edit (approximately 17.8 GB)
- WAN Motion Control (approximately 45.4 GB)
- Motion Control GOD Edition (approximately 61.3 GB)
- MiniMax H3 (approximately 63.4 GB)
- KRQW2.1 (approximately 44.3 GB)

KRQW2.1 installs REDGPT FP8, Krea 2 Turbo FP8, its Civitai LoRA, Qwen3-VL
8B BF16 and 4B FP8 text encoders, Qwen Image 2.1 VAE BF16 and Krea 2 Real VAE.
Its seven resources are selected by default in the expandable tile. Files already
installed by another preset are verified and reused. The preset updates ComfyUI
before setup and installs six pinned node packs: rgthree, Custom Scripts,
SeedVR2 Video Upscaler, Easy Use, Regeneration Gate and Bond Node Suite. The gate retains its
upstream repository and node identifiers so existing KRQW2.1 workflows load.
Set `CIVITAI_TOKEN` (or `CIVITAI_API_TOKEN`) on the pod for REDGPT and the Civitai
LoRA; without it those two files are skipped with warnings. Hugging Face files
continue to use the existing `hf download` path. This preset installs dependencies;
it does not include the product workflow JSON. SeedVR2 can download its own
upscaler weights when its node first runs; they are not among these seven files.

The catalog installs only models, supporting files and custom nodes. Product
workflow JSON files are deliberately not included.

Model download failures are reported as warnings while remaining files continue.
Custom-node or system-tool failures prevent a workflow from being marked ready.

Every pipeline includes Bond Node Suite, pinned to a reviewed Git commit.
ExifTool is installed as the Debian package `libimage-exiftool-perl`, together
with FFmpeg. Both are baked into new images using `apt-get`; older images install
missing tools automatically during workflow setup. The launcher checks that
`exiftool -ver` and `ffmpeg -version` work before proceeding.

Custom nodes are cloned into a temporary folder and exposed to ComfyUI only
after their pinned checkout and package initializer are present. Python
requirements use ComfyUI's configured environment and constrain its existing
Torch, TorchVision, TorchAudio, TorchCodec and NumPy versions. Retrying a manual
node install repairs requirements even when the repository is already there.

After setup, the launcher restarts ComfyUI and checks its live `/object_info`
registry for every selected node pack. SeedVR2 requires all four of its node
types; Bond requires all 26. The setup panel lists each package's verification
result. Failed installs, missing registrations and failed restarts produce an
error instead of a ready message. Transient network failures receive one retry.
The existing HF CLI transfer path is unchanged.

The initial setup waits for ComfyUI and its configured Python environment.
`COMFYUI_READY_TIMEOUT` defaults to 600 seconds; `COMFYUI_RESTART_TIMEOUT`
defaults to 300 seconds to allow custom-node imports on the first restart.

The bundled Windows installers also include Bond Node Suite. On Windows,
install ExifTool separately and add `exiftool.exe` to PATH; the `apt-get`
installation applies to the Linux RunPod and Vast templates.

Some custom nodes expect a model inside their own directory. Catalog
`model_links` place the already-downloaded model at that private path with a
hard link when possible, falling back to a copy, so the model is not downloaded
again.

## Custom models

The **Custom models** section accepts a direct HTTP(S) model link and a target
folder inside `ComfyUI/models`. It includes ComfyUI's standard model locations,
discovers existing folders on the pod and can create a new custom subfolder.

Every click adds one download to a single serial queue. Custom downloads always
start from scratch: an existing `.part` file is removed before the request. A
complete model with the same filename and recognized size/checksum is skipped
and shown under **Downloaded models** instead of being overwritten.

## Custom nodes

The **Custom nodes** section accepts GitHub repository links and processes every
click through one serial install queue. Repositories are cloned into a temporary
folder, their `requirements.txt` is installed with ComfyUI's Python environment,
and the completed folder is then moved into `ComfyUI/custom_nodes`.

Git and pip work has bounded timeouts. Workflow installs can be cancelled during
those phases, and pip first avoids build isolation so it reuses the image's CUDA
packages; it retries normally only when a missing build backend requires it.

An existing checkout with the same Git origin is shown as already found. Failed
clones or dependency installs remove their temporary folder instead of leaving
an incomplete custom node behind. Newly installed nodes require a ComfyUI
restart before they become available; the **Restart ComfyUI** button performs
that restart without restarting the pod.

## Diagnostics

`/api/diagnostics` returns recent workflow download and command timings as JSON.
`/api/diagnostics/report` is a plain-text version suitable for support requests.
Neither endpoint includes download URLs, filesystem paths or credentials.

## RunPod template

Use:

```text
Container image: sdcioba/comfyui-workflow-launcher:2.1
HTTP ports:      3000, 8188, 8888
Container disk:  at least 100 GB for the largest individual installer
```

No persistent volume is required. The public service URLs follow RunPod's normal
format:

```text
https://POD_ID-3000.proxy.runpod.net
https://POD_ID-8188.proxy.runpod.net
https://POD_ID-8888.proxy.runpod.net
```

Set `JUPYTER_PASSWORD` in the RunPod template before exposing JupyterLab.
Set `HF_TOKEN` when using Image Edit, and make sure the
token's account has accepted the applicable Hugging Face model licenses.
Images published by the project's GitHub Actions workflow can instead include
the dedicated `HF_TOKEN` repository secret as a baked download
credential. A runtime `HF_TOKEN` always takes precedence over the baked file.

## Remote UI updates

At startup, the baked bootstrapper checks:

```text
LAUNCHER_GITHUB_REPO=simbo1005/AI1-Model-Grabber-DC
LAUNCHER_GITHUB_REF=main
LAUNCHER_AUTO_UPDATE=1
```

If the repository is public, no GitHub credential is required. If it is private,
the pod needs `GITHUB_TOKEN`. When GitHub is unavailable or the downloaded source
is invalid, the launcher safely falls back to the version baked into the image.

Changes to HTML, CSS, JavaScript, the Python launcher or `catalog/workflows.json`
therefore appear on newly started pods without rebuilding the image, provided
they do not introduce new Python packages.

## Workflow catalog

Workflow tiles live in `catalog/workflows.json`. A real workflow can define files
and custom nodes:

```json
{
  "id": "example-workflow",
  "title": "Example Workflow",
  "description": "Installs everything needed for the example.",
  "badge": "IMAGE",
  "accent": "#b8ff5a",
  "estimated_size": "18.4 GB",
  "update_comfyui": true,
  "files": [
    {
      "name": "example-model.safetensors",
      "url": "https://huggingface.co/owner/repo/resolve/main/model.safetensors",
      "destination": "models/diffusion_models/example-model.safetensors",
      "size_bytes": 123456789,
      "sha256": "optional-sha256",
      "auth": "huggingface"
    },
    {
      "name": "Example workflow",
      "url": "https://example.com/workflow.json",
      "destination": "user/default/workflows/example.json",
      "auth": "none"
    }
  ],
  "custom_nodes": [
    {
      "name": "Example-ComfyUI-Node",
      "repo": "https://github.com/example/Example-ComfyUI-Node.git",
      "ref": "pin-a-tag-or-commit-here",
      "install_requirements": true
    }
  ]
}
```

Every file in a workflow is shown as a checkbox, grouped from its destination
folder (diffusion models, LoRAs, VAEs, text encoders, upscale models and support
resources). Existing entries are selected by default. Set
`"default_selected": false` on a file only when it should be offered but not
preselected. A resource belongs only to the workflow entries that contain it,
so architecture-specific additions must be placed only in their compatible
pipeline. Download URLs and authentication data remain server-side.

Krea 2 Raw is available in the Krea tile but is intentionally not preselected.
The four `simbo926/rmdl` LoRAs are hosted in a gated repository and therefore
require `HF_TOKEN`. The Apache-2.0 NiceGirls and KNP resources are mirrored with
upstream attribution at `simbo926/dsnn-krea2-resources`; other public additions
continue to use their revision-pinned original sources.

Set `update_comfyui` to `true` when a preset requires the newest ComfyUI code.
Before downloading that preset, the launcher updates from
`Comfy-Org/ComfyUI:master` and installs its requirements into the ComfyUI Python
environment. The standard end-of-preset restart then loads the new version.

Supported file authentication values are `none`, `huggingface`, `civitai` and
`github`. Corresponding environment names are documented in `.env.example`.
Download URLs and authentication details are not returned by the public catalog
API.

## Local Windows installers

Standalone Windows installers for Dataset Generator, Krea 2 and MiniMax H3 live
in `local-installers/`. Copy the required `.bat` file directly into the main
ComfyUI directory—the folder containing `models` and `custom_nodes`—and run it
while ComfyUI is stopped. The scripts verify SHA-256 checksums, install pinned
custom-node versions and their requirements, and retain successful items if a
later item fails. Dataset Generator reads a gated-model token from `HF_TOKEN` or
prompts for one. MiniMax H3 also updates ComfyUI before installing its files.

## Security note

Do not treat a token supplied to a user-controlled pod as secret. A person with
Jupyter, SSH or container access can inspect the environment, filesystem and
running processes. Never commit tokens to GitHub.

The automated publishing workflow can deliberately place the dedicated,
fine-grained `HF_TOKEN` Actions secret in the final image so public
template users do not need to configure Hugging Face themselves. This keeps the
credential out of source control and build logs, but it does not make the token
secret from anyone who can pull or inspect the final image. Treat that token as
public, narrowly scoped and disposable.

For production gated models, prefer one of:

1. Bake distributable model files into independent Docker layers.
2. Require each pod owner to provide a fine-grained read-only token.
3. Issue short-lived download URLs from a separate trusted service.

The launcher supports `HF_TOKEN` and `CIVITAI_TOKEN` for controlled/private use,
but it cannot hide those values from the owner of the pod.

## Local launcher development

Create a Python environment and install:

```text
pip install -r requirements-launcher.txt pytest
```

Then run:

```text
DEMO_DURATION_OVERRIDE=1 python -m uvicorn launcher.app:app --port 3000
```

On Windows PowerShell, set environment variables with `$env:NAME="value"` first.

## Build manually

```text
docker build -t sdcioba/comfyui-workflow-launcher:2.1 .
docker push sdcioba/comfyui-workflow-launcher:2.1
```

Alternatively, run the included GitHub Actions workflow after adding repository
secret named `DOCKERHUB_TOKEN`. Test builds publish only the requested tag;
select `publish_latest` only when promoting a tested release.
