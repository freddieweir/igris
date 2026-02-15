"""igris CLI — unified command for security enforcement management."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import typer

app = typer.Typer(
    name="igris",
    help="YubiKey-gated security enforcement for git, Docker, and shell operations.",
    no_args_is_help=True,
)


def _repo_root() -> Path:
    """Resolve the igris repository root."""
    return Path(__file__).resolve().parent.parent.parent


def _is_vm() -> bool:
    """Detect VM environment."""
    return os.environ.get("USER", "").endswith("vm")


def _shell_config() -> Path:
    """Detect the user's shell config file."""
    if Path.home().joinpath(".zshrc").exists():
        return Path.home() / ".zshrc"
    if sys.platform == "darwin":
        return Path.home() / ".bash_profile"
    return Path.home() / ".bashrc"


@app.command()
def status() -> None:
    """Show enforcement status (Docker, git, environment)."""
    shell_config = _shell_config()
    config_text = shell_config.read_text() if shell_config.exists() else ""

    typer.echo("=== igris enforcement status ===\n")

    # Environment
    env = "VM (autonomous)" if _is_vm() else "Main machine (co-pairing)"
    typer.echo(f"Environment:  {env}")
    typer.echo(f"User:         {os.environ.get('USER', 'unknown')}")

    # Master enforcement
    enabled = os.environ.get("TOMB_YUBIKEY_ENABLED", "true")
    if enabled == "true" or "TOMB_YUBIKEY_ENABLED=true" in config_text:
        typer.echo("Enforcement:  ENABLED")
    else:
        typer.echo("Enforcement:  DISABLED")

    typer.echo("")

    # Git wrapper
    if "git-yubikey-wrapper" in config_text or "YubiKey Git Enforcement" in config_text:
        typer.echo("git wrapper:  installed")
    else:
        typer.echo("git wrapper:  not installed")

    # gh wrapper
    if "gh-yubikey-wrapper" in config_text:
        typer.echo("gh wrapper:   installed")
    else:
        typer.echo("gh wrapper:   not installed")

    # rm wrapper
    if "Dangerous rm Protection" in config_text:
        typer.echo("rm protect:   installed")
    else:
        typer.echo("rm protect:   not installed")

    # Docker wrapper
    if "Docker Operation Gating" in config_text:
        docker_enabled = os.environ.get("IGRIS_DOCKER_ENABLED", "true")
        typer.echo(f"Docker:       installed (enabled={docker_enabled})")
        policy_path = Path.home() / ".config" / "igris" / "policy.yaml"
        if policy_path.exists():
            typer.echo(f"              policy: {policy_path}")
    else:
        typer.echo("Docker:       not installed")

    typer.echo("")

    # YubiKey slot config
    repo_root = _repo_root()
    config_file = repo_root / "configs" / "yubikey-enforcement.yml"
    if config_file.exists():
        import yaml

        with open(config_file) as f:
            cfg = yaml.safe_load(f)
        slot = os.environ.get("IGRIS_OTP_SLOT")
        if not slot and isinstance(cfg, dict):
            yk = cfg.get("yubikey", {})
            slot = str(yk.get("slot", 1)) if isinstance(yk, dict) else "1"
        typer.echo(f"OTP Slot:     {slot or '1'}")

    # Recent audit entries
    audit_path = Path.home() / ".cache" / "igris" / "audit.jsonl"
    if audit_path.exists():
        lines = audit_path.read_text().strip().splitlines()
        recent = lines[-3:] if len(lines) >= 3 else lines
        if recent:
            typer.echo("\nRecent Docker audit:")
            for line in recent:
                try:
                    entry = json.loads(line)
                    ts = entry.get("timestamp", "?")[:19]
                    op = entry.get("operation", "?")
                    outcome = entry.get("outcome", "?")
                    level = entry.get("auth_level", "?")
                    typer.echo(f"  {ts}  {op:30s}  {level:15s}  {outcome}")
                except json.JSONDecodeError:
                    pass


