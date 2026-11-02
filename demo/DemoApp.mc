import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Cycles through every race screen with fake data, for screenshots.
class DemoApp extends OrienteeringApp {

    private var _demo as DemoRace;
    private var _view as RaceView?;
    private var _timer as Timer.Timer;
    private var _step as Number = 0;

    function initialize() {
        OrienteeringApp.initialize();
        _demo = new DemoRace();
        race = _demo;
        _timer = new Timer.Timer();
    }

    function onStart(state as Dictionary?) as Void {}
    function onStop(state as Dictionary?) as Void {}

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new RaceView(_demo);
        _view = view;
        apply();
        _timer.start(method(:next), 4000, true);
        return [view, new WatchUi.BehaviorDelegate()];
    }

    function next() as Void {
        _step = (_step + 1) % 8;
        apply();
        WatchUi.requestUpdate();
    }

    private function apply() as Void {
        var view = _view as RaceView;
        var d = _demo;
        d.lastPunchAt = -1000000;
        d.state = STATE_RUNNING;
        d.punched = 6;
        d.splits = [95000, 142000, 211000, 78000, 187000, 124000];
        d.fakeTimer = 34 * 60000 + 12000;
        d.fakeLeg = 2 * 60000 + 47000;
        view.page = 0;
        switch (_step) {
            case 0: d.state = STATE_IDLE; break;
            case 1: break;
            case 2: view.page = 1; break;
            case 3: view.page = 2; break;
            case 4: d.lastPunchAt = System.getTimer(); break;
            case 5: d.state = STATE_PAUSED; break;
            case 7: d.punched = 14; d.fakeLeg = 31000; break;
            case 6: d.state = STATE_DONE; d.saved = true; d.punched = 14; d.fakeTimer = 52 * 60000 + 38000; break;
        }
    }
}

class DemoRace extends RaceSession {

    var fakeTimer as Number = 0;
    var fakeLeg as Number = 0;

    function initialize() {
        RaceSession.initialize();
        numControls = 14;
        gpsAccuracy = Position.QUALITY_GOOD;
    }

    function timerMs() as Number { return fakeTimer; }
    function legMs() as Number { return fakeLeg; }
    function distanceM() as Float { return 4870.0; }
    function legDistanceM() as Float { return 312.0; }
    function heartRate() as Number? { return 168; }
}
