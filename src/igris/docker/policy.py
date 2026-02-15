"""Docker operation policy engine for igris.

Classifies Docker CLI commands into auth levels:
- auto_approve: read-only operations, no YubiKey needed
- single_tap: state-changing operations, one YubiKey tap
- dual_tap: destructive operations, two YubiKey taps
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Optional

import yaml


class AuthLevel(str, Enum):
    AUTO_APPROVE = "auto_approve"
    SINGLE_TAP = "single_tap"
    DUAL_TAP = "dual_tap"


# Docker CLI aliases → canonical subcommand mapping
_DOCKER_ALIASES: dict[str, str] = {
    "ps": "container.list",
    "run": "container.run",
    "exec": "container.exec",
    "rm": "container.rm",
    "kill": "container.kill",
    "stop": "container.stop",
    "start": "container.start",
    "restart": "container.restart",
    "logs": "container.logs",
    "inspect": "container.inspect",
    "create": "container.create",
    "attach": "container.attach",
    "wait": "container.wait",
    "top": "container.top",
    "stats": "container.stats",
    "diff": "container.diff",
    "cp": "container.cp",
    "commit": "container.commit",
    "export": "container.export",
    "rename": "container.rename",
    "update": "container.update",
    "port": "container.port",
    "pause": "container.pause",
    "unpause": "container.unpause",
    "pull": "image.pull",
    "push": "image.push",
    "build": "image.build",
    "images": "image.list",
    "rmi": "image.rm",
    "tag": "image.tag",
    "save": "image.save",
    "load": "image.load",
    "history": "image.history",
    "login": "login",
    "logout": "logout",
    "info": "info",
    "version": "version",
    "events": "events",
    "search": "search",
}

# Default policy (embedded fallback)
DEFAULT_POLICY: dict[str, list[str]] = {
    "auto_approve": [
        "container.logs",
        "container.list",
        "container.inspect",
        "container.top",
        "container.stats",
        "container.diff",
        "container.port",
        "container.wait",
        "image.list",
        "image.inspect",
        "image.history",
        "network.list",
        "network.inspect",
        "volume.list",
        "volume.inspect",
        "compose.ps",
        "compose.logs",
        "compose.config",
        "info",
        "version",
        "events",
        "search",
    ],
    "single_tap": [
        "container.start",
        "container.stop",
        "container.restart",
        "container.create",
        "container.run",
        "container.pause",
        "container.unpause",
        "container.rename",
        "container.update",
        "container.cp",
        "container.commit",
        "container.export",
        "container.attach",
        "image.pull",
        "image.build",
        "image.tag",
        "image.save",
        "image.load",
        "image.push",
        "network.create",
        "network.connect",
        "network.disconnect",
        "volume.create",
        "compose.up",
        "compose.down",
        "compose.restart",
        "compose.build",
        "compose.pull",
        "compose.start",
        "compose.stop",
        "compose.create",
        "login",
        "logout",
    ],
    "dual_tap": [
        "container.exec",
        "container.rm",
        "container.kill",
        "image.rm",
        "volume.rm",
        "network.rm",
        "compose.rm",
        "system.prune",
        "builder.prune",
        "image.prune",
        "container.prune",
        "network.prune",
        "volume.prune",
    ],
}


@dataclass
class PolicyConfig:
    """Loaded policy configuration."""

    operations: dict[str, AuthLevel] = field(default_factory=dict)

    @classmethod
    def load(cls, policy_path: Optional[Path] = None) -> PolicyConfig:
        """Load policy from YAML file, falling back to embedded defaults."""
        config = cls()

        # Try loading from file
        raw: dict[str, list[str]] | None = None
        if policy_path and policy_path.exists():
            with open(policy_path) as f:
                data = yaml.safe_load(f)
                if isinstance(data, dict) and "policy" in data:
                    raw = data["policy"]

        if raw is None:
            raw = DEFAULT_POLICY

        # Build operation → auth_level mapping
        for level_name, ops in raw.items():
            try:
                level = AuthLevel(level_name)
            except ValueError:
                continue
            for op in ops:
                config.operations[op] = level

        return config

    def classify(self, operation: str) -> AuthLevel:
        """Return the auth level for a dotted operation name."""
        if operation in self.operations:
            return self.operations[operation]
        # Unknown operations default to single_tap (safe)
        return AuthLevel.SINGLE_TAP


def parse_docker_args(args: list[str]) -> str:
    """Parse Docker CLI arguments into a dotted operation name.

    Examples:
        ["ps"]                    → "container.list"
        ["exec", "c1", "bash"]    → "container.exec"
        ["compose", "up", "-d"]   → "compose.up"
        ["container", "rm", "c1"] → "container.rm"
        ["system", "prune"]       → "system.prune"
        ["image", "ls"]           → "image.list"
    """
    if not args:
        return "unknown"

    # Skip global flags (e.g. --host, -H, --tls, --context)
    idx = 0
    while idx < len(args) and args[idx].startswith("-"):
        # Flags that take a value
        if args[idx] in ("-H", "--host", "--context", "--config", "--log-level", "-l"):
            idx += 2
        else:
            idx += 1

    remaining = args[idx:]
    if not remaining:
        return "unknown"

    cmd = remaining[0]

    # Handle docker compose
    if cmd in ("compose", "docker-compose"):
        if len(remaining) < 2:
            return "compose.unknown"
        subcmd = remaining[1]
        # Normalize aliases
        if subcmd in ("ls", "list"):
            subcmd = "ps"
        return f"compose.{subcmd}"

    # Handle top-level management commands (docker container, docker image, etc.)
    management_commands = {
        "container", "image", "network", "volume", "system", "builder",
        "manifest", "trust", "plugin", "config", "secret", "service",
        "stack", "node", "swarm", "context",
    }
    if cmd in management_commands:
        if len(remaining) < 2:
            return f"{cmd}.unknown"
        subcmd = remaining[1]
        # Normalize list aliases
        if subcmd in ("ls", "list"):
            subcmd = "list"
        if subcmd == "prune":
            return f"{cmd}.prune"
        return f"{cmd}.{subcmd}"

    # Handle top-level aliases (docker ps → container.list, etc.)
    if cmd in _DOCKER_ALIASES:
        return _DOCKER_ALIASES[cmd]

    # Unknown top-level command
    return f"{cmd}.unknown"


def classify_docker_command(
    args: list[str],
    policy: Optional[PolicyConfig] = None,
) -> tuple[str, AuthLevel]:
    """Classify a Docker command and return (operation, auth_level)."""
    if policy is None:
        policy = PolicyConfig.load()
    operation = parse_docker_args(args)
    return operation, policy.classify(operation)
