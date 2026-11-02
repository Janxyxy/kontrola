import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Cycles through every race screen with fake data, for screenshots.
// The step comes from the wall clock (4 s each, 9 steps), so tools/screens.py
// knows which screen is up without watching the display.
const STEP_SECONDS = 4;
const STEPS = 9;
class DemoApp extends KontrolaApp {

    private var _demo as DemoRace;
    private var _view as RaceView?;
    private var _timer as Timer.Timer;
    private var _step as Number = -1;
    private var _menuShown as Boolean = false;

    function initialize() {
        KontrolaApp.initialize();
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
        _timer.start(method(:tick), 250, true);
        return [view, new WatchUi.BehaviorDelegate()];
    }

    private function clockStep() as Number {
        return (Time.now().value() / STEP_SECONDS) % STEPS;
    }

    function tick() as Void {
        var step = clockStep();
        if (step == _step) {
            return;
        }
        if (_menuShown) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            _menuShown = false;
        }
        _step = step;
        apply();
        if (_step == 8) {
            var menu = new WatchUi.Menu2({:title => "Race"});
            menu.addItem(undoItem(_demo));
            WatchUi.pushView(menu, new WatchUi.Menu2InputDelegate(), WatchUi.SLIDE_IMMEDIATE);
            _menuShown = true;
        }
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
            case 8: break;
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
