"""Tests for Docker operation policy engine."""

import tempfile
from pathlib import Path

import pytest

from igris.docker.policy import (
    AuthLevel,
    PolicyConfig,
    classify_docker_command,
    parse_docker_args,
)


class TestParseDockerArgs:
    """Test Docker CLI argument parsing into dotted operation names."""

    def test_top_level_aliases(self):
        assert parse_docker_args(["ps"]) == "container.list"
        assert parse_docker_args(["run", "nginx"]) == "container.run"
        assert parse_docker_args(["exec", "c1", "bash"]) == "container.exec"
        assert parse_docker_args(["rm", "c1"]) == "container.rm"
        assert parse_docker_args(["kill", "c1"]) == "container.kill"
        assert parse_docker_args(["logs", "c1"]) == "container.logs"
        assert parse_docker_args(["inspect", "c1"]) == "container.inspect"
        assert parse_docker_args(["pull", "nginx"]) == "image.pull"
        assert parse_docker_args(["push", "myimg"]) == "image.push"
        assert parse_docker_args(["build", "."]) == "image.build"
        assert parse_docker_args(["images"]) == "image.list"
        assert parse_docker_args(["rmi", "img"]) == "image.rm"
        assert parse_docker_args(["info"]) == "info"
        assert parse_docker_args(["version"]) == "version"

    def test_management_commands(self):
        assert parse_docker_args(["container", "rm", "c1"]) == "container.rm"
        assert parse_docker_args(["container", "ls"]) == "container.list"
        assert parse_docker_args(["container", "list"]) == "container.list"
        assert parse_docker_args(["image", "ls"]) == "image.list"
        assert parse_docker_args(["image", "rm", "img"]) == "image.rm"
        assert parse_docker_args(["network", "ls"]) == "network.list"
        assert parse_docker_args(["network", "rm", "net"]) == "network.rm"
        assert parse_docker_args(["volume", "ls"]) == "volume.list"
        assert parse_docker_args(["volume", "rm", "vol"]) == "volume.rm"
        assert parse_docker_args(["system", "prune"]) == "system.prune"
        assert parse_docker_args(["builder", "prune"]) == "builder.prune"

    def test_compose_commands(self):
        assert parse_docker_args(["compose", "up", "-d"]) == "compose.up"
        assert parse_docker_args(["compose", "down"]) == "compose.down"
        assert parse_docker_args(["compose", "ps"]) == "compose.ps"
        assert parse_docker_args(["compose", "logs"]) == "compose.logs"
        assert parse_docker_args(["compose", "rm"]) == "compose.rm"
        assert parse_docker_args(["compose", "build"]) == "compose.build"
        assert parse_docker_args(["compose", "config"]) == "compose.config"
        assert parse_docker_args(["compose", "restart"]) == "compose.restart"
        assert parse_docker_args(["compose", "pull"]) == "compose.pull"

    def test_global_flags_skipped(self):
        assert parse_docker_args(["-H", "tcp://host:2375", "ps"]) == "container.list"
        assert parse_docker_args(["--host", "tcp://host:2375", "rm", "c1"]) == "container.rm"
        assert parse_docker_args(["--context", "mainmac", "exec", "c1", "sh"]) == "container.exec"

    def test_empty_args(self):
        assert parse_docker_args([]) == "unknown"

    def test_unknown_command(self):
        result = parse_docker_args(["somethingweird"])
        assert result == "somethingweird.unknown"


