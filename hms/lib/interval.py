"""
Parse time intervals in natural format similar to Docker HEALTHCHECK.
Supports: 1d, 2h, 3m, 4s (days, hours, minutes, seconds)
"""

import re
from typing import Optional


def parse_interval(interval_str: str) -> Optional[int]:
    """
    Parse a time interval in natural format (e.g. "30m", "2h", "1d") to seconds.

    Args:
        interval_str: String with interval (e.g. "30m", "2h", "1d")

    Returns:
        Interval in seconds or None if invalid

    Examples:
        parse_interval("30m") -> 1800
        parse_interval("2h") -> 7200
        parse_interval("1d") -> 86400
        parse_interval("45s") -> 45
        parse_interval("1h30m") -> 5400
        parse_interval("1h 30m") -> 5400 (with spaces)
    """
    if not interval_str or not isinstance(interval_str, str):
        return None

    interval_str = interval_str.strip().lower()
    if not interval_str:
        return None

    # Remove spaces for parsing
    interval_str_normalized = interval_str.replace(" ", "")

    # Pattern to find numbers followed by a unit
    pattern = r"(\d+)([smhd])"
    matches = re.findall(pattern, interval_str_normalized)

    if not matches:
        return None

    # Verify that the full duration was parsed (no extra characters)
    reconstructed = "".join(f"{num}{unit}" for num, unit in matches)
    if reconstructed != interval_str_normalized:
        return None

    total_seconds = 0
    unit_map = {
        "s": 1,
        "m": 60,
        "h": 3600,
        "d": 86400,
    }

    for num_str, unit in matches:
        num = int(num_str)
        total_seconds += num * unit_map[unit]

    return total_seconds if total_seconds > 0 else None


def format_interval(seconds: int) -> str:
    """
    Format seconds to a readable interval (e.g. "1h 30m 45s").

    Args:
        seconds: Interval in seconds

    Returns:
        Formatted interval string

    Examples:
        format_interval(1800) -> "30m"
        format_interval(7200) -> "2h"
        format_interval(86400) -> "1d"
        format_interval(5400) -> "1h 30m"
    """
    if seconds <= 0:
        return "0s"

    units = [
        ("d", 86400),
        ("h", 3600),
        ("m", 60),
        ("s", 1),
    ]

    parts = []
    remaining = seconds

    for unit_name, unit_seconds in units:
        if remaining >= unit_seconds:
            count = remaining // unit_seconds
            remaining %= unit_seconds
            parts.append(f"{count}{unit_name}")

    return " ".join(parts) if parts else "0s"
