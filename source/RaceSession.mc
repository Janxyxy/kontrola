import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.UserProfile;

enum RaceState {
    STATE_IDLE,
    STATE_RUNNING,
    STATE_PAUSED,
    STATE_DONE
}

// Recording + split bookkeeping. One lap in the FIT file = one leg.
class RaceSession {

    var state as RaceState = STATE_IDLE;
    var numControls as Number = 0;          // 0 = unknown
    var punched as Number = 0;              // controls punched so far
    var splits as Array<Number> = [];       // leg times in ms
    var lastPunchAt as Number = -100000;    // System.getTimer() of last punch
    var saved as Boolean = false;
    var gpsAccuracy as Position.Quality = Position.QUALITY_NOT_AVAILABLE;

    private var _session as ActivityRecording.Session?;
    private var _legField as FitContributor.Field?;
    private var _controlsField as FitContributor.Field?;
    private var _legStartTime as Number = 0;     // timerTime (ms) at leg start
    private var _legStartDist as Float = 0.0;    // elapsedDistance (m) at leg start
    private var _prevStartDists as Array<Float> = [];  // leg start distances, for undo

    function initialize() {
        loadSettings();
    }

    function loadSettings() as Void {
        var n = Application.Properties.getValue("numControls");
        numControls = (n instanceof Number && n >= 0) ? n : 0;
    }

    function setNumControls(n as Number) as Void {
        numControls = n;
        Application.Properties.setValue("numControls", n);
    }

    // --- recording lifecycle ---

    function start() as Void {
        if (state != STATE_IDLE) {
            return;
        }
        var session = ActivityRecording.createSession({
            :name => "Orienteering",
            :sport => Activity.SPORT_RUNNING,
            :subSport => Activity.SUB_SPORT_TRAIL
        });
        _legField = session.createField("leg", 0, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_LAP});
        _controlsField = session.createField("controls", 1, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION});
        _legField.setData(1);
        _controlsField.setData(0);
        session.start();
        _session = session;
        punched = 0;
        splits = [];
        _legStartTime = 0;
        _legStartDist = 0.0;
        _prevStartDists = [];
        state = STATE_RUNNING;
    }

    function pause() as Void {
        if (state == STATE_RUNNING && _session != null) {
            _session.stop();
            state = STATE_PAUSED;
        }
    }

    function resume() as Void {
        if (state == STATE_PAUSED && _session != null) {
            _session.start();
            state = STATE_RUNNING;
        }
    }

    // Lap button: close the current leg at a control.
    function punch() as Void {
        var session = _session;
        var legField = _legField;
        var controlsField = _controlsField;
        if (state != STATE_RUNNING || session == null || legField == null || controlsField == null) {
            return;
        }
        var now = timerMs();
        splits.add(now - _legStartTime);
        session.addLap();           // writes the lap with the current "leg" value
        punched++;
        legField.setData(punched + 1);
        controlsField.setData(punched);
        _legStartTime = now;
        _prevStartDists.add(_legStartDist);
        _legStartDist = distanceM();
        lastPunchAt = System.getTimer();
    }

    // Take back the last punch: the current leg continues from the previous control.
    // The lap already in the FIT file can't be removed, but the next lap gets the
    // same "leg" number, so laps sharing a leg number belong to one leg.
    function undoPunch() as Boolean {
        var legField = _legField;
        var controlsField = _controlsField;
        if (punched == 0 || legField == null || controlsField == null
                || (state != STATE_RUNNING && state != STATE_PAUSED)) {
            return false;
        }
        var last = splits[splits.size() - 1];
        splits = splits.slice(0, splits.size() - 1);
        _legStartTime -= last;
        _legStartDist = _prevStartDists[_prevStartDists.size() - 1];
        _prevStartDists = _prevStartDists.slice(0, _prevStartDists.size() - 1);
        punched--;
        legField.setData(punched + 1);
        controlsField.setData(punched);
        lastPunchAt = -100000;
        return true;
    }

    function save() as Void {
        if (_session == null) {
            return;
        }
        if (_session.isRecording()) {
            _session.stop();
        }
        _session.save();
        _session = null;
        saved = true;
        state = STATE_DONE;
    }

    function discard() as Void {
        if (_session == null) {
            return;
        }
        if (_session.isRecording()) {
            _session.stop();
        }
        _session.discard();
        _session = null;
        state = STATE_DONE;
    }

    function saveIfRecording() as Void {
        if (state == STATE_RUNNING || state == STATE_PAUSED) {
            save();
        }
    }

    // --- values for the screens ---

    function timerMs() as Number {
        var info = Activity.getActivityInfo();
        return (info != null && info.timerTime != null) ? info.timerTime as Number : 0;
    }

    function distanceM() as Float {
        var info = Activity.getActivityInfo();
        return (info != null && info.elapsedDistance != null) ? info.elapsedDistance as Float : 0.0;
    }

    function heartRate() as Number? {
        var info = Activity.getActivityInfo();
        return info != null ? info.currentHeartRate : null;
    }

    // 1..5 from the user's running HR zones, 0 below zone 1
    function heartRateZone(hr as Number) as Number {
        var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_RUNNING);
        if (zones == null || zones.size() < 6 || hr < zones[0]) {
            return 0;
        }
        for (var i = 1; i < 6; i++) {
            if (hr <= zones[i]) {
                return i;
            }
        }
        return 5;
    }

    function legMs() as Number {
        return timerMs() - _legStartTime;
    }

    function legDistanceM() as Float {
        return distanceM() - _legStartDist;
    }

    // Label of the control we're heading to: "7/14", "7", or "F"
    function targetLabel() as String {
        var next = punched + 1;
        if (numControls > 0) {
            return next > numControls ? "F" : next.format("%d") + "/" + numControls.format("%d");
        }
        return next.format("%d");
    }

    function lastSplitMs() as Number? {
        return splits.size() > 0 ? splits[splits.size() - 1] : null;
    }
}
