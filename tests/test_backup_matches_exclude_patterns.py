import pytest

from hms.plugins.common.system.backup import BackupPlugin


@pytest.mark.parametrize(
    "path,patterns,expected",
    [
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            ["/config/tdarr/server/Tdarr/Backups/"],
            True,
            id="absolute_path_match",
        ),
        pytest.param(
            "data/media/config/tdarr/server/Tdarr/Backups/file.zip",
            ["/config/tdarr/server/Tdarr/Backups/"],
            False,
            id="absolute_path_no_match_different_parent",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            ["Backups"],
            True,
            id="simple_directory_name_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            ["Backup"],
            False,
            id="similar_name_no_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            ["tdarr/server/Tdarr/Backups/*"],
            True,
            id="wildcard_pattern_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            ["server/Tdarr/Other/*"],
            False,
            id="wildcard_pattern_no_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            ["config/tdarr/server/Tdarr/Backups/"],
            True,
            id="exact_path_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/BackupsX/file.zip",
            ["config/tdarr/server/Tdarr/Backups/"],
            False,
            id="similar_path_no_match",
        ),
        pytest.param(
            "foo/bar/baz.txt",
            ["*.txt"],
            True,
            id="glob_extension_match",
        ),
        pytest.param(
            "foo/bar/baz.tar.gz",
            ["*.txt"],
            False,
            id="glob_extension_no_match",
        ),
        pytest.param(
            "foo/bar/baz.txt",
            ["", "  ", "# comment", "*.txt"],
            True,
            id="pattern_with_empty_and_comments",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            ["/config"],
            True,
            id="root_path_match",
        ),
    ],
)
def test_matches_exclude_patterns(path, patterns, expected):
    """Test that exclude patterns matching works correctly."""
    plugin = BackupPlugin()
    result = plugin._matches_exclude_patterns(path, patterns)
    assert result is expected, (
        f"Path: {path}\n"
        f"Patterns: {patterns}\n"
        f"Expected: {expected}\n"
        f"Got: {result}"
    )
