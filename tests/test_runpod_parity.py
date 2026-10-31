"""Shared Vast features with RunPod's own service addresses and transfer path."""
import importlib
import os
from pathlib import Path

from fastapi.testclient import TestClient
import pytest

launcher = importlib.import_module("launcher.app")


def test_public_image_never_embeds_huggingface_credentials():
    root = Path(__file__).resolve().parents[1]
    dockerfile = (root/"Dockerfile").read_text()
    workflow = (root/".github/workflows/docker-publish.yml").read_text()
    assert "hf_download_token" not in dockerfile
    assert "REQUIRE_HF_DOWNLOAD_TOKEN" not in dockerfile
    assert "secrets.HF_TOKEN" not in workflow
    assert "secrets.DOCKERHUB_TOKEN" in workflow


def test_runpod_service_links_and_explicit_overrides(monkeypatch):
    monkeypatch.setenv("RUNPOD_POD_ID", "parity-test")
    monkeypatch.delenv("COMFYUI_PUBLIC_URL", raising=False)
    monkeypatch.delenv("JUPYTER_PUBLIC_URL", raising=False)
    assert launcher.comfy_public_url() == "https://parity-test-8188.proxy.runpod.net"
    assert launcher.jupyter_public_url() == "https://parity-test-8888.proxy.runpod.net"
    state = launcher.JobController().state.export()
    assert state["comfy_url"] == launcher.comfy_public_url()
    assert state["jupyter_url"] == launcher.jupyter_public_url()
    monkeypatch.setenv("COMFYUI_PUBLIC_URL", "https://comfy.example.test/")
    monkeypatch.setenv("JUPYTER_PUBLIC_URL", "https://lab.example.test/")
    assert launcher.comfy_public_url() == "https://comfy.example.test"
    assert launcher.jupyter_public_url() == "https://lab.example.test"
    monkeypatch.delenv("RUNPOD_POD_ID")
    monkeypatch.delenv("COMFYUI_PUBLIC_URL")
    monkeypatch.delenv("JUPYTER_PUBLIC_URL")
    assert launcher.comfy_public_url() == launcher.jupyter_public_url() == ""


def test_header_service_links_are_always_present():
    with TestClient(launcher.app) as client:
        page = client.get("/")
        assert page.status_code == 200
        assert 'id="service-comfy-button"' in page.text
        assert 'id="service-jupyter-button"' in page.text


def token_environment(monkeypatch, tmp_path):
    monkeypatch.delenv("HF_TOKEN", raising=False)
    monkeypatch.delenv("HUGGING_FACE_HUB_TOKEN", raising=False)
    monkeypatch.setenv("HF_TOKEN_FILE", str(tmp_path/"absent-token"))
    monkeypatch.delenv("HF_XET_NUM_CONCURRENT_RANGE_GETS", raising=False)
    monkeypatch.delenv("LAUNCHER_HF_XET_RANGE_GETS", raising=False)


def test_hf_runtime_defaults_match_vast_without_changing_parent(monkeypatch, tmp_path):
    token_environment(monkeypatch, tmp_path)
    monkeypatch.setenv("HF_HUB_DISABLE_XET", "1")
    monkeypatch.setenv("HF_XET_HIGH_PERFORMANCE", "0")
    environment = launcher.hf_download_environment(requires_token=False)
    assert environment["HF_XET_HIGH_PERFORMANCE"] == "1"
    assert environment["HF_XET_NUM_CONCURRENT_RANGE_GETS"] == "32"
    assert "HF_HUB_DISABLE_XET" not in environment
    assert os.environ["HF_HUB_DISABLE_XET"] == "1"
    assert os.environ["HF_XET_HIGH_PERFORMANCE"] == "0"


def test_hf_range_setting_respects_template_override(monkeypatch, tmp_path):
    token_environment(monkeypatch, tmp_path)
    monkeypatch.setenv("LAUNCHER_HF_XET_RANGE_GETS", "48")
    assert launcher.hf_download_environment(requires_token=False)["HF_XET_NUM_CONCURRENT_RANGE_GETS"] == "48"
    monkeypatch.setenv("HF_XET_NUM_CONCURRENT_RANGE_GETS", "16")
    assert launcher.hf_download_environment(requires_token=False)["HF_XET_NUM_CONCURRENT_RANGE_GETS"] == "16"


def test_hf_token_auth_and_missing_token_are_preserved(monkeypatch, tmp_path):
    token_environment(monkeypatch, tmp_path)
    with pytest.raises(RuntimeError, match="Hugging Face access"):
        launcher.hf_download_environment(requires_token=True)
    token = "hf_TEST_ONLY_parity_credential"
    monkeypatch.setenv("HF_TOKEN", token)
    assert launcher.hf_download_environment(requires_token=False)["HF_TOKEN"] == token
    assert launcher.hf_download_environment(requires_token=True)["HF_TOKEN"] == token