class TestPolicyConfig:
    """Test policy loading and classification."""

    def test_default_policy_classifies_read_ops(self):
        policy = PolicyConfig.load()
        assert policy.classify("container.logs") == AuthLevel.AUTO_APPROVE
        assert policy.classify("container.list") == AuthLevel.AUTO_APPROVE
        assert policy.classify("image.list") == AuthLevel.AUTO_APPROVE
        assert policy.classify("info") == AuthLevel.AUTO_APPROVE
        assert policy.classify("version") == AuthLevel.AUTO_APPROVE
        assert policy.classify("compose.ps") == AuthLevel.AUTO_APPROVE

    def test_default_policy_classifies_write_ops(self):
        policy = PolicyConfig.load()
        assert policy.classify("container.start") == AuthLevel.SINGLE_TAP
        assert policy.classify("container.stop") == AuthLevel.SINGLE_TAP
        assert policy.classify("container.run") == AuthLevel.SINGLE_TAP
        assert policy.classify("image.pull") == AuthLevel.SINGLE_TAP
        assert policy.classify("image.build") == AuthLevel.SINGLE_TAP
        assert policy.classify("compose.up") == AuthLevel.SINGLE_TAP
        assert policy.classify("compose.down") == AuthLevel.SINGLE_TAP

    def test_default_policy_classifies_destructive_ops(self):
        policy = PolicyConfig.load()
        assert policy.classify("container.exec") == AuthLevel.DUAL_TAP
        assert policy.classify("container.rm") == AuthLevel.DUAL_TAP
        assert policy.classify("container.kill") == AuthLevel.DUAL_TAP
        assert policy.classify("image.rm") == AuthLevel.DUAL_TAP
        assert policy.classify("volume.rm") == AuthLevel.DUAL_TAP
        assert policy.classify("system.prune") == AuthLevel.DUAL_TAP

    def test_unknown_operation_defaults_to_single_tap(self):
        policy = PolicyConfig.load()
        assert policy.classify("something.unusual") == AuthLevel.SINGLE_TAP

    def test_load_from_yaml(self):
        yaml_content = """
policy:
  auto_approve:
    - custom.read
  single_tap:
    - custom.write
  dual_tap:
    - custom.destroy
"""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
            f.write(yaml_content)
            f.flush()
            policy = PolicyConfig.load(Path(f.name))

        assert policy.classify("custom.read") == AuthLevel.AUTO_APPROVE
        assert policy.classify("custom.write") == AuthLevel.SINGLE_TAP
        assert policy.classify("custom.destroy") == AuthLevel.DUAL_TAP
        # Unknown still defaults
        assert policy.classify("unknown.op") == AuthLevel.SINGLE_TAP

        Path(f.name).unlink()

    def test_load_nonexistent_file_uses_defaults(self):
        policy = PolicyConfig.load(Path("/nonexistent/policy.yaml"))
        assert policy.classify("container.logs") == AuthLevel.AUTO_APPROVE
        assert policy.classify("container.exec") == AuthLevel.DUAL_TAP


class TestClassifyDockerCommand:
    """Integration tests for the full classify pipeline."""

    def test_ps_auto_approved(self):
        op, level = classify_docker_command(["ps"])
        assert op == "container.list"
        assert level == AuthLevel.AUTO_APPROVE

    def test_exec_dual_tap(self):
        op, level = classify_docker_command(["exec", "container1", "bash"])
        assert op == "container.exec"
        assert level == AuthLevel.DUAL_TAP

    def test_compose_up_single_tap(self):
        op, level = classify_docker_command(["compose", "up", "-d"])
        assert op == "compose.up"
        assert level == AuthLevel.SINGLE_TAP

    def test_system_prune_dual_tap(self):
        op, level = classify_docker_command(["system", "prune"])
        assert op == "system.prune"
        assert level == AuthLevel.DUAL_TAP

    def test_logs_auto_approved(self):
        op, level = classify_docker_command(["logs", "-f", "container1"])
        assert op == "container.logs"
        assert level == AuthLevel.AUTO_APPROVE

    def test_restart_single_tap(self):
        op, level = classify_docker_command(["restart", "container1"])
        assert op == "container.restart"
        assert level == AuthLevel.SINGLE_TAP

    def test_with_global_flags(self):
        op, level = classify_docker_command(["--context", "mainmac", "exec", "c1", "sh"])
        assert op == "container.exec"
        assert level == AuthLevel.DUAL_TAP
