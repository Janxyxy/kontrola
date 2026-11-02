import Toybox.Attention;
import Toybox.Lang;
import Toybox.WatchUi;

// Buttons, FR955 layout:
//   START  start / pause (opens pause menu)
//   BACK   punch control (lap) while recording; exit when idle/done
//   UP/DN  switch screens
//   hold UP  settings before start, race menu (undo punch) while racing
// Touch is ignored so branches and sleeves can't pause or lap.
class RaceDelegate extends WatchUi.BehaviorDelegate {

    private var _race as RaceSession;
    private var _view as RaceView;

    function initialize(race as RaceSession, view as RaceView) {
        BehaviorDelegate.initialize();
        _race = race;
        _view = view;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ENTER) {
            onStartKey();
            return true;
        }
        if (key == WatchUi.KEY_ESC) {
            return onLapKey();
        }
        return false;   // UP / DOWN / MENU fall through to behaviors
    }

    private function onStartKey() as Void {
        switch (_race.state) {
            case STATE_IDLE:
                _race.start();
                vibrate(400);
                break;
            case STATE_RUNNING:
                _race.pause();
                vibrate(200);
                openPauseMenu();
                break;
            case STATE_PAUSED:
                openPauseMenu();
                break;
        }
        WatchUi.requestUpdate();
    }

    private function onLapKey() as Boolean {
        switch (_race.state) {
            case STATE_RUNNING:
                _race.punch();
                vibrate(150);
                WatchUi.requestUpdate();
                return true;
            case STATE_PAUSED:
                return true;    // don't exit with an unsaved race
            default:
                WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);   // root view -> exits app
                return true;
        }
    }

    function onNextPage() as Boolean {
        if (_race.state == STATE_RUNNING || _race.state == STATE_PAUSED) {
            _view.nextPage(1);
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_race.state == STATE_RUNNING || _race.state == STATE_PAUSED) {
            _view.nextPage(-1);
        }
        return true;
    }

    function onMenu() as Boolean {
        if (_race.state == STATE_IDLE) {
            openSettingsMenu();
        } else if (_race.state == STATE_RUNNING) {
            openRaceMenu();     // timer keeps running
        }
        return true;
    }

    // swallow touch-generated behaviors
    function onSelect() as Boolean { return true; }
    function onBack() as Boolean { return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { return true; }
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean { return true; }

    // --- menus ---

    private function openPauseMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "Paused"});
        menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
        menu.addItem(new WatchUi.MenuItem("Save", null, :save, null));
        if (_race.punched > 0) {
            menu.addItem(undoItem(_race));
        }
        menu.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
        WatchUi.pushView(menu, new PauseMenuDelegate(_race), WatchUi.SLIDE_UP);
    }

    private function openRaceMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "Race"});
        menu.addItem(undoItem(_race));
        WatchUi.pushView(menu, new RaceMenuDelegate(_race), WatchUi.SLIDE_UP);
    }

    private function openSettingsMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "Settings"});
        var n = _race.numControls;
        menu.addItem(new WatchUi.MenuItem("Controls", n > 0 ? n.format("%d") : "unknown", :controls, null));
        menu.addItem(new WatchUi.MenuItem("Version", APP_VERSION, :version, null));
        WatchUi.pushView(menu, new SettingsMenuDelegate(_race), WatchUi.SLIDE_UP);
    }
}

// "Undo punch  C7 · 0:04" (sub label names the punch that would be removed)
function undoItem(race as RaceSession) as WatchUi.MenuItem {
    var last = race.lastSplitMs();
    var sub = last != null ? "C" + race.punched.format("%d") + "  " + formatTime(last) : "nothing to undo";
    return new WatchUi.MenuItem("Undo punch", sub, :undo, null);
}

function vibrate(ms as Number) as Void {
    if (Attention has :vibrate) {
        Attention.vibrate([new Attention.VibeProfile(100, ms)]);
    }
}
