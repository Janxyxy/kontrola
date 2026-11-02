import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _race as RaceSession;

    function initialize(race as RaceSession) {
        Menu2InputDelegate.initialize();
        _race = race;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :resume) {
            _race.resume();
            vibrate(200);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :save) {
            _race.save();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :discard) {
            WatchUi.pushView(new WatchUi.Confirmation("Discard race?"),
                new DiscardConfirmDelegate(_race), WatchUi.SLIDE_IMMEDIATE);
        }
    }

    // BACK closes the menu and stays paused
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class DiscardConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _race as RaceSession;

    function initialize(race as RaceSession) {
        ConfirmationDelegate.initialize();
        _race = race;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _race.discard();
            // confirmation pops itself; also close the pause menu underneath
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        return true;
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _race as RaceSession;

    function initialize(race as RaceSession) {
        Menu2InputDelegate.initialize();
        _race = race;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :controls) {
            var factory = new NumberFactory(0, 60);
            var picker = new WatchUi.Picker({
                :title => new WatchUi.Text({:text => "Controls", :color => Graphics.COLOR_WHITE,
                    :font => Graphics.FONT_SMALL, :locX => WatchUi.LAYOUT_HALIGN_CENTER,
                    :locY => WatchUi.LAYOUT_VALIGN_BOTTOM}),
                :pattern => [factory],
                :defaults => [_race.numControls]
            });
            WatchUi.pushView(picker, new ControlsPickerDelegate(_race, item), WatchUi.SLIDE_LEFT);
        }
    }
}

class ControlsPickerDelegate extends WatchUi.PickerDelegate {

    private var _race as RaceSession;
    private var _item as WatchUi.MenuItem;

    function initialize(race as RaceSession, item as WatchUi.MenuItem) {
        PickerDelegate.initialize();
        _race = race;
        _item = item;
    }

    function onAccept(values as Array) as Boolean {
        var n = values[0] as Number;
        _race.setNumControls(n);
        _item.setSubLabel(n > 0 ? n.format("%d") : "unknown");
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onCancel() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// 0..max, index == value
class NumberFactory extends WatchUi.PickerFactory {

    private var _min as Number;
    private var _max as Number;

    function initialize(min as Number, max as Number) {
        PickerFactory.initialize();
        _min = min;
        _max = max;
    }

    function getSize() as Number {
        return _max - _min + 1;
    }

    function getValue(index as Number) as Object? {
        return _min + index;
    }

    function getDrawable(index as Number, selected as Boolean) as WatchUi.Drawable? {
        var v = _min + index;
        return new WatchUi.Text({:text => v == 0 ? "-" : v.format("%d"),
            :color => Graphics.COLOR_WHITE, :font => Graphics.FONT_NUMBER_MEDIUM,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER, :locY => WatchUi.LAYOUT_VALIGN_CENTER});
    }
}
