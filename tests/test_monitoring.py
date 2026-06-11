
from hms.lib.monitoring import HealthEvent, compute_disk_event, compute_health_events

# --- compute_health_events ---


def test_first_unhealthy_reading_does_not_alert():
    events, state = compute_health_events({}, {"media": "unhealthy"})
    assert events == []
    assert state == {"media": {"state": "unhealthy", "alerted": False}}


def test_second_consecutive_unhealthy_alerts():
    prev = {"media": {"state": "unhealthy", "alerted": False}}
    events, state = compute_health_events(prev, {"media": "unhealthy"})
    assert events == [HealthEvent("media", "alert", "unhealthy")]
    assert state["media"]["alerted"] is True


def test_already_alerted_does_not_repeat():
    prev = {"media": {"state": "unhealthy", "alerted": True}}
    events, state = compute_health_events(prev, {"media": "unhealthy"})
    assert events == []
    assert state["media"]["alerted"] is True


def test_recovery_notifies_once():
    prev = {"media": {"state": "unhealthy", "alerted": True}}
    events, state = compute_health_events(prev, {"media": "ready"})
    assert events == [HealthEvent("media", "recovery", "ready")]
    assert state["media"]["alerted"] is False


def test_ready_without_previous_alert_is_silent():
    events, state = compute_health_events({}, {"media": "ready"})
    assert events == []
    assert state == {"media": {"state": "ready", "alerted": False}}


def test_empty_stack_is_dropped_from_tracking():
    prev = {"media": {"state": "unhealthy", "alerted": True}}
    events, state = compute_health_events(prev, {"media": "empty"})
    assert events == []
    assert "media" not in state


def test_starting_keeps_alerted_flag_without_event():
    prev = {"media": {"state": "unhealthy", "alerted": True}}
    events, state = compute_health_events(prev, {"media": "starting"})
    assert events == []
    assert state["media"] == {"state": "starting", "alerted": True}


def test_multiple_stacks_independent():
    prev = {
        "media": {"state": "unhealthy", "alerted": False},
        "infra": {"state": "ready", "alerted": False},
    }
    readings = {"media": "unhealthy", "infra": "ready"}
    events, state = compute_health_events(prev, readings)
    assert events == [HealthEvent("media", "alert", "unhealthy")]
    assert state["infra"] == {"state": "ready", "alerted": False}


# --- compute_disk_event ---


def test_disk_alert_when_crossing_threshold():
    assert compute_disk_event(90.0, 85, alerted=False) == ("alert", True)


def test_disk_alert_not_repeated_while_above():
    assert compute_disk_event(91.0, 85, alerted=True) == (None, True)


def test_disk_no_recovery_inside_hysteresis_band():
    # alerted y al 82% con umbral 85: aún no recupera (banda 80-85)
    assert compute_disk_event(82.0, 85, alerted=True) == (None, True)


def test_disk_recovery_below_hysteresis():
    assert compute_disk_event(79.9, 85, alerted=True) == ("recovery", False)


def test_disk_below_threshold_silent():
    assert compute_disk_event(50.0, 85, alerted=False) == (None, False)
