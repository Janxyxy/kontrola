import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

const PAGE_COUNT = 3;          // 0 main, 1 body, 2 splits
const SPLIT_POPUP_MS = 4000;   // how long the split is shown after a punch

// Race mode screens. Deliberately no map, position or bearing (IOF-legal).
class RaceView extends WatchUi.View {

    var page as Number = 0;
    private var _race as RaceSession;
    private var _timer as Timer.Timer;

    function initialize(race as RaceSession) {
        View.initialize();
        _race = race;
        _timer = new Timer.Timer();
    }

    function onShow() as Void {
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function nextPage(step as Number) as Void {
        page = (page + step + PAGE_COUNT) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        switch (_race.state) {
            case STATE_IDLE:
                drawPreStart(dc);
                return;
            case STATE_DONE:
                drawDone(dc);
                return;
        }

        if (System.getTimer() - _race.lastPunchAt < SPLIT_POPUP_MS) {
            drawSplitPopup(dc);
        } else if (page == 0) {
            drawMain(dc);
        } else if (page == 1) {
            drawBody(dc);
        } else {
            drawSplits(dc);
        }

        if (_race.state == STATE_PAUSED) {
            drawPausedBanner(dc);
        }
    }

    // --- screens ---

    private function drawPreStart(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        text(dc, cx, h * 0.14, Graphics.FONT_SMALL, "ORIENTEERING", Graphics.COLOR_ORANGE);

        var gps = gpsLabel();
        text(dc, cx, h * 0.36, Graphics.FONT_MEDIUM, "GPS " + gps[0], gps[1]);

        var ctl = _race.numControls > 0 ? _race.numControls.format("%d") : "-";
        text(dc, cx, h * 0.55, Graphics.FONT_MEDIUM, "Controls " + ctl, Graphics.COLOR_WHITE);

        text(dc, cx, h * 0.76, Graphics.FONT_XTINY, "START to begin", Graphics.COLOR_LT_GRAY);
        text(dc, cx, h * 0.86, Graphics.FONT_XTINY, "hold UP: settings", Graphics.COLOR_LT_GRAY);
    }

    private function drawMain(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        // heading to
        text(dc, cx, h * 0.15, Graphics.FONT_MEDIUM, "C " + _race.targetLabel(), Graphics.COLOR_ORANGE);

        // leg time (big)
        text(dc, cx, h * 0.43, Graphics.FONT_NUMBER_HOT, formatTime(_race.legMs()), Graphics.COLOR_WHITE);
        text(dc, cx, h * 0.60, Graphics.FONT_XTINY, "LEG", Graphics.COLOR_LT_GRAY);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 0.15, h * 0.67, w * 0.85, h * 0.67);

        // total
        text(dc, cx, h * 0.77, Graphics.FONT_NUMBER_MILD, formatTime(_race.timerMs()), Graphics.COLOR_WHITE);
        text(dc, cx, h * 0.89, Graphics.FONT_XTINY, "TOTAL", Graphics.COLOR_LT_GRAY);
    }

    private function drawBody(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        var hr = _race.heartRate();
        text(dc, cx, h * 0.25, Graphics.FONT_NUMBER_HOT, hr != null ? hr.format("%d") : "--", Graphics.COLOR_RED);
        text(dc, cx, h * 0.42, Graphics.FONT_XTINY, "HR", Graphics.COLOR_LT_GRAY);

        text(dc, w * 0.30, h * 0.62, Graphics.FONT_NUMBER_MILD, formatDist(_race.legDistanceM()), Graphics.COLOR_WHITE);
        text(dc, w * 0.30, h * 0.75, Graphics.FONT_XTINY, "LEG KM", Graphics.COLOR_LT_GRAY);

        text(dc, w * 0.70, h * 0.62, Graphics.FONT_NUMBER_MILD, formatDist(_race.distanceM()), Graphics.COLOR_WHITE);
        text(dc, w * 0.70, h * 0.75, Graphics.FONT_XTINY, "TOTAL KM", Graphics.COLOR_LT_GRAY);
    }

    private function drawSplits(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        text(dc, cx, h * 0.14, Graphics.FONT_XTINY, "SPLITS", Graphics.COLOR_ORANGE);

        var n = _race.splits.size();
        if (n == 0) {
            text(dc, cx, h / 2, Graphics.FONT_SMALL, "no controls yet", Graphics.COLOR_LT_GRAY);
            return;
        }
        // last 5, newest on top
        var rows = n < 5 ? n : 5;
        for (var i = 0; i < rows; i++) {
            var idx = n - 1 - i;
            var y = h * 0.28 + i * h * 0.13;
            var color = i == 0 ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY;
            text(dc, w * 0.32, y, Graphics.FONT_SMALL, "C" + (idx + 1).format("%d"), color);
            text(dc, w * 0.62, y, Graphics.FONT_SMALL, formatTime(_race.splits[idx]), color);
        }
    }

    private function drawSplitPopup(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var split = _race.lastSplitMs();

        text(dc, cx, h * 0.25, Graphics.FONT_MEDIUM, "C" + _race.punched.format("%d"), Graphics.COLOR_ORANGE);
        text(dc, cx, h * 0.50, Graphics.FONT_NUMBER_HOT, split != null ? formatTime(split) : "--", Graphics.COLOR_WHITE);
        text(dc, cx, h * 0.75, Graphics.FONT_SMALL, "next " + _race.targetLabel(), Graphics.COLOR_LT_GRAY);
    }

    private function drawDone(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        text(dc, cx, h * 0.25, Graphics.FONT_MEDIUM, "DONE", Graphics.COLOR_ORANGE);
        text(dc, cx, h * 0.48, Graphics.FONT_NUMBER_MILD, formatTime(_race.timerMs()), Graphics.COLOR_WHITE);
        text(dc, cx, h * 0.66, Graphics.FONT_SMALL, _race.punched.format("%d") + " controls", Graphics.COLOR_LT_GRAY);
        text(dc, cx, h * 0.84, Graphics.FONT_XTINY, "BACK to exit", Graphics.COLOR_LT_GRAY);
    }

    private function drawPausedBanner(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_YELLOW);
        dc.fillRectangle(0, 0, w, h * 0.09);
        text(dc, w / 2, h * 0.055, Graphics.FONT_XTINY, "PAUSED", Graphics.COLOR_BLACK);
    }

    // --- helpers ---

    private function text(dc as Graphics.Dc, x as Numeric, y as Numeric, font as Graphics.FontDefinition,
                          s as String, color as Graphics.ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function gpsLabel() as [String, Graphics.ColorType] {
        switch (_race.gpsAccuracy) {
            case Position.QUALITY_GOOD:
                return ["ready", Graphics.COLOR_GREEN];
            case Position.QUALITY_USABLE:
                return ["ok", Graphics.COLOR_YELLOW];
            default:
                return ["searching", Graphics.COLOR_RED];
        }
    }
}

function formatTime(ms as Number) as String {
    var s = ms / 1000;
    var hh = s / 3600;
    var mm = (s % 3600) / 60;
    var ss = s % 60;
    if (hh > 0) {
        return hh.format("%d") + ":" + mm.format("%02d") + ":" + ss.format("%02d");
    }
    return mm.format("%d") + ":" + ss.format("%02d");
}

function formatDist(m as Float) as String {
    return (m / 1000.0).format("%.2f");
}
