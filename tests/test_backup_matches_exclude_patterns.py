import pytest

from hms.plugins.common.system.backup import _is_excluded


@pytest.mark.parametrize(
    "rel,is_dir,patterns,expected",
    [
        pytest.param(
            "config/tdarr/server/Tdarr/Backups",
            True,
            ["/config/tdarr/server/Tdarr/Backups/"],
            True,
            id="absolute_dir_match",
        ),
        pytest.param(
            "data/media/config/tdarr/server/Tdarr/Backups",
            True,
            ["/config/tdarr/server/Tdarr/Backups/"],
            False,
            id="absolute_dir_no_match_different_parent",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups",
            True,
            ["Backups"],
            True,
            id="simple_directory_name_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups",
            True,
            ["Backup"],
            False,
            id="similar_name_no_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            False,
            ["config/tdarr/server/Tdarr/Backups/*"],
            True,
            id="wildcard_full_path_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            False,
            ["server/Tdarr/Other/*"],
            False,
            id="wildcard_pattern_no_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups",
            True,
            ["config/tdarr/server/Tdarr/Backups/"],
            True,
            id="exact_dir_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/BackupsX",
            True,
            ["config/tdarr/server/Tdarr/Backups/"],
            False,
            id="similar_dir_no_match",
        ),
        pytest.param(
            "foo/bar/baz.txt",
            False,
            ["*.txt"],
            True,
            id="glob_extension_match",
        ),
        pytest.param(
            "foo/bar/baz.tar.gz",
            False,
            ["*.txt"],
            False,
            id="glob_extension_no_match",
        ),
        pytest.param(
            "foo/bar/baz.txt",
            False,
            ["", "  ", "# comment", "*.txt"],
            True,
            id="pattern_with_empty_and_comments",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            False,
            ["/config"],
            True,
            id="root_component_match",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            False,
            ["config/tdarr/server/Tdarr/Backups"],
            True,
            id="ancestor_path_excludes_file",
        ),
        pytest.param(
            "config/tdarr/server/Tdarr/Backups/file.zip",
            False,
            ["/config/tdarr/server/Tdarr/Backups/"],
            False,
            id="dir_only_pattern_skipped_for_files",
        ),
    ],
)
def test_is_excluded(rel, is_dir, patterns, expected):
    """Test that _is_excluded correctly identifies excluded paths."""
    result = _is_excluded(rel, is_dir, patterns)
    assert result is expected, (
        f"rel: {rel}\n"
        f"is_dir: {is_dir}\n"
        f"patterns: {patterns}\n"
        f"expected: {expected}\n"
        f"got: {result}"
    )
