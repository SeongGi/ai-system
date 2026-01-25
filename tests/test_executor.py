"""
Test suite for executor module.
"""

import pytest
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from executor import CommandExecutor
from security import SecurityFilter


@pytest.fixture
def executor():
    """Create a command executor."""
    return CommandExecutor(timeout=5)


@pytest.fixture
def security_filter(tmp_path):
    """Create a security filter."""
    blacklist_file = tmp_path / "blacklist.txt"
    blacklist_file.write_text("rm\nmkfs\n")
    return SecurityFilter(str(blacklist_file))


def test_execute_simple_command(executor):
    """Test executing a simple command."""
    success, output = executor.execute("echo 'Hello, World!'")
    assert success
    assert "Hello, World!" in output


def test_execute_failing_command(executor):
    """Test executing a command that fails."""
    success, output = executor.execute("ls /nonexistent_directory_12345")
    assert not success
    assert "No such file or directory" in output or "cannot access" in output


def test_execute_empty_command(executor):
    """Test executing an empty command."""
    success, output = executor.execute("")
    assert not success
    assert "Empty command" in output


def test_execute_with_timeout(executor):
    """Test command timeout."""
    # This command should timeout
    success, output = executor.execute("sleep 10")
    assert not success
    assert "timed out" in output.lower()


def test_execute_with_validation_safe(executor, security_filter):
    """Test executing a safe command with validation."""
    success, output, error = executor.execute_with_validation(
        "echo 'test'", security_filter
    )
    assert success
    assert "test" in output
    assert error is None


def test_execute_with_validation_unsafe(executor, security_filter):
    """Test executing an unsafe command with validation."""
    success, output, error = executor.execute_with_validation(
        "rm -rf /tmp/test", security_filter
    )
    assert not success
    assert output == ""
    assert error is not None
    assert "Security check failed" in error
