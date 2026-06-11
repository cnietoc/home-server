"""
Pure decision logic for the monitoring jobs (health-watch, disk-watch).

Kept free of Docker/config/state dependencies so it can be unit-tested.
"""

from typing import NamedTuple, Optional


class HealthEvent(NamedTuple):
    stack: str
    kind: str  # "alert" | "recovery"
    state: str  # readiness that triggered the event


def compute_health_events(previous: dict, readings: dict) -> tuple[list[HealthEvent], dict]:
    """
    Compare current readiness readings against the persisted previous state.

    :param previous: {stack: {"state": str, "alerted": bool}} from the last run
    :param readings: {stack: readiness} where readiness is one of
                     "ready" | "starting" | "unhealthy" | "empty"
    :return: (events, new_state) — events to notify and the state to persist

    Rules:
    - An alert fires only on the SECOND consecutive "unhealthy" reading
      (debounce against transient failures during deploys/restarts).
    - A recovery fires when an alerted stack returns to "ready".
    - "empty" stacks (intentionally down) are dropped from tracking silently.
    - "starting" keeps the alerted flag so recovery still fires on "ready".
    """
    events: list[HealthEvent] = []
    new_state: dict = {}

    for stack, reading in readings.items():
        prev = previous.get(stack, {})
        prev_state = prev.get("state")
        alerted = bool(prev.get("alerted"))

        if reading == "empty":
            continue

        if reading == "unhealthy":
            if prev_state == "unhealthy" and not alerted:
                events.append(HealthEvent(stack, "alert", reading))
                alerted = True
        elif reading == "ready":
            if alerted:
                events.append(HealthEvent(stack, "recovery", reading))
            alerted = False

        new_state[stack] = {"state": reading, "alerted": alerted}

    return events, new_state


# Recovery requires dropping this many points below the threshold (hysteresis).
DISK_HYSTERESIS = 5


def compute_disk_event(
    usage_percent: float, threshold: int, alerted: bool
) -> tuple[Optional[str], bool]:
    """
    Decide whether disk usage warrants a notification.

    :param usage_percent: current usage (0-100)
    :param threshold: alert threshold in percent
    :param alerted: whether an alert is currently active
    :return: (event, new_alerted) — event is "alert", "recovery" or None
    """
    if usage_percent >= threshold and not alerted:
        return "alert", True
    if alerted and usage_percent < threshold - DISK_HYSTERESIS:
        return "recovery", False
    return None, alerted