@app.command()
def docker(
    args: list[str] = typer.Argument(None, help="Docker command arguments"),
) -> None:
    """Docker passthrough with policy gating (same logic as shell wrapper)."""
    from igris.docker.audit import log_entry
    from igris.docker.policy import AuthLevel, PolicyConfig, classify_docker_command

    if not args:
        typer.echo("Usage: igris docker <docker-args>")
        raise typer.Exit(1)

    # VM bypass
    if _is_vm():
        _exec_docker(args)

    # Enforcement disabled
    if os.environ.get("IGRIS_DOCKER_ENABLED", "true") == "false":
        _exec_docker(args)
    if os.environ.get("TOMB_YUBIKEY_ENABLED", "true") == "false":
        _exec_docker(args)

    policy_path = Path.home() / ".config" / "igris" / "policy.yaml"
    policy = PolicyConfig.load(policy_path)
    operation, level = classify_docker_command(args, policy)

    if level == AuthLevel.AUTO_APPROVE:
        log_entry(operation, level.value, "approved", f"docker {' '.join(args)}")
        _exec_docker(args)

    repo_root = _repo_root()
    verify_script = repo_root / "scripts" / "hardware-verify.sh"

    if level == AuthLevel.SINGLE_TAP:
        if verify_script.exists():
            result = subprocess.run(
                [str(verify_script), f"docker {operation}"],
                check=False,
            )
            if result.returncode != 0:
                log_entry(operation, level.value, "denied", f"docker {' '.join(args)}")
                typer.echo("Hardware verification failed. Docker operation aborted.", err=True)
                raise typer.Exit(1)
        log_entry(operation, level.value, "approved", f"docker {' '.join(args)}")
        _exec_docker(args)

    if level == AuthLevel.DUAL_TAP:
        typer.echo(f"Dual-tap required for: docker {operation}", err=True)
        if verify_script.exists():
            # First tap
            typer.echo("First YubiKey tap...", err=True)
            r1 = subprocess.run(
                [str(verify_script), f"docker {operation} [tap 1/2]"],
                check=False,
            )
            if r1.returncode != 0:
                log_entry(operation, level.value, "denied", f"docker {' '.join(args)}")
                raise typer.Exit(1)

            # Second tap (cache disabled)
            import time

            time.sleep(1)
            typer.echo("Second YubiKey tap required (confirmation)...", err=True)
            env = os.environ.copy()
            env["TOMB_VERIFICATION_CACHE_ENABLED"] = "false"
            r2 = subprocess.run(
                [str(verify_script), f"docker {operation} [tap 2/2]"],
                env=env,
                check=False,
            )
            if r2.returncode != 0:
                log_entry(operation, level.value, "denied", f"docker {' '.join(args)}")
                raise typer.Exit(1)

        log_entry(operation, level.value, "approved", f"docker {' '.join(args)}")
        _exec_docker(args)


def _exec_docker(args: list[str]) -> None:
    """Execute the real docker binary (does not return)."""
    docker_bin = os.environ.get("IGRIS_DOCKER_BINARY")
    if not docker_bin:
        import shutil

        docker_bin = shutil.which("docker")
    if not docker_bin:
        typer.echo("Docker binary not found", err=True)
        raise typer.Exit(1)
    os.execvp(docker_bin, [docker_bin, *args])


@app.command()
def audit(
    tail: int = typer.Option(10, "--tail", "-n", help="Number of entries to show"),
) -> None:
    """View recent Docker audit entries."""
    audit_path = Path.home() / ".cache" / "igris" / "audit.jsonl"
    if not audit_path.exists():
        typer.echo("No audit entries found.")
        raise typer.Exit(0)

    lines = audit_path.read_text().strip().splitlines()
    recent = lines[-tail:] if len(lines) > tail else lines

    typer.echo(f"{'Timestamp':<22} {'Operation':<30} {'Level':<15} {'Outcome':<10} {'Command'}")
    typer.echo("-" * 100)
    for line in recent:
        try:
            entry = json.loads(line)
            ts = entry.get("timestamp", "?")[:19]
            op = entry.get("operation", "?")
            level = entry.get("auth_level", "?")
            outcome = entry.get("outcome", "?")
            cmd = entry.get("raw_command", "?")[:40]
            typer.echo(f"{ts:<22} {op:<30} {level:<15} {outcome:<10} {cmd}")
        except json.JSONDecodeError:
            pass


@app.command()
def policy(
    show: bool = typer.Option(True, "--show", help="Display current policy"),
) -> None:
    """Display current Docker policy configuration."""
    policy_path = Path.home() / ".config" / "igris" / "policy.yaml"

    if not policy_path.exists():
        typer.echo("No custom policy found. Using embedded defaults.")
        typer.echo(f"Expected location: {policy_path}")
        typer.echo("")
        _show_default_policy()
        return

    if show:
        typer.echo(f"Policy file: {policy_path}\n")
        typer.echo(policy_path.read_text())


def _show_default_policy() -> None:
    """Display the embedded default policy."""
    from igris.docker.policy import DEFAULT_POLICY

    typer.echo("=== Embedded Default Policy ===\n")
    for level_name, ops in DEFAULT_POLICY.items():
        typer.echo(f"[{level_name}]")
        for op in ops:
            typer.echo(f"  - {op}")
        typer.echo("")


if __name__ == "__main__":
    app()
