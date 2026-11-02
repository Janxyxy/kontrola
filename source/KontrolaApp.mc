import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

class KontrolaApp extends Application.AppBase {

    var race as RaceSession;

    function initialize() {
        AppBase.initialize();
        race = new RaceSession();
    }

    function onStart(state as Dictionary?) as Void {
        // GPS on from launch so we have a fix before the start
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    function onStop(state as Dictionary?) as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        // never lose a race if the app is closed mid-recording
        race.saveIfRecording();
    }

    function onPosition(info as Position.Info) as Void {
        race.gpsAccuracy = info.accuracy;
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() as Void {
        race.loadSettings();
        WatchUi.requestUpdate();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new RaceView(race);
        return [view, new RaceDelegate(race, view)];
    }
}

function getApp() as KontrolaApp {
    return Application.getApp() as KontrolaApp;
}
